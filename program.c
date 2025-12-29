#include <stdio.h>

#include "xparameters.h"

#include "netif/xadapter.h"

#include "platform.h"
#include "platform_config.h"
#if defined (__arm__) || defined(__aarch64__)
#include "xil_printf.h"
#endif

#include "lwip/tcp.h"
#include "xil_cache.h"

// --- CUSTOM INCLUDES & DEFINES START ---
#include "xil_io.h"
#include "lwip/udp.h"
#include <stdint.h>
#include <inttypes.h> // for PRIu32 if needed

// FIFO Addresses
#define FIFO_BASE XPAR_AXI_FIFO_MM_S_0_BASEADDR
//#define ISR  0x00  // Interrupt Status Register
#define RDFR 0x18  // Receive Data FIFO Reset
#define RDFO 0x1C  // Receive Data FIFO Occupancy
#define RDFD 0x20  // Receive Data FIFO Data
#define RLR  0x24  // Receive Length Register

// Global UDP structures
struct udp_pcb *my_udp_pcb;
ip_addr_t target_ip;

// --- CUSTOM INCLUDES END ---


#if LWIP_IPV6==1
#include "lwip/ip.h"
#else
#if LWIP_DHCP==1
#include "lwip/dhcp.h"
#endif
#endif

/* defined by each RAW mode application */
void print_app_header();
int start_application();
int transfer_data();
void tcp_fasttmr(void);
void tcp_slowtmr(void);

/* missing declaration in lwIP */
void lwip_init();

#if LWIP_IPV6==0
#if LWIP_DHCP==1
extern volatile int dhcp_timoutcntr;
err_t dhcp_start(struct netif *netif);
#endif
#endif

extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;
static struct netif server_netif;
struct netif *echo_netif;

#if LWIP_IPV6==1
void print_ip6(char *msg, ip_addr_t *ip)
{
	print(msg);
	xil_printf(" %x:%x:%x:%x:%x:%x:%x:%x\n\r",
		   IP6_ADDR_BLOCK1(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK2(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK3(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK4(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK5(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK6(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK7(&ip->u_addr.ip6),
		   IP6_ADDR_BLOCK8(&ip->u_addr.ip6));

}
#else
void print_ip(char *msg, ip_addr_t *ip)
{
	print(msg);
	xil_printf("%d.%d.%d.%d\n\r", ip4_addr1(ip), ip4_addr2(ip),
		   ip4_addr3(ip), ip4_addr4(ip));
}

void print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
{

	print_ip("Board IP: ", ip);
	print_ip("Netmask : ", mask);
	print_ip("Gateway : ", gw);
}
#endif

#if defined (__arm__) && !defined (ARMR5)
#if XPAR_GIGE_PCS_PMA_SGMII_CORE_PRESENT == 1 || XPAR_GIGE_PCS_PMA_1000BASEX_CORE_PRESENT == 1
int ProgramSi5324(void);
int ProgramSfpPhy(void);
#endif
#endif

#ifdef XPS_BOARD_ZCU102
#if defined (XPAR_XIICPS_0_DEVICE_ID) || defined (XPAR_XIICPS_0_BASEADDR)
int IicPhyReset(void);
#endif
#endif


// --- CUSTOM HELPER FUNCTIONS START ---
// safer send function
void send_trade_packet(const char *payload, size_t payload_len) {
    struct pbuf *p;
    if (!my_udp_pcb) {
        xil_printf("send_trade_packet: no UDP pcb\n\r");
        return;
    }
    if (payload_len == 0) return;

    // allocate pbuf, allow room for null if you want to print/debug on receiver (optional)
    p = pbuf_alloc(PBUF_TRANSPORT, (u16_t)payload_len, PBUF_RAM);
    if (!p) {
        xil_printf("pbuf_alloc failed (len=%u)\n\r", (unsigned)payload_len);
        return;
    }

    // copy exactly payload_len bytes (no assumption of null-termination)
    memcpy(p->payload, payload, payload_len);

    if (udp_send(my_udp_pcb, p) != ERR_OK) {
        xil_printf("udp_send failed\n\r");
    }
    pbuf_free(p);
}

void setup_custom_udp() {
    my_udp_pcb = udp_new();
    if (!my_udp_pcb) {
        xil_printf("udp_new failed!\n\r");
        return;
    }

    // HARDCODE YOUR PC IP HERE: 192.168.1.50
    IP4_ADDR(&target_ip, 192, 168, 1, 50);

    // Connect to PC Port 5001
    if (udp_connect(my_udp_pcb, &target_ip, 5001) != ERR_OK) {
        xil_printf("udp_connect failed\n\r");
        // we still keep pcb, but note the failure
    } else {
        xil_printf("UDP Custom Setup Complete. Target: 192.168.1.50:5001\r\n");
    }
}
// --- CUSTOM HELPER FUNCTIONS END -


int main()
{
#if LWIP_IPV6==0
	ip_addr_t ipaddr, netmask, gw;

#endif
	/* the mac address of the board. this should be unique per board */
	unsigned char mac_ethernet_address[] =
	{ 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };

	echo_netif = &server_netif;
#if defined (__arm__) && !defined (ARMR5)
#if XPAR_GIGE_PCS_PMA_SGMII_CORE_PRESENT == 1 || XPAR_GIGE_PCS_PMA_1000BASEX_CORE_PRESENT == 1
	ProgramSi5324();
	ProgramSfpPhy();
#endif
#endif

	/* Define this board specific macro in order perform PHY reset on ZCU102 */
#ifdef XPS_BOARD_ZCU102
	if (IicPhyReset()) {
		xil_printf("Error performing PHY reset \n\r");
		return -1;
	}
#endif

	init_platform();

#if LWIP_IPV6==0
#if LWIP_DHCP==1
	ipaddr.addr = 0;
	gw.addr = 0;
	netmask.addr = 0;
#else
	/* initialize IP addresses to be used */
	IP4_ADDR(&ipaddr,  192, 168,   1, 10);
	IP4_ADDR(&netmask, 255, 255, 255,  0);
	IP4_ADDR(&gw,      192, 168,   1,  1);
#endif
#endif
	print_app_header();

	lwip_init();

#if (LWIP_IPV6 == 0)
	/* Add network interface to the netif_list, and set it as default */
	if (!xemac_add(echo_netif, &ipaddr, &netmask,
		       &gw, mac_ethernet_address,
		       PLATFORM_EMAC_BASEADDR)) {
		xil_printf("Error adding N/W interface\n\r");
		return -1;
	}
#else
	/* Add network interface to the netif_list, and set it as default */
	if (!xemac_add(echo_netif, NULL, NULL, NULL, mac_ethernet_address,
		       PLATFORM_EMAC_BASEADDR)) {
		xil_printf("Error adding N/W interface\n\r");
		return -1;
	}
	echo_netif->ip6_autoconfig_enabled = 1;

	netif_create_ip6_linklocal_address(echo_netif, 1);
	netif_ip6_addr_set_state(echo_netif, 0, IP6_ADDR_VALID);

	print_ip6("\n\rBoard IPv6 address ", &echo_netif->ip6_addr[0].u_addr.ip6);

#endif
	netif_set_default(echo_netif);

#ifndef SDT
	/* now enable interrupts */
	platform_enable_interrupts();
#endif

	/* specify that the network if is up */
	netif_set_up(echo_netif);

#if (LWIP_IPV6 == 0)
#if (LWIP_DHCP==1)
	/* Create a new DHCP client for this interface.
	 * Note: you must call dhcp_fine_tmr() and dhcp_coarse_tmr() at
	 * the predefined regular intervals after starting the client.
	 */
	dhcp_start(echo_netif);
	dhcp_timoutcntr = 240;

	while (((echo_netif->ip_addr.addr) == 0) && (dhcp_timoutcntr > 0)) {
		xemacif_input(echo_netif);
	}

	if (dhcp_timoutcntr <= 0) {
		if ((echo_netif->ip_addr.addr) == 0) {
			xil_printf("DHCP Timeout\r\n");
			xil_printf("Configuring default IP of 192.168.1.10\r\n");
			IP4_ADDR(&(echo_netif->ip_addr),  192, 168,   1, 10);
			IP4_ADDR(&(echo_netif->netmask), 255, 255, 255,  0);
			IP4_ADDR(&(echo_netif->gw),      192, 168,   1,  1);
		}
	}

	ipaddr.addr = echo_netif->ip_addr.addr;
	gw.addr = echo_netif->gw.addr;
	netmask.addr = echo_netif->netmask.addr;
#endif

	print_ip_settings(&ipaddr, &netmask, &gw);

#endif
	/* start the application (web server, rxtest, txtest, etc..) */
	start_application();


	// --- CUSTOM SETUP INSERTION ---
	setup_custom_udp();

	// Reset FIFO
	//Xil_Out32(FIFO_BASE + RDFR, 0xA5);
	// ------------------------------

	//static int counter = 0;
	/* receive and process packets */
	while (1) {
		if (TcpFastTmrFlag) {
			tcp_fasttmr();
			TcpFastTmrFlag = 0;
		}
		if (TcpSlowTmrFlag) {
			tcp_slowtmr();
			TcpSlowTmrFlag = 0;
		}
		xemacif_input(echo_netif);
//		// --- CUSTOM LOOP LOGIC (safe, consumes full FIFO packet) ---
		u32 packets_waiting = Xil_In32(FIFO_BASE + RDFO);

//		IF BROKEN, uncomment this to test if the UDP functions are working.
//		counter++;
//		if (counter % 1000000 == 0) {
//			send_trade_packet("TEST,123,456",strlen("TEST,123,456"));
//			xil_printf("Sent test UDP packet\r\n");
//			counter = 0;
//		}


		if (packets_waiting > 0) {
		    // 1. Pop Length (Required to clear/advance packet from FIFO)
		    volatile u32 len = Xil_In32(FIFO_BASE + RLR);
		    // Sanity-check len (protect against bogus values)
		    if (len == 0 || len > 65536) { // adjust max as appropriate for your FIFO
		        xil_printf("FIFO: bogus length: %u; skipping\n\r", (unsigned)len);
		        // try to clear len bytes anyway but be careful -- here we skip
		        continue;
		    }

		    // Number of 32-bit words to read (round up)
		    u32 words = (len + 3) / 4;

		    // we'll gather first word (if any) to decode trade message
		    u32 first_word = 0;
		    for (u32 i = 0; i < words; ++i) {
		        u32 w = Xil_In32(FIFO_BASE + RDFD);
		        if (i == 0) first_word = w;
		        // If we switch to multi-word packets, store more words here.
		    }

		    // Now parse first_word as before (if protocol puts all fields in first 32 bits)
		    u32 type  = (first_word >> 31) & 0x1;
		    u32 qty   = (first_word >> 16) & 0x7FFF;
		    u32 price = first_word & 0xFFFF;

		    // Format and send: be defensive about buffer size
		    char buffer[64];
		    int n = snprintf(buffer, sizeof(buffer), "%s,%u,%u", (type ? "BUY" : "SELL"), (unsigned)qty, (unsigned)price);
		    xil_printf("RDFO = %u\n\r", Xil_In32(FIFO_BASE + RDFO));
		    if (n < 0) {
		        xil_printf("sprintf error\n\r");
		    } else {
		        // send exact bytes (exclude trailing NUL)
		        send_trade_packet(buffer, (size_t)n);
		    }

		    //static int counter = 0;

		}

		//xil_printf("FIFO: waiting=%u len=%u first=0x%08x\n\r", (unsigned)packets_waiting, (unsigned)len, (unsigned)first_word);
		transfer_data();
	}

	/* never reached */
	cleanup_platform();

	return 0;
}
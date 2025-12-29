# UDP Packet Generator for Real-Time Data Acquisition

A hardware/software co-design project implementing a real-time trading data generator on a Xilinx Zynq FPGA. The system generates synthetic market data, executes trading decisions using an EMA crossover algorithm, and transmits trade events over UDP Ethernet.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [System Architecture](#system-architecture)
- [Hardware Requirements](#hardware-requirements)
- [Software Requirements](#software-requirements)
- [Project Structure](#project-structure)
- [Module Descriptions](#module-descriptions)
  - [Market Generator](#market-generator-market_genv)
  - [DSP Trader](#dsp-trader-dsp_traderv)
  - [Trader Top](#trader-top-trader_topv)
  - [AXI FIFO Data Path](#axi-fifo-data-path)
  - [Embedded Software](#embedded-software)
- [Running the System](#running-the-system)
- [Simulation and Testing](#simulation-and-testing)
- [Data Format](#data-format)
- [Design Limitations](#design-limitations)

## Overview

This project demonstrates a complete end-to-end system that generates, processes, transports, and visualizes live trading data. The FPGA fabric handles deterministic, high-speed data generation and trading algorithm execution, while the ARM processor provides flexible networking capabilities via the lwIP TCP/IP stack.

The system simulates a financial market by:
1. Generating a continuous stream of pseudo-random stock prices
2. Applying an Exponential Moving Average (EMA) crossover trading algorithm
3. Streaming trade events through an AXI-Stream FIFO
4. Transmitting trade decisions as UDP packets over Ethernet

## Features

- **LFSR-based Market Simulation**: Generates realistic random-walk price movements
- **Hardware-Accelerated Trading**: EMA crossover algorithm implemented entirely in FPGA fabric
- **Real-Time UDP Streaming**: Trade events transmitted with minimal latency
- **AXI-Stream Interface**: Standard protocol for hardware/software communication
- **Modular Design**: Easily extensible for more complex trading strategies
- **Complete Verification**: Comprehensive testbenches for all modules

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Zynq-7000 SoC                                    │
│  ┌───────────────────────────────────────┐  ┌────────────────────────┐  │
│  │         Programmable Logic (PL)       │  │  Processing System (PS)│  │
│  │                                       │  │                        │  │
│  │  ┌────────────┐    ┌──────────────┐   │  │  ┌──────────────────┐  │  │
│  │  │ market_gen │───▶│  dsp_trader  │   │  │  │   ARM Cortex-A9  │  │  │
│  │  │  (LFSR)    │    │  (EMA Algo)  │   │  │  │                  │  │  │
│  │  └────────────┘    └──────┬───────┘   │  │  │  ┌────────────┐  │  │  │
│  │                          │            │  │  │  │  lwIP UDP  │  │  │  │
│  │                          ▼            │  │  │  │   Stack    │  │  │  │
│  │               ┌──────────────────┐    │  │  │  └─────┬──────┘  │  │  │
│  │               │   trader_top     │    │  │  │        │         │  │  │
│  │               │  (AXI-Stream)    │    │  │  │        ▼         │  │  │
│  │               └────────┬─────────┘    │  │  │  ┌────────────┐  │  │  │
│  │                        │              │  │  │  │ Ethernet   │  │  │  │
│  │                        ▼              │  │  │  │    MAC     │  │  │  │
│  │               ┌──────────────────┐    │  │  │  └─────┬──────┘  │  │  │
│  │               │  AXI-Stream FIFO │◀───┼──┼──┼────────┘         │  │  │
│  │               │      (IP)        │    │  │  │                  │  │  │
│  │               └──────────────────┘    │  │  └──────────────────┘  │  │
│  └───────────────────────────────────────┘  └────────────────────────┘  │
│                                                          │              │
└──────────────────────────────────────────────────────────┼──────────────┘
                                                           │
                                                           ▼
                                                    ┌─────────────┐
                                                    │  Ethernet   │
                                                    │    PHY      │
                                                    │(RTL8211E-VL)│
                                                    └──────┬──────┘
                                                           │
                                                           ▼
                                                      UDP Packets
                                                    to Host PC:5001
```

## Hardware Requirements

| Component | Specification |
|-----------|---------------|
| **FPGA Board** | Digilent Cora Z7-07s Development Board |
| **FPGA Chip** | Xilinx Zynq-7000 XC7Z007S-1CLG400C |
| **Processor** | ARM Cortex-A9 (single-core) |
| **FPGA Fabric** | Artix-7 |
| **Ethernet PHY** | RTL8211E-VL (on-board) |
| **Debug Interface** | USB-UART |
| **Host PC** | Any computer with Ethernet interface |

### Network Configuration

| Device | IP Address | Port |
|--------|------------|------|
| FPGA Board | 192.168.1.10 | 62510 (source) |
| Host PC | 192.168.1.50 | 5001 (destination) |

## Software Requirements

### Development Tools

- **Xilinx Vivado** - Synthesis, implementation, and simulation
- **Xilinx Vitis/SDK** - Embedded C development and deployment
- **Wireshark** - UDP packet capture and analysis

### Libraries

- **lwIP** - Lightweight TCP/IP stack for UDP communication

### Languages

- **Verilog HDL** - Hardware modules
- **SystemVerilog** - Testbenches
- **C** - Embedded software

## Project Structure

```
udp-packet-generator/
├── hdl/
│   ├── market_gen.v          # LFSR-based price generator
│   ├── dsp_trader.v          # EMA trading algorithm
│   └── trader_top.v          # Top-level wrapper with AXI-Stream
├── tb/
│   ├── tb_market_gen.sv      # Market generator testbench
│   ├── tb_dsp_trader.sv      # Trading algorithm testbench
│   └── tb_trader_top.sv      # Integration testbench
├── sw/
│   └── main.c                # Embedded C application
├── ip/
│   └── (Xilinx IP configurations)
├── constraints/
│   └── (XDC constraint files)
└── README.md
```

## Module Descriptions

### Market Generator (`market_gen.v`)

Generates a continuous stream of simulated stock prices using a pseudo-random number generator.

**Key Features:**
- 32-bit Linear Feedback Shift Register (LFSR) with taps at bits [31, 21, 1, 0]
- Configurable update rate via `CLK_DIV` parameter
- Random walk price model with configurable step size
- Price clamping between 100 and 60,000

**Interface:**
```verilog
module market_gen #(
    parameter CLK_DIV = 100000  // Clock divider for update rate
)(
    input  wire        clk,
    input  wire        rst,
    output reg  [15:0] price,
    output reg         valid
);
```

**Algorithm:**
1. LFSR generates pseudo-random bits each cycle
2. Direction (up/down) determined by LFSR bit 0
3. Step size computed from LFSR bits [3:0]
4. Price updated when clock divider counter reaches threshold
5. `valid` signal pulses high for one cycle on each update

### DSP Trader (`dsp_trader.v`)

Implements an Exponential Moving Average (EMA) crossover trading algorithm.

**Key Features:**
- Dual EMA calculation (short-term and long-term)
- Q16.16 fixed-point arithmetic for precision
- Hysteresis threshold to prevent noise trading
- 200-cycle warmup period for EMA stabilization
- Single-cycle trade decision output

**Interface:**
```verilog
module dsp_trader (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] price_in,
    input  wire        price_valid,
    output reg  [31:0] trade_word,
    output reg         trade_valid
);
```

**EMA Update Equations:**
```
ema_short = ema_short + ((price - ema_short) >>> 3)   // α ≈ 0.125
ema_long  = ema_long  + ((price - ema_long)  >>> 6)   // α ≈ 0.0156
```

**Trading Logic:**
- **BUY**: When `ema_short - ema_long` crosses above `+THRESHOLD`
- **SELL**: When `ema_short - ema_long` crosses below `-THRESHOLD`
- `THRESHOLD = 65536` (1.0 in Q16.16 format)

### Trader Top (`trader_top.v`)

Top-level integration module that connects all hardware components and provides the AXI-Stream interface.

**Interface:**
```verilog
module trader_top (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [31:0] axis_tdata,
    output reg         axis_tvalid,
    output reg         axis_tlast,
    input  wire        axis_tready
);
```

**AXI-Stream Protocol:**
- Each trade event is a single 32-bit word packet
- `axis_tlast` asserted with every `axis_tvalid` (1-word packets)
- Backpressure support via `axis_tready`

### AXI FIFO Data Path

The AXI FIFO IP block serves as the communication bridge between the FPGA fabric (PL) and the Zynq Processing System (PS). Trade messages generated by the hardware logic are sent into the FIFO using the AXI-Stream protocol, where they are temporarily stored until the processor is ready to read them.

This decouples the timing of hardware and software, ensuring that no data is lost even if the processor momentarily falls behind. On the PS side, the FIFO exposes a simple AXI-Lite memory-mapped interface, allowing the C program to poll status registers, read the length of each packet, and retrieve the 32-bit trade word.

### Embedded Software

The C application running on the ARM Cortex-A9 handles:
1. lwIP network stack initialization
2. UDP socket configuration
3. AXI FIFO polling and data retrieval
4. Trade word decoding
5. UDP packet transmission

**FIFO Register Map:**
| Offset | Register | Description |
|--------|----------|-------------|
| 0x18 | RDFR | Receive Data FIFO Reset |
| 0x1C | RDFO | Receive Data FIFO Occupancy |
| 0x20 | RDFD | Receive Data FIFO Data |
| 0x24 | RLR | Receive Length Register |

**Read Sequence:**
1. Check RDFO for available packets
2. Read RLR to pop packet length (required to advance packet from FIFO)
3. Read RDFD to retrieve 32-bit trade word
4. Decode and format as ASCII string
5. Transmit via UDP

## Running the System

### Hardware Setup

1. Connect FPGA board to PC via Ethernet cable
2. Connect USB cable for JTAG programming and UART
3. Configure PC Ethernet interface:
   - IP: 192.168.1.50
   - Subnet: 255.255.255.0

### Capture Packets

Use Wireshark on the host machine to capture and inspect incoming packets:

```bash
# Start Wireshark with filter
wireshark -i eth0 -f "udp port 5001"
```

### Expected Output

UDP packets with ASCII payload:
```
BUY,50,1350
SELL,50,2229
BUY,50,2376
SELL,50,2874
```

## Simulation and Testing

### Market Generator Testbench

The `tb_market_gen` testbench verifies that the market generator produces periodic, random price updates at the correct intervals.

**Verification Points:**
- Price initialization to 1000
- Valid pulse timing matches CLK_DIV
- Price stays within bounds [100, 60000]
- Random walk behavior with small variations

### DSP Trader Testbench

The `tb_dsp_trader` testbench confirms the behavior of the EMA trading algorithm with controlled inputs.

**Verification Points:**
- Warmup period behavior (200 cycles, no trades emitted)
- EMA convergence from initial values
- BUY signal on upward threshold crossover
- SELL signal on downward threshold crossover
- Correct trade word encoding

### Trader Top Testbench

The `tb_trader_top` testbench verifies that the module correctly outputs packets over the AXI-Stream interface.

**Verification Points:**
- AXI-Stream protocol compliance
- Single-cycle `axis_tvalid` and `axis_tlast` pulses
- Correct backpressure handling via `axis_tready`
- End-to-end data flow from market generation to trade output

**Example Trade Words from Simulation:**
```
0x80320546 → BUY,  50, 1350
0x0032060B → SELL, 50, 1547
0x803207A5 → BUY,  50, 1957
```

## Data Format

### Trade Word Encoding (32 bits)

```
┌────────┬─────────────────┬──────────────────────────────┐
│ Bit 31 │   Bits [30:16]  │        Bits [15:0]           │
├────────┼─────────────────┼──────────────────────────────┤
│  Type  │    Quantity     │           Price              │
│ 1=BUY  │   (15 bits)     │         (16 bits)            │
│ 0=SELL │   Fixed: 50     │       Range: 100-60000       │
└────────┴─────────────────┴──────────────────────────────┘
```

### Example Decoding

```
0x80320546 → BUY,  50, 1350  (0x546  = 1350)
0x0032060B → SELL, 50, 1547  (0x60B  = 1547)
0x803207A5 → BUY,  50, 1957  (0x7A5  = 1957)
```

### UDP Payload Format

ASCII CSV string: `<TYPE>,<QTY>,<PRICE>`

Examples:
- `BUY,50,1350`
- `SELL,50,2874`

## Design Limitations

### Ethernet PHY Constraint

Part of the original purpose of this project was to implement an Ethernet networking stack entirely in the programmable logic, without using a CPU. However, the Cora Z7-07s board connects the Ethernet PHY (RTL8211E-VL) directly to the Processing System's MIO (multiplexed I/O) pins. These MIO pins belong to the PS and cannot be multiplexed to the PL.

**Original Goal:** Implement the entire UDP stack in FPGA fabric for minimum latency.

**Actual Implementation:** Uses ARM processor with lwIP stack, adding software latency.

### Alternative Approach

For true hardware-only Ethernet, the project could have involved:
1. Using a development board with RGMII (Reduced Gigabit Media Independent Interface) pins routed to PL
2. Implementing an RGMII interface to communicate with the Ethernet PHY
3. Creating an MDIO state machine that configures the PHY at boot

This approach would have achieved lower latency, which was in the spirit of the design's original objective. Prototype Verilog code for this alternative approach is included in the project annexure.

---

## Quick Reference

### Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Clock Frequency | 50 MHz | FCLK_CLK0 from PS |
| Price Range | 100 - 60,000 | Clamped market prices |
| EMA Short α | 0.125 (1/8) | Fast-moving average |
| EMA Long α | 0.0156 (1/64) | Slow-moving average |
| Threshold | 65536 | Trade trigger (Q16.16) |
| Warmup Cycles | 200 | EMA stabilization period |
| Trade Quantity | 50 | Fixed per trade |

### Network Settings

```
FPGA Board:  192.168.1.10:62510
Host PC:     192.168.1.50:5001
Protocol:    UDP
```

### Useful Commands

```bash
# Capture UDP traffic
tcpdump -i eth0 udp port 5001 -X

# Wireshark filter
udp.port == 5001

# Test network connectivity
ping 192.168.1.10
```

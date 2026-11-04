# STM32 Secure Telemetry Link

A demo project built to show that I can do the work described in Kepler
Communications'
[Embedded Software Designer role](https://jobs.lever.co/kepler/accae2f6-7ffe-49a8-a485-ee9c13421c95)
in Toronto.

An STM32 board plays the "spacecraft" and a Raspberry Pi 5 plays the "ground
station". The STM32 boots only signed firmware, reads digital I/O from a CANopen
module over CAN, and sends that state to the Pi over an encrypted, authenticated
Ethernet link. The Pi displays the state and can send commands back to set the
module's outputs.

**Status (Nov 3, 2026):** in progress, with a target of Dec 2, 2026. Week 1 of 4 has
started and no firmware exists yet, so everything below describes the planned
design. See [PLAN.md](PLAN.md) for the schedule.

## Documentation

| Document                                                                    | What it covers                                            |
| --------------------------------------------------------------------------- | --------------------------------------------------------- |
| [Plan](PLAN.md)                                                             | Schedule, materials, build layout and security demos      |
| [Boot](documentation/boot.md)                                               | The three programs, slots A and B, and boot checks        |
| [Cryptography](documentation/cryptography.md)                               | What each cryptographic technique does and why it's used  |
| [Memory](documentation/memory.md)                                           | Flash and RAM layout, and where keys and images live      |
| [Threat model](documentation/threat_model.md)                               | Assets, attackers, trust boundaries and security requirements |
| [CAN peripheral](documentation/peripheral_CAN.md)                           | CAN1 pins, bit timing, sample point and interrupts        |
| [Job mapping](documentation/job-description-to-project-mapping.md)          | What part of the project covers each posting requirement  |
| [License](licensing/LICENSE)                                                | This project's license                                    |
| [Third-party notices](licensing/third-party-notices.md)                     | Third-party software, its licenses and their conditions   |

## What the demo shows

- A change on a CANopen input appears in a terminal stream on the Pi, updated every
  500 ms, with stale data clearly flagged.
- A command from the Pi sets a CANopen output over the encrypted link.
- Attacks fail visibly: a tampered firmware image, an old signed image, a replayed
  command, and a man-in-the-middle during the handshake are all rejected, and a
  packet capture shows only ciphertext.

## Hardware architecture

```text
+--------------------------------------------------------------------+
|                          Developer laptop                          |
|           Ozone, RTT, SystemView, pytest, Wireshark, SSH           |
+--------------------------------------------------------------------+
         |                                             |
         | USB: J-Link on ST-LINK,                     | Wi-Fi: SSH,
         | virtual COM port (UART)                     | capture files
         |                                             |
+--------+-----------------+                  +--------+-------------+
| STM32F746G-DISCO         |                  | Raspberry Pi 5       |
| "spacecraft"             |     Ethernet     | "ground station"     |
|                          |   encrypted UDP  |                      |
| Cortex-M7, FreeRTOS      |<================>| Raspberry Pi OS      |
| Bootloader, Monocypher   |  direct cable,   | Python daemon        |
| 16 MB QSPI flash         |    static IPs    | Attacker proxy       |
| (update slots A and B)   |                  | (demos only)         |
+---+--------------+-------+                  +--------+-------------+
    |              |                                   |
    | I2C          | CAN TX/RX                         | I2C (stretch)
    |              |                                   |
+---+------+  +----+---------+                   +-----+--------+
| ATECC608 |  | CAN          |                   | I2C IMU      |
| P-256    |  | transceiver  |                   | (stretch:    |
| identity |  +----+---------+                   | kernel       |
| key      |       |                             | driver)      |
+----------+       |                             +--------------+
                   | CAN bus: CANopen NMT, SDO, heartbeat
                   | 120 ohm termination as required
              +----+---------+
              | CANopen IO   |
              | module       |
              | DI and DO    |
              +--------------+
```

The cryptography is explained in
[documentation/cryptography.md](documentation/cryptography.md).

## How the project maps to the job description

See [documentation/job-description-to-project-mapping.md](documentation/job-description-to-project-mapping.md)
for a table of what part of the project covers each requirement in the posting.

## Stretch goal: Linux kernel integration

If time remains after the demo video is recorded, I'll add a minimal out-of-tree I2C
kernel driver and device tree overlay for an IMU on the Pi 5. This is my first kernel
work, so it's timeboxed to protect the core demo.

## Out of scope

- VHDL, Verilog and any FPGA programming
- Yocto image
- GUI
- Hardware tests triggered from GitHub Actions; these run locally with pytest

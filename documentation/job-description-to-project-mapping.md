# Job Description to Project Mapping

## Résumé framing

One line to use, adjusted to match what actually gets built:

> Designed a secure telemetry system on STM32 with FreeRTOS, signed two-stage
> A/B bootloader over QSPI flash, X25519 plus AEAD link encryption with an
> ATECC608-backed device identity, CANopen I/O over CAN, an Ethernet-linked Linux
> ground station, and automated hardware-in-the-loop testing.

If the optional driver gets built, add "a custom I2C kernel driver and device tree
overlay". Don't claim it otherwise. The posting requires this experience, so if
it's skipped, say plainly that kernel work is something to grow into.

When applying, use the posting's title: "Embedded Software Designer".

## Mapping overview

This maps Kepler Communications' Embedded Software Designer role to the parts of
this project.

Requirements are paraphrased from the
[posting](https://jobs.lever.co/kepler/accae2f6-7ffe-49a8-a485-ee9c13421c95).
Coverage describes the plan, not finished work:

- **Direct:** the project exercises this.
- **Partial:** the project exercises part of this.
- **Stretch:** only if time remains.
- **Not covered:** the project doesn't show this.

## Responsibilities

| From the posting                                                | Project part                                                                                       | Coverage |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | -------- |
| Reliable embedded software for spacecraft and ground systems    | STM32 "spacecraft" firmware and Pi "ground station" daemon, as a lab analogue rather than flight work | Partial  |
| Secure communications: encryption, authentication, key exchange | X25519 key exchange, ChaCha20-Poly1305, mutual authentication with signatures, replay protection   | Direct   |
| Device drivers, kernel modules, hardware interfaces             | CAN, QSPI, I2C and UART on the STM32; a Linux kernel driver is the stretch goal                    | Partial  |
| Automated tests, validation tools, technical documentation      | Host unit tests, pytest hardware tests, attack tool, README and design notes                       | Direct   |

## Required skills

| From the posting                                       | Project part                                                                      | Coverage |
| ------------------------------------------------------ | --------------------------------------------------------------------------------- | -------- |
| C/C++ for embedded: concurrency, interrupts            | FreeRTOS tasks and queues, ISR-driven UART with DMA, traced with SystemView       | Direct   |
| Interfaces such as SPI, I2C, UART and CAN              | QSPI flash, I2C to the ATECC608, UART console, CANopen over CAN                   | Direct   |
| Embedded Linux and/or RTOS, including FreeRTOS         | FreeRTOS on the STM32; Raspberry Pi OS on the ground station                      | Direct   |
| Build systems such as Yocto                            | Removed from scope to save time                                                   | Not covered |
| Kernel modules, device drivers, device trees           | I2C kernel driver and device tree overlay for an IMU on the Pi                    | Stretch  |
| Automated test frameworks, hardware/software integration | Hardware-in-the-loop tests with pytest, fault injection, CI builds and unit tests | Direct   |
| System design, debugging, testing, performance analysis | Threat model and flash layout, Ozone fault debugging, 500 ms timing checks       | Direct   |
| Git-based version control and code review              | Git and GitHub Actions; as a solo project, it has no peer review                  | Partial  |
| AI-assisted engineering tools                          | Planned with Claude Code, with the decisions recorded in the plan                 | Direct   |

## Bonus skills

| From the posting                                   | Project part                                                            | Coverage |
| -------------------------------------------------- | ----------------------------------------------------------------------- | -------- |
| Secure boot                                        | Ed25519-signed images, rollback counter, tamper tests                   | Direct   |
| Multi-stage bootloaders                            | Immutable stage 1 verifying stage 2, with A/B update and recovery       | Direct   |
| Key management and HSMs                            | Device identity key generated and locked on an ATECC608 secure element  | Direct   |
| Encrypted communications                           | The secure link above, with attack demos                                | Direct   |
| Networking and modern protocols                    | UDP over lwIP, and a handshake following a published signed-ephemeral pattern | Partial  |
| Linux networking: routing, netlink, packet processing | UDP daemon and a packet-rewriting proxy; no routing or netlink       | Partial  |
| Aerospace software                                 | Spacecraft and ground station framing only                              | Not covered |
| RTL (Verilog/VHDL) and embedded SoCs               | No Verilog, VHDL or FPGA work; excluded by choice                       | Not covered |

A project can't show the posting's experience requirements (4+ years, a degree) or
cross-functional collaboration and mentoring, so those aren't mapped here.

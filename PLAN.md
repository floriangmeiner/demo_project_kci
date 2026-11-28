# STM32 Secure Telemetry Link: Plan

**Window:** Nov 2, 2026 to Jan 22, 2027, with the core milestone on Dec 18
(moved from Dec 2 on Nov 26)

**Status:** Slice 1 starting (last updated Nov 26, 2026)

**Approach:** minimize effort and maximize demo impact. Anything that doesn't
support the demo video or a stated requirement in the posting is a candidate to
cut.

## Goal

A portfolio project that mirrors the [Kepler Embedded Software
role](https://jobs.lever.co/kepler/accae2f6-7ffe-49a8-a485-ee9c13421c95): an
STM32 "spacecraft" running FreeRTOS with a secure bootloader and an encrypted,
authenticated link to a Linux "ground station", with automated hardware tests
and CI. A small kernel driver and device tree overlay on the Pi are optional.

The build uses the STM32F746G-DISCO board already owned (no TrustZone or
hardware crypto, so crypto runs in software), with the device identity key on
an ATECC608 secure element.

## Architecture

Hardware (power supplies not shown; see [Pin assignments](#pin-assignments)):

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
| Bootloader, Monocypher   |  + TFTP images,  | Python daemon        |
| 16 MB QSPI flash         |  direct cable,   | Attacker proxy       |
| (update slots A and B)   |    static IPs    | (demos only)         |
+---+--------------+-------+                  +--------+-------------+
    |              |                                   |
    | I2C3         | CAN1: PB9 TX, PB8 RX              | I2C (optional)
    |              |                                   |
+---+------+  +----+---------+                   +-----+--------+
| ATECC608 |  | CAN          |                   | I2C IMU      |
| P-256    |  | transceiver  |                   | (optional    |
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

### Pin assignments

CAN1 is reachable on the Arduino header, but it uses the same two pins as the
header's I2C1, so the ATECC608 uses I2C3 instead. Its SDA pin, `PC9`, only
reaches the microSD slot, so a Saiko Systems ST-SD-uSDv2.0 adapter plugs into
the slot and brings it out to a header (see [ATECC608 wiring](#atecc608-wiring)
below). This comes from the [B-04
schematic](vendors/st_microelectronics/stm32f746g-disco/MB1191_B-04/mb1191-f746ngh6-b04-schematic.pdf),
which matches this board's `MB1191-B-04` sticker, along with UM1907 and CubeMX's
pin data. It has **not been tested on hardware**.

| Function            | MCU pin | MCU ball | Header           | Notes                              |
| ------------------- | ------- | -------- | ---------------- | ---------------------------------- |
| CAN1 RX             | PB8     | A7       | CN7 pin 10 (D15) | 2.7 kohm on-board pull-up to 3.3 V |
| CAN1 TX             | PB9     | B4       | CN7 pin 9 (D14)  | 2.7 kohm on-board pull-up to 3.3 V |
| ATECC608 SCL (I2C3) | PA8     | F15      | CN7 pin 3 (D10)  | No on-board pull-up                |
| ATECC608 SDA (I2C3) | PC9     | F14      | None (microSD slot) | Via the adapter's J2 pin 1; 47 kohm on-board pull-up |
| Red LED             | PI3     | C13      | CN4 pin 8 (D7)   | Series resistor                    |
| Green LED           | PI2     | C14      | CN7 pin 1 (D8)   | Series resistor                    |
| LD1, on-board green | PI1     | D14      | CN7 pin 6 (D13)  | Active high; for the first blink test |
| User button B1 (blue) | PI11  | F3       | None (on-board)  | Active high, with an on-board pull-down |
| UART TX (USART1)    | PA9     | E15      | None (ST-LINK)   | Virtual COM port                   |
| UART RX (USART1)    | PB7     | B5       | None (ST-LINK)   | Virtual COM port                   |
| 25 MHz clock (HSE)  | PH0     | G1       | None (on-board)  | From X2, in bypass mode            |
| 3.3 V, GND          | -       | -        | CN6 pins 4, 6    | ATECC608, transceiver logic supply |

Constraints on these pins:

- PB8 and PB9 also go to the camera connector and CN2 (the I2C extension
  connector), so keep both empty.
- The on-board pull-ups suit CAN, but use a transceiver with 3.3 V logic,
  because a 5 V RXD output would drive PB8 against a pull-up to 3.3 V. The owned
  transceivers' part number still needs checking.

### ATECC608 wiring

The ST-SD-uSDv2.0 is a microSD-shaped PCB (J3) that plugs into the DISCO's
microSD slot (CN3), with a 0.1" 10-pin header (J2) and an SD socket (J1) that
stays empty. Its signals pass straight through, with no pull-ups or buffers.
The only other parts are a power LED and its 470 ohm resistor. The manual is in
[`vendors/saiko_systems_ltd/`](vendors/saiko_systems_ltd/ST-SD-USDV2.0_cea6be.pdf),
with the schematic on PDF page 9.

J2's pinout, read from that schematic. **Confirm it with a continuity meter
before wiring.**

| J2 pin | Signal | DISCO pin |
| ------ | ------ | --------- |
| 1      | D1     | `PC9`, used as I2C3 SDA |
| 2      | D0     | `PC8`     |
| 3      | GND    | GND       |
| 4      | CLK    | `PC12`    |
| 5      | +3V3   | The microSD slot's supply |
| 6      | CMD    | `PD2`     |
| 7      | D3     | `PC11`    |
| 8      | D2     | `PC10`    |
| 9      | SD_CD  | J1's card detect; not connected |
| 10     | SD_WP  | J1's write protect; not connected |

ATECC608 breakout connections:

| Breakout | Connects to |
| -------- | ----------- |
| SDA      | Adapter J2 pin 1 (`PC9`) |
| SCL      | CN7 pin 3, Arduino D10 (`PA8`) |
| GND      | Adapter J2 pin 3, or CN6 pin 6 |
| 3.3 V    | CN6 pin 4 |

- **Pull-ups:** I2C needs one on each line. The DISCO has only a weak 47 kohm
  pull-up on `PC9` (B-04 schematic, page 5) and none on `PA8`, so they come
  from the breakout. If it has none, add 4.7 kohm resistors to 3.3 V.
- **Power:** take 3.3 V from CN6 rather than J2 pin 5, which depends on how the
  DISCO powers its microSD slot.
- **CubeMX:** move the ATECC608 from I2C2 (`PF0`, `PF1`) to I2C3 (`PA8`, `PC9`)
  in Slice 8, and leave SDMMC1 off. Neither pin is used by anything else in the
  project; QSPI's `IO0` is on `PD11`.

Other CAN pins on this chip, and why they aren't used:

| CAN pins               | Connected to on this board      | Why not                                 |
| ---------------------- | ------------------------------- | --------------------------------------- |
| CAN1: PA11, PA12       | USB FS connector CN13           | Fallback; see below                     |
| CAN1: PD0, PD1         | SDRAM data lines                | No header access                        |
| CAN1: PI9, PH13        | LCD VSYNC, camera power enable  | Used by on-board parts; no header pins  |
| CAN2: PB5, PB6         | USB HS PHY, QSPI chip select    | PB6 is needed for QSPI                  |
| CAN2: PB12, PB13       | USB HS PHY                      | PHY shares the lines; no header access  |

**Fallback:** PA11 and PA12 reach CN13 through a USB filter chip (U18), so CAN
could use a micro-USB breakout, which would leave I2C1 free for the ATECC608. It
needs USB FS disabled and VBUS left unconnected, and CAN through that filter is
untested.

Data flow: CANopen IO module -> CAN -> STM32 -> encrypted Ethernet -> daemon on
the Pi 5.

Demo: flip an input on the CANopen module and see the state change at the
ground station. A ground-station command sets a module output over the link,
so a replayed command is visibly rejected.

Crypto:

- **Boot signing:** Ed25519, with the private key kept off the board.
- **Session keys:** ephemeral X25519.
- **Traffic:** ChaCha20-Poly1305.
- **Device identity:** P-256, with the key on the ATECC608. The Pi verifies it
  in Python.
- **Ground station identity:** Ed25519 in software on the Pi. The STM32 verifies
  it with Monocypher, so the STM32 needs no P-256 code of its own.

Interfaces shown:

| Interface | Where                                          |
| --------- | ---------------------------------------------- |
| CAN       | STM32 to the CANopen module                    |
| QSPI      | STM32 to on-board flash, for the update slots  |
| I2C       | STM32 to the ATECC608; Pi to the IMU (optional driver) |
| UART      | STM32 console, via the ST-LINK virtual COM port |

## Ground station daemon

One Python program on the Pi 5 (`asyncio` and `cryptography`) that holds the
keys, prints the stream and takes commands. There is no GUI.

Terminal stream:

```text
12:04:31.500 seq=1042 age=8ms   DI 0-7: 1 0 0 1 0 0 0 0  DO 0-3: 0 1 0 0  module=OK
12:04:33.502 seq=1046 STALE age=1502ms  (2 frames missed)  link=DOWN
```

Soft realtime rules, checked by the hardware tests:

- **Period:** the STM32 sends a state frame every 500 ms, with a sequence number
  and its own timestamp. It polls the module faster, about every 100 ms.
- **Late:** a frame is flagged after 750 ms.
- **Stale:** after 1.5 s, the display says STALE rather than showing old values
  as current.

Link and commands:

- **Transport:** UDP, because only the newest state frame matters and TCP would
  retransmit old ones after a dropout.
- **Commands:** typed as `set DO2 1`. They set a state rather than toggling, and
  carry a command ID that the STM32 acknowledges, so a lost command can be
  retried safely.
- **Firmware updates (Slice 7):** the daemon sends an authenticated
  `update` command over the encrypted link, which turns on the STM32's TFTP
  server. The Pi then sends the signed image with `tftp put`. The STM32 writes
  it to the inactive QSPI slot, turns TFTP off again and restarts into the
  bootloader, which verifies and installs it. See
  [peripheral_ETH.md](documentation/peripheral_ETH.md#loading-firmware-images-with-tftp).

The CANopen module and the outputs' behavior on link loss are still open; see
[TODO.md](TODO.md#hardware).

## Status at a glance

| Slice | Week of          | Focus                                   | Working days | Status      |
| ----- | ---------------- | --------------------------------------- | ------------ | ----------- |
| -     | Nov 2 to Nov 6   | CubeMX configuration, MPU, design docs  | -            | Done        |
| 1     | Nov 26           | Bring-up and CAN smoke test             | 2            | Not started |
| 2     | Nov 30           | Unencrypted end-to-end                  | 3            | Not started |
| 3     | Dec 7            | Secure link and link attacks            | 3 to 4       | Not started |
| 4     | Dec 14           | Signed boot; **core milestone Dec 18**  | 3            | Not started |
| 5     | Dec 21           | CANopen                                 | 2            | Not started |
| -     | Dec 28           | Off or catch-up                         | -            | -           |
| 6     | Jan 4            | QSPI A/B slots and recovery             | 3            | Not started |
| 7, 8  | Jan 11           | TFTP updates, ATECC608 device identity  | 3.5          | Not started |
| 9     | Jan 18           | Docs and video                          | 2            | Not started |

## Ground rules

- **Never set readout protection (RDP) to level 2.** It is irreversible and
  bricks debug access for good. Level 1 is the highest level to use.
- Keep the test board at RDP level 0. At level 1, flash is locked once a
  debugger connects, which breaks J-Link flashing and probably RTT. Going back
  to level 0 mass-erases the flash, so test level 1 manually as a separate step.

## Materials

### Core hardware (STM32F746G-DISCO already owned)

- [x] STM32F746G-DISCO board (owned): Cortex-M7 at 216 MHz, 1 MB flash, 16 MB
  QSPI flash, Ethernet, 4.3" touch screen. No TrustZone and no hardware
  crypto.
- [x] Type-A to mini-B USB cable for the board's ST-LINK port (CN14).
- [x] Ethernet cable, connecting the Pi 5 and the STM32 directly with static
      IPs.
- [x] Raspberry Pi 5 (owned): the "ground station", running Raspberry Pi OS.
- [x] microSD card and power supply for the Pi 5.
- [x] Reflash the on-board ST-LINK with SEGGER's J-Link firmware, for flashing,
      RTT and SystemView over one USB cable. Done Nov 4: it shows as `J-Link
      STLink` (firmware V21), and J-Link Commander connects over SWD and
      identifies the Cortex-M7. Flashing, RTT and SystemView aren't tested yet.
      The J-Link Base (owned) isn't needed unless this fails.
- [ ] At least two ATECC608 secure-element breakouts on I2C (Adafruit #4314 or
  SparkFun Qwiic ATECC608A). Supports P-256 only. Locking is permanent, so a
  configuration mistake can use up a chip.
- [ ] Saiko Systems ST-SD-uSDv2.0 SD-to-microSD adapter (Digi-Key
  3457-ST-SD-USDV2.0-ND), to bring `PC9` out of the microSD slot for the
  ATECC608's SDA, plus a 10-pin 0.1" header to solder to its J2. See [ATECC608
  wiring](#atecc608-wiring).
- [x] Breadboard, male-to-male and male-to-female jumper wires, 4.7 kohm
  pull-up resistors.
- [x] I2C IMU (owned), wired to the Pi 5 only for the optional kernel driver.
      3.3 V logic only.
- [x] One red LED, one green LED and two series resistors, to show which
      firmware version is running. They use two spare general-purpose outputs,
      PI3 (D7) and PI2 (D8).
- [x] A cheap logic analyzer (8-channel Saleae clone).
- [x] CAN transceivers and CANopen IO module (owned). Still needs: 3.3 V logic
      confirmed on the transceivers, 120 ohm terminators as required, and power
      for the module. CAN1 is on CN7 pins 9 and 10; see [Pin
      assignments](#pin-assignments).

### Software and tools (all free)

- VS Code as the main editor, with GNU Make, Ubuntu's `gcc-arm-none-eabi`
  compiler, and STM32CubeMX for pin, clock and code generation.
- `tools/embedded_dev_tooling` (Git submodule, private repo) installs and pins
  the compiler, CubeMX and SEGGER tools with `toolchain.sh`. Tools are found
  through `PATH`, so the firmware build must not depend on files inside the
  submodule.
- ST's F746G-DISCO examples and BSP as the starting point for Ethernet with lwIP
  and for QSPI.
- SEGGER J-Link Software Pack, Ozone debugger, RTT for logging, and
  SystemView for RTOS tracing.
- FreeRTOS (via STM32Cube or standalone), lwIP for Ethernet, Monocypher as the
  only STM32 crypto library, CryptoAuthLib for the ATECC608, and a small custom
  bootloader.
- Raspberry Pi OS for the ground station, plus kernel headers for the optional
  driver.
- Unity or GoogleTest, pytest, GitHub Actions.
- Python with the `cryptography` library for signing tools and the daemon.
- Wireshark for inspecting the Ethernet link.

### Build layout

Our makefiles build everything. CubeMX's generated Makefile in
`kepler_demo_stm32f746g-disco/` is never run by us: `mk/cube.mk` includes it to
read its file lists and chip flags, so regenerating can't undo our build
settings. See [build_system.md](documentation/build_system.md). The bootloader
makefiles and signing are planned; the rest exists since Nov 27.

```text
Makefile          # make, make flash, make size, make clean
mk/cube.mk        # reads the generated Makefile's files and flags
mk/common.mk      # shared compiler flags and rules
app/Makefile      # the application
stage1/Makefile   # planned: the bootloader programs
stage2/Makefile
kepler_demo_stm32f746g-disco/
                  # CubeMX output: HAL, startup code, generated Makefile
vendors/          # third-party source kept in this repo, including RTT
tools/debug/      # flash script and Ozone project
```

See [system_boot.md](documentation/system_boot.md) for what the three programs
do.

## How the schedule works

The work is split into seven slices. Each slice builds one feature all the way
through, and ends with something that works, its tests, and a recorded video
clip. The final video is assembled from those clips.

Slices are sized in working days, and each gets a calendar week, so a week with
only two or three working days doesn't break the plan. The estimates add up to
about 22 working days, at roughly 3 to 4 days a week.

Rules:

- **Finish each slice before starting the next.** A half-done slice has no demo
  value.
- **Record the clip on the day a slice works,** while the setup is still on the
  bench.
- **When a week runs short, push the remaining slices back.** Don't squeeze two
  slices into one week.
- **After a gap of more than a week, re-plan** and add a change log entry.
- **Apply once the core milestone is reached** (Dec 18), rather than waiting for
  the end date. The later slices improve the demo and can be mentioned as work
  in progress.

## Done so far (Nov 2 to Nov 6)

- [x] Reflash the on-board ST-LINK with J-Link firmware. Done Nov 4: J-Link
      Commander connects over SWD. Flashing, RTT and SystemView aren't tested.
- [x] Set up the Git repo and the `embedded_dev_tooling` submodule.
- [x] Check on paper that the CAN pins are reachable and whether they clash with
      I2C. They are reachable and they do clash; see [Pin
      assignments](#pin-assignments). LED pins chosen.
- [x] Do the hardware setup in CubeMX and generate the code. Done Nov 4 to 6: it
      builds with no warnings, but hasn't run on the board. Settings are in
      [core_cortexM7.md](documentation/core_cortexM7.md),
      [core_NVIC.md](documentation/core_NVIC.md),
      [core_oscillators.md](documentation/core_oscillators.md),
      [middleware_RTOS.md](documentation/middleware_RTOS.md),
      [middleware_LWIP.md](documentation/middleware_LWIP.md),
      [peripheral_CAN.md](documentation/peripheral_CAN.md),
      [peripheral_ETH.md](documentation/peripheral_ETH.md),
      [peripheral_QSPI.md](documentation/peripheral_QSPI.md),
      [peripheral_UART.md](documentation/peripheral_UART.md) and
      [peripheral_GPIO.md](documentation/peripheral_GPIO.md).
- [x] Set up the MPU. Done Nov 6: regions 1 to 6 in CubeMX, and the MemManage
      and HardFault handlers save the fault registers. See
      [MPU](documentation/core_cortexM7.md#mpu). The violation tests are in
      Slice 1.

## Slice 1 (week of Nov 26): Bring-up and CAN Smoke Test

**Estimate:** 2 working days. **Status:** In progress (Nov 26)

**Done when:** the board runs our code, and you know whether CAN works.

- [ ] Order at least two ATECC608 breakouts and the ST-SD-uSDv2.0 adapter
      (Nov 26), the parts still unticked under [Materials](#materials). They're
      needed in Slice 8, and shipping is the biggest schedule risk.
- [x] Decide how the ATECC608 connects. Decided Nov 26: I2C3 on `PA8` and
      `PC9`, through the microSD adapter. See [ATECC608
      wiring](#atecc608-wiring).
- [x] Make the two remaining code fixes in [TODO.md](TODO.md#finish-the-setup):
      the FreeRTOS hook bodies and the `EthIf` stack. Done Nov 26.
- [x] Confirm the tools with `toolchain.sh verify`. Done Nov 26: every tool in
      `stm32.conf` matches.
- [x] Flash with `flash.jlink` and check that LD1 blinks at 1 Hz. Done Nov 26:
      the script works and LD1 blinks. It's now `tools/debug/flash_app.jlink`,
      run with `make flash`. See
      [tools/debug/README.md](tools/debug/README.md).
- [x] Get the RTT source into the repo, because CI can't see
      `~/.embedded-tools`. Done Nov 27: git submodules of SEGGER's GitHub
      repos, RTT at `vendors/segger/rtt/` (V8.58.0) and SystemView at
      `vendors/segger/systemview/` (V4.10).
- [x] Add our own `Makefile`, `mk/common.mk` and `app/Makefile` around the
      generated project, with `-Wl,--print-memory-usage` in the link flags.
      Done Nov 27, plus `mk/cube.mk`, which reads the generated Makefile's
      file lists. The flash image is byte-for-byte identical to CubeMX's
      build. See [build_system.md](documentation/build_system.md).
- [x] Trace and log with SEGGER SystemView, with RTT as its transport. Done
      Nov 27: FreeRTOS events, eight traced interrupts, `LOG()` messages,
      heap plots and the `git describe` version, recorded on the board from
      boot, with no overflows during a ping. A ping takes about 210 µs on the
      board. See [tracing_systemview.md](documentation/tracing_systemview.md).
- [ ] Check the MPU on the board: a normal boot first, then the deliberate
      violation tests in a debug build. The normal boot passed Nov 26: LD1
      blinks, all eight threads run, and `fault_record` is all zeros. See
      [Tests](documentation/core_cortexM7.md#tests).
- [x] Send a line out of the UART and confirm it arrives on `/dev/ttyACM0`.
      Done Nov 27: a polled boot line from `defaultTask` arrives at 115200
      8N1, after flashing and after a reset. See
      [peripheral_UART.md](documentation/peripheral_UART.md).
- [ ] CAN smoke test (timebox: 2 hours): confirm the transceiver has 3.3 V
      logic, note the module's bitrate, node ID, supply voltage and
      termination, and exchange one frame with it. Use the logic analyzer on TX
      and RX if it fails. Record the result in the notes; it decides Slice 5.

**Notes:**

## Slice 2 (week of Nov 30): Unencrypted End-to-End

**Estimate:** 3 working days. **Status:** Not started

**Done when:** a button press shows on the Pi, and the `set` command drives an
LED. Record a clip.

The blue button (`PI11`) is the input and the red and green LEDs are the
outputs, so this slice doesn't depend on CAN.

- [ ] Write the application threads, connected by queues. CubeMX generates their
      creation code:
  - `defaultTask`: starts lwIP and the other threads, then exits or idles.
  - `canOpenTask`: reads the inputs and applies output commands. It reads the
    button and drives the LEDs until Slice 5 adds CANopen.
  - `linkTask`: telemetry / command framing, and owns the UDP socket and (from
    Slice 3) the session keys.

  See [middleware_RTOS.md](documentation/middleware_RTOS.md) for stack sizes and
  priorities.
- [ ] Add an ISR-driven UART console with DMA on the virtual COM port. The data
      cache stays off, so DMA buffers need no cache maintenance; see
      [peripheral_ETH.md](documentation/peripheral_ETH.md#caches).
- [ ] Define a binary telemetry packet format, with no CRC on the link, because
      the AEAD tag will detect corruption. Write host-side unit tests for
      encode/decode.
- [ ] Bring up UDP over lwIP from ST's example, with static IPs (STM32
      10.1.1.123, Pi 10.1.1.1) and a direct cable to the Pi 5. Leave the
      Ethernet buffers where the linker puts them for now; see [Memory
      placement](documentation/peripheral_ETH.md#memory-placement).
- [ ] Write the first version of the daemon, unencrypted: the 500 ms terminal
      stream and the `set` command.

**Notes:**

## Slice 3 (week of Dec 7): Secure Link and Link Attacks

**Estimate:** 3 to 4 working days. **Status:** Not started

**Done when:** replay, bit-flip and man-in-the-middle attacks fail visibly, and
Wireshark shows only ciphertext. Record clips.

- [ ] Implement the handshake, following a published signed-ephemeral pattern
      (SIGMA-I, the approach behind the TLS 1.3 handshake): ephemeral X25519 key
      exchange, with each side signing to prove its identity using
      pre-provisioned keys. Then ChaCha20-Poly1305 with sequence numbers for
      replay protection.
- [ ] Use the hardware RNG for keys and check its error flags. Derive each AEAD
      nonce from the sequence number and never repeat one.
- [ ] Put device identity signing behind a small interface, and use a software
      Ed25519 test key, so the ATECC608 can be swapped in in Slice 8.
- [ ] Add encryption and authentication to the daemon, and carry the `set`
      command over the encrypted link.
- [ ] Add security counters to telemetry and show them in the terminal stream
      (0.5 day): bad tags, replays and failed handshakes.
- [ ] Add crypto test coverage (0.5 day): published test vectors (RFC 8439, RFC
      7748, RFC 8032), nonces never repeating, and an injected RNG error
      stopping key generation.
- [ ] Build the attacker tool on the Pi 5 (0.5 day): one Python UDP proxy
      between the STM32 and the daemon, with `replay`, `flip-bit` and
      `swap-key` modes.
- [ ] Build the link attack demos as pytest tests (0.5 day): the link rows in
      [Security demos](#security-demos). Capture with `tcpdump` on the Pi and
      view the result in Wireshark on the laptop.
- [ ] GitHub Actions (0.5 day): build the firmware in a container pinned to the
      same compiler version as local (13.2.1), and run the host unit tests with
      `make test`. CI doesn't check out the private submodule.

**Notes:**

## Slice 4 (week of Dec 14): Signed Boot

**Estimate:** 3 working days. **Status:** Not started

**Done when:** tampered and old images are refused, and the LEDs show the
running version. Record clips. **This completes the core milestone (Dec 18).**

One bootloader checks the application in internal flash. Images are loaded with
the J-Link, so this slice doesn't need QSPI.

- [ ] Design the internal flash layout: the bootloader and the application (1
      MB, single bank, uneven sectors).
- [ ] Add the bootloader's Makefile and linker script, so the build produces it
      and the application.
- [ ] Write the bootloader: verify an Ed25519 signature on the application image
      with Monocypher before jumping to it. Give it its own MPU setup, and turn
      the MPU off before jumping. The application sets `VTOR` to its own vector
      table at `0x08040000`.
- [ ] Add a version counter so an old signed image cannot be reinstalled. Store
      it in the F7's 1 KB OTP area (per RM0385), or state the limit in the
      threat model.
- [ ] Write the signing script in Python.
- [ ] Add the version LEDs to the application: v1 blinks red and v2 blinks
      green, set by build flags (`make app VERSION=1 LED_COLOR=RED`). See
      [system_boot.md](documentation/system_boot.md) for the expected result at
      each demo step.
- [ ] Build the boot attack demos as tests (0.5 day): flipped byte, wrong
      signing key and old signed image. See [Security demos](#security-demos).
- [ ] Protect the bootloader with flash write-protection, the MPU and readout
      protection level 1, and test what each one stops, as a separate manual
      step. **Never use readout protection level 2: it is irreversible.**
- [ ] Move `fault_record` to RAM that survives reset, and log the reset reason.

**Notes:**

## Slice 5 (week of Dec 21): CANopen

**Estimate:** 2 working days, timeboxed. **Status:** Not started

**Done when:** a CANopen module input shows on the Pi, and `set` drives a module
output. Record a clip. Skip this slice if the Slice 1 smoke test failed and the
CN13 fallback doesn't help either.

- [ ] Add a minimal hand-written CANopen master on the STM32: NMT start, SDO
      polling of the module's inputs, and heartbeat monitoring. Report module
      state in telemetry, including an unplugged module or a lost heartbeat.
- [ ] Switch `canOpenTask` from the button and LEDs to the module.

**Notes:**

## Week of Dec 28: Off or Catch-up

No slice is planned this week.

## Slice 6 (week of Jan 4): QSPI A/B Slots and Recovery

**Estimate:** 3 working days. **Status:** Not started

**Done when:** a new image in the inactive slot is verified and installed, and a
signed image that never confirms itself makes the board fall back to the last
good one. Record a clip.

- [ ] Get the QSPI flash working with ST's BSP: erase and write in indirect
      mode, then read back a test pattern in memory-mapped mode (which is
      read-only). Confirm the chip with READ ID. Memory-mapped reads use MPU
      region 2; see [MPU](documentation/core_cortexM7.md#mpu).
- [ ] Lay out slot A, slot B and the update metadata in the 16 MB QSPI flash.
- [ ] Extend the bootloader: pick the slot to boot, verify the image there, copy
      it into internal flash, and verify the copy. The bootloader's MPU setup
      makes internal flash writable for the copy.
- [ ] Add the confirm step: a new application must confirm itself as good, or
      the bootloader restores the last good image from the other slot at the
      next reset.
- [ ] Load test images into the slots with the J-Link until Slice 7.
- [ ] Add the A/B recovery demo as a test: a signed image that never confirms
      itself. See [Security demos](#security-demos).

**Notes:**

## Slice 7 (week of Jan 11): Firmware Updates over TFTP

**Estimate:** 1.5 working days. **Status:** Not started

**Done when:** the ground station sends a signed image over TFTP, and the board
installs and runs it. Record a clip.

- [ ] Add the authenticated `update` command to the encrypted link and the
      daemon. It turns the TFTP server on, and the server turns off again after
      one transfer or a timeout.
- [ ] Write the TFTP callbacks: refuse reads, refuse any mode but `octet`, write
      each block to the inactive slot, then check the length and hash at close
      and report them over the link. See [lwIP's TFTP
      server](documentation/peripheral_ETH.md#lwips-tftp-server).
- [ ] Mark the update pending and restart into the bootloader, which verifies
      and installs it.
- [ ] Add the "Update gate" demo as a test: `tftp put` with no `update` command
      first gets no reply. See [Security demos](#security-demos).

**Notes:**

## Slice 8 (week of Jan 11): ATECC608 Device Identity

**Estimate:** 2 working days. **Status:** Not started

**Done when:** the handshake is signed by a key generated on the ATECC608, and
reading that key's slot is refused while the chip can still sign. Record a clip.

- [ ] Check the adapter's pinout with a continuity meter, then wire the
      ATECC608 as in [ATECC608 wiring](#atecc608-wiring). Move it from I2C2 to
      I2C3 (`PA8`, `PC9`) in CubeMX, and regenerate.
- [ ] Port CryptoAuthLib and read the chip's serial number.
- [ ] Write down the configuration, then generate a P-256 key on the chip and
      lock it as non-readable. **Locking is permanent**, so try it on the spare
      chip first.
- [ ] Swap the device identity from the Slice 3 software test key to the
      ATECC608, behind the same interface. The Pi verifies the P-256 signature.
- [ ] Add the key-read demo as a test: reading the private key slot is refused,
      while the chip can still produce a valid signature. See [Security
      demos](#security-demos).

**Notes:**

## Slice 9 (week of Jan 18): Docs and Video

**Estimate:** 2 working days. **Status:** Not started

**Done when:** the video is recorded and the README is complete. **End date:
Fri Jan 22, 2027.**

- [ ] Add a scripted demo runner and a README table of feature, attack, expected
      result and test link (0.5 day).
- [ ] Finish the README and the docs in `documentation/`: architecture diagram,
      flash layout, design notes, test results, and lessons learned. Bring the
      threat model up to date (see [TODO.md](TODO.md#threat-model)). It must
      state this board's limits: any running code can ask the ATECC608 to sign,
      session keys sit in RAM without isolation, RDP level 1 can be defeated in
      a lab, the I2C wires can be sniffed or spoofed unless protected, and one
      bootloader can't itself be safely updated.
- [ ] Assemble a 3 minute demo video from the slice clips: an input change at
      the ground station, an output set by command, a firmware update sent from
      the ground station over TFTP, a failed update falling back to the last
      good image, the ATECC608 refusing to give up its key, tampered and old
      images refused (with the LEDs showing the running version), Wireshark
      showing only ciphertext, a replayed command rejected, and a
      man-in-the-middle handshake failing.

**Notes:**

## Not scheduled

These are cut from the current schedule. Add them back only if every slice is
done early:

- Two bootloader stages: an immutable stage 1 that verifies stage 2. One
  bootloader can't itself be safely updated.
- The kernel driver and device tree overlay for the IMU on the Pi.
- SystemView tracing, except when needed for debugging.
- Static analysis in CI (cppcheck or clang-tidy).
- Hardware-in-the-loop tests beyond the attack demos, and fault injection for a
  dropped link or lost module.

If slices run late, cut Slice 5 first (the button and LEDs stay as the I/O),
then Slice 7 (images are loaded with the J-Link), then Slice 8 (the software
test key stays, and the threat model states it), then Slice 6.

## Security demos

Each crypto feature gets an attack demo that doubles as a hardware test, so
fault injection, test evidence and the video share the same scripts. Demos use
scripted runs, and the on-path attacker is a controlled setup in which the STM32
is pointed at the attacker tool on the Pi 5, which forwards to the daemon.

| Feature                 | Attack                                                | Expected result                               | Built in |
| ----------------------- | ----------------------------------------------------- | --------------------------------------------- | -------- |
| Signed boot             | Flip an image byte; wrong signing key                 | Boot refused, reason shown on RTT             | Slice 4  |
| Rollback counter        | Install v2, then a correctly signed v1                | v1 refused as too old                         | Slice 4  |
| A/B recovery            | Install a signed image that never confirms            | Board reverts to the last good image          | Slice 6  |
| ATECC608 key protection | Read the private key slot                             | Read refused; chip can still sign             | Slice 8  |
| Update gate             | `tftp put` an image with no `update` command first    | No reply: the TFTP server is off, slots untouched | Slice 7 |
| AEAD confidentiality    | Capture traffic while toggling an input               | No readable state; same state differs on wire | Slice 3  |
| AEAD integrity          | Flip one bit of a `set` command                       | Rejected, output unchanged, counter goes up   | Slice 3  |
| Replay protection       | Set DO2 to 0, then resend a captured "DO2 = 1"        | DO2 stays 0, counter goes up                  | Slice 3  |
| Man-in-the-middle       | Swap the X25519 public key in transit                 | Signature check fails, no session is set up   | Slice 3  |

The boot demos also show the result on the red and green version LEDs. Covered
by tests rather than live demos: algorithm test vectors, nonces never repeating,
and RNG error handling. Forward secrecy is a design property, stated in the
README without a demo.

Guardrails:

- Never log key material, even in debug builds.
- Keep the test key and debug paths out of the release build.
- Say clearly in the video which demos use the test key.

### Development time

These are working-day estimates, and they assume full days on the project.

| Work                              | When              | Estimate         |
| --------------------------------- | ----------------- | ---------------- |
| Security counters in telemetry    | Slice 3           | 0.5 day          |
| Test vectors, nonce and RNG tests | Slice 3           | 0.5 day          |
| Attacker tool                     | Slice 3           | 0.5 day          |
| Link attack demos                 | Slice 3           | 0.5 day          |
| Boot attack demos                 | Slice 4           | 0.5 day          |
| A/B recovery demo                 | Slice 6           | 0.25 day         |
| Update gate demo                  | Slice 7           | 0.25 day         |
| ATECC608 key-read demo            | Slice 8           | 0.25 day         |
| Demo runner and README table      | Slice 9           | 0.5 day          |
| **Total**                         |                   | **About 3 days** |

## Priorities if time gets tight

1. Encrypted and authenticated link with replay protection.
2. Signed bootloader with rollback.
3. Automated hardware tests and CI.
4. CANopen input and output on the STM32.
5. Optional: kernel driver and device tree overlay on the Pi (Raspberry Pi OS).

## Out of scope

Removed to save time. The first two mean those posting items go unshown or only
partly shown:

- **Yocto:** low-level Linux is shown only if the optional driver gets built.
- **Hardware tests run by GitHub Actions:** hardware tests are still automated
  with local pytest, and CI still runs builds, unit tests and static analysis.
- **Others:** NUCLEO-H563ZI port, Verilog/HDL, GUI, MCUboot, mbedTLS, Pi 4,
  classic SPI, CMake and Ninja, and Pi-side CAN.

## Résumé framing

One line to use, adjusted to match what actually gets built:

> Designed a secure telemetry system on STM32 with FreeRTOS, signed two-stage
> A/B bootloader over QSPI flash, X25519 plus AEAD link encryption with an
> ATECC608-backed device identity, CANopen I/O over CAN, an Ethernet-linked
> Linux ground station, and automated hardware-in-the-loop testing.

If the optional driver gets built, add "a custom I2C kernel driver and device
tree overlay". Don't claim it otherwise. The posting requires this experience,
so if it's skipped, say plainly that kernel work is something to grow into.

When applying, use the posting's title: "Embedded Software Designer".

## Change log

- **Nov 27, 2026:** The UART works: a polled boot line from `defaultTask`
  arrives on `/dev/ttyACM0` through the J-Link's virtual COM port.
- **Nov 27, 2026:** Chose SEGGER SystemView over plain RTT logging, for its
  timeline of threads and interrupts, and added it: FreeRTOS trace hooks,
  eight traced interrupts, `LOG()` messages, heap plots, timing markers and
  the `git describe` version. `make FW_SYSVIEW=0` removes it all. SEGGER's
  FreeRTOS kernel patch isn't used, because it doesn't fit V10.2.0 or the
  Cortex-M7 port. Recorded on the board the same day. Starting the recording
  in the firmware lets SystemView show start-up; it has to wait until the
  scheduler runs, because an earlier start stopped the board.
- **Nov 27, 2026:** Added our own makefiles: a top-level `Makefile`,
  `mk/cube.mk`, `mk/common.mk` and `app/Makefile`, with output in `build/app/`.
  They read the CubeMX Makefile's file lists instead of copying them, so the
  build layout no longer says "hand-written". The flash image matches CubeMX's
  byte for byte. Moved the flash script and Ozone project to `tools/debug/`,
  added SEGGER RTT (V8.58.0) and SystemView (V4.10) as git submodules under
  `vendors/segger/`, replacing a copied-in RTT, and decided to make the whole
  repo public, with the copyright review deferred.
- **Nov 26, 2026:** Started Slice 1. Filled in the FreeRTOS stack overflow and
  malloc-failed hooks, raised the `EthIf` stack from 350 to 1024 bytes, made
  `defaultTask` blink LD1 at 1 Hz as a heartbeat, and added `flash.jlink` and
  [build_system.md](documentation/build_system.md). `toolchain.sh verify`
  passes. The first J-Link session connected, but `loadfile` failed on a wrong
  path. The earlier build still on the board answered 483 pings with no loss,
  at 2 to 5 ms with spikes up to 216 ms, from a host on Wi-Fi. Flashing with
  `flash.jlink` then worked, and LD1 blinks: the first run of our own build.
  From a wired host it answers pings in 0.54 ms on average, with no loss.
- **Nov 26, 2026:** Chose the ATECC608 wiring: I2C3, with SCL on `PA8` (D10)
  and SDA on `PC9` through a Saiko Systems ST-SD-uSDv2.0 adapter in the microSD
  slot. Added the adapter to Materials and its pinout and the wiring to Pin
  assignments. The CubeMX change waits for Slice 8.
- **Nov 26, 2026:** Put the ATECC608 back in as Slice 8 (week of Jan 11, after
  TFTP). Docs and video become Slice 9, and the end date moves to Jan 22, 2027.
  Slice 1 now orders the parts and decides the I2C wiring. The core milestone
  stays Dec 18.
- **Nov 26, 2026:** Put QSPI A/B slots with recovery (Slice 6) and TFTP updates
  (Slice 7) back into the schedule. Docs and video become Slice 8, and the end
  date moves to Jan 15, 2027. The core milestone stays Dec 18. The ATECC608,
  which was the other Slice 6 option, is now not scheduled.
- **Nov 26, 2026:** Relaxed the schedule, because work won't happen every day.
  The end date is now Jan 8, 2027, with a core milestone on Dec 18: the
  encrypted link, link attacks and signed boot, recorded. Replaced the four
  phases with seven slices, each built end to end and ending with a recorded
  clip, sized in working days with a calendar week each. The button and LEDs
  are the I/O until CANopen in Slice 5, after a 2-hour CAN smoke test in Slice
  1. Signed boot uses one bootloader and internal flash only. QSPI A/B slots and
  the ATECC608 are a choice of one in Slice 6. Two bootloader stages, TFTP,
  the kernel driver, SystemView, static analysis and wider hardware tests are
  not scheduled. This replaces the Dec 12 plan from earlier the same day.
- **Nov 26, 2026:** Moved the deadline from Dec 2 to Dec 12 after a pause from
  Nov 7 to Nov 25 with no progress. Replaced the four weeks with four phases:
  bring-up (Nov 26 to 30), secure link (Dec 1 to 4), bootloader (Dec 5 to 8),
  and tests, docs and video (Dec 9 to 12). The link now comes before the
  bootloader, matching the priorities. The ATECC608 is now optional in Phase 2,
  and two bootloader stages and TFTP are "if on schedule" in Phase 3. CAN has a
  1-day timebox, with the button and LEDs as stand-in I/O. Added a cut order.
- **Nov 5, 2026:** Planned the full MPU setup for Week 1 instead of adding
  regions as needed: QSPI registers and window, RAM with no execute, read-only
  flash, a null guard and a main stack guard, with MemManage fault reporting.
  The bootloader stages' MPU setup stays in Week 2. Threat model R12 is now a
  known limit, because every thread runs privileged.
- **Nov 5, 2026:** Added TFTP firmware updates outside the Week 3 task: in the
  architecture diagram, the daemon's link section, the security demos (the
  "Update gate" test) and the demo video. Enabled lwIP's TFTP server in CubeMX.
- **Nov 5, 2026:** Configured in CubeMX: the UART (USART1 on PA9 and PB7), the
  red and green LEDs on PI3 and PI2, the user button on PI11, HSE in bypass
  mode, QSPI flash size, clock and chip select time, the 48 MHz RNG clock, the
  FreeRTOS overflow and malloc-failed checks, and a 4096-byte `tcpip_thread`
  stack. Confirmed the board is `MB1191-B-04` with the Micron N25Q128A flash,
  and added docs for QSPI, oscillators and lwIP. Switched the PLL to HSE,
  keeping 216 MHz, and restored CAN retransmission and bus-off. Re-enabled the
  CAN interrupts, which had been dropped. Still open, in TODO.md: the QSPI MPU
  region, the `EthIf` stack and the hook bodies.
- **Nov 5, 2026:** Moved outstanding questions and the remaining CubeMX settings
  into [TODO.md](TODO.md). Weekly tasks stay here.
- **Nov 4, 2026:** Rechecked after the latest CubeMX regeneration. QSPI pins,
  the 32,768-byte heap, CAN retransmission, bus-off and the RNG are now in the
  code. Found that the MPU region also blocks the QSPI registers, which should
  fault at startup, and made that the first Week 1 fix. Settled three items from
  RM0385 and the schematic: HSE needs bypass mode, the Ethernet DMA can reach
  DTCM, and 25 MHz is a legal RNG clock.
- **Nov 4, 2026:** Cross-checked the docs against the `.ioc`, generated code,
  linker map and UM1907. Added fixes to Week 1: wrong QSPI pins, HSI as the
  clock source, the RNG clock, and undersized lwIP stacks. Noted that the MPU
  blocks memory-mapped QSPI, and that the RX buffers don't fit in SRAM2, so
  their placement is now an open decision.
- **Nov 4, 2026:** Did the first pass of the CubeMX setup and regenerated the
  code: CAN1 on PB8 and PB9, TIM6 as the HAL time base, final interrupt
  priorities, thread stacks, instruction cache on, and LD1 on PI1 for the blink
  test. It builds with no warnings but hasn't run on the board. Added the
  remaining settings to Week 1, including a heap too small for the lwIP threads.
  Pointed the build layout at the real CubeMX folder.
- **Nov 4, 2026:** Reflashed the on-board ST-LINK with J-Link firmware and
  confirmed an SWD connection to the Cortex-M7. Flashing, RTT, SystemView and
  UART aren't tested yet.
- **Nov 3, 2026:** Turned the data cache off, so DMA needs no MPU regions or
  cache maintenance, and turned the instruction cache on. Revisit only if crypto
  is too slow.
- **Nov 3, 2026:** Chose TFTP for loading firmware images over the network, kept
  off until an authenticated command turns it on. Added a 1-day task to Week 3.
- **Nov 3, 2026:** Checked CAN access against the board schematic. CAN1 is
  reachable on PB8 and PB9 but clashes with I2C1, so the ATECC608 moves to I2C2
  on PF0 and PF1, which still needs a physical wiring route. Added pin
  assignments, a CAN fallback on CN13, and a Week 1 hardware test. CAN is not
  yet tested on hardware.
- **Nov 3, 2026:** Switched from CMake and Ninja to hand-written Makefiles
  alongside CubeMX's, and added the build layout. Added `embedded_dev_tooling`
  as a submodule, with tools found through `PATH`. Added red and green version
  LEDs on two spare outputs. Separate docs now live in `documentation/`, so
  they're no longer out of scope.
- **Nov 2, 2026:** Made the kernel driver and overlay optional: only after the
  video is recorded, timeboxed to 2 to 3 days, and first to skip if behind.
- **Nov 2, 2026:** Applied time savers: removed Yocto, the H563 port, GitHub-run
  hardware tests, the Pi 4, classic SPI and separate design docs. Switched to a
  custom bootloader and Monocypher only. Moved CANopen and an unencrypted
  end-to-end link into Week 1, and timeboxed the ATECC608. Trimmed the attack
  demos to eight and added the daemon design. The kernel driver now targets the
  I2C IMU.
- **Nov 2, 2026:** Added attack demos for each crypto feature, with development
  time in Weeks 2 to 4. Refocused the demo video on five attacks.
- **Nov 2, 2026:** Revised against the Kepler posting. Removed all Verilog/HDL
  work and Pi-side CAN. Added CANopen input, a required Pi kernel driver and
  overlay, and early CI. Made Yocto low priority, committed to the ATECC608 for
  device identity, reordered priorities, and corrected technical details (QSPI,
  RDP level 1 and CI, rollback counter, flash layout, nonces, handshake, cache,
  H563 crypto).
- **Nov 2, 2026:** Plan created from Florian's original 4-week outline. Added
  weekly checklists, ground rules and NUCLEO-H563ZI sourcing notes.

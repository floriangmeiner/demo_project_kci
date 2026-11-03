# STM32 Secure Telemetry Link: 4-Week Plan

**Window:** Nov 2 to Dec 2, 2026

**Status:** Week 1 in progress (last updated Nov 2, 2026)

**Approach:** minimize effort and maximize demo impact. Anything that doesn't
support the demo video or a stated requirement in the posting is a candidate to
cut.

## Goal

A portfolio project that mirrors the
[Kepler Embedded Software role](https://jobs.lever.co/kepler/accae2f6-7ffe-49a8-a485-ee9c13421c95):
an STM32 "spacecraft" running FreeRTOS with a secure bootloader and an encrypted,
authenticated link to a Linux "ground station", with automated hardware tests
and CI. A small kernel driver and device tree overlay on the Pi are optional.

The build uses the STM32F746G-DISCO board already owned (no TrustZone or
hardware crypto, so crypto runs in software), with the device identity key on
an ATECC608 secure element.

## Architecture

Hardware (power supplies not shown; the CAN pins are still to be confirmed in
UM1907):

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
    | I2C          | CAN TX/RX                         | I2C (optional)
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

Open questions:

- [ ] Which CANopen module is it, and how many DI and DO does it have? The plan
  assumes the standard CiA 401 I/O profile (inputs at `0x6000`, outputs at
  `0x6200`). Confirm this in the module's manual.
- [ ] What should the outputs do if the link drops? Default until decided: turn
  them off after a timeout.

## Status at a glance

| Week | Dates           | Focus                                   | Status      |
| ---- | --------------- | --------------------------------------- | ----------- |
| 1    | Nov 2 to Nov 8  | Foundations and unencrypted end-to-end  | In progress |
| 2    | Nov 9 to Nov 15 | QSPI and secure bootloader              | Not started |
| 3    | Nov 16 to 22    | Secure link and ATECC608                | Not started |
| 4    | Nov 23 to Dec 2 | Hardware tests, attacks, polish         | Not started |

## Ground rules

- **Never set readout protection (RDP) to level 2.** It is irreversible and
  bricks debug access for good. Level 1 is the highest level to use.
- Keep the test board at RDP level 0. At level 1, flash is locked once a debugger
  connects, which breaks J-Link flashing and probably RTT. Going back to level
  0 mass-erases the flash, so test level 1 manually as a separate step.

## Materials

### Core hardware (STM32F746G-DISCO already owned)

- [x] STM32F746G-DISCO board (owned): Cortex-M7 at 216 MHz, 1 MB flash, 16 MB
  QSPI flash, Ethernet, 4.3" touch screen. No TrustZone and no hardware
  crypto.
- [x] Type-A to mini-B USB cable for the board's ST-LINK port (CN14).
- [x] Ethernet cable, connecting the Pi 5 and the STM32 directly with static IPs.
- [x] Raspberry Pi 5 (owned): the "ground station", running Raspberry Pi OS.
- [ ] microSD card and power supply for the Pi 5.
- [ ] Reflash the on-board ST-LINK with SEGGER's J-Link firmware, for flashing,
  RTT and SystemView over one USB cable (check SEGGER's current terms and the
  revert steps first). The J-Link Base (owned) isn't needed unless this fails.
- [ ] At least two ATECC608 secure-element breakouts on I2C (Adafruit #4314 or
  SparkFun Qwiic ATECC608A). Supports P-256 only. Locking is permanent, so a
  configuration mistake can use up a chip.
- [ ] Breadboard, male-to-male and male-to-female jumper wires, 4.7 kohm
  pull-up resistors.
- [x] I2C IMU (owned), wired to the Pi 5 only for the optional kernel driver. 3.3 V
  logic only.
- [ ] A cheap logic analyzer (8-channel Saleae clone).
- [x] CAN transceivers and CANopen IO module (owned). Still needs: two
  reachable CAN pins on the Discovery board (check UM1907), 120 ohm terminators
  as required, and power for the module.

### Software and tools (all free)

- VS Code as the main editor, with CMake and Ninja, the Arm GNU Toolchain
  (arm-none-eabi), and STM32CubeMX for pin, clock and code generation.
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

## Week 1 (Nov 2 to Nov 8): Foundations and Unencrypted End-to-End

**Status:** In progress

- [ ] Order the remaining parts today: the secure elements, breadboard parts,
  microSD card, power supply and logic analyzer (shipping is the biggest schedule
  risk).
- [ ] Check in UM1907 that the CAN pins are reachable and whether they clash
  with I2C on the Arduino header (unverified). Note the CANopen module's
  bitrate, node ID, supply voltage and termination.
- [ ] Set up VS Code, the Arm GNU Toolchain, the SEGGER J-Link Software Pack
  and a Git repo.
- [ ] Generate the project with CubeMX into a CMake build; flash, blink an LED,
  and print logs over SEGGER RTT.
- [ ] GitHub Actions from the start: build firmware with a pinned Arm GNU
  Toolchain container and run host unit tests.
- [ ] Bring up FreeRTOS with SEGGER SystemView tracing to see task timing and
  ISR latency.
- [ ] Create three tasks: CANopen I/O polling, telemetry framing, and command
  handling. Use queues and an ISR-driven UART with DMA on the ST-LINK virtual COM
  port (confirm it works with the J-Link firmware). The Cortex-M7 data cache needs
  non-cacheable MPU regions or cache maintenance for DMA buffers.
- [ ] Define a binary telemetry packet format, with no CRC on the link, because
  the AEAD tag will detect corruption. Write host-side unit tests for
  encode/decode.
- [ ] Add a minimal hand-written CANopen master on the STM32: NMT start, SDO
  polling of the module's inputs, and heartbeat monitoring. Report module
  state in telemetry, including an unplugged module or a lost heartbeat.
- [ ] Bring up UDP over lwIP from ST's example, with static IPs and a direct
  cable to the Pi 5. Ethernet DMA descriptors and buffers need the same cache
  handling as UART DMA.
- [ ] Write the first version of the daemon, unencrypted: the 500 ms terminal
  stream and the `set` command, so the CAN-to-terminal path and the output command
  work end to end.

**Notes:**

## Week 2 (Nov 9 to Nov 15): Secure Bootloader

**Status:** Not started

- [ ] Get the QSPI flash working, using ST's BSP: erase and write in indirect
  mode, then read back a test pattern in memory-mapped mode (which is read-only).
- [ ] Design the flash layout: stage 1, stage 2 and the application in internal
  flash (1 MB, single bank, uneven sectors), and slot A, slot B and metadata in
  the 16 MB QSPI flash.
- [ ] Write the custom bootloader: verify an Ed25519 signature on the application
  image with Monocypher before jumping to it.
- [ ] Make it two-stage: a small stage 1 that never changes verifies stage 2,
  which verifies the application. Both stages share the verification code.
- [ ] Add A/B update with rollback if the new image fails to confirm itself:
  stage the new image in QSPI, verify it, then copy it into internal flash.
- [ ] Add a version counter so an old signed image cannot be reinstalled. Store
  it outside QSPI (F7 OTP, to be confirmed in RM0385, or the ATECC608's
  monotonic counter), or state the limit in the threat model.
- [ ] Write the signing script in Python.
- [ ] Build the boot attack demos as tests (0.5 day, by Nov 15): flipped byte,
  wrong signing key, tampered stage 2, old signed image, and an image that never
  confirms itself. See [Security demos](#security-demos).
- [ ] Protect stage 1 with flash write-protection, the MPU and readout
  protection level 1, and test what each one stops, as a separate manual step.
  **Never use readout protection level 2: it is irreversible.**
- [ ] Log reset reasons and hard faults to a persistent region.
- [ ] Use Ozone to debug the bootloader-to-app handoff and inspect fault
  registers.

**Notes:**

## Week 3 (Nov 16 to Nov 22): Secure Link and ATECC608

**Status:** Not started

- [ ] Implement the handshake, following a published signed-ephemeral pattern
  (SIGMA-I, the approach behind the TLS 1.3 handshake): ephemeral X25519 key
  exchange, with each side signing to prove its identity using pre-provisioned
  keys. Then ChaCha20-Poly1305 with sequence numbers for replay protection.
- [ ] Use the hardware RNG for keys and check its error flags. Derive each AEAD
  nonce from the sequence number and never repeat one.
- [ ] Put device identity signing behind a small interface and bring the link up
  with a software Ed25519 test key, so the ATECC608 can't block the link.
- [ ] Add encryption and authentication to the daemon, and carry the `set` command
  over the encrypted link.
- [ ] Add security counters to telemetry and show them in the terminal stream
  (0.5 day): bad tags, replays and failed handshakes.
- [ ] Add crypto test coverage (0.5 day): published test vectors (RFC 8439, RFC
  7748, RFC 8032), nonces never repeating, and an injected RNG error stopping
  key generation.
- [ ] Bring up I2C to the ATECC608 and port CryptoAuthLib, then move the device
  identity to it: generate a P-256 key on the chip and lock it as non-readable.
  Timebox this to 1 day after the link works on the test key; locking is
  permanent. If it overruns, ship the test key and state the limit in the threat
  model.
- [ ] Add the ATECC608 key-read demo (0.25 day): reading the private key slot is
  refused, while the chip can still produce a valid signature.

**Notes:**

## Week 4 (Nov 23 to Dec 2): Hardware Tests, Attacks, Polish

**Status:** Not started

- [ ] Hardware-in-the-loop tests with local pytest, run from the laptop: flash the
  board through the J-Link, read output over RTT, send commands over SSH to the
  daemon, and verify telemetry and the soft realtime limits.
- [ ] Fault injection: dropped link, CANopen module lost. Bad signatures,
  corrupted frames and replayed packets are covered by the security demos.
- [ ] Build the attacker tool on the Pi 5 (0.5 day, Nov 23): one Python UDP proxy
  between the STM32 and the daemon, with `replay`, `flip-bit` and `swap-key` modes.
- [ ] Build the link attack demos as tests (0.5 day, Nov 24): the link rows in
  [Security demos](#security-demos). Capture with `tcpdump` on the Pi and view the
  result in Wireshark on the laptop.
- [ ] Add a scripted demo runner and a README table of feature, attack, expected
  result and test link (0.5 day, Nov 25).
- [ ] GitHub Actions: add lint and static analysis (cppcheck or clang-tidy).
- [ ] Write the README, with no separate design docs: architecture diagram, threat
  model, flash layout, design notes, test results, and lessons learned. The threat
  model must state this board's limits: any running code can ask the ATECC608 to
  sign, session keys sit in RAM without isolation, RDP level 1 can be defeated in
  a lab, and the I2C wires can be sniffed or spoofed unless protected.
- [ ] Record a 2 to 3 minute demo video showing a CANopen input change at the
  ground station, an output set by command, and five attacks: tampered image
  refused, old signed image refused, Wireshark capture showing only ciphertext,
  replayed command rejected, and a man-in-the-middle handshake failing.
- [ ] Optional, only after the video is recorded: a minimal out-of-tree I2C kernel
  driver and device tree overlay for the IMU on the Pi 5. Timebox to 2 to 3 days,
  and don't use the buffer days. Stop at the timebox even if it isn't finished.
- [ ] Buffer days (Nov 30 to Dec 2) for slippage.

If behind schedule, skip the optional driver first, then cut the ATECC608 (ship
the test key and state the limit in the threat model).

**Notes:**

## Security demos

Each crypto feature gets an attack demo that doubles as a hardware test, so
fault injection, test evidence and the video share the same scripts. Demos use
scripted runs, and the on-path attacker is a controlled setup in which the STM32
is pointed at the attacker tool on the Pi 5, which forwards to the daemon.

| Feature                 | Attack                                                | Expected result                               | Built in |
| ----------------------- | ----------------------------------------------------- | --------------------------------------------- | -------- |
| Signed two-stage boot   | Flip an image byte; wrong signing key; tamper stage 2 | Boot refused, reason shown on RTT             | Week 2   |
| Rollback counter        | Install v2, then a correctly signed v1                | v1 refused as too old                         | Week 2   |
| A/B recovery            | Install a signed image that never confirms            | Board reverts to the last good image          | Week 2   |
| ATECC608 key protection | Read the private key slot                             | Read refused; chip can still sign             | Week 3   |
| AEAD confidentiality    | Capture traffic while toggling an input               | No readable state; same state differs on wire | Week 4   |
| AEAD integrity          | Flip one bit of a `set` command                       | Rejected, output unchanged, counter goes up   | Week 4   |
| Replay protection       | Set DO2 to 0, then resend a captured "DO2 = 1"        | DO2 stays 0, counter goes up                  | Week 4   |
| Man-in-the-middle       | Swap the X25519 public key in transit                 | Signature check fails, no session is set up   | Week 4   |

Covered by tests rather than live demos: algorithm test vectors, nonces never
repeating, and RNG error handling. Forward secrecy is a design property, stated in
the README without a demo.

Guardrails:

- Never log key material, even in debug builds.
- Keep the test key and debug paths out of the release build.
- Say clearly in the video which demos use the test key.

### Development time

These are working-day estimates, and they assume full days on the project.

| Work                              | When              | Estimate         |
| --------------------------------- | ----------------- | ---------------- |
| Boot attack demos                 | Week 2, by Nov 15 | 0.5 day          |
| Security counters in telemetry    | Week 3            | 0.5 day          |
| Test vectors, nonce and RNG tests | Week 3            | 0.5 day          |
| ATECC608 key-read demo            | Week 3            | 0.25 day         |
| Attacker tool                     | Week 4, Nov 23    | 0.5 day          |
| Link attack demos                 | Week 4, Nov 24    | 0.5 day          |
| Demo runner and README table      | Week 4, Nov 25    | 0.5 day          |
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
- **Others:** NUCLEO-H563ZI port, Verilog/HDL, GUI, MCUboot, mbedTLS, Pi 4, classic
  SPI, separate design docs, and Pi-side CAN.

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

## Change log

- **Nov 2, 2026:** Made the kernel driver and overlay optional: only after the video
  is recorded, timeboxed to 2 to 3 days, and first to skip if behind.
- **Nov 2, 2026:** Applied time savers: removed Yocto, the H563 port, GitHub-run
  hardware tests, the Pi 4, classic SPI and separate design docs. Switched to a
  custom bootloader and Monocypher only. Moved CANopen and an unencrypted
  end-to-end link into Week 1, and timeboxed the ATECC608. Trimmed the attack demos
  to eight and added the daemon design. The kernel driver now targets the I2C IMU.
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

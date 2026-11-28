# Outstanding Work

Open questions and unfinished setup work, last checked on Nov 26, 2026 against
the `.ioc` from Nov 6 and the code from Nov 26. The slice tasks and schedule
stay in [PLAN.md](PLAN.md).

The current build runs on the board since Nov 26: it flashes, starts, blinks
LD1 and answers pings in about 0.5 ms. Ethernet and lwIP work. For the other
peripherals, start-up working means they initialised, not that they work, so
their settings are still untested in use. See [Check on
hardware](#check-on-hardware).

## Finish the setup

The CubeMX settings and code edits are done, and the build runs on the board.
The remaining checks are under [Check on hardware](#check-on-hardware).

- [x] **Fill in the two hook functions** in `freertos.c`. Done Nov 26: both stop
      the board, at a breakpoint when a debugger is attached. See [What the
      hooks do now](documentation/middleware_RTOS.md#what-the-hooks-do-now).
- [x] **Raise the `EthIf` stack to 1024 bytes.** Done Nov 26, in the `USER CODE`
      block near the top of `LWIP/Target/ethernetif.c`. See [Raising the
      `EthIf` stack](documentation/middleware_LWIP.md#raising-the-ethif-stack).
- [x] **Add MPU regions 1 to 6.** Done Nov 6, and in `MPU_Config`: QSPI
      registers, memory-mapped QSPI, RAM with no execute, read-only flash, a
      null guard and a main stack guard. Builds; not yet run on the board. See
      [Regions](documentation/core_cortexM7.md#regions).
- [x] **Add fault reporting.** Done Nov 6: `MemManage_Handler` and
      `HardFault_Handler` save the fault registers in `fault_record` and stop
      at a breakpoint when a debugger is attached. See [MemManage fault
      reporting](documentation/core_cortexM7.md#memmanage-fault-reporting).
- [x] **Enable lwIP's TFTP server.** Done Nov 5: `LWIP_TFTP` on, with
      32-character filenames. The callbacks and `tftp_init` are Slice 7 code.
      See [lwIP's TFTP
      server](documentation/peripheral_ETH.md#lwips-tftp-server).
- [x] **Finish the USART1 interrupt and DMA setup.** Done Nov 5: USART1
      interrupt at priority 5, RX DMA on DMA2 stream 2 in circular mode, and TX
      DMA on DMA2 stream 7, both at priority 5. See [Recommended
      setup](documentation/peripheral_UART.md#recommended-setup).
- [x] **Re-enable the four CAN1 interrupts at priority 5.** Done Nov 5: TX, RX0,
      RX1 and SCE, with handlers in `stm32f7xx_it.c`. See
      [Interrupts](documentation/peripheral_CAN.md#interrupts).
- [x] **Turn CAN1's automatic retransmission and automatic bus-off management
      back on.** Done Nov 5: both are `ENABLE` in `main.c`, with 500 kbit/s
      timing. See [Settings](documentation/peripheral_CAN.md#settings).
- [x] **Set the QSPI flash size field to 23.** Done Nov 5, and in the code. See
      [Flash size](documentation/peripheral_QSPI.md#flash-size).
- [x] **Switch the PLL from HSI to HSE.** Done Nov 5: HSE in bypass mode, M =
      25, N = 432, P = 2, Q = 9, giving 216 MHz, with APB1 still at 54 MHz. See
      [Setting it up in
      CubeMX](documentation/core_oscillators.md#setting-it-up-in-cubemx).
- [x] **Fix the LSE mode.** Done Nov 5: set to Crystal/Ceramic Resonator, which
      matches X3. Nothing uses LSE yet, so it isn't started. See
      [X3](documentation/core_oscillators.md#x3-the-32768-khz-crystal).
- [x] **Enable the stack overflow check and malloc-failed hook.** Done Nov 5:
      set to 2 and 1.
- [x] **Raise the `tcpip_thread` stack to 4096 bytes.** Done Nov 5, and in
      `lwipopts.h`. CubeMX calls the unit words, but it's used as bytes. See
      [Stack size units](documentation/middleware_LWIP.md#stack-size-units).
- [x] **Set the RNG clock to 48 MHz from PLLQ.** Done Nov 5, and in the code.
- [x] **Add the UART** for the virtual COM port. Done Nov 5: USART1 on `PA9` and
      `PB7`, at 115200 baud.
- [x] **Add the version LEDs,** `PI3` (red) and `PI2` (green). Done Nov 5,
      labelled `EXT_LD_RD` and `EXT_LD_GN`. The LEDs and resistors still need
      wiring.
- [x] **Add the blue user button** on `PI11`. Done Nov 5, labelled `B1_USER`.
- [x] **Set the QSPI prescaler to 7 (27 MHz) and chip select high time to 6
      cycles.** Done Nov 5, and in the code. Sample shifting stays at None. See
      [QSPI settings](documentation/peripheral_QSPI.md#settings).

## Decisions

### Hardware

- [x] **How should the ATECC608 connect?** Decided Nov 26: I2C3, with SCL on
      `PA8` (Arduino D10) and SDA on `PC9`. `PC9` only reaches the microSD slot
      (CN3), as the card's `DAT1` line, so a Saiko Systems ST-SD-uSDv2.0
      adapter plugs into the slot and brings it out to a header. See [Pin
      assignments](PLAN.md#pin-assignments) for the wiring. The CubeMX project
      still has I2C2 on `PF0` and `PF1`; move it to I2C3 in Slice 8.
  - **Why not the others:** I2C2's pins have no route (`PF0` and `PF1` go only
    to SDRAM, `PB10`, `PB11` and `PH4` to the USB HS PHY, `PH5` to SDRAM), and
    I2C1 shares `PB8` and `PB9` with CAN1. Software I2C on spare header pins
    and moving CAN1 to CN13 were the other options.
- [ ] **Where should the Ethernet buffers go?** The plan's SRAM2 location can't
      hold the 12 RX buffers. The recommendation is to leave them where the
      linker puts them for first bring-up. See [Memory
      placement](documentation/peripheral_ETH.md#memory-placement).
- [ ] **Where should the version counter live?** The options are the F7's OTP
      area or an ATECC608 monotonic counter.
- [ ] **Which CANopen module is it, and how many DI and DO does it have?** The
      plan assumes the standard CiA 401 I/O profile (inputs at `0x6000`, outputs
      at `0x6200`). Confirm this in the module's manual.
- [ ] **What should the outputs do if the link drops?** Default until decided:
      turn them off after a timeout.
- [ ] **Should the ATECC608 be locked, or demoed unlocked?** Locking is
      permanent. The plan locks it, and [the threat
      model](documentation/system_threat_model.md#9-open-questions) still lists
      this as open.

### UART

- [ ] **What is the UART for?** The proposal is an always-available console:
      boot and status messages, plus a few read-only commands, readable without
      a debugger. See [What the UART is
      for](documentation/peripheral_UART.md#what-the-uart-is-for).

### Build

- [ ] **When should the build make several application versions?** Deferred
      on Nov 27, to Slice 4 at the latest, when the boot demos need them. A and
      B are QSPI slots, not separate programs: every version is linked for the
      same internal flash address (see [Slots A and
      B](documentation/system_boot.md#slots-a-and-b)). So the build needs
      versions, not slot images:

  | Variant | Settings | Used for |
  | ------- | -------- | -------- |
  | `v1_RED` | `VERSION=1 LED_COLOR=RED` | First install; later the old image the version check refuses |
  | `v2_GREEN` | `VERSION=2 LED_COLOR=GREEN` | The good update |
  | `v2_GREEN_noconfirm` | `VERSION=2 LED_COLOR=GREEN CONFIRM=0` | The A/B recovery demo |

  The tampered and wrong-key images come from the signing script, not the
  build. The proposed plan:
  1. **Settings:** `VERSION`, `LED_COLOR` and `CONFIRM` in `app/Makefile`,
     passed as `-DAPP_VERSION`, `-DAPP_LED_<colour>` and `-DAPP_CONFIRM`, and
     only to `app/` files, so the CubeMX objects stay the same in every
     variant.
  2. **One output folder per variant,** such as `build/app/v2_GREEN/`, named
     from the settings, so variants never overwrite or mix with each other. A
     clean build takes about 2.6 s, so building each one in full is cheap.
  3. **A `flags.txt` file per output folder** that the objects depend on, so
     changed compiler flags always force a rebuild.
  4. **Targets:** `make app VERSION=2 LED_COLOR=GREEN`, `make images` for all
     three, and `make flash` with the same settings, which writes a J-Link
     script for that variant.
  5. **Move the LED code** from `StartDefaultTask` in `main.c` into
     `app/src/app.c` as `app_run()`. Do this with the RTT work, which adds the
     same file.

  Slice 4 then adds an application linker script at `0x08040000`, an image
  header with the version, and `make sign`. Slice 6 adds loading a QSPI slot
  with the J-Link.
  - **Until then, beware:** `make` doesn't rebuild when only flags change. After
    passing different settings on the command line, such as `FW_OPT=-O2`, run
    `make clean` first, or the build mixes old and new object files.

### Repository

- [x] **Should the repo be public?** Decided Nov 27: yes, all of it, so
      reviewers can see how the project was built. Only personal details,
      secrets, and copyrighted material that can't be redistributed stay out.
      The repo is already pushed to GitHub, so anything removed must also be
      removed from the history. The steps are below.
- [ ] **Personal details:** a scan on Nov 27 found nothing in the tracked text
      files. Your personal email address is the author address on every
      commit, though.
  - Set `git config user.email` to your GitHub noreply address, and turn on
    GitHub's "Keep my email addresses private" and "Block command line pushes
    that expose my email".
  - Rewrite the existing commits' author address with `git filter-repo
    --mailmap` before the repo goes public.
  - The board photos have no GPS data. The annotated schematics contain no
    paths or names of yours.
- [ ] **Copyrighted files:** deferred on Nov 27. The vendor files stay in the
      repo for now, and how to handle them gets reviewed later. ST's documents
      say "All rights reserved" and grant no license, so redistributing them
      isn't permitted, although the realistic risk is a takedown request, not a
      lawsuit. They also add 107 MB to the repo. The proposal for the review is
      to keep only what's yours or licensed for redistribution, and link to the
      rest.

  | Keep | Remove, and link instead | Check the license first |
  | ---- | ------------------------ | ----------------------- |
  | Your code, docs and photos | ST: RM0385, DS10916, UM1907, the B-01 and B-04 schematics and their annotated PDFs | Adafruit's ATECC608 guide and schematic: Adafruit often uses CC BY-SA, which allows it with attribution |
  | CubeMX output: HAL and BSP (BSD-3-Clause), CMSIS (Apache-2.0), FreeRTOS (MIT), lwIP (BSD-3-Clause) | Micron N25Q128A datasheet | The board CAD models: ST's `MB1191B-V14.step` and `.zip`. The `case_screen_side` files can stay if you designed the case |
  | SEGGER RTT (BSD-style) | Microchip ATECC608A summary and app note | |
  | The `.xopp` annotation files, which hold your notes and only refer to ST's PDF by name | Saiko Systems ST-SD-uSDv2.0 manual | |
  | | Kepler's job posting PDF; the README already links to the posting | |

  - Keep removed files locally, and add `.gitignore` rules so they can't be
    committed again.
  - Each removed file gets a link to its download page, for example in a
    references list in `vendors/`.
  - The ebook PDF is already excluded by `.gitignore`.

### Threat model

- [ ] **Should [system_threat_model.md](documentation/system_threat_model.md) be
      brought up to date?** It disagrees with the plan in these places:
  - **Board:** it recommends an STM32H573I-DK stretch port that the plan
    removed, still asks whether to switch boards, and says the plan lists the
    H563 as having hardware crypto.
  - **Settled choices:** it leaves MCUboot or custom, ChaCha or AES-GCM, ECDH or
    X25519, and Ed25519 or P-256 open.
  - ~~**Diagram:** it shows old task names and a TrustZone key store, which
    this chip doesn't have.~~ Done Nov 5: it now shows the current threads, the
    two boot stages and the ATECC608.
  - **R1:** stage 1 verifies every image, but the design has stage 2 verify the
    application.
  - **R2:** the key hash is in OTP, but the design keeps the public key in
    write-protected stage 1.
- [ ] **Should these threat model requirements be built, or marked as known
      limits?**
  - ~~**R12:** relies on FreeRTOS-MPU, but the build uses the non-MPU
    port.~~ Decided Nov 5: a known limit. The MPU catches bugs and blocks code
    running from RAM, but doesn't separate threads.
  - **R13:** requires persistent security event logs, but the plan only has
    counters.

## Check on hardware

- [x] Flash the board through the J-Link. Done Nov 26 with `JLinkExe
      -CommandFile flash.jlink`, run from `kepler_demo_stm32f746g-disco/`. The
      first try failed with "Failed to open file." because `JLinkExe` was
      started from the repo root.
- [ ] Flash with `make flash` from the repo root, which uses the new
      `tools/debug/flash_app.jlink` and the build in `build/app/`. Check that
      LD1 blinks, and that the Ozone project at its new path still opens the
      `.elf`. See [tools/debug/README.md](tools/debug/README.md).
- [x] **Record with SystemView.** Done Nov 27. Recording works since Nov 27: about 985,000
      events over 2 minutes, with the application name and version
      (`8208283-dirty`) shown. See
      [Recording](documentation/tracing_systemview.md#recording).
  - [x] All eight threads appear, and every interrupt shows by name.
  - [x] `defaultTask` runs every 500 ms: 0.500 000 106 s between runs, each
    taking 15.8 µs to toggle LD1 and send both heap samples.
  - [x] The Terminal shows a status line every 10 s.
  - [x] The heap samples arrive: "Free heap" and "Lowest free heap", 10,952
    bytes each, as Data Sample events, and the Data Plot shows both channels
    with their units.
  - [x] SystemView reads the clock as 216 MHz, so timestamps are real time.
    No overflows at 7,382 events/s without network traffic.
  - [x] The boot message: press reset, then start recording. Pressing reset
    while recording doesn't work: the reset stops the recording (Nov 27).
    The firmware now starts recording when `defaultTask` starts. Checked Nov
    27: the boot message shows at 0.48 ms, with the thread list.
  - [x] Pinging the board shows the `ETH` interrupt, then `EthIf`, then
    `tcpip_thread`. Measured on Nov 27: receive interrupt 11.1 µs, `EthIf`
    56.6 µs, `tcpip_thread` waits 15.9 µs for the higher-priority `EthIf`,
    then runs 93.0 µs, is interrupted by the transmit-complete `ETH`
    interrupt, and finishes in 35.4 µs: about 210 µs per ping on the board.
  - [x] The recording shows no overflow gaps during the ping. Checked Nov 27:
    0 overflows in 8.7 s and 62,333 events, including the ping.
  - [x] With SystemView closed, LD1 still blinks and pings still answer.
    Checked Nov 27, after a reset and before recording, with the firmware
    recording from boot and nothing reading the buffer.
- [x] Check that LD1 blinks at 1 Hz after flashing. Done Nov 26: it blinks. So
      the clock setup, every `MX_..._Init` call and `MPU_Config` completed
      without reaching `Error_Handler` or a fault, and the scheduler runs.
- [x] Attach Ozone and check `fault_record`. Done Nov 26: all fields are zero,
      so no fault handler has run. The project is now
      `tools/debug/kepler_demo_ozone_setup.jdebug`; see
      [tools/debug/README.md](tools/debug/README.md).
- [x] In Ozone's **View > RTOS**, check all eight threads exist. Done Nov 26:
      `defaultTask`, `canOpenTask`, `linkTask`, `tcpip_thread`, `EthIf`,
      `EthLink`, `IDLE` and `Tmr Svc` are all listed, so every thread was
      created and the heap had room for them.
- [x] Ping the board at `10.1.1.123` with the new build from a wired host.
      Done Nov 26: 10 of 10 replies, 0.40 to 0.56 ms, average 0.54 ms; the
      first took 1.05 ms because of ARP. An earlier test from a host on Wi-Fi
      took 2 to 5 ms with spikes up to 216 ms, which was the Wi-Fi link, not
      the board.
- [ ] Confirm the virtual COM port passes data with the J-Link firmware.
- [x] Check the board's revision against the schematic. The sticker says
      `MB1191-B-04`, and the matching schematic is in
      [`MB1191_B-04/`](vendors/st_microelectronics/stm32f746g-disco/MB1191_B-04/mb1191-f746ngh6-b04-schematic.pdf).
- [ ] **Confirm the QSPI flash chip with READ ID (`9Fh`)** once QSPI runs. A
      B-04 board should have the Micron N25Q128A, which returns `20h BAh 18h`.
      See [Flash chip](documentation/peripheral_QSPI.md#flash-chip).
- [ ] Before wiring the ATECC608, check the ST-SD-uSDv2.0 adapter with a
      continuity meter: J3's `DAT1` pad (microSD pin 8) should beep to J2 pin
      1, and GND to J2 pin 3. The J2 pinout was read from the manual's
      schematic, so it needs confirming.
- [ ] Check the ATECC608 breakout has pull-ups on SDA and SCL. If not, add 4.7
      kohm resistors to 3.3 V. The DISCO board only has a weak 47 kohm pull-up
      on `PC9`, and none on `PA8`.
- [ ] Confirm the owned transceivers have 3.3 V logic.
- [ ] Note the CANopen module's bitrate, node ID, supply voltage and
      termination.
- [ ] Measure the thread stacks and free heap once everything is running. See
      [Measuring stacks](documentation/middleware_RTOS.md#measuring-stacks).
      Heap measured Nov 27 with SystemView: 10,952 bytes free, and the lowest
      it has been is also 10,952, steady over 160 s. Measure again once the
      link and CANopen code run. Thread stacks are still to measure.

## Licenses

- [x] Check the SEGGER SystemView target code's license when it's added. Done
      Nov 27: the same BSD-style terms as RTT, which allow redistribution if
      the copyright notice is kept. It's a git submodule at
      `vendors/segger/systemview/`, pinned to V4.10.
- [ ] Confirm which SEGGER license covers Ozone with J-Link OB, and whether the
      Friendly License covers a portfolio project made while job hunting.
- [ ] Check the Ubuntu `gcc-arm-none-eabi` package terms, GNU Make's license and
      ST's SLA0048.

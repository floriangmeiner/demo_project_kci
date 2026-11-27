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

### Repository

- [ ] **Should the vendor files go in a public repo?** They're all committed
      now. `vendors/` holds:
  - **ST:** the B-01 and B-04 schematics with their annotated copies, UM1907,
    RM0385, DS10916 and the board's CAD models (`.step`, `.3mf`, `.zip`).
    Two board photos sit beside them; if they're your own, they can stay.
  - **Others:** the Micron N25Q128A datasheet, the Saiko Systems ST-SD-uSDv2.0
    manual, Adafruit's ATECC608 breakout guide and schematic, and two Microchip
    ATECC608A documents.
  - **Also:** `references/job_description/` holds Kepler's job posting as a
    PDF. The ebook PDF is already excluded by `.gitignore`.
  - **Recommendation:** link to the vendors' PDFs instead, and keep the
    annotated copies and the posting private until the terms are checked.
    Because they're committed, they also need removing from the history before
    the repo goes public.

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
      started from the repo root. See
      [Flashing](documentation/build_system.md#flashing).
- [ ] Test RTT and SystemView through the J-Link.
- [x] Check that LD1 blinks at 1 Hz after flashing. Done Nov 26: it blinks. So
      the clock setup, every `MX_..._Init` call and `MPU_Config` completed
      without reaching `Error_Handler` or a fault, and the scheduler runs.
- [ ] Attach Ozone with RTOS awareness on, and check all eight threads exist:
      `defaultTask`, `canOpenTask`, `linkTask`, `tcpip_thread`, `EthIf`,
      `EthLink`, `IDLE` and `Tmr Svc`. `fault_record` should be all zeros. If
      the board stopped in `record_fault`, a FreeRTOS hook or `Error_Handler`,
      note where and the values.
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

## Licenses

- [ ] Check the SEGGER SystemView target code's license when it's added.
- [ ] Confirm which SEGGER license covers Ozone with J-Link OB, and whether the
      Friendly License covers a portfolio project made while job hunting.
- [ ] Check the Ubuntu `gcc-arm-none-eabi` package terms, GNU Make's license and
      ST's SLA0048.

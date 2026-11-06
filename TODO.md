# Outstanding Work

Open questions and unfinished setup work, last checked against the `.ioc` saved
at 18:57 on Nov 5, 2026. The weekly tasks and schedule stay in
[PLAN.md](PLAN.md).

Nothing has run on the board yet, so every setting below is untested.

## Finish the CubeMX settings

Make these changes in CubeMX, in this order, then regenerate and rebuild:

- [ ] **Add MPU regions 1 to 6.** Do this first. Region 1, for the QSPI
      registers, is the urgent one: the current region 0 blocks them, so
      `MX_QUADSPI_Init` should fault at startup, before any blink test can run.
      The others are memory-mapped QSPI, RAM with no execute, read-only flash, a
      null guard and a main stack guard. Values are in
      [Regions](documentation/core_cortexM7.md#regions).
- [ ] **Add MemManage fault reporting:** not in CubeMX. `HAL_MPU_Enable`
      already enables the fault, so only the `MemManage_Handler` and
      `HardFault_Handler` bodies are needed. Commit the CubeMX change first,
      then add them in their `USER CODE` blocks.
      See [MemManage fault
      reporting](documentation/core_cortexM7.md#memmanage-fault-reporting).
- [ ] **Fill in the two hook functions** in `freertos.c`. CubeMX generated them
      empty, so a detected overflow or failed allocation is ignored. See [What
      the hooks do now](documentation/middleware_RTOS.md#what-the-hooks-do-now).
- [ ] **Raise the `EthIf` stack to 1024 bytes:** not in CubeMX. Change
      `INTERFACE_THREAD_STACK_SIZE` from 350 to 1024 in the `USER CODE` block
      near the top of `LWIP/Target/ethernetif.c`. See [Raising the `EthIf`
      stack](documentation/middleware_LWIP.md#raising-the-ethif-stack).
- [x] **Enable lwIP's TFTP server.** Done Nov 5: `LWIP_TFTP` on, with
      32-character filenames. The callbacks and `tftp_init` are Week 3 code.
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

- [ ] **How should the ATECC608 connect?** `PF0` and `PF1` (I2C2) run only to
      the SDRAM address lines and have no header pin. I2C2's other pins are no
      easier: `PB10`, `PB11` and `PH4` go to the USB HS PHY, and `PH5` to SDRAM
      write enable. CN2 is on I2C1, which shares `PB8` and `PB9` with CAN1. The
      CubeMX project has I2C2 on `PF0` and `PF1` until this is decided. The
      options are:
  - **I2C3 on `PA8` (D10) and `PC9` (microSD D1):** the recommendation. It needs
    a microSD breakout.
  - **Software I2C on spare header pins:** such as `PG6` (D2) and `PG7` (D4).
  - **CAN1 on the CN13 fallback:** this frees I2C1 and CN2, but CAN through that
    USB filter chip is untested. See [Pin assignments](PLAN.md#pin-assignments).
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

- [ ] **Should the vendor files go in a public repo?** `MB1191_B-01/` has the
      older schematic with `19176.xopp` and `19176_annotated.pdf`, which are
      staged. `vendors/` also holds the B-04 schematic, the Micron datasheet,
      UM1907, RM0385 and DS10916. The recommendation is to link to ST's PDFs
      instead, and keep the annotated copies private until ST's terms are
      checked.

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

- [ ] Flash the board through the J-Link, then test RTT and SystemView. So far
      only the SWD connection is confirmed.
- [ ] Confirm the virtual COM port passes data with the J-Link firmware.
- [x] Check the board's revision against the schematic. The sticker says
      `MB1191-B-04`, and the matching schematic is in
      [`MB1191_B-04/`](vendors/st_microelectronics/stm32f746g-disco/MB1191_B-04/mb1191-f746ngh6-b04-schematic.pdf).
- [ ] **Confirm the QSPI flash chip with READ ID (`9Fh`)** once QSPI runs. A
      B-04 board should have the Micron N25Q128A, which returns `20h BAh 18h`.
      See [Flash chip](documentation/peripheral_QSPI.md#flash-chip).
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

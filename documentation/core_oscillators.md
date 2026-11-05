# Core: Oscillators

Where the STM32F746G-DISCO's clocks come from, the difference between a crystal and a crystal
oscillator, and how to set up the main clock in CubeMX.

Wiring is from the
[B-04 schematic](../vendors/st_microelectronics/stm32f746g-disco/MB1191_B-04/mb1191-f746ngh6-b04-schematic.pdf),
PDF page 3. Chip limits are from DS10916 Rev 5 and RM0385 Rev 9. Nothing has been tested on
hardware.

## Crystal or crystal oscillator

These sound alike, but they're different parts, and they connect to the STM32 differently.

| | Crystal | Crystal oscillator |
| ------------------- | -------------------------------------- | ---------------------------------------- |
| **What it is**      | A passive piece of quartz that vibrates at one frequency | A sealed module: a crystal plus the circuit that drives it |
| **Makes a clock on its own?** | No, something has to drive it | Yes, as soon as it has power |
| **Pins**            | 2                                      | Usually 4: power, ground, output and enable |
| **Needs power?**    | No                                     | Yes                                      |
| **Load capacitors?** | Yes                                   | No                                       |
| **Output**          | None until driven                      | A ready-made clock signal                |
| **STM32 pins used** | 2: `OSC_IN` and `OSC_OUT`              | 1: `OSC_IN`                              |
| **STM32 mode**      | Crystal                                | Bypass                                   |
| **On this board**   | X3, 32.768 kHz                         | X2, 25 MHz                               |

**The quick way to tell them apart on a schematic:** a two-pin part with a capacitor to ground
on each side is a crystal. A box with `VDD`, `OUT`, `EN` and `GND` is an oscillator.

## The two STM32 modes

The STM32 has an amplifier between `OSC_IN` and `OSC_OUT` for driving a crystal. The two modes
decide whether that amplifier is used.

```text
Crystal mode: the STM32 drives the crystal      Bypass mode: the oscillator drives the STM32

  OSC_IN  ────┬── crystal ──┬── OSC_OUT           oscillator OUT ── OSC_IN
              │             │                                       OSC_OUT: free, usable as GPIO
         load capacitors to ground
```

**Choosing the wrong mode:** in crystal mode, the STM32 would try to drive a crystal that isn't
there while X2 is already driving `PH0`. It might appear to work, but it isn't the correct setup
for this circuit. In bypass mode with a real crystal, nothing would drive the crystal, so
the clock wouldn't start.

## Clock sources on this board

| Source | Frequency  | Where it is            | Type               | Used for                | In this project |
| ------ | ---------- | ---------------------- | ------------------ | ----------------------- | --------------- |
| HSI    | 16 MHz     | Inside the STM32       | RC oscillator      | Default clock after reset | Not used after startup; replaced by HSE |
| HSE    | 25 MHz     | X2, on the board       | Crystal oscillator | Main clock              | Used, in bypass mode |
| LSE    | 32.768 kHz | X3, on the board       | Crystal            | Real-time clock         | Set to crystal mode, but not used, so not started |
| LSI    | 32 kHz     | Inside the STM32       | RC oscillator      | Low-power timing, such as a watchdog | Not set up |
| -      | 24 MHz     | X1, on the board       | Crystal oscillator | USB HS PHY and camera module, not the STM32's clocks | Not used |

## X2: the 25 MHz oscillator

```text
3V3 ─┬──────────────────── X2 pin 4 (VDD)
     │
     └── R5 (10 kΩ) ──┬─── X2 pin 1 (EN)
                      │
                 C5 (100 nF)
                      │
                     GND   X2 pin 2 (GND) ── GND

     X2 pin 3 (OUT) ── OSC_25M ──┬── R30 (100 Ω) ── PH0 (ball G1), OSC_IN
                                 │
                                 └── Ethernet PHY, XTAL1/CLKIN

     PH1 (ball H1), OSC_OUT: not connected
```

- **The part:** `NZ2520SB-25.00M`, an oscillator module. That's why this clock uses bypass mode.
- **Always on:** R5 pulls `EN` high, so X2 runs whenever the board has 3.3 V. Firmware can't turn
  it off, and it needs no setup.
- **Shared with Ethernet:** the same net feeds the LAN8742 PHY, so Ethernet's 25 MHz doesn't depend
  on the STM32's clock settings. See [peripheral_ETH.md](peripheral_ETH.md).
- **R30:** a 100 Ω resistor in series with `PH0`. The schematic doesn't say why, but a series
  resistor like this is commonly used to reduce ringing on a clock line.
- **`PH1`:** free in bypass mode, though it has no route to a header on this board.

X2's own datasheet isn't in `vendors/`, so its exact accuracy and output levels haven't been
checked. The STM32's limits for a bypass clock are:

| Requirement on `OSC_IN` | Limit                 | X2                  |
| ----------------------- | --------------------- | ------------------- |
| Frequency               | 1 to 50 MHz           | 25 MHz: within range |
| High level              | At least 0.7 × VDD    | Not checked         |
| Low level               | At most 0.3 × VDD     | Not checked         |
| Duty cycle              | 45% to 55%            | Not checked         |

## X3: the 32.768 kHz crystal

X3 (`NX3215SA-32.768K`) is a true crystal, wired to `PC14` and `PC15` with load capacitors C12 and
C13 (4.7 pF each) and 0 Ω resistors R31 and R32. It's the board's example of the other kind of
part. It would run the real-time clock, which this project doesn't use.

## Why not stay on HSI

HSI needs no parts on the board, so it's the simplest clock, but it's less accurate:

| Condition                 | HSI accuracy    |
| ------------------------- | --------------- |
| 25 °C, factory calibrated | ±1%             |
| –10 to 85 °C              | ±4%             |
| –40 to 105 °C             | –8% to +4.5%    |

Every CAN bit is timed from this clock, and all the nodes on the bus need to stay in step. See
[Clock accuracy](peripheral_CAN.md#clock-accuracy). A crystal oscillator is normally far more
accurate than an RC oscillator, and X2 is already on the board, so switching costs nothing.

## Setting it up in CubeMX

1. Under System Core > RCC, set **High Speed Clock (HSE)** to **BYPASS Clock Source**. This takes
   `PH0` and leaves `PH1` free.
2. In the Clock Configuration tab, set the input frequency to 25 MHz.
3. Select HSE as the PLL source, and set the values below.
4. Keep the system clock on the PLL, then regenerate.

The system clock stays at 216 MHz, so CAN timing and the other peripheral settings don't change:

| Stage          | HSE (now)            | HSI (before Nov 5)   |
| -------------- | -------------------- | -------------------- |
| Input          | 25 MHz               | 16 MHz               |
| M (divide)     | 25, giving 1 MHz     | 8, giving 2 MHz      |
| N (multiply)   | 432, giving 432 MHz  | 216, giving 432 MHz  |
| P (divide)     | 2, giving **216 MHz** | 2, giving **216 MHz** |
| Q (divide)     | 9, giving 48 MHz     | 9, giving 48 MHz     |

After regenerating, `SystemClock_Config` in `main.c` should have:

```c
RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
RCC_OscInitStruct.HSEState = RCC_HSE_BYPASS;
RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
RCC_OscInitStruct.PLL.PLLM = 25;
RCC_OscInitStruct.PLL.PLLN = 432;
RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
RCC_OscInitStruct.PLL.PLLQ = 9;
```

**If the clock doesn't start:** `HAL_RCC_OscConfig` returns an error when HSE isn't ready, and the
generated code then calls `Error_Handler`, so the firmware stops there. Check that the mode is
bypass rather than crystal, then probe `OSC_25M`.

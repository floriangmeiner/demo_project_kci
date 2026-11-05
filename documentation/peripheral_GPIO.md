# GPIO Peripheral

How general-purpose pins are set up on the STM32F746G-DISCO.

These values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`),
and `MX_GPIO_Init` in `main.c` matches them. Nothing has been tested on
hardware.

## Settings

| Pin    | User label  | Signal        | Output level | Mode             | Pull-up/pull-down | Maximum output speed | Used for                 |
| ------ | ----------- | ------------- | ------------ | ---------------- | ----------------- | -------------------- | ------------------------ |
| `PI1`  | `LD1`       | `GPIO_Output` | Low          | Output push-pull | None              | Low                  | On-board green LED       |
| `PI2`  | `EXT_LD_GN` | `GPIO_Output` | Low          | Output push-pull | None              | Low                  | External green LED (D8)  |
| `PI3`  | `EXT_LD_RD` | `GPIO_Output` | Low          | Output push-pull | None              | Low                  | External red LED (D7)    |
| `PI11` | `B1_USER`   | `GPIO_Input`  | -            | Input            | None              | -                    | Blue user button         |

The `.ioc` only records settings changed from their defaults, so `MX_GPIO_Init`
is the fuller record of these values.

`PI2` and `PI3` drive the version LEDs described in
[system_boot.md](system_boot.md#showing-which-version-is-running). Their LEDs
and series resistors still need wiring.

## User button wiring

PDF page 5 of the B-04 schematic (`mb1191-f746ngh6-b04-schematic.pdf`) shows B1,
the blue button, wired like this:

```text
VDD ── B1 ──┬── R18 (10 kΩ) ──┬── SB6 ── PI11
            │                 │
       R19 (10 kΩ)      C10 (100 nF)
            │                 │
           GND               GND
```

- **Active high:** `PI11` reads high while the button is pressed.
- **No internal pull:** R19 already pulls the line low when the button is
  released.
- **Filter:** R18 and C10 smooth the signal over about 1 ms, which may not
  remove all contact bounce, so firmware should still debounce it.
- **Solder bridge:** the path runs through SB6, so check that it's fitted if the
  button doesn't respond.

## LD1 wiring

PDF page 8 of the B-04 schematic (`mb1191-f746ngh6-b04-schematic.pdf`) shows
LD1, a green LED, wired like this:

```text
PI1 ── SB8 ── R59 (510 Ω) ── LD1 (green) ── GND
 │
 └── CN7 pin 6 (Arduino D13, SPI2_SCK)
```

- **Active high:** the LED lights only when `PI1` supplies current, because its
  other side goes to ground.
- **Solder bridge:** the path runs through SB8, so check that it's fitted on the
  board if the LED doesn't respond.
- **Shared pin:** `PI1` is also D13 on CN7, so it can't be used as a clean SPI
  clock while it drives the LED. The plan doesn't use D13.

## Why push-pull

LD1 has to be driven high, and an open-drain output can only pull a pin low or
let it float. No current would reach the LED in either state:

| Pin written as   | Open drain         | Push-pull (used)    |
| ---------------- | ------------------ | ------------------- |
| `GPIO_PIN_SET`   | Floats, LED off    | Drives high, LED on |
| `GPIO_PIN_RESET` | Pulls low, LED off | Drives low, LED off |

The other settings follow from this:

- **Output level, Low:** the LED stays off at startup.
- **No pull:** the output drives the pin both ways, so a pull resistor adds
  nothing.
- **Speed, Low:** an LED doesn't need fast edges.

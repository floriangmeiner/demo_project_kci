# QSPI Peripheral

How the QUADSPI peripheral is set up on the STM32F746G-DISCO to reach the
board's 128-Mbit (16 MB) flash, which holds firmware slots A and B.

These values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`),
and `MX_QUADSPI_Init` in `main.c` matches them. Definitions are from RM0385 Rev
9, DS10916 Rev 5 and Micron's N25Q128A datasheet (Rev. T). Nothing has been
tested on hardware, and the recommended values come from the datasheets.

> **Open issue:** the MPU blocks the QSPI registers. See
> [MPU](core_cortexM7.md#mpu).

## Settings

| Setting             | Now           | Recommended | What it means                                         |
| ------------------- | ------------- | ----------- | ----------------------------------------------------- |
| Flash size          | 23            | Keep        | Size of the flash, as a code. See [Flash size](#flash-size) |
| Clock prescaler     | 7 (27 MHz)    | Keep        | Divides the 216 MHz bus clock. See [Clock prescaler](#clock-prescaler) |
| FIFO threshold      | 1             | Keep        | Bytes in the FIFO that trigger a transfer request     |
| Sample shifting     | None          | Keep        | When read data is sampled. See [Sample shifting](#sample-shifting) |
| Chip select high time | 6 cycles    | Keep        | Minimum time chip select stays high between commands. See [Chip select high time](#chip-select-high-time) |
| Clock mode          | Mode 0        | Keep        | The clock stays low while idle. The flash supports modes 0 and 3 |
| Flash ID            | Flash 1       | Keep       | Uses bank 1, where this flash is connected             |
| Dual flash          | Disabled      | Keep       | The board has one flash chip                           |

**Where to set them:** in CubeMX, under Pinout & Configuration > Connectivity >
QUADSPI > Parameter Settings.

## Flash size

**The number is a code, not a size in bytes or megabytes.** It goes into the
peripheral's `FSIZE` field, and RM0385 defines the flash size as:

```text
Bytes in flash = 2^(FSIZE + 1)
```

`FSIZE + 1` is the number of address bits needed to reach every byte of the
flash.

| Flash size value | Calculation | Size                   | Addresses it allows       |
| ---------------- | ----------- | ---------------------- | ------------------------- |
| 1 (old value)    | 2^2         | **4 bytes**            | `0x000000` to `0x000003`  |
| 19               | 2^20        | 1 MB                   | `0x000000` to `0x0FFFFF`  |
| 22               | 2^23        | 8 MB                   | `0x000000` to `0x7FFFFF`  |
| **23 (now)**     | 2^24        | **16 MB (16,777,216 bytes)** | `0x000000` to `0xFFFFFF` |
| 24               | 2^25        | 32 MB                  | `0x000000` to `0x1FFFFFF` |

So the old value of 1 didn't mean one megabyte: it told the peripheral the flash
held 4 bytes.

**Why it matters:** the peripheral rejects any address past that size, in both
modes:

- **Indirect mode (erase, write, read):** it sets the transfer error flag if the
  address, or the address plus the data length, goes past the size.
- **Memory-mapped mode (read-only):** an access past the size gives a bus error.
  On the CPU, that's a bus fault, or a HardFault if bus faults aren't enabled.

With the old value of 1, slot B at offset `0x100000` and nearly all of slot A
would be out of range. See
[system_memory.md](system_memory.md#qspi-flash-images-a-and-b).

## Clock prescaler

This number is also a code. The QSPI clock is:

```text
QSPI clock = 216 MHz / (prescaler + 1)
```

| Prescaler  | Divides by | QSPI clock | Note                                     |
| ---------- | ---------- | ---------- | ---------------------------------------- |
| 255        | 256        | 0.84 MHz   | CubeMX's slowest setting                 |
| 127 (old value) | 128   | 1.69 MHz   | A 1 MB read on one data line takes about 5 seconds |
| **7 (now)** | 8         | 27 MHz     | Good timing margin, and fast enough      |
| 3          | 4          | 54 MHz     | Thin margin; the limit for the plain READ command |
| 1          | 2          | 108 MHz    | The flash's and QSPI's limit; see [Sample shifting](#sample-shifting) |

At 27 MHz, a 1 MB slot takes about 0.3 seconds to read on one data line, or
about 0.08 seconds with the quad output read command. The project reads slots at
boot and during updates, so more speed wouldn't show in the demo. RM0385 notes
that odd division factors don't give a 50% duty cycle, so an even divide (an odd
prescaler value) is the simpler choice.

## Chip select high time

The flash needs chip select high for a minimum time between commands, called
`tSHSL`:

| After this command                | Symbol   | Minimum |
| --------------------------------- | -------- | ------- |
| A read                            | `tSHSL1` | 20 ns   |
| Anything else (write, erase)      | `tSHSL2` | 50 ns   |

The QSPI setting is in clock cycles, so the number needed depends on the clock.
The peripheral uses one setting for all commands, so it has to meet the 50 ns:

| QSPI clock | One cycle | Cycles needed for 50 ns |
| ---------- | --------- | ----------------------- |
| 1.69 MHz (old) | 593 ns | 1                      |
| 27 MHz     | 37 ns     | 2                       |
| 54 MHz     | 18.5 ns   | 3                       |
| 108 MHz    | 9.3 ns    | 6                       |

**Recommendation: 6 cycles.** That's safe at every prescaler, so a later clock
change can't break it, and it adds only about 0.2 µs per command at 27 MHz. The
old setting of 1 cycle was valid only at the old 1.69 MHz, and would break at 27
MHz.

## Sample shifting

The flash changes its output on the falling clock edge. The QSPI normally reads
it half a cycle later, or a full cycle later with half-cycle shifting on. These
are the limits that matter:

| Limit                                    | Value |
| ---------------------------------------- | ----- |
| Flash output valid after falling edge (`tCLQV`, 30 pF) | 7 ns maximum |
| Flash output held after falling edge (`tCLQX`) | 1 ns minimum |
| STM32 setup time before sampling (`ts(IN)`) | 1 ns minimum |
| STM32 hold time after sampling (`th(IN)`) | 3 ns minimum |

With no shift, half a cycle must cover 7 ns + 1 ns = 8 ns, before any delay on
the board:

| QSPI clock | Half a cycle | Margin with no shift |
| ---------- | ------------ | -------------------- |
| 27 MHz     | 18.5 ns      | 10.5 ns              |
| 54 MHz     | 9.3 ns       | 1.3 ns               |
| 108 MHz    | 4.6 ns       | Fails by 3.4 ns      |

**Recommendation: no shift, at 27 MHz.** Half-cycle shifting would sample right
as the flash changes its output, where the 1 ns hold is less than the STM32's 3
ns, leaving only board delay to make up the difference. It's worth trying only
if 108 MHz is ever needed. These are worst-case sums from the datasheets, so
confirm them with the Week 2 read-back test.

## Flash chip

> **The Micron N25Q128A is obsolete.** This board should have one, but a newer
> board wouldn't, so check the board version before reusing these values on
> another board.

**This board is `MB1191-B-04`, so it should have the N25Q128A.** UM1907's
revision history puts the first flash change at B-05. The B-04 schematic
(`mb1191-f746ngh6-b04-schematic.pdf`, PDF page 7) shows the N25Q128A13EF840E,
which is the datasheet in `vendors/micron/`. Later boards use other chips:

| Board version        | Flash chip            | Firmware impact, per UM1907 |
| -------------------- | --------------------- | --------------------------- |
| Before `F746NGH6-B05` | Micron N25Q128A      | -                           |
| `F746NGH6-B05` on    | Micron MT25QL128ABA1EW9-0SIT | None                 |
| `F746NGH6-C03` on    | Winbond W25Q128JVEIQ  | **Yes**                     |

**To confirm it:** send the READ ID command (`9Fh`) once QSPI runs. The N25Q128A
returns `20h BAh 18h`. The chip itself is marked `8CA15 RW137`, a short code
that hasn't been decoded.

**On a C-03 or later board:** get the Winbond datasheet and recheck this
section, the chip select time, the sample shifting sums and the command list
before reusing this driver.

### N25Q128A values

| Item                  | Value                       | What it means for this project            |
| --------------------- | --------------------------- | ----------------------------------------- |
| Supply voltage        | 2.7 V to 3.6 V              | Fine on the board's 3.3 V                 |
| Maximum clock         | 108 MHz; 54 MHz for plain READ | 27 MHz is within both                  |
| Capacity              | 128 Mbit, 24-bit addresses  | Flash size value of 23                    |
| Page, for programming | 256 bytes                   | Split TFTP blocks at page boundaries      |
| Erase sizes           | 4 KB, 64 KB or the whole chip | The smallest area that can be erased is 4 KB |
| Endurance             | 100,000 erase cycles minimum | Plenty for this demo                     |
| DQ3 function          | `HOLD#`                     | The QSPI holds IO3 high in single-line phases |
| Power-up              | 150 µs before reading       | Check if stage 1 reads QSPI early         |

These are the command details Week 2's driver needs:

- **Read command:** quad output fast read (`6Bh`) works without changing any
  flash settings, and uses 8 dummy cycles by default.
- **Dummy cycles:** too few for the clock makes the flash return wrong data. The
  default of 8 is enough for `6Bh` up to 108 MHz.
- **Programming past a page:** data that runs past the end of a page wraps to
  the start of that same page and overwrites it, with no error.
- **Settings to leave alone:** avoid the nonvolatile configuration register and
  execute-in-place mode. Both survive a reset, so a mistake would outlast the
  firmware that made it.

### Erase and program times

| Operation               | Typical | Maximum |
| ----------------------- | ------- | ------- |
| Page program, 256 bytes | 0.5 ms  | 5 ms    |
| Subsector erase, 4 KB   | 0.25 s  | 0.8 s   |
| Sector erase, 64 KB     | 0.7 s   | 3 s     |
| Whole chip erase        | 170 s   | 250 s   |

These are the datasheet's standard values. Parts from week 36 of 2014 onward
have faster figures for some of them, but the erase and program maximums are
safe either way. Set driver timeouts and any watchdog from the maximums. See
[system_memory.md](system_memory.md#qspi-flash-images-a-and-b) for what this
means for slots.

## Pins

These go to the on-board flash, so they don't need any wiring. They match
UM1907's pin table.

| Signal   | Pin    | Alternate function |
| -------- | ------ | ------------------ |
| `CLK`    | `PB2`  | AF9                |
| `NCS`    | `PB6`  | AF10               |
| `IO0`    | `PD11` | AF9                |
| `IO1`    | `PD12` | AF9                |
| `IO2`    | `PE2`  | AF9                |
| `IO3`    | `PD13` | AF9                |

`PB6` is also a CAN2 pin, which is one reason CAN2 isn't used. See
[Pin assignments](../PLAN.md#pin-assignments).

## MPU

The CPU reaches the QSPI flash in two ways. The MPU checks every CPU access in
both, but it checks different addresses.

### Path 1: indirect mode (erase and write)

```text
        CPU
         |
         |  writes to QUADSPI registers
         |  (address 0xA0001000, peripheral space)
         v
  +-------------+
  |     MPU     |  checks: is 0xA0001000 allowed?
  +------+------+  needs region 1: device memory, read/write
         |
         v
  +------------------+
  | QUADSPI          |  builds the flash command:
  | controller       |  "erase sector", "program page"
  +--------+---------+
           |  quad SPI pins (CLK, CS, IO0 to IO3)
           v
  +------------------+
  | N25Q128A flash   |
  | (16 MB)          |
  +------------------+
```

The CPU never touches the flash addresses here. It only talks to the
controller's registers, so the MPU sees register accesses, not flash accesses.

### Path 2: memory-mapped mode (read)

```text
        CPU
         |
         |  reads from 0x90000000 to 0x90FFFFFF
         |  (the flash window)
         v
  +-------------+
  |     MPU     |  checks: is 0x90000000 allowed?
  +------+------+  needs region 2: normal memory, read-only
         |
         v
  +------------------+
  | QUADSPI          |  turns each read into flash
  | controller       |  read commands automatically
  +--------+---------+
           |
           v
  +------------------+
  | N25Q128A flash   |
  +------------------+
```

The CPU reads the flash like ordinary memory, and the controller does the
command work behind the scenes. A write here doesn't program the flash. With the
region read-only, the MPU turns a stray write into a fault that can be caught.

### The two MPU regions needed

| Region | Address range | Attributes | Why | When |
| ------ | ------------- | ---------- | --- | ---- |
| 1 | QUADSPI registers, `0xA0001000`, 4 KB | Device memory, read/write, no execute | So indirect mode can work | Now: without it, the firmware faults at startup |
| 2 | `0x90000000`, 16 MB window | Normal memory, read-only, no execute | Safe reads of slots A and B | Before Week 2's memory-mapped read-back |

**Execute on region 2:** a general setup allows execution from the window so
code can run straight from QSPI, known as execute in place. This project never
runs code from QSPI: stage 2 copies the chosen image into internal flash and
checks it there. So execution stays off, which also stops an unverified image in
QSPI from being run by mistake.

The exact CubeMX values for both regions are in
[core_cortexM7.md](core_cortexM7.md#mpu).

### Summary

- **Indirect mode:** the CPU writes registers, and the controller writes the
  flash. The MPU guards the registers with region 1.
- **Memory-mapped mode:** the CPU reads flash addresses directly. The MPU guards
  the window with region 2.
- **Current problem:** the existing region 0 blocks both ranges, so the first
  write to the QSPI registers, in `MX_QUADSPI_Init`, should fault at startup.

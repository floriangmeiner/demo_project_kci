# Core: Cortex-M7

How the Cortex-M7 core's instruction cache and MPU are set up on the STM32F746G-DISCO.

Values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`) and the generated
`main.c`. Nothing has been tested on hardware, and the speedup hasn't been measured.

> **Open issue, stops startup:** the current MPU setting blocks the QSPI registers, so
> `MX_QUADSPI_Init` should fault before the scheduler starts. See [MPU](#mpu).

## Settings

CubeMX location: Pinout & Configuration > System Core > CORTEX_M7 > Cortex Interface
Settings.

| Setting             | Value    | Why                                                       |
| ------------------- | -------- | --------------------------------------------------------- |
| Flash Interface     | AXI      | Firmware is linked at `0x08000000`                        |
| CPU ICache          | Enabled  | Speeds up code running from flash                         |
| CPU DCache          | Disabled | Avoids coherency problems with Ethernet DMA               |
| ART Accelerator     | Disabled | Sits on the flash's ITCM path, which this code doesn't use |
| Instruction Prefetch | Disabled | Sits on the same ITCM path                               |

`main.c` turns the cache on by calling `SCB_EnableICache()`, near the start of `main()`.
The data cache decision is explained in [peripheral_ETH.md](peripheral_ETH.md#caches).

## What the instruction cache is

It's a small, fast memory inside the Cortex-M7 (4 KB on this chip) that keeps copies of
recently run instructions. When the CPU needs one of those again, it reads the copy
instead of going back to flash.

## Why it's used

The CPU runs at 216 MHz, but flash can't keep up. `main.c` sets `FLASH_LATENCY_7`, which
means 7 wait states, or 8 CPU cycles for each flash read. Without a cache, the CPU has to
go to flash for its instructions.

The cache isn't strictly required, because the code still runs correctly without it, just
slower.

## What it gains

- **Faster crypto:** X25519, signature checks and ChaCha20-Poly1305 all run in software
  and spend their time in tight loops, which suits a cache well. This matters more because
  the data cache is off.
- **Less time in handlers and network code:** this leaves more CPU time for threads.
- **No DMA problems:** the Ethernet DMA only touches data, and code doesn't change while it
  runs, so the coherency problem that keeps the data cache off doesn't apply.

To measure the speedup, time a handshake with the cycle counter, with the cache on and
off.

## Bootloader

Stage 2 writes the new application into internal flash, and the cache could still hold old
instructions from that address. If stage 2 turns the cache on, it should call
`SCB_InvalidateICache()` after copying and before jumping to the application.

The simplest option is to leave the cache off in both bootloader stages. See
[system_boot.md](system_boot.md).

## MPU

CubeMX's "Speculation default mode" is enabled, which generates one MPU region in
`MPU_Config`. It stops the CPU reaching addresses where nothing should be read
speculatively.

| Setting            | Value                                                    |
| ------------------ | -------------------------------------------------------- |
| Region             | 0, covering the full 4 GB                                |
| Disabled sub-regions | `0x87`, which leaves the region's rules off for `0x00000000` to `0x5FFFFFFF` and `0xE0000000` up |
| Blocked addresses  | `0x60000000` to `0xDFFFFFFF`, with no access             |

Internal flash, RAM and the peripherals at `0x40000000` to `0x5FFFFFFF` are outside the
blocked range, so they aren't affected. Two QSPI ranges are inside it:

| Range                        | What it is                | What happens                            | When to fix |
| ---------------------------- | ------------------------- | --------------------------------------- | ----------- |
| `0xA0001000` to `0xA0001FFF` | QSPI control registers    | Every QSPI command, in any mode, faults | Now         |
| `0x90000000` up              | Memory-mapped QSPI flash  | Memory-mapped reads fault               | Week 2      |

**The first one stops startup.** `main()` calls `MPU_Config` first, and `MX_QUADSPI_Init`
then writes to the QSPI registers. The region applies to privileged code too, and the
MemManage fault isn't enabled, so this should become a HardFault before the scheduler
starts. This comes from reading the code and RM0385's memory map, and hasn't been run on
the board.

In CubeMX, under CORTEX_M7, add a higher-numbered region for each one. A higher-numbered
region overrides a lower one where they overlap. These values are proposed and untested:

| Setting              | Registers (now)      | Flash (Week 2)         |
| -------------------- | -------------------- | ---------------------- |
| Region               | 1                    | 2                      |
| Base address         | `0xA0001000`         | `0x90000000`           |
| Size                 | 4 KB                 | 16 MB                  |
| Sub-region disable   | `0x0`                | `0x0`                  |
| TEX level            | 0                    | 1                      |
| Access permission    | All access permitted | Read-only              |
| Instruction access   | Disabled             | Disabled               |
| Shareable            | Enabled              | Disabled               |
| Cacheable            | Disabled             | Disabled               |
| Bufferable           | Enabled              | Disabled               |

The first column makes the registers device memory, and the second makes the flash normal,
non-cacheable memory that can't run code. Stage 2 needs both regions if it reads slots in
memory-mapped mode.

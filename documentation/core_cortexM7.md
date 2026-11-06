# Core: Cortex-M7

How the Cortex-M7 core's instruction cache and MPU are set up on the
STM32F746G-DISCO.

Values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`) and the
generated `main.c`. Nothing has been tested on hardware, and the speedup hasn't
been measured.

> **MPU status, Nov 6:** regions 1 to 6 and the fault handlers are in the code
> and build, but haven't run on the board. See [MPU](#mpu).

## Settings

CubeMX location: Pinout & Configuration > System Core > CORTEX_M7 > Cortex
Interface Settings.

| Setting             | Value    | Why                                                       |
| ------------------- | -------- | --------------------------------------------------------- |
| Flash Interface     | AXI      | Firmware is linked at `0x08000000`                        |
| CPU ICache          | Enabled  | Speeds up code running from flash                         |
| CPU DCache          | Disabled | Avoids coherency problems with Ethernet DMA               |
| ART Accelerator     | Disabled | Sits on the flash's ITCM path, which this code doesn't use |
| Instruction Prefetch | Disabled | Sits on the same ITCM path                               |

`main.c` turns the cache on by calling `SCB_EnableICache()`, near the start of
`main()`. The data cache decision is explained in
[peripheral_ETH.md](peripheral_ETH.md#caches).

## What the instruction cache is

It's a small, fast memory inside the Cortex-M7 (4 KB on this chip) that keeps
copies of recently run instructions. When the CPU needs one of those again, it
reads the copy instead of going back to flash.

## Why it's used

The CPU runs at 216 MHz, but flash can't keep up. `main.c` sets
`FLASH_LATENCY_7`, which means 7 wait states, or 8 CPU cycles for each flash
read. Without a cache, the CPU has to go to flash for its instructions.

The cache isn't strictly required, because the code still runs correctly without
it, just slower.

## What it gains

- **Faster crypto:** X25519, signature checks and ChaCha20-Poly1305 all run in
  software and spend their time in tight loops, which suits a cache well. This
  matters more because the data cache is off.
- **Less time in handlers and network code:** this leaves more CPU time for
  threads.
- **No DMA problems:** the Ethernet DMA only touches data, and code doesn't
  change while it runs, so the coherency problem that keeps the data cache off
  doesn't apply.

To measure the speedup, time a handshake with the cycle counter, with the cache
on and off.

## Bootloader

Stage 2 writes the new application into internal flash, and the cache could
still hold old instructions from that address. If stage 2 turns the cache on, it
should call `SCB_InvalidateICache()` after copying and before jumping to the
application.

The simplest option is to leave the cache off in both bootloader stages. See
[system_boot.md](system_boot.md).

## MPU

The MPU checks every CPU access against a set of regions, and faults if the
access breaks a region's rules. This Cortex-M7 has 8 regions, numbered 0 to 7.
Where regions overlap, the higher number wins. Addresses outside every region
use the default memory map, because the control mode is "privileged default"
(`MPU_PRIVILEGED_DEFAULT`).

**Decision, Nov 5:** set up all the application's regions now, in Week 1,
together with MemManage fault reporting. Only the bootloader stages' own MPU
setup waits for Week 2, because those programs don't exist yet.

### What it can and can't do here

Every thread runs privileged, because the build uses FreeRTOS's normal port,
not FreeRTOS-MPU. Any code can rewrite the MPU, so it **isn't a wall between
threads**. What it does give:

- **Accidents fault at once:** a stray write to flash or a null pointer read
  stops at the instruction that caused it, instead of corrupting data quietly.
- **No code runs from RAM:** code injected into a buffer can't execute.
- **The cause is recorded:** with the MemManage fault enabled, `SCB->MMFAR`
  holds the faulting address, which points straight at the region involved.

Threat model R12 asks for the MPU to keep application threads out of boot and
key memory, which needs FreeRTOS-MPU. That is out of scope, so R12 is a known
limit. See [system_threat_model.md](system_threat_model.md#7-hardware-mapping).

### Why region 0 exists

CubeMX's "Speculation default mode" generates region 0. The Cortex-M7 can read
ahead speculatively, and a speculative read of external memory that isn't set
up, such as the SDRAM at `0xC0000000`, can stall the bus. Region 0 blocks
`0x60000000` to `0xDFFFFFFF`:

| Setting              | Value                                                  |
| -------------------- | ------------------------------------------------------ |
| Base, size           | `0x0`, 4 GB                                            |
| Disabled sub-regions | `0x87`, which turns the region off for `0x00000000` to `0x5FFFFFFF` and `0xE0000000` up |
| Access               | None                                                   |

Two QSPI ranges fall inside it. **The QSPI registers at `0xA0001000` stop
startup:** `MX_QUADSPI_Init` writes to them, which raises a MemManage fault
before the scheduler starts. The generated `MemManage_Handler` is an endless
loop, so the board just stops there. Memory-mapped
QSPI at `0x90000000` is blocked too. Regions 1 and 2 below fix both. This
comes from reading the code and RM0385's memory map, and hasn't been run on
the board.

### Regions

All proposed and untested. CubeMX location: Pinout & Configuration > System
Core > CORTEX_M7 > Parameter Settings > Cortex Memory Protection Unit Region
N Settings. Set MPU Region to Enabled to show the other fields. Region 0
belongs to Speculation default mode Settings, so leave it as it is.

Table 1 has the values to enter, using CubeMX's own wording. The MPU Access
Permission names are long, so Table 1 uses a short name for each, and Table 4
gives the full CubeMX option.

**Table 1: Region settings to enter in CubeMX**

| Region | Use | MPU Region Base Address | MPU Region Size | MPU SubRegion Disable | MPU TEX field level | MPU Access Permission | MPU Instruction Access | MPU Shareability Permission | MPU Cacheable Permission | MPU Bufferable Permission |
| ------ | --- | ----------------------- | --------------- | --------------------- | ------------------- | --------------------- | ---------------------- | --------------------------- | ------------------------ | ------------------------- |
| 0 | Speculation guard (exists, leave it) | 0x0 | 4GB | 0x87 | level 0 | No access | DISABLE | ENABLE | DISABLE | DISABLE |
| 1 | QSPI registers | 0xA0001000 | 4KB | 0x0 | level 0 | Full access | DISABLE | ENABLE | DISABLE | ENABLE |
| 2 | QSPI flash, memory-mapped | 0x90000000 | 16MB | 0x0 | level 1 | Read-only | DISABLE | DISABLE | DISABLE | DISABLE |
| 3 | All RAM | 0x20000000 | 512KB | 0x0 | level 1 | Full access | **DISABLE** | DISABLE | DISABLE | DISABLE |
| 4 | Internal flash | 0x08000000 | 1MB | 0x0 | level 0 | Read-only | **ENABLE** | DISABLE | **ENABLE** | DISABLE |
| 5 | Null guard | 0x0 | 1KB | 0x0 | level 0 | No access | DISABLE | ENABLE | DISABLE | DISABLE |
| 6 | Main stack guard | 0x2004FC00 | 32B | 0x0 | level 0 | No access | DISABLE | ENABLE | DISABLE | DISABLE |
| 7 | Spare | MPU Region: Disabled | | | | | | | | |

Under Cortex Memory Protection Unit Control Settings, MPU Control Mode stays at
"Background Region Privileged accesses only + MPU Disabled during hard fault,
NMI and FAULTMASK handlers". CubeMX turns that into
`HAL_MPU_Enable(MPU_PRIVILEGED_DEFAULT)`, which sets two things in the MPU's
control register (`MPU->CTRL`):

**Table 2: MPU control register bits set by `MPU_PRIVILEGED_DEFAULT`**

| Bit | Value | Meaning |
| --- | ----- | ------- |
| `PRIVDEFENA` | 1 | Privileged code may use the default memory map wherever no region applies. Without it, any address outside the regions faults |
| `HFNMIENA` | 0 | The MPU is off while the HardFault, NMI and FAULTMASK handlers run, so a fault handler can read any address while it logs |

`HAL_MPU_Enable` also sets `MEMFAULTENA` in `SCB->SHCSR`, so MPU violations
already go to `MemManage_Handler` instead of HardFault.

The five MPU Control Mode options, and what CubeMX generates for each:

**Table 3: MPU Control Mode options**

| MPU Control Mode | HAL value | `PRIVDEFENA` | `HFNMIENA` |
| ---------------- | --------- | ------------ | ---------- |
| MPU NOT USED | No `MPU_Config` at all | - | - |
| Background Region Access Not Allowed + MPU Disabled during hard fault, NMI and FAULTMASK handlers | `MPU_HFNMI_PRIVDEF_NONE` | 0 | 0 |
| Background Region Access Not Allowed + MPU Enabled during hard fault, NMI and FAULTMASK handlers | `MPU_HARDFAULT_NMI` | 0 | 1 |
| **Background Region Privileged accesses only + MPU Disabled during hard fault, NMI and FAULTMASK handlers (used)** | `MPU_PRIVILEGED_DEFAULT` | 1 | 0 |
| Background Region Privileged accesses only + MPU Enabled during hard fault, NMI and FAULTMASK handlers | `MPU_HFNMI_PRIVDEF` | 1 | 1 |

Why the one used:

- **Background "Privileged accesses only", not "Access Not Allowed":** with
  "Access Not Allowed", every address outside a region faults, so peripherals,
  system memory (the unique ID and OTP at `0x1FF0F000`) and anything forgotten
  would each need a region, from only 8. Every thread is privileged, so the
  stricter list would add little protection here. The core's own registers at
  `0xE0000000` and up, such as `SCB` and `NVIC`, ignore the MPU either way.
- **"MPU Disabled during hard fault":** the HardFault handler can still run
  when the fault was caused by the stack itself. If the main stack overflows
  into region 6, the CPU can't save registers on entry to `MemManage_Handler`,
  and the fault escalates to HardFault. With the MPU off in HardFault, that
  entry succeeds and the handler can report the cause. With it on, the CPU
  would lock up.

The six MPU Access Permission options:

**Table 4: MPU Access Permission options**

| CubeMX option | HAL value | Privileged code | Unprivileged code | Short name in Table 1 |
| ------------- | --------- | --------------- | ----------------- | --------------------- |
| ALL ACCESS NOT PERMITTED | `MPU_REGION_NO_ACCESS` | None | None | No access (regions 0, 5, 6) |
| Privileged READS\WRITES Permissions | `MPU_REGION_PRIV_RW` | Read, write | None | |
| Privileged READS\WRITES Permissions + Unprivileged READS Permissions | `MPU_REGION_PRIV_RW_URO` | Read, write | Read | |
| ALL ACCESS PERMITTED | `MPU_REGION_FULL_ACCESS` | Read, write | Read, write | Full access (regions 1, 3) |
| Privileged READS Permissions | `MPU_REGION_PRIV_RO` | Read | None | |
| Privileged READS Permissions + Unprivileged READS Permissions | `MPU_REGION_PRIV_RO_URO` | Read | Read | Read-only (regions 2, 4) |

Every thread runs privileged, so only the privileged column matters today.
The unprivileged column would only matter with FreeRTOS-MPU. The last option
has two spaces before "READS" in CubeMX.

Sub-region disable is `0x0` for regions 1 to 6. In memory type terms, region 1
is device memory, regions 2 and 3 are normal non-cacheable memory, region 4 is
normal write-through memory, and regions 0, 5 and 6 are strongly ordered.

Notes:

- **Region 1:** device memory keeps register writes in order and unmerged.
- **Region 2:** read-only because memory-mapped mode can't write anyway, so a
  stray write faults instead of being lost. No code runs from QSPI, because
  images are copied to internal flash first.
- **Region 3:** the RAM is 320 KB, but region sizes are powers of two, and the
  extra 192 KB is unused address space. The lwIP heap at `0x20048000` and the
  Ethernet buffers stay readable and writable. Nothing in the code is placed
  in RAM to run (no `__RAM_FUNC` users as of Nov 5).
- **Region 4, a gotcha:** the instruction cache only caches regions marked
  cacheable. Marking flash non-cacheable would silently lose the cache's
  speedup. Read-only means the application can't program internal flash
  through these addresses. It never needs to, because it writes images to
  QSPI.
- **Region 5:** a null pointer read lands in ITCM RAM at `0x0`, which the
  linker script doesn't use, and returns junk without an error. The vector
  table isn't there: `SystemInit` leaves `VTOR` alone, so it comes from the
  BOOT_ADD0 option byte, whose default is `0x00200000`. Confirm `SCB->VTOR` on
  the first run.
- **Region 6:** after the scheduler starts, interrupt handlers use the main
  stack, which grows down from `_estack` (`0x20050000`). The linker script
  reserves 1 KB (`_Min_Stack_Size`), and this guard is its bottom 32 bytes, so
  992 bytes are usable. If `_Min_Stack_Size` or the RAM layout changes, move the
  guard to match. Thread stacks are checked by
  `configCHECK_FOR_STACK_OVERFLOW`, not the MPU.

### MemManage fault reporting

The MemManage fault is already enabled by `HAL_MPU_Enable`. The generated
`MemManage_Handler` and `HardFault_Handler` were empty endless loops, so as of
Nov 6 both call `record_fault` in `stm32f7xx_it.c`, in `USER CODE` blocks.
HardFault needs it too, because a stack guard hit ends up there, as do bus and
usage faults, which aren't enabled.

`record_fault` turns interrupts off, then saves these into the global
`fault_record`:

| Field | Register | Holds |
| ----- | -------- | ----- |
| `source` | - | 1 for HardFault, 2 for MemManage |
| `cfsr` | `SCB->CFSR` | Which fault: MemManage, bus or usage, and why |
| `hfsr` | `SCB->HFSR` | Whether a fault escalated to HardFault (`FORCED`) |
| `mmfar` | `SCB->MMFAR` | The address that broke an MPU rule, if `MMARVALID` is set in `cfsr` |
| `bfar` | `SCB->BFAR` | The address of a bus error, if `BFARVALID` is set in `cfsr` |

If a debugger is attached, it then stops at a breakpoint. Without one, a
breakpoint would itself fault, so it skips straight to the endless loop. The
status bits are left set, so they can also be read live.

To read a fault in Ozone: look at `fault_record` in the watch window, and use
the call stack to see the code that faulted.

`fault_record` is in normal RAM, so a reset clears it. Week 2's persistent
fault log moves it to RAM that survives reset, and adds the reset reason.

### Tests

Each test breaks one rule on purpose. They go in a debug build only, following
the plan's guardrail on debug paths.

| Test | Expected result |
| ---- | --------------- |
| Normal boot | No fault: QSPI init, Ethernet and the blink test all work |
| Read `*(volatile uint32_t *)0` | MemManage fault, `MMFAR` = `0x0` |
| Copy a `bx lr` instruction into a RAM buffer and call it | MemManage fault, instruction access violation |
| Write to `0x08000000` | MemManage fault, `MMFAR` = `0x08000000` |
| Write to `0x90000000` in memory-mapped mode | MemManage fault |
| Deep recursion in an interrupt handler | HardFault, with `HFSR` FORCED and `CFSR` showing a MemManage stacking error (`MSTKERR`) |

If the first boot faults, read `CFSR` and `MMFAR` in Ozone. To rule a region
out, turn off its Enable setting in CubeMX.

### Later

| Item | When |
| ---- | ---- |
| MPU setup in stage 1 and stage 2. Stage 2 needs internal flash writable to install images, and reads QSPI | Week 2 |
| Stage 2 turns the MPU off before jumping, and the application's `MPU_Config` sets it up again | Week 2 |
| Once the application moves to `0x08040000`, it must set `VTOR` itself | Week 2 |
| Make the flash controller registers read-only after `SystemClock_Config`, so code can't change option bytes such as RDP or WRP. Can't be in CubeMX's `MPU_Config`, which runs before the clock setup writes the flash wait states | Optional |

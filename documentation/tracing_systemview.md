# Tracing with SEGGER SystemView

How the firmware records thread switches, interrupts, log messages and plotted
values for SEGGER SystemView, how to view them, and how to add your own.

Built and recorded on the board on Nov 27, 2026: the build has no warnings,
and with tracing off the image is byte-for-byte identical to CubeMX's build.
Recordings show every thread and traced interrupt, the log messages and heap
plots, start-up from `defaultTask` on, and no overflows during a ping.

## What it gives you

SystemView shows a timeline of everything the firmware does, recorded live
through the J-Link while the firmware runs at full speed:

| Window | Shows |
| ------ | ----- |
| Timeline | Which thread or interrupt runs when, to the CPU cycle |
| Events | Every recorded event: thread switches, FreeRTOS calls, interrupts, messages |
| Terminal | `LOG()`, `LOG_WARN()` and `LOG_ERROR()` messages |
| Data Plot | Values the firmware samples, such as the free heap |
| Contexts | CPU time per thread and interrupt, and how often each ran |

For example, pinging the board shows the `ETH` interrupt, then `EthIf`, then
`tcpip_thread`: the receive path from the [lwIP call
flow](../references/lwIP_call_flow.md), measured on real hardware.

## How it fits together

```text
FreeRTOS kernel ── trace hooks ──┐
interrupt handlers ─ TRACE_ISR ──┤
LOG(), plots, markers ───────────┼──> SEGGER_SYSVIEW.c ──> RTT buffer "SysView"
                                 │     (encodes events)     (8 KB in RAM)
                                                                 │
                                          J-Link reads RAM over SWD
                                                                 v
                                                      SystemView app on the PC
```

| Part | Where | Role |
| ---- | ----- | ---- |
| SystemView target code | `vendors/segger/systemview/`, submodule, V4.10 | Encodes events |
| RTT | `vendors/segger/rtt/`, submodule, V8.58.0 | Ring buffer in RAM that the J-Link reads |
| FreeRTOS integration | `Sample/FreeRTOSV10/` in the SystemView submodule | Turns FreeRTOS's trace hooks into events |
| Our settings | `app/config/SEGGER_SYSVIEW_Conf.h` | Buffer size and message formatting |
| Our setup | `app/src/trace.c`, `app/inc/trace.h` | Cycle counter, system description, interrupt names, plots |
| Our logging | `app/inc/log.h` | `LOG()`, `LOG_WARN()`, `LOG_ERROR()` |

### Changes to CubeMX's files

All inside `USER CODE` blocks, so regenerating keeps them, and all switched on
only when `FW_SYSVIEW` is 1:

| File | Block | Change |
| ---- | ----- | ------ |
| `Core/Inc/FreeRTOSConfig.h` | `Defines` | Sets `INCLUDE_xTaskGetIdleTaskHandle` and includes `SEGGER_SYSVIEW_FreeRTOS.h`, which defines FreeRTOS's trace hooks |
| `Core/Src/main.c` | `Includes`, `SysInit`, `5` | Calls `trace_init()` after the clock setup; in `defaultTask`, calls `trace_start()`, logs a boot message, and calls `trace_periodic()` in the LD1 loop |
| `Core/Src/stm32f7xx_it.c` | `Includes`, each handler's `0` and `1` | `TRACE_ISR_ENTER()` and `TRACE_ISR_EXIT()` in eight handlers |

The traced interrupts are `ETH`, the four CAN1 interrupts, `USART1` and its two
DMA streams. `TIM6`, the 1 kHz HAL tick, isn't traced: it would mostly add
noise. All eight are named in SystemView, as is `TIM6`, in `trace.c`.

`FW_SYSVIEW` is set by `app/Makefile`. CubeMX's own Makefile doesn't set it,
so its build stays exactly as generated.

## Recording

1. Build and flash: `make flash`.
2. Start the SystemView app (`SystemView`).
3. **Target > Recorder Configuration**, choose J-Link, then set (needed once):

   | Section | Setting | Value |
   | ------- | ------- | ----- |
   | J-Link Connection | Connection | USB; Serial Number empty |
   | Target Connection | Device | `STM32F746NG` |
   | Target Connection | Target Interface | SWD |
   | Target Connection | Interface Speed [kHz] | 4000 |
   | Target Connection | Number of cores | Auto |
   | RTT Control Block Detection | | Auto |

   Leave Use Advanced Settings off; this project needs nothing from it. If
   recording can't find RTT, see [How SystemView finds the RTT
   buffer](#how-systemview-finds-the-rtt-buffer).

4. **Target > Start Recording** (F5). Stop with F9.

- **To record start-up,** reset the board first, then start recording within
  a moment. The firmware starts recording itself when `defaultTask` starts
  (`TRACE_RECORD_FROM_BOOT` in `trace.c`), so the events from then on,
  including the boot message, wait in the RTT buffer until the app reads them.
  Once the buffer is full, newer events are dropped, which shows as an
  overflow when recording starts. Resetting the board *while* recording
  doesn't work: the reset clears the RTT buffer and stops the recording (found
  on Nov 27).
- **Recording can't start before the scheduler does.** Starting it in
  `trace_init()` stopped the board on Nov 27: `SEGGER_SYSVIEW_Start()` reads
  the FreeRTOS tick count, and FreeRTOS's interrupt priority check fails
  until the scheduler is running. The failed `configASSERT()` stops the CPU
  with interrupts off.
- **SystemView and Ozone both use the J-Link.** Close one before using the
  other, or attach Ozone without halting.
- **Without SystemView,** the firmware runs normally. Events go into the RTT
  buffer, and once it's full, new ones are dropped. Nothing ever blocks.

### How SystemView finds the RTT buffer

The firmware and the SystemView app aren't connected in any way except the
J-Link reading the chip's RAM. Before it can read any events, SystemView has to
find the **RTT control block**: a small structure in RAM, `_SEGGER_RTT` in
`SEGGER_RTT.c`, that lists each RTT buffer, where it is in RAM, and how far it
has been written and read. The control block starts with the text `SEGGER
RTT`, which is what makes it findable.

**RTT Control Block Detection** picks how SystemView finds it:

| Setting | How the control block is found | When to use it |
| ------- | ------------------------------ | -------------- |
| Auto | The J-Link searches the chip's RAM for the `SEGGER RTT` text | Normally; this is what works on this board |
| Read from ELF file | SystemView reads the address of the `_SEGGER_RTT` symbol from the `.elf` you select | If Auto doesn't find it |

**Auto can fail if the control block isn't in RAM yet.** The firmware writes
it in `SEGGER_SYSVIEW_Init()`, which `trace_init()` calls early in `main()`.
Starting a recording while the board is held in reset or stopped in the
debugger before that point finds nothing. Start the firmware first.

**Read from ELF file needs the `.elf` that's on the board.** Select
`build/app/kepler_demo_app.elf`. The address changes whenever the code or data
changes, so after rebuilding without flashing, the `.elf` points at the wrong
place. `make flash` builds and flashes together, which keeps the two in step.
To see the address yourself:

```bash
arm-none-eabi-nm build/app/kepler_demo_app.elf | grep -w _SEGGER_RTT
```

In the build from Nov 27 it's `0x20011AC0`, in SRAM1. The 8 KB buffer that the
control block points to, `_UpBuffer`, sits next to it.

**The data cache must stay off, or RTT must be set up for it.** The J-Link
reads RAM directly, not through the CPU's caches. Today only the instruction
cache is on (`SCB_EnableICache()` in `main.c`), so every event the CPU writes
is in RAM straight away. If the data cache is turned on later, events can sit
in the cache where the J-Link can't see them: SystemView would show stale or
missing data. Then either keep the RTT buffers in memory that isn't cached,
such as the DTCM at `0x20000000`, or set up RTT's cache handling.

## Logging

```c
#include "log.h"

LOG("Link up after %u ms", ms);
LOG_WARN("Replay rejected, sequence %u", seq);
LOG_ERROR("Bad tag on frame %u", frame);
```

- **Never log key material,** nonces or session secrets. Anyone with the
  debugger attached can read the trace.
- **Prefer `%d`, `%u`, `%x`, `%c` and `%p`.** SystemView sends the numbers and
  the PC formats the message, which takes very little time on the board.
- **`%s` works, but is slower.** A message containing `%s` is formatted on the
  board instead, because the PC can't read the string from the board's memory.
  This needs `SEGGER_SYSVIEW_PRINTF_IMPLICIT_FORMAT`, which our settings turn
  on; by default, `%s` would print an address.
- **At most 16 arguments, and don't use `%%`:** SystemView counts every `%` as
  an argument.

The firmware logs two messages today:
- `Boot complete: scheduler and network running`, once, from `defaultTask`;
- a status line every 10 s with the uptime, free heap and lowest free heap.

## Plotting values

`trace.c` samples two values every 500 ms, shown in the Data Plot window:

| ID | Name | Unit | Source |
| -- | ---- | ---- | ------ |
| 0 | Free heap | bytes | `xPortGetFreeHeapSize()` |
| 1 | Lowest free heap | bytes | `xPortGetMinimumEverFreeHeapSize()` |

To plot something else:
1. Add an ID to the `enum` in `trace.c`.
2. Register it in `send_system_description()` with `register_plot()`.
   Registration has to happen there, because SystemView doesn't keep
   registrations between recordings: the callback runs every time recording
   starts.
3. Sample it with `sample(id, &value)` wherever the value changes, or
   regularly. The value must be in a variable that stays valid during the call.

## Timing a section of code

```c
TRACE_MARK_START(1);
crypto_decrypt(frame);
TRACE_MARK_STOP(1);
```

The span shows in the timeline, with its duration. Useful for measuring the
handshake and the per-frame encryption in Slice 3.

## Settings

| Setting | Value | Why |
| ------- | ----- | --- |
| `SEGGER_SYSVIEW_RTT_BUFFER_SIZE` | 8192 | The default 1 KB overflows during Ethernet traffic; overflows show as gaps |
| `SEGGER_SYSVIEW_PRINTF_IMPLICIT_FORMAT` | 1 | Makes `%s` work in `LOG()` |
| `TRACE_RECORD_FROM_BOOT` | 1 | Records from boot, so start-up can be seen; 0 records only once the app starts recording |
| RTT channel | Chosen automatically, named "SysView" | Channel 0 stays free |
| Timestamps | Cycle counter, 216 MHz | `trace_init()` starts it; SystemView doesn't |
| RAM base | `0x20000000` | Object addresses are sent relative to it, which keeps events short |
| Lock | RTT's: `BASEPRI` at `0x20` | Masks interrupt priorities 2 to 15 while an event is written. Interrupts at priority 0 or 1 must not record events |

Cost, from the build on Nov 27: 7.5 KB of flash and 9.9 KB of RAM, mostly the
8 KB buffer. Each event takes a few hundred CPU cycles.

## Turning it off

```bash
make clean
make FW_SYSVIEW=0
```

This removes all tracing and logging: the SEGGER code isn't built, the hooks in
CubeMX's files aren't compiled in, and `LOG()` calls disappear. The image is
then byte-for-byte identical to CubeMX's own build. A release build will use
this, following the rule to keep debug paths out of release builds.

## Version notes

- **No FreeRTOS kernel patch.** SEGGER provides a patch for some extra events,
  but it's written for FreeRTOS V10.0.0 and the Cortex-M0, M3 and M4F ports,
  while this project has V10.2.0 with the Cortex-M7 r0p1 port. Without it, the
  FreeRTOS tick interrupt (SysTick) doesn't show as an interrupt, and stack
  start addresses aren't reported. Thread switches, FreeRTOS calls and
  everything above work.
- **SystemView V4.10 with RTT 8.58.** SystemView V4.10 expects RTT's settings
  in `SEGGER_RTT_Conf.h`, but RTT 8.58 moved its defaults to
  `SEGGER_RTT_ConfDefaults.h`, which stops the build. Our
  `SEGGER_SYSVIEW_Conf.h` includes that file to fix it. SystemView V4.12.0
  does the same itself, so the line can go when moving to it; that also needs
  the SystemView app updated to V4.12.
- **Firmware version.** The system description names the application `Kepler
  demo` plus the `git describe` version, which `app/Makefile` writes to
  `build/app/gen/fw_version.h`. A build from uncommitted changes ends in
  `-dirty`.

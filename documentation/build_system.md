# Build System

How the STM32F746G-DISCO firmware is built and flashed, which tools it uses,
and what to watch for when CubeMX regenerates the project.

Last checked on Nov 26, 2026. The build works and gives no warnings, and
flashing with `flash.jlink` works on the board.

## Quick commands

Run these from the firmware folder, `kepler_demo_stm32f746g-disco/`.

| Task | Command |
| ---- | ------- |
| Build | `make -j$(nproc)` |
| Clean build | `make clean && make -j$(nproc)` |
| Show RAM and flash use | `make LIBDIR=-Wl,--print-memory-usage -W build/main.o` |
| Show section sizes | `arm-none-eabi-size build/kepler_demo_stm32f746g-disco.elf` |
| Flash | `JLinkExe -CommandFile flash.jlink` |
| Debug | `Ozone`; see [Debugging with Ozone](#debugging-with-ozone) |
| Check the tools | `../tools/embedded_dev_tooling/toolchain.sh verify stm32` |

### Flashing

Connect USB to CN14, the debug USB port, build, then run from the firmware
folder:

```bash
JLinkExe -CommandFile flash.jlink
```

[`flash.jlink`](../kepler_demo_stm32f746g-disco/flash.jlink) is a J-Link
Commander script. It runs these commands in order:

| Command | What it does |
| ------- | ------------ |
| `ExitOnError 1` | Stops the script with an error if any command fails |
| `device STM32F746NG` | Selects the chip, so J-Link knows its flash layout |
| `si SWD` | Uses the SWD interface |
| `speed 4000` | Sets the SWD clock to 4 MHz |
| `connect` | Connects to the CPU |
| `r` | Resets and halts the CPU |
| `loadfile build/kepler_demo_stm32f746g-disco.hex` | Erases, programs and verifies the flash |
| `r` | Resets and halts again, so the new image starts from reset |
| `g` | Starts the firmware |
| `exit` | Closes J-Link Commander |

`loadfile` should end with `O.K.`, and LD1 should then blink once a second.

**Run it from the firmware folder.** J-Link resolves the `.hex` path from the
folder `JLinkExe` was started in, not from the script's folder. Started anywhere
else, `loadfile` prints "Failed to open file." `ExitOnError 1` makes J-Link
stop there with an error, instead of carrying on and restarting the old
firmware, which is what happened on Nov 26.

To flash by hand instead, start `JLinkExe -device STM32F746NG -if SWD -speed
4000 -autoconnect 1` and type the commands from `r` onwards at the `J-Link>`
prompt.

### Debugging with Ozone

The Ozone project is
[`kepler_demo_ozone_setup.jdebug`](../kepler_demo_stm32f746g-disco/kepler_demo_ozone_setup.jdebug)
in the firmware folder. Open it with **File > Open**, or `Ozone
kepler_demo_ozone_setup.jdebug`. It sets up:

| Setting | Value |
| ------- | ----- |
| Device | `STM32F746NG` |
| Connection | J-Link, SWD, 4 MHz, USB |
| Register descriptions | Ozone's `Cortex-M7F.svd`, which covers the core registers, including the fault registers in the SCB, but not the STM32 peripherals |
| Program file | `$(ProjectDir)/build/kepler_demo_stm32f746g-disco.elf` |
| RTOS awareness | `FreeRTOSPlugin_Cortex-M` |

**FreeRTOS awareness** comes from this line in the project's `OnProjectLoad`,
under "User settings":

```c
Project.SetOSPlugin ("FreeRTOSPlugin_Cortex-M");
```

When the project loads, the Console should say `RTOS awareness plugin loaded:
.../FreeRTOSPlugin_Cortex-M.js`. **View > RTOS** then lists every thread with
its state, priority and stack.

- **Use `FreeRTOSPlugin_Cortex-M`, not `FreeRTOSPlugin_CM7`.** Both ship with
  Ozone V350a and cover the Cortex-M7, but SEGGER has deprecated the CM7 plugin.
- **Typing the command in the Console only lasts for that session.** Ozone
  doesn't save it into the project, so it has to be in the `.jdebug` file.
- **To recreate the project,** use the New Project Wizard with the settings
  above, then add the `SetOSPlugin` line by hand.
- **Delete any `Project.AddPathSubstitute` lines before committing.** Ozone
  may add them when it saves. They contain the absolute path of your checkout,
  and aren't needed: each machine's `.elf` records its own build folder, so
  Ozone finds the sources without them.

To look at the running firmware without reflashing it, use **Debug > Start
Debug Session > Attach to Running Program**, then Halt. While the CPU is halted,
LD1 stops blinking and the board doesn't answer pings.

## Tools

| Tool | Version | From | Used for |
| ---- | ------- | ---- | -------- |
| `arm-none-eabi-gcc` | 13.2.1 | Ubuntu apt, `gcc-arm-none-eabi` | Compiling and linking |
| GNU Make | 4.3 | Ubuntu apt | Running the generated `Makefile` |
| STM32CubeMX | 6.18.1 | ST | Generating the project, including the `Makefile` |
| J-Link software | V978 | SEGGER | Flashing (`JLinkExe`), RTT viewer, GDB server |
| Ozone | V350a | SEGGER | Debugging |
| SystemView | V410b | SEGGER | Thread tracing, not set up yet |
| SEGGER RTT source | V8.58 | SEGGER on GitHub | Logging over the debug probe, not added yet |

`tools/embedded_dev_tooling/toolchain.sh` installs and checks these versions,
and `configs/stm32.conf` lists them. See its
[README](../tools/embedded_dev_tooling/README.md). The SEGGER tools and CubeMX
are linked into `~/.embedded-tools/bin`, which `~/.bashrc` adds to `PATH`.

The board's on-board ST-LINK has been reflashed with J-Link firmware, so use
the SEGGER tools, not ST's.

## How the build works

The `Makefile` is generated by CubeMX, because the `.ioc` sets **Project
Manager > Project > Toolchain / IDE** to Makefile
(`ProjectManager.TargetToolchain=Makefile`).

| Setting | Value | Where it comes from |
| ------- | ----- | ------------------- |
| Target name | `kepler_demo_stm32f746g-disco` | `TARGET` |
| Debug info | On (`-g -gdwarf-2`) | `DEBUG = 1` |
| Optimization | `-Og` | `OPT` |
| CPU and FPU | `-mcpu=cortex-m7 -mthumb -mfpu=fpv5-sp-d16 -mfloat-abi=hard` | `MCU` |
| Defines | `USE_HAL_DRIVER`, `STM32F746xx` | `C_DEFS` |
| C library | newlib-nano (`-specs=nano.specs`), with `-lc -lm -lnosys` | `LDFLAGS`, `LIBS` |
| Dead code removal | `-fdata-sections -ffunction-sections` and `--gc-sections` | `CFLAGS`, `LDFLAGS` |
| Linker script | `STM32F746xx_FLASH.ld` | `LDSCRIPT` |
| Compiler path | Whatever is on `PATH`, or `make GCC_PATH=...` | `GCC_PATH` |

`-mfpu=fpv5-sp-d16` is the single-precision FPU. The STM32F746 has no
double-precision FPU, so `double` maths runs in software.

The linker script gives the firmware two regions:

| Region | Start | Size | Holds |
| ------ | ----- | ---- | ----- |
| `FLASH` | `0x08000000` | 1 MB | Code and constants |
| `RAM` | `0x20000000` | 320 KB | Data, the FreeRTOS heap and the main stack |

### Build outputs

All outputs go in `build/`, which `.gitignore` excludes.

| File | What it is | Used by |
| ---- | ---------- | ------- |
| `kepler_demo_stm32f746g-disco.elf` | Program with debug symbols | Ozone, `arm-none-eabi-size`, GDB |
| `kepler_demo_stm32f746g-disco.hex` | Intel HEX image, with addresses | `JLinkExe loadfile` |
| `kepler_demo_stm32f746g-disco.bin` | Raw image, no addresses | Later: signing and TFTP updates |
| `kepler_demo_stm32f746g-disco.map` | Linker map: where every symbol went | Checking memory placement |
| `*.o`, `*.d`, `*.lst` | Objects, dependency files and assembly listings | `make` itself |

### Memory use

From `make LIBDIR=-Wl,--print-memory-usage -W build/main.o` on Nov 26:

| Region | Used | Size | Used |
| ------ | ---- | ---- | ---- |
| RAM | 72,872 B | 320 KB | 22% |
| FLASH | 75,092 B | 1 MB | 7% |

How the command works:
- **`LIBDIR=-Wl,--print-memory-usage`** puts the linker option into the link
  step. The generated `Makefile` leaves `LIBDIR` empty, so this doesn't replace
  anything.
- **`-W build/main.o`** makes `make` treat `main.o` as changed, which forces a
  relink. Without it, an up-to-date build prints nothing.

lwIP's heap isn't counted in RAM. `LWIP_RAM_HEAP_POINTER` fixes it at
`0x20048000` instead of letting the linker place it. See [Memory
placement](peripheral_ETH.md#memory-placement).

## CubeMX regeneration

Generate Code in CubeMX rewrites the `Makefile` and every generated source file.

- **The `Makefile` has no `USER CODE` blocks.** Any edit to it is lost at the
  next generation. Pass changes on the command line, as the memory use command
  does, or put them in a separate makefile (see [Planned](#planned)).
- **Source files keep their `USER CODE` blocks**, because the `.ioc` has
  `ProjectManager.KeepUserCode=true`. Code outside the blocks is overwritten.
- **New source files go in the `Makefile` automatically** only if CubeMX
  generated them. Our own `.c` files need adding, which is another reason for
  the separate makefile.
- **`ProjectManager.DeletePrevious=true`** deletes generated files that CubeMX
  no longer generates, for example if a middleware is turned off.

## Planned

- **Our own makefile around the generated one** (Slice 1). It would include the
  generated `Makefile` and add our source files, include paths, a `flash`
  target, the memory report and warning flags, so that regenerating can't undo
  them.
- **A release build** with `DEBUG = 0` and higher optimization, without the
  test key or debug paths.
- **The bootloader as a second build** (Slice 4), with its own linker script.
- **A firmware build in CI** (Slice 3).

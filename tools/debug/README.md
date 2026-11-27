# Debug Tools

Files for flashing and debugging the firmware through the board's J-Link. Both
read the build output in `build/app/`, so build first with `make` from the repo
root. [build_system.md](../../documentation/build_system.md) covers the whole
build.

| File | Tool | What it's for |
| ---- | ---- | ------------- |
| [`flash_app.jlink`](flash_app.jlink) | J-Link Commander (`JLinkExe`) | Programs the application into the chip's flash and starts it |
| [`kepler_demo_ozone_setup.jdebug`](kepler_demo_ozone_setup.jdebug) | Ozone | The debugger project: chip, connection, program file and FreeRTOS awareness |

## `flash_app.jlink`

A J-Link Commander script. Run it with `make flash` from the repo root, which
builds first, or directly from the repo root with:

```bash
JLinkExe -CommandFile tools/debug/flash_app.jlink
```

| Command | What it does |
| ------- | ------------ |
| `ExitOnError 1` | Stops the script with an error if any command fails |
| `device STM32F746NG` | Selects the chip, so J-Link knows its flash layout |
| `si SWD` | Uses the SWD interface |
| `speed 4000` | Sets the SWD clock to 4 MHz |
| `connect` | Connects to the CPU |
| `r` | Resets and halts the CPU |
| `loadfile build/app/kepler_demo_app.hex` | Erases, programs and verifies the flash |
| `r` | Resets and halts again, so the new image starts from reset |
| `g` | Starts the firmware |
| `exit` | Closes J-Link Commander |

A good run ends `loadfile` with `O.K.`, and LD1 then blinks once a second.

- **Run it from the repo root.** J-Link resolves the `.hex` path from the folder
  `JLinkExe` was started in, not from the script's folder. `make flash` always
  does this.
- **`ExitOnError 1` matters.** Without it, a failed `loadfile`, for example
  "Failed to open file.", is followed by `r` and `g`, which restart the old
  firmware as if nothing went wrong. That happened on Nov 26.
- **J-Link Commander scripts can't hold comments,** which is why the
  explanation is here instead of in the file.

## `kepler_demo_ozone_setup.jdebug`

An Ozone project, which is a script that runs when Ozone opens it. Open it with
**File > Open** in Ozone, or `Ozone tools/debug/kepler_demo_ozone_setup.jdebug`.

| Setting | Value |
| ------- | ----- |
| Device | `STM32F746NG` |
| Connection | J-Link, SWD, 4 MHz, USB |
| Register descriptions | Ozone's `Cortex-M7F.svd`, which covers the core registers, including the fault registers in the SCB, but not the STM32 peripherals |
| RTOS awareness | `FreeRTOSPlugin_Cortex-M`, so **View > RTOS** lists the threads |
| Program file | `$(ProjectDir)/../../build/app/kepler_demo_app.elf`; `$(ProjectDir)` is this folder |

- **To look at the running firmware without reflashing it,** use **Debug >
  Start Debug Session > Attach to Running Program**, then Halt. While halted,
  LD1 stops blinking and the board doesn't answer pings.
- **The RTOS plugin line is written by hand,** in `OnProjectLoad` under "User
  settings". Typing `Project.SetOSPlugin(...)` in Ozone's Console only lasts for
  that session.
- **Use `FreeRTOSPlugin_Cortex-M`, not `FreeRTOSPlugin_CM7`.** Both ship with
  Ozone V350a, but SEGGER has deprecated the CM7 one.
- **Delete any `Project.AddPathSubstitute` lines before committing.** Ozone may
  add them when it saves. They contain the absolute path of your checkout and
  aren't needed, because each machine's `.elf` records its own build folder.

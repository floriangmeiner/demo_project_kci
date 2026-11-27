# SEGGER RTT, vendored copy

SEGGER's Real Time Transfer target source, used for logging through the J-Link.
It's kept in this repo so that CI can build the firmware without
`~/.embedded-tools`.

| Item | Value |
| ---- | ----- |
| Version | 8.58.0, released Jun 3, 2026 (tag `V8.58.0`) |
| Source | [SEGGERMicro/RTT](https://github.com/SEGGERMicro/RTT), installed by `tools/embedded_dev_tooling/toolchain.sh` into `~/.embedded-tools/rtt/V8.58` |
| Copied | Nov 27, 2026 |
| Changes | None: every file is byte-for-byte the same as the release |
| License | SEGGER's BSD-style license in [LICENSE.md](LICENSE.md). Keep the copyright notice in every file |

## What's here

| File | Used for |
| ---- | -------- |
| `RTT/SEGGER_RTT.c`, `RTT/SEGGER_RTT.h` | The control block and ring buffers the J-Link reads |
| `RTT/SEGGER_RTT_ConfDefaults.h` | Default settings; includes `SEGGER_RTT_Conf.h` |
| `RTT/SEGGER_RTT_printf.c` | `SEGGER_RTT_printf`, a small `printf` that needs no heap |
| `RTT/SEGGER_RTT_ASM_ARMv7M.S` | Fast write routine. `SEGGER_RTT.h` turns on `RTT_USE_ASM` for GCC on ARMv7-M, so this file must be built |
| `Config/SEGGER_RTT_Conf.h` | The settings file. Change settings here, not in `SEGGER_RTT_ConfDefaults.h` |
| `LICENSE.md`, `README.md` | SEGGER's license and readme |

The build needs both `RTT/` and `Config/` on the include path.

## Left out

- **`Syscalls/`:** these route newlib's `printf` to RTT. Newlib's `printf` is
  large, uses the heap, and isn't safe from several threads without extra
  FreeRTOS setup. The firmware uses `SEGGER_RTT_printf` instead.
- **`Examples/`, `gen_pack.sh` and `SEGGER.RTT.pdsc`:** not needed to build.

## Updating

Install the new version with `toolchain.sh`, copy the same files over these,
and update the version and date above. If `Config/SEGGER_RTT_Conf.h` has been
changed here by then, merge the changes instead of overwriting it.

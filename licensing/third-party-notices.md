# Third-Party Notices

A record of the third-party software this project uses or plans to use, its
license, and where to find that license.

Licenses were checked against each project's own license page on Nov 3, 2026,
unless marked otherwise. Check them again when adding or upgrading a component,
because terms can change between versions. This is a working record, not legal
advice.

## Project license

This project's own code is under the MIT License. See [LICENSE](LICENSE).
Third-party software keeps its own license, as listed below.

## Software in the firmware

These are the items to watch most closely, because they ship inside the firmware
binary and their notices have to be kept.

| Software                     | Used for                | License                                                  | License text                                                                                  | Status  |
| ---------------------------- | ----------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ------- |
| FreeRTOS kernel              | RTOS                    | MIT                                                      | [LICENSE.md](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/LICENSE.md)                | In use (V10.2.0) |
| lwIP                         | UDP over Ethernet       | BSD-3-Clause                                             | [COPYING](https://github.com/lwip-tcpip/lwip/blob/master/COPYING)                             | In use (2.1.2_Cube) |
| Monocypher                   | X25519, ChaCha20-Poly1305, Ed25519 | BSD-2-Clause or CC0-1.0, our choice           | [LICENCE.md](https://github.com/LoupVaillant/Monocypher/blob/master/LICENCE.md)               | Planned |
| CryptoAuthLib                | ATECC608 access         | Microchip license (see conditions)                       | [license.txt](https://github.com/MicrochipTech/cryptoauthlib/blob/main/license.txt)           | Planned |
| STM32F7 HAL and BSP          | Peripherals, QSPI       | BSD-3-Clause                                             | [STM32CubeF7 LICENSE.md](https://github.com/STMicroelectronics/STM32CubeF7/blob/master/LICENSE.md) | HAL in use (FW_F7 V1.17.4) |
| CMSIS and CMSIS Device       | Cortex-M support        | Apache-2.0                                               | [STM32CubeF7 LICENSE.md](https://github.com/STMicroelectronics/STM32CubeF7/blob/master/LICENSE.md) | In use (FW_F7 V1.17.4) |
| ST example projects          | Starting point for lwIP and QSPI | SLA0044, or BSD-3-Clause for basic examples (see conditions) | [STM32CubeF7 LICENSE.md](https://github.com/STMicroelectronics/STM32CubeF7/blob/master/LICENSE.md) | Planned |
| SEGGER RTT                   | Logging                 | SEGGER BSD-style license                                 | [LICENSE.md](https://github.com/SEGGERMicro/RTT/blob/master/LICENSE.md)                       | Planned |
| SEGGER SystemView target code | RTOS tracing           | Not checked                                              | Check the source file headers when added                                                      | Planned |
| newlib                       | C library, via the toolchain | Several permissive licenses, varying by file        | [COPYING.NEWLIB](https://sourceware.org/git/?p=newlib-cygwin.git;a=blob_plain;f=COPYING.NEWLIB;hb=HEAD) | In use |

## Software on the ground station

| Software              | Used for                 | License                     | License text                                                                 | Status  |
| --------------------- | ------------------------ | --------------------------- | ---------------------------------------------------------------------------- | ------- |
| Python                | Daemon, tools            | PSF License                 | [LICENSE](https://github.com/python/cpython/blob/main/LICENSE)               | Planned |
| `cryptography`        | Daemon, signing tools    | Apache-2.0 or BSD-3-Clause  | [LICENSE](https://github.com/pyca/cryptography/blob/main/LICENSE)            | Planned |
| tcpdump               | Packet capture for demos | BSD                         | [LICENSE](https://github.com/the-tcpdump-group/tcpdump/blob/master/LICENSE)  | Planned |
| Raspberry Pi OS       | Operating system         | Varies by package; not checked | Listed per package on the installed system in `/usr/share/doc`            | Planned |

## Development and test tools

These don't ship in the firmware, so their licenses don't normally apply to the
code they're used to build or check.

| Software                 | Used for            | License                                     | License text                                                                 | Status      |
| ------------------------ | ------------------- | ------------------------------------------- | ---------------------------------------------------------------------------- | ----------- |
| Ubuntu `gcc-arm-none-eabi` | Compiler          | GPL components with the GCC Runtime Library Exception; package terms not checked | [Package](https://packages.ubuntu.com/gcc-arm-none-eabi) | In use (13.2.1) |
| GNU Make                 | Build system        | GPL-3.0 or later; not checked on Nov 3      | [GNU Make](https://www.gnu.org/software/make/)                               | In use      |
| STM32CubeMX              | Code generation     | ST SLA0048 (not read in full)               | [SLA0048](https://www.st.com/sla0048)                                        | In use (6.18.1) |
| VS Code                  | Editor              | Microsoft product license; source code is MIT | [Product license](https://code.visualstudio.com/license)                   | In use |
| pytest                   | Hardware tests      | MIT                                         | [LICENSE](https://github.com/pytest-dev/pytest/blob/main/LICENSE)            | Planned     |
| Unity                    | Unit tests          | MIT                                         | [LICENSE.txt](https://github.com/ThrowTheSwitch/Unity/blob/master/LICENSE.txt) | Undecided |
| GoogleTest               | Unit tests          | BSD-3-Clause                                | [LICENSE](https://github.com/google/googletest/blob/main/LICENSE)            | Undecided   |
| cppcheck                 | Static analysis     | GPL-3.0                                     | [COPYING](https://github.com/danmar/cppcheck/blob/main/COPYING)              | Undecided   |
| clang-tidy               | Static analysis     | Apache-2.0 with LLVM Exceptions             | [LICENSE.TXT](https://github.com/llvm/llvm-project/blob/main/LICENSE.TXT)    | Undecided   |
| Wireshark                | Packet inspection   | GPL-2.0                                     | [COPYING](https://github.com/wireshark/wireshark/blob/master/COPYING)        | Planned     |
| SEGGER SystemView (host) | RTOS tracing        | SEGGER Friendly License for non-commercial use | [SFL](https://www.segger.com/purchase/licensing/license-sfl/)             | Planned     |
| SEGGER Ozone             | Debugging           | SEGGER license; which one applies to J-Link OB isn't confirmed | [SFL](https://www.segger.com/purchase/licensing/license-sfl/), [Commercial](https://www.segger.com/purchase/licensing/license-cul/) | Planned |
| J-Link OB firmware       | ST-LINK reflash     | SEGGER terms (see conditions)               | [ST-LINK On-Board](https://www.segger.com/products/debug-probes/j-link/models/other-j-links/st-link-on-board/) | In use (V21) |

## Conditions to follow

- **CryptoAuthLib:** may be used only with Microchip products, which fits the
  ATECC608. Any redistribution in source or binary form must include Microchip's
  terms and disclaimer, so a public binary or source copy needs them.
- **ST example projects:** most are under SLA0044, which is more restrictive
  than the rest of the package. Only basic examples are BSD-3-Clause. Check the
  license of any example used as a starting point before publishing code derived
  from it.
- **J-Link OB firmware:** SEGGER allows it only with ST devices, on evaluation
  boards, and for development or evaluation, not production. It comes without
  support. The STM32F746G-DISCO is listed as supported, and it can be reverted
  to ST-LINK. This project's board has been reflashed.
- **SEGGER tools:** SEGGER's Friendly License allows non-commercial use,
  including private individuals, hobby projects and self-study, but excludes
  developing products or services to sell. Its page doesn't address portfolio
  projects made while job hunting, so ask SEGGER if a clear answer is needed.
- **BSD, MIT and Apache components in the firmware:** keep their copyright
  notices, and include them with any distributed binary. Apache-2.0 also has its
  own notice requirements.
- **GPL tools:** GNU Make, cppcheck and Wireshark are only run, not linked into
  the firmware. The GCC Runtime Library Exception covers code built with the
  compiler. Publishing copies of these tools themselves would bring GPL
  obligations.
- **ST and other vendor documents:** datasheets and manuals are copyrighted by
  their publishers. Check their terms before committing copies to a public
  repository, and link to them otherwise. `vendors/st_microelectronics/`
  currently holds copies of the board schematic, an annotated schematic, UM1907,
  RM0385 and DS10916, and `vendors/micron/` holds the flash datasheet, so check
  this before the repository goes public.

## Keeping this up to date

When adding a component:

1. Add a row with its license and a link to the license text.
2. Record the version or commit once it's actually in use, and change its
   status.
3. Keep the original license file with any source copied into the repository.

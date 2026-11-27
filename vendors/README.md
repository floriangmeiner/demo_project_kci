# Third-Party Material

Everything in this folder is third-party material, unless a file says
otherwise. It isn't the work of this project's author, and it isn't covered by
this project's [MIT License](../licensing/LICENSE).

## Reference documents

The datasheets, manuals, schematics, CAD models and other documents here are
kept only as a reference for the hardware this project uses. They're unmodified
copies of what each publisher makes available. All rights in them remain with
their copyright holders, as stated in each document. This project claims no
ownership of them and grants no rights to them.

| Folder | Contents | Copyright holder |
| ------ | -------- | ---------------- |
| `st_microelectronics/stm32f746g/` | RM0385 reference manual, DS10916 datasheet | STMicroelectronics |
| `st_microelectronics/stm32f746g-disco/` | UM1907 user manual, MB1191 board schematics (revisions B-01 and B-04), board CAD models | STMicroelectronics |
| `micron/N25Q128A13EF840E/` | N25Q128A QSPI flash datasheet | Micron Technology, Inc. |
| `microchip/ATECC608A/` | ATECC608A summary datasheet, CryptoAuth debugging application note | Microchip Technology Inc. |
| `adafruit/4314/` | ATECC608 breakout guide and schematic | Adafruit Industries |
| `saiko_systems_ltd/` | ST-SD-uSDv2.0 adapter manual | Saiko Systems Ltd. |

**Annotated schematics.** The `*_annotated.pdf` files and the
[Xournal++](https://xournalpp.github.io/) `.xopp` files add this project's notes
on top of ST's schematics. The notes are this project's own work. The
schematics underneath remain STMicroelectronics' property, as above. Xournal++
is a free, open-source note-taking app; open a `.xopp` file in it to see the
notes as editable layers over the schematic PDF in the same folder.

## Third-party source code

| Folder | Contents | License |
| ------ | -------- | ------- |
| `segger/rtt/` | SEGGER RTT, a git submodule of [SEGGERMicro/RTT](https://github.com/SEGGERMicro/RTT) pinned to tag V8.58.0 | SEGGER's BSD-style license, in [LICENSE.md](https://github.com/SEGGERMicro/RTT/blob/V8.58.0/LICENSE.md) |
| `segger/systemview/` | SEGGER SystemView target code, a git submodule of [SEGGERMicro/SystemView](https://github.com/SEGGERMicro/SystemView) pinned to tag V4.10 | SEGGER's BSD-style license, in each source file's header |

Source code here keeps its own license, which allows it to be redistributed.
Both SEGGER folders are git submodules: this repository records only which
commit to use, and the files come from SEGGER's own repositories. They're
unmodified, and our settings for them live in `app/`. Only some of their files
are built; for example, RTT's `Syscalls/` folder isn't, because it routes
newlib's `printf` through the heap.
See [third-party-notices.md](../licensing/third-party-notices.md) for every
third-party component and its conditions.

## Removal requests

If you hold the rights to any document here and would like it removed, please
open an issue on this repository and it will be taken down promptly.

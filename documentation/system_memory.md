# Memory

Where code, images and cryptographic material live in this system.

This is the proposed layout, and nothing is built yet. Addresses and sizes may
change. The sector map and RAM addresses match the reference manual (RM0385 Rev
9), which puts the 1 KB OTP area at `0x1FF0F000`.

## Overview

| Memory             | Size   | On which bus    | Contents                                          |
| ------------------ | ------ | --------------- | ------------------------------------------------- |
| Internal flash     | 1 MB   | Inside the STM32 | Stage 1, stage 2, provisioning data, running application |
| QSPI flash         | 16 MB  | QSPI            | Update images in slots A and B, update metadata   |
| ATECC608           | 16 slots | I2C           | Device private key, optional counter              |
| OTP                | 1 KB   | Inside the STM32 | Version counter (one of two options)              |
| SRAM               | 320 KB | Inside the STM32 | Stacks, heap, network buffers, session keys       |
| Backup SRAM        | 4 KB   | Inside the STM32 | Reset reasons and fault log                       |
| Pi 5 microSD       | Varies | Inside the Pi   | Daemon, ground station private key, device public key |

## Internal flash

The sectors are uneven, and erasing clears a whole sector, so the layout follows
sector boundaries.

| Sector | Address      | Size   | Contents                                               |
| ------ | ------------ | ------ | ------------------------------------------------------ |
| 0-1    | `0x08000000` | 64 KB  | Stage 1 and the boot public key (write-protected)      |
| 2      | `0x08010000` | 32 KB  | Provisioning data, including the ground station public key |
| 3      | `0x08018000` | 32 KB  | Reserved                                               |
| 4      | `0x08020000` | 128 KB | Stage 2                                                |
| 5-7    | `0x08040000` | 768 KB | Running application                                    |

The application is limited to 768 KB, the size of the space it runs from.

## QSPI flash: images A and B

QSPI is memory-mapped at `0x90000000` for reading.

| Address      | Size     | Contents                                            |
| ------------ | -------- | --------------------------------------------------- |
| `0x90000000` | 1 MB     | Slot A: signed application image                    |
| `0x90100000` | 1 MB     | Slot B: signed application image                    |
| `0x90200000` | 64 KB    | Update metadata, copy 1                             |
| `0x90210000` | 64 KB    | Update metadata, copy 2                             |
| `0x90220000` | About 13.9 MB | Unused                                         |

- **Slots:** one holds the last good image and the other receives the next
  update. [system_boot.md](system_boot.md) describes how they're used.
- **Metadata:** records which slot is active and whether an update is pending.
  Two copies mean a power cut during a write can't lose both.
- **Trust:** QSPI isn't protected, so anyone with the board could rewrite it.
  Images aren't trusted until their signature passes, and a bad metadata value
  can only cause a failed check or a recovery, never unsigned code running.
  Secrets never go here.

**Flash chip:** this board (`MB1191-B-04`) should have the Micron N25Q128A,
which is now obsolete, and later boards use different chips. The notes below are
for the N25Q128A. See [Flash chip](peripheral_QSPI.md#flash-chip).

- **Alignment:** the flash has 65,536 pages of 256 bytes and 256 sectors of 64
  KB, each divided into 4 KB subsectors. All the addresses above start on a 64
  KB sector boundary, so erasing one area can't touch its neighbour.
- **Time to update a slot:** a 1 MB slot is 16 sectors and 4,096 pages. Erasing
  takes about 11 seconds, or 48 at most. Programming takes about 2 seconds, or
  20 at most. Erase before the TFTP transfer starts, as
  [peripheral_ETH.md](peripheral_ETH.md#loading-firmware-images-with-tftp) says,
  and keep any watchdog from firing during these waits.
- **Wear:** each sector is rated for at least 100,000 erase cycles, so the
  metadata copies won't wear out in this demo.

## Where cryptographic material lives

| Item                               | Location                         | Protection                                 |
| ---------------------------------- | -------------------------------- | ------------------------------------------ |
| Boot private key (Ed25519)         | Developer's laptop, never on the board | Kept off the system                  |
| Boot public key (Ed25519)          | Stage 1 and stage 2 in internal flash | Not secret; must not be replaceable  |
| Device private key (P-256)         | ATECC608 slot                    | Generated on the chip, can't be read out   |
| Device public key (P-256)          | Pi 5 microSD                     | Not secret; must not be replaceable        |
| Ground station private key (Ed25519) | Pi 5 microSD                   | File permissions only                      |
| Ground station public key (Ed25519) | Internal flash, sector 2        | Not secret; must not be replaceable        |
| Temporary X25519 keys, session keys | STM32 and Pi RAM                | Never stored; wiped after use              |
| Version counter                    | OTP or an ATECC608 counter (undecided) | Can only increase                    |
| Software test key                  | Development builds only          | Must stay out of the release build         |

## Devices on the I2C bus

**STM32 bus:** the ATECC608 is the only storage device planned, at 7-bit address
`0x60`. There's no separate EEPROM in the design, because nothing needs one.

The ATECC608 has its own internal EEPROM, split into these zones:

| Zone          | Size                   | Planned use                                        |
| ------------- | ---------------------- | -------------------------------------------------- |
| Data          | 1208 bytes, 16 slots   | Device private key in one slot; the rest unused for now |
| Configuration | Access rules per slot  | Locked once set, which is permanent                |
| OTP           | 64 bytes               | Unused                                             |
| Counters      | 2 monotonic counters   | Option for the version counter                     |

The exact slot assignment will be decided during provisioning. The ATECC608's
I2C wires aren't protected, so someone with the board could watch or fake that
traffic. The private key itself never crosses the bus.

**Pi bus:** the only device is the IMU, used if the optional kernel driver gets
built. It stores no project data.

## RAM

| Memory      | Address      | Size   | Contents                                          |
| ----------- | ------------ | ------ | ------------------------------------------------- |
| DTCM        | `0x20000000` | 64 KB  | Stacks and session keys                           |
| SRAM1       | `0x20010000` | 240 KB | FreeRTOS heap, lwIP, general data                 |
| SRAM2       | `0x2004C000` | 16 KB  | Ethernet DMA descriptors and buffers              |
| Backup SRAM | `0x40024000` | 4 KB   | Reset reasons and fault log, kept across resets   |

Backup SRAM avoids wearing out flash with fault logs. Its contents aren't secret
and shouldn't be trusted without checking them, and secrets never go there.

This table is the target, and three things don't match it yet:

- **One RAM region:** the linker script treats all 320 KB as one region,
  starting in DTCM, so the current build fills DTCM first and runs about 5 KB
  into SRAM1, ending at `0x200115D0`. Splitting it needs linker script changes.
- **Thread stacks:** they come from the FreeRTOS heap, so they live wherever the
  heap goes. They can't be in DTCM while the heap is in SRAM1, unless the heap
  moves or `linkTask` gets a static stack. See
  [middleware_RTOS.md](middleware_RTOS.md#memory).
- **SRAM2:** 16 KB can't hold the 12 generated RX buffers, and the main stack
  starts at the top of it. See [Memory
  placement](peripheral_ETH.md#memory-placement).

## Not used

The board's external SDRAM isn't part of the design.

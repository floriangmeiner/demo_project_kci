# Boot Sequence and Verification

This is the planned design. The bootloader isn't built yet. The proposed addresses
are in [memory.md](memory.md) and may change.

The STM32 only runs firmware signed with our Ed25519 private key. That key stays off
the board, and the bootloader holds only the public key.

## The three programs

The firmware is three separate programs, each with its own linker script.

| Program     | What it does                                                         | Runs from                     |
| ----------- | -------------------------------------------------------------------- | ----------------------------- |
| Stage 1     | First code after reset. Checks stage 2, and never changes            | Internal flash, `0x08000000`  |
| Stage 2     | The main bootloader. Picks a slot, checks the image, copies it to internal flash | Internal flash, `0x08020000` |
| Application | FreeRTOS, CAN and the encrypted link                                 | Internal flash, `0x08040000`  |

Two bootloader stages mean stage 2 could be fixed later while stage 1 stays
permanently trusted. Merging them into one bootloader is the fallback if Week 2 runs
late, at the cost of never being able to safely update that bootloader.

## Slots A and B

A and B aren't separate programs. They're two storage slots in QSPI flash, and each
holds a signed copy of the application.

```text
Internal flash                         QSPI flash
+------------------+                   +------------------------+
| Stage 1          |                   | Slot A: application v1 |
| Stage 2          | <-- reads slots --| Slot B: application v2 |
| Application      | <-- copies the    +------------------------+
| (running copy)   |     chosen one
+------------------+
```

Both versions are linked for the same internal flash address, because whichever one
is chosen gets copied there before it runs. An update writes the new version into the
slot not holding the last good image, so a version can end up in either slot.

## Boot sequence

```text
Reset
  |
Stage 1 (never changes)
  |  Check stage 2's signature
  |  Bad: stop and report the reason
  |
Stage 2
  |  Install a pending update, if there is one (see below)
  |  Check the application's signature and version
  |  Bad: restore the last good image, or stop if there is none
  |
Application
  |  Runs its startup checks, then confirms itself as good
```

Each step checks the next one before running it, so trust starts at stage 1. Stage 1
is protected by flash write-protection, the MPU and readout protection level 1.

## What gets checked

- **Signature:** proves the image is ours and that no byte has changed.
- **Version:** must not be lower than the stored version counter, so an old image
  with a valid signature is still refused. The counter is kept outside QSPI, because
  QSPI is easier to rewrite.

## Where the images live

| Location            | Contents                           |
| ------------------- | ---------------------------------- |
| Internal flash      | Stage 1, stage 2, running application |
| QSPI flash (16 MB)  | Slot A, slot B, update metadata    |

The application always runs from internal flash.

## Updates and recovery

1. The Pi sends a new signed image over TFTP, and the application writes it to a free
   QSPI slot. See [peripheral_ETH.md](peripheral_ETH.md#loading-firmware-images-with-tftp).
2. Stage 2 verifies it, copies it to internal flash and verifies the copy.
3. The new application starts and has to confirm itself as good.
4. If it does, the update is kept and the version counter goes up.
5. If it resets without confirming, for example from a crash or a watchdog timeout,
   stage 2 restores the last good image from the other slot.

## Showing which version is running

Each application version blinks its own LED, so the result of an update can be seen
on video without a debugger. RTT logs print the version as well.

This takes two general-purpose outputs, each driving an external LED through a series
resistor. The pins are still to be chosen, and must be spare 3.3 V pins that don't
clash with CAN, I2C, Ethernet or QSPI (check UM1907).

The colour belongs to the version, not the slot, and is set at build time. The source
code is the same apart from these flags:

```bash
make app VERSION=1 LED_COLOR=RED
make app VERSION=2 LED_COLOR=GREEN
```

| Demo step                                    | Expected result                          |
| -------------------------------------------- | ---------------------------------------- |
| v1 installed                                 | Red blinks                               |
| v2 built to never confirm itself, then reset | Green blinks briefly, then back to red   |
| Good v2 installed                            | Green blinks                             |
| Tampered image                               | Refused, green keeps blinking            |
| Old signed v1, after v2 is confirmed         | Refused by the version check, green keeps blinking |

Only the application drives these LEDs, so both staying off means the boot stopped
before the application ran.

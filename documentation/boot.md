# Boot Sequence and Verification

This is the planned design. The bootloader isn't built yet, and the exact flash
layout is still to be decided.

The STM32 only runs firmware signed with our Ed25519 private key. That key stays off
the board, and the bootloader holds only the public key.

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

1. A new signed image is written to a free QSPI slot.
2. Stage 2 verifies it, copies it to internal flash and verifies the copy.
3. The new application starts and has to confirm itself as good.
4. If it does, the update is kept and the version counter goes up.
5. If it resets without confirming, for example from a crash or a watchdog timeout,
   stage 2 restores the last good image from the other slot.

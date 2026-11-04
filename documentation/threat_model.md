# Threat Model and Security Requirements

**Status:** Draft for review (Nov 4, 2026)
**Scope:** STM32 "spacecraft" plus Linux "ground station" demo, framed as a
LEO satellite and its ground segment.

## 1. System framing

The STM32 board plays a small satellite bus computer. The Raspberry Pi plays
the ground station. Ethernet stands in for the RF space link, so anything a
radio eavesdropper or a rogue uplink transmitter could do, a host on the
Ethernet segment can do.

Three things about LEO shape the model:

- **The link is public.** Anyone with an antenna in the footprint can listen
  and transmit during a pass. The link must be treated as hostile.
- **There is no hands-on recovery after launch.** A bricked satellite is a
  lost satellite, so availability and safe fallback matter as much as
  secrecy. Every security check must fail to a known good image, never to a
  dead board.
- **Physical access happens before launch.** Integration, test and shipping
  sites are where hands touch the hardware. On orbit, the realistic threats
  arrive over the link or through a bad update.

The real-world analogue is CCSDS Space Data Link Security (SDLS, CCSDS
355.0-B): authenticated encryption, sequence numbers with an anti-replay
window, and managed keys. This demo is a small, honest version of that idea.

```
        Ground segment                    Space segment (STM32)
 +------------------------+        +----------------------------------+
 | Signing host (offline) |        |  Stage 1 boot (immutable, ROT)   |
 |  firmware signing key  |        |        | verifies                |
 +-----------+------------+        |        v                         |
             | signed image        |  Stage 2 / app slots A and B     |
             v                     |        |                         |
 +------------------------+  link  |  +-----+-------------------+     |
 | Ground station (Pi 5)  |<======>|  | Link task | Cmd task     |     |
 |  ground link key       |   TB2  |  | Sensor    | Telemetry    |     |
 +------------------------+        |  +-----+-------------------+     |
                                   |        | TB3                     |
                                   |  Key store (flash, ATECC608 or   |
                                   |  TrustZone secure world)         |
                                   |  SWD debug port  (TB4)           |
                                   +----------------------------------+
```

## 2. Assets

| ID | Asset                        | Property that matters            |
| -- | ---------------------------- | -------------------------------- |
| A1 | Firmware signing private key | Confidentiality (offline only)   |
| A2 | Boot root of trust: stage 1  | Integrity, immutability          |
|    | and the public key it trusts |                                  |
| A3 | Firmware images (A/B slots)  | Integrity, authenticity          |
| A4 | Anti-rollback version state  | Integrity, monotonic             |
| A5 | Device long-term link key    | Confidentiality, non-export      |
| A6 | Session keys and nonces      | Confidentiality, uniqueness      |
| A7 | Telecommands (uplink)        | Integrity, authenticity, fresh   |
| A8 | Telemetry (downlink)         | Integrity, then confidentiality  |
| A9 | Satellite availability       | Must always boot something good  |

Note that commands (A7) are the crown jewel of a real mission. A forged
command can deorbit or burn out a spacecraft; leaked telemetry usually
cannot. Integrity and freshness come before confidentiality.

## 3. Attackers

| ID | Attacker                     | Can do                            |
| -- | ---------------------------- | --------------------------------- |
| T1 | Link eavesdropper            | Read every frame on the link      |
| T2 | Active link attacker         | Inject, replay, reorder, drop,    |
|    | (rogue uplink)               | modify frames; impersonate either |
|    |                              | end                               |
| T3 | Malicious update             | Deliver a forged, corrupted or    |
|    |                              | old (validly signed) image        |
| T4 | Pre-launch physical access   | Probe SWD, I2C and QSPI buses;    |
|    | (integration site, supply    | read or rewrite external flash;   |
|    | chain)                       | attach a debugger                 |
| T5 | Compromised application task | Code execution in one FreeRTOS    |
|    | (bug in a parser)            | task; tries to reach keys, boot   |
|    |                              | code or other tasks               |

## 4. Trust boundaries

- **TB1, signing host to device.** Only images signed by A1 cross into the
  boot chain. The signing key never touches the device or the CI runner.
- **TB2, ground station to satellite.** The link. Nothing received is
  trusted until the AEAD tag and sequence number check pass.
- **TB3, application to secrets.** Application tasks may ask for crypto
  operations but should never read A5 directly.
- **TB4, outside world to chip.** Debug port, external QSPI flash and the
  I2C bus to the secure element are all reachable by T4.

## 5. Scope

**In scope:** T1, T2, T3, and T5 within what the MPU can enforce. T4 limited
to non-invasive access: a debugger on SWD, reading or rewriting QSPI flash,
sniffing or driving the I2C bus.

**Out of scope, stated as limits:**

- Invasive and lab attacks: voltage or clock glitching, laser fault
  injection, decapping, side-channel power analysis. RDP level 1 on STM32F2
  and F7 parts has published glitching bypasses; the demo says so rather
  than claiming protection it does not have.
- Compromise of the ground station host itself, and of the signing host.
- RF jamming and denial of service on the link (detected, not prevented).
- Radiation-induced upsets. These are a safety problem, not a security one,
  though signature checks and A/B fallback also catch a corrupted image.
- Key revocation and over-the-air rekeying (named as future work).

## 6. Requirements

Each requirement names the threats it answers.

| ID  | Requirement                                  | Threats      |
| --- | -------------------------------------------- | ------------ |
| R1  | Immutable stage 1 verifies a signature on    | T3, T4       |
|     | every image before running it (signed boot)  |              |
| R2  | The trusted public key (or its hash) cannot  | T4, T5       |
|     | be rewritten after provisioning              |              |
| R3  | Reject any image older than the stored       | T3           |
|     | minimum version (anti-rollback); state is    |              |
|     | monotonic and survives power loss            |              |
| R4  | A/B slots with a confirm step; a failed or   | T3, A9       |
|     | unconfirmed image falls back, never bricks   |              |
| R5  | Verify images held in external QSPI after    | T4           |
|     | copying to internal flash, not before (no    |              |
|     | check-then-use gap)                          |              |
| R6  | Mutually authenticated handshake with        | T1, T2       |
|     | ephemeral keys (forward secrecy)             |              |
| R7  | AEAD on every frame (ChaCha20-Poly1305 or    | T1, T2       |
|     | AES-GCM); never reuse a nonce under one key  |              |
| R8  | Strict sequence numbers with a replay window | T2           |
|     | in both directions; rekey before wrap        |              |
| R9  | Keys and nonces from a true hardware RNG,    | T1, T2       |
|     | health-checked at start-up                   |              |
| R10 | Device long-term key is never readable by    | T4, T5       |
|     | the application or over the debug port       |              |
| R11 | Debug and readout locked at RDP level 1 in   | T4           |
|     | the "flight" build. **Never RDP level 2.**   |              |
| R12 | Stage 1 and key regions write-protected;     | T4, T5       |
|     | MPU keeps app tasks out of boot and key RAM  |              |
| R13 | Log security events (bad signature, replay,  | All          |
|     | bad tag, rollback attempt) to persistent     |              |
|     | storage and downlink them                    |              |

## 7. Hardware mapping

How well each candidate board meets each requirement. "SW" means done in
software with no hardware help. "Partial" means met against the in-scope
attackers but with a stated limit.

| Req | F746-DISCO + ATECC608          | STM32H573I-DK                    |
| --- | ------------------------------ | -------------------------------- |
| R1  | SW verify (Ed25519 or P-256)   | HW PKA verify; ST or OEM         |
|     |                                | immutable root of trust          |
| R2  | Key hash in OTP + write        | Provisioned into secure option   |
|     | protection on stage 1          | bytes and the RoT, then locked   |
| R3  | ATECC608 monotonic counter, or | Counter in secure flash behind   |
|     | thermometer bits in OTP        | TrustZone                        |
| R4  | MCUboot or custom, SW          | Same, plus OEMiRoT               |
| R5  | Copy QSPI to internal flash,   | Same, or OTFDEC decrypt-on-fly   |
|     | then verify                    |                                  |
| R6  | ECDH in ATECC608 (P-256) or    | HW PKA, keys in secure world     |
|     | X25519 in SW                   |                                  |
| R7  | SW ChaCha20-Poly1305           | HW AES-GCM                       |
| R8  | SW                             | SW                               |
| R9  | On-chip RNG                    | On-chip RNG                      |
| R10 | Partial: key stays in the      | Yes: secure world, plus SAES     |
|     | ATECC608, but the app can use  | with a hardware unique key       |
|     | it as an oracle                |                                  |
| R11 | RDP level 1 (partial,          | Product state "Closed" with a    |
|     | glitchable)                    | regression password              |
| R12 | WRP + MPU (FreeRTOS-MPU)       | TrustZone + MPU                  |
| R13 | Any board                      | Any board                        |

The F207 plus ATECC608 maps the same as the F746 column on every row, only
slower, so it is not listed separately (see the first note below).

Notes on the mapping:

- **The F207 adds nothing over the F746.** It is slower, has less RAM, and
  has no QSPI or crypto hardware (the crypto variant is the F217). Drop it.
- **ATECC608 bus exposure.** A T4 attacker on the I2C bus can talk to the
  secure element directly. Use the ATECC608's IO protection key to bind it
  to this MCU, and accept that the binding secret then sits in MCU flash
  under RDP level 1.
- **ATECC608 locking is irreversible.** Locking its config and data zones
  cannot be undone, which is the same class of step as RDP level 2. Buy a
  spare and write the config down before locking.
- **The H5 equivalent of the RDP rule.** H5 parts use product states instead
  of RDP levels. "Closed" can be regressed with a provisioned password;
  "Locked" is permanent. The ground rule becomes: **never set the "Locked"
  product state**, and never close the part before the regression password
  is provisioned and tested.
- **NUCLEO-H563ZI check.** As far as I know the H563 has TrustZone but not
  the AES, SAES and PKA blocks; those come with the H573. Worth confirming
  in the datasheet before ordering, since the plan lists the H563 as having
  hardware crypto.

## 8. Recommendation

Build on the **F746-DISCO plus ATECC608**. It meets every requirement
against the in-scope attackers, it is already owned, and it keeps the
4-week schedule. Its two honest gaps are R10 (the app can use the key even
if it cannot read it) and R11 (RDP level 1 is glitchable). Both get stated
in the README as known limits, which is itself a good signal for the role.

Keep the **STM32H573I-DK** as the stretch port. It closes R10 and R11 with
TrustZone and lifecycle states, and that before-and-after comparison makes a
strong interview story. It does not justify a board change now unless it can
arrive this week.

## 9. Open questions

- Board choice: confirm the recommendation above, or switch now.
- Are you willing to lock an ATECC608 (irreversible), or should the demo
  run with an unlocked part and say so?
- Ed25519 in software for boot, or P-256 everywhere so boot and link share
  the ATECC608? P-256 everywhere is simpler; Ed25519 is faster in software.

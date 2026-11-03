# Cryptography

This project uses five cryptographic techniques. They answer three questions: is this
firmware genuine, who is on the other end of the link, and how is the traffic
protected?

## Signing and encrypting

- **Signing** proves who created something and that it hasn't changed. A private
  key creates the signature, and a public key checks it. The public key doesn't
  need to be secret.
- **Encrypting** hides the content, so only someone with the right key can read
  it.

## Cryptographic techniques used in this system

| Technique               | Algorithm         | What it is                  | Why it matters                                                                | Where it runs                              |
| ----------------------- | ----------------- | --------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------ |
| Boot signing            | Ed25519           | Digital signature           | Stops tampered or unauthorized firmware from running                          | Signed on the laptop, checked on the STM32 |
| Session keys            | Ephemeral X25519  | Key exchange                | Creates a fresh secret for each session, so recorded traffic stays protected  | STM32 and Pi                               |
| Traffic                 | ChaCha20-Poly1305 | Authenticated encryption    | Stops anyone reading telemetry or changing commands in transit                | STM32 and Pi                               |
| Device identity         | P-256             | Hardware-backed signature   | Proves the Pi is talking to the real STM32, and the key can't be copied off the chip | Signed on the ATECC608, checked on the Pi  |
| Ground station identity | Ed25519           | Digital signature           | Proves the STM32 is taking commands from the real ground station              | Signed on the Pi, checked on the STM32     |

### 1. Boot signing (Ed25519)

This protects the firmware.

- **How it works:** the developer's laptop signs each firmware image with a
  private key. The STM32 holds only the public key, and it checks the signature
  before running the image.
- **Why the private key stays off the board:** someone who steals the board can't
  use it to sign malicious firmware.
- **Why Ed25519:** it's a modern signature scheme that's fast in software and hard
  to implement badly.

### 2. Session keys (ephemeral X25519)

This creates a shared secret for the link.

- **How it works:** X25519 is a key exchange. Each side generates a temporary key
  pair and sends over its public half, and both can then calculate the same
  secret. Someone watching the wire sees both public halves but can't calculate
  it.
- **What "ephemeral" means:** the keys are new for each session and thrown away
  afterwards. Stealing a long-term key later doesn't unlock recorded traffic,
  which is called forward secrecy.
- **The gap it leaves:** X25519 alone doesn't tell you who you're talking to. The
  two identity items close that gap.

### 3. Traffic (ChaCha20-Poly1305)

This protects every packet after the handshake, using a key derived from the
shared secret.

- **ChaCha20** encrypts the data, so nobody can read it.
- **Poly1305** adds a tag, so any change to the packet is detected and it gets
  rejected.
- **Why ChaCha20 instead of AES:** speed. The F746 has no crypto hardware, so
  encryption runs in software, where ChaCha20 is generally faster than AES. AES
  mainly pulls ahead on chips with hardware acceleration.

### 4. Device identity (P-256 on the ATECC608)

This proves the Pi is talking to the real STM32.

- **How it works:** during the handshake, the ATECC608 signs the session's key
  exchange using a private key that can't be read off the chip. The Pi checks that
  signature in Python with the device's known public key.
- **Why P-256:** it's the only curve the ATECC608 supports, so the hardware decides
  this one.

### 5. Ground station identity (Ed25519 on the Pi)

This is the same check in the other direction, proving the STM32 is talking to the
real ground station.

- **How it works:** the Pi signs with its private key, stored in software, and the
  STM32 checks it with Monocypher.
- **Why not P-256 here too:** the STM32 would need extra P-256 code. Using Ed25519
  lets it reuse what the bootloader already needs.

## How they work together

```text
Power on:  STM32 checks the firmware signature (Ed25519)
              |
Connect:   Both sides exchange temporary keys (X25519)
           STM32's ATECC608 signs the exchange (P-256); Pi verifies
           Pi signs the exchange (Ed25519); STM32 verifies
              |
Running:   Every packet is encrypted and tagged (ChaCha20-Poly1305)
```

The signatures are what stop a man-in-the-middle attack. An attacker who swaps the
temporary keys in transit changes what was signed, so the check fails and no
session is set up.

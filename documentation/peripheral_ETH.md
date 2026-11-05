# Ethernet Peripheral

How Ethernet is set up on the STM32F746G-DISCO, using FreeRTOS, lwIP and DMA, to carry
the encrypted UDP link to the Raspberry Pi 5.

These values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`) and the
generated code. Nothing has been tested on hardware, and the recommendations below are
proposals until they're built and tested.

## Settings

| Setting            | Value                         | Status                                     |
| ------------------ | ----------------------------- | ------------------------------------------ |
| Interface and PHY  | RMII, LAN8742                 | Good                                       |
| RX mode            | Interrupt                     | Good: a task wakes when a frame arrives    |
| Ethernet interrupt | On, priority 6                | Good: FreeRTOS `FromISR` calls are allowed |
| lwIP               | 2.1.2 (ST's Cube version)     | Good                                       |
| FreeRTOS           | CMSIS-RTOS v2                 | Good                                       |
| DHCP               | Off                           | Good: the direct cable has no DHCP server  |
| STM32 IP address   | `10.1.1.123`                  | Good                                       |
| Netmask            | `255.255.255.0`               | Good                                       |
| Gateway            | `10.1.1.1`                    | Not needed on a direct cable, but harmless |
| Default task stack | 1024 words (4 KB)             | Good if lwIP starts from this task         |
| FreeRTOS heap      | 32,768 bytes                  | Good: see [Memory](middleware_RTOS.md#memory) |
| Descriptor and buffer addresses | Not set          | **Open:** see [Memory placement](#memory-placement) |
| Data cache         | Not enabled                   | Good: off by decision, see [Caches](#caches) |
| Instruction cache  | Enabled                       | Good: see [core_cortexM7.md](core_cortexM7.md) |

CubeMX shows addresses with leading zeros, such as `010.001.001.123`. These are still
decimal values. The Pi needs a static address on the same subnet, such as `10.1.1.1`.

### Pins

| Signal      | STM32 pin |
| ----------- | --------- |
| `REF_CLK`   | `PA1`     |
| `MDIO`      | `PA2`     |
| `MDC`       | `PC1`     |
| `CRS_DV`    | `PA7`     |
| `RXD0`      | `PC4`     |
| `RXD1`      | `PC5`     |
| `TX_EN`     | `PG11`    |
| `TXD0`      | `PG13`    |
| `TXD1`      | `PG14`    |

These go to the on-board PHY and RJ45 connector CN9, so they don't need any wiring.

## Network protocols

lwIP provides the network protocols. The values below come from the `.ioc`, or from
lwIP's defaults where the `.ioc` and `lwipopts.h` don't list a setting.

### Enabled

| Protocol | Layer     | General function                                     | How it's useful here                                                        |
| -------- | --------- | ---------------------------------------------------- | --------------------------------------------------------------------------- |
| Ethernet | Link      | Carries frames between devices on the same cable     | The physical link from the STM32 to the Pi                                  |
| ARP      | Link      | Finds the Ethernet (MAC) address for an IP address   | Lets the STM32 and Pi find each other from their static IPs                 |
| IPv4     | Network   | Addresses packets and routes them between networks   | Carries the `10.1.1.x` addressing, and splits or rejoins oversized packets  |
| ICMP     | Network   | Sends network status and error messages              | Makes `ping` work, which is the quickest first test of the link             |
| UDP      | Transport | Sends individual packets, with no connection or retries | Carries telemetry and commands; a late reading is better replaced than resent |
| TCP      | Transport | Sends a reliable, ordered byte stream over a connection | Not used by this project; on by default (see below)                         |
| TFTP     | Application | Transfers files in small numbered blocks over UDP  | Loads signed firmware images onto the board (not enabled in the `.ioc` yet) |

Each protocol is carried inside the one below it:

```text
Encrypted telemetry or command (our protocol, not part of lwIP)
  inside UDP (which port)
    inside IPv4 (which device)
      inside Ethernet (which MAC address on the cable)
```

ARP and ICMP are helpers that work alongside this. They don't carry application data.

**Why UDP:** the link is soft real-time, and telemetry goes out every 500 ms. If a packet
is lost, the next one replaces it, whereas TCP would hold up newer data while resending
the old. Commands still need confirming, so the design adds its own command IDs and
acknowledgements. UDP also doesn't protect data, which is what the AEAD encryption and
replay protection are for.

**Recommendation for TCP:** turn it off in lwIP if nothing ends up using it. That saves
memory and removes code an attacker could reach over the link.

**Security note:** ARP and ICMP have no authentication, so someone on the link could fake
their messages. That could disrupt traffic or redirect it, but they couldn't read or
forge commands, because that protection comes from the encrypted link above them.

### Loading firmware images with TFTP

The Pi sends a signed image to a TFTP server in the running application, on UDP port
69, using lwIP's TFTP server. This is the planned design, and it's untested. To turn it
on, enable `LWIP_TFTP` in CubeMX and call `tftp_init` with the callbacks that write to
QSPI.

```text
Pi: tftp put image.bin
  |
Application receives 512-byte blocks and writes them to the inactive QSPI slot
  |
Application asks for a restart once the transfer is complete
  |
Stage 2 verifies the signature and version, then installs the image
```

Things to design for:

- **TFTP has no security of its own.** It has no login or encryption, so anyone on the
  link could try to send a file. An image without a valid signature is still refused at
  boot, but someone could keep overwriting the inactive slot to disrupt an update. Keep
  the server off until the ground station sends an authenticated "update" command over
  the encrypted link, and turn it off again afterward.
- **The image isn't secret.** TFTP sends it unencrypted, so a capture reveals the firmware.
  That's acceptable here because no secrets are stored in images.
- **Slow flash can stall the network.** lwIP's TFTP server runs on lwIP's raw API, so its
  callbacks run in `tcpip_thread`. Erasing QSPI inside a callback would block all network
  traffic, so erase the slot before the transfer starts.
- **Only the application receives images.** The bootloader has no network code, which
  keeps it small and easier to trust.
- **An interrupted transfer must be harmless.** Only mark an update as pending after the
  full image has arrived. The active slot is never touched.

### Turned off

| Protocol or service | General function                          | Why it's off                                  |
| ------------------- | ----------------------------------------- | --------------------------------------------- |
| DHCP                | Assigns IP addresses automatically        | Static IPs; the direct cable has no server    |
| DNS                 | Turns names into IP addresses             | Devices use IP addresses directly             |
| AutoIP              | Picks an address when there's no DHCP     | Static IPs                                    |
| IPv6                | Newer version of IP                       | IPv4 is enough for a direct cable             |
| IGMP                | Manages multicast groups                  | There are only two devices on the link        |
| HTTP server (HTTPD) | Serves web pages                          | No web interface, and less to attack          |
| SNMP                | Monitors and manages network devices      | Telemetry already reports status              |
| SNTP                | Sets the clock from a time server         | Not needed: there's no server on the link     |

## DMA

DMA isn't optional here. The F746's Ethernet controller has its own built-in DMA, and
ST's driver only works through it. This is also the simplest setup.

**Why CubeMX shows no DMA options for Ethernet:** CubeMX's DMA Settings tab is for the
general-purpose DMA1 and DMA2 controllers, where you choose a stream and channel. The
Ethernet controller doesn't use those. Its DMA is part of the Ethernet peripheral, so
there's nothing to assign, and it's always in use. It's configured through descriptors
and buffers instead: the driver sets them up, and [Memory placement](#memory-placement)
covers where they go.

### What DMA does

DMA moves network data between the Ethernet controller and RAM without the CPU. A
received frame takes this path:

```text
Frame arrives from the PHY
  |
Ethernet DMA copies it into a receive buffer in RAM (no CPU involved)
  |
Ethernet interrupt fires
  |
EthIf thread wakes and passes the frame to lwIP
  |
linkTask receives it from its UDP socket
```

Sending works the other way: the driver points the DMA at the frame in RAM, and the DMA
feeds it to the controller.

### Why it helps this project

- **The CPU is free for other work.** It doesn't have to copy each frame byte by byte,
  so it stays available for crypto and CAN polling.
- **A busy CPU doesn't lose frames straight away.** During a slow handshake calculation,
  incoming frames still land in the receive buffers. Frames are only dropped if all the
  buffers fill up.
- **It suits FreeRTOS.** Threads can sleep until the interrupt says a frame has arrived,
  so nothing wastes time checking for data.
- **There's less custom code.** ST's driver and lwIP port already work this way.

Speed isn't the main reason. A telemetry packet every 500 ms wouldn't stress the CPU
either way. The practical reason is that this is how the hardware and ST's driver work,
and the other benefits come with it.

### What it costs

- **Memory placement:** descriptors and buffers must go in the right RAM, using linker
  sections. See [Memory placement](#memory-placement).
- **Cache handling:** with the data cache on, the CPU and DMA can see different data.
  Starting with it off avoids this. See [Caches](#caches).
- **Harder debugging:** a wrong descriptor or buffer setting can stop traffic without
  any obvious error.
- **RAM use:** the buffers take up RAM permanently.

## Recommended setup

1. **Keep interrupt RX mode.** A dedicated Ethernet task sleeps until a frame arrives,
   so it uses no CPU in between.
2. **Keep static IPs and DHCP off.** The Pi and the STM32 connect directly.
3. **Use lwIP's `netconn` or socket API from a task.** This keeps network code out of
   interrupts.
4. **Decide where descriptors and buffers go.** See [Memory placement](#memory-placement).
5. **Keep the data cache off and the instruction cache on.** See [Caches](#caches).

## Memory placement

[system_memory.md](system_memory.md) plans to put descriptors and buffers in SRAM2 at
`0x2004C000`, but that doesn't work with the generated code as it stands.

The generated code places the descriptors in sections named `.RxDescripSection` and
`.TxDescripSection`, but `STM32F746xx_FLASH.ld` has no entries for them and has one 320 KB
RAM region. The current build's linker map shows where everything ends up:

| Item                   | Size         | Address now  | Memory |
| ---------------------- | ------------ | ------------ | ------ |
| TX descriptors         | 160 bytes    | `0x20000088` | DTCM   |
| RX descriptors         | 160 bytes    | `0x20000128` | DTCM   |
| RX buffers, 12         | 18,819 bytes | `0x20000668` | DTCM   |
| lwIP packet pool       | 9,731 bytes  | `0x2000E3BC` | Crosses from DTCM into SRAM1 |
| lwIP heap              | 1,600 bytes  | `0x20048000` | SRAM1  |
| Main stack (top)       | 1 KB minimum | `0x20050000` | SRAM2  |

Moving these to SRAM2 runs into two problems:

- **Size:** SRAM2 is 16 KB, and the 12 RX buffers alone need 18.8 KB. About 10 buffers would
  fit alongside the descriptors, with nothing else there.
- **Main stack:** the stack used before the scheduler starts, and by interrupts afterward,
  starts at the top of SRAM2 and grows down. It would need to move.

The lwIP heap address is fixed by `LWIP_RAM_HEAP_POINTER`, and the linker doesn't reserve
it. Linked data currently ends at `0x200115D0`, so it's safe while other RAM use stays below
it. Check it if the RAM layout changes.

**Recommendation:** leave these where the linker puts them for the first bring-up, and get
`ping` working. RM0385 section 2.1.10 lists SRAM1, SRAM2 and DTCM as targets of the Ethernet
DMA, so all of today's locations are reachable. With the data cache off, there's no coherency
reason to separate them. SRAM2 placement only becomes necessary if the data cache is turned
on later, because that's what the MPU non-cacheable region would cover.

## Caches

**Decision: the data cache is off.** With it off, the CPU and the Ethernet DMA always see
the same data in RAM, so this whole type of bug can't happen, and no MPU regions or cache
maintenance are needed to get Ethernet working. The demo traffic is light, and DTCM is
fast without a cache, so the cost should be small. It can be revisited if crypto is
measurably too slow. The details are below.

### What a cache is

A cache is a small, fast memory inside the Cortex-M7 that keeps copies of recently used
data, because reading main memory is slower. The F746 has two:

- **Instruction cache:** holds copies of code. Code doesn't change while running, so it
  can't go out of date in normal use.
- **Data cache:** holds copies of data from RAM. With it on, a CPU write can stay in the
  cache for a while before reaching RAM, and a CPU read can return the cached copy
  without looking at RAM at all.

This works without any special handling as long as the CPU is the only thing using that
RAM.

### Why the Ethernet DMA makes this harder

The DMA reads and writes RAM directly and can't see the cache, so the CPU and the DMA
can end up with different values for the same address. This can go wrong in two ways:

```text
Sending: the DMA sends old data
  CPU writes a new frame      -> new data is still only in the cache
  DMA reads the buffer in RAM -> finds old data and sends it

Receiving: the CPU reads old data
  DMA writes a new frame to RAM -> RAM has the new data
  CPU reads the buffer          -> gets the old copy from the cache
```

The same problem can affect descriptors, the small records the CPU and DMA use to pass
buffers back and forth. It can look like corrupted frames, repeated old frames or
traffic stopping. These bugs are hard to find because they depend on what's in the
cache at the time, and they can seem to disappear when you change the code or attach a
debugger.

For this project, a corrupted frame would normally fail the AEAD tag check, so it would
look like a crypto or network error rather than a cache problem.

### Where the cache matters in the Ethernet stack

Only the bottom of the stack shares memory with the DMA. Everything above it is
ordinary CPU code.

| Layer                    | Job                                       | Affected by the cache? |
| ------------------------ | ----------------------------------------- | ---------------------- |
| `linkTask`               | Encrypts telemetry, decrypts commands     | No                     |
| lwIP                     | Handles IP and UDP                        | No                     |
| `ethernetif.c`           | Connects lwIP to ST's driver              | Yes, if handling buffers directly |
| ST's ETH driver          | Manages descriptors and buffers           | Yes                    |
| Ethernet MAC and DMA     | Moves frames between hardware and RAM     | Source of the problem  |
| LAN8742 PHY              | Converts to and from signals on the cable | No                     |

### The three ways to handle it

| Option                          | How it works                                                     | Effort and risk                                                       |
| ------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| Data cache off (our start)      | The CPU always uses RAM directly, so both sides see the same data | No extra setup, but other CPU code loses the cache's speed           |
| MPU non-cacheable region        | The cache stays on, but the MPU excludes the DMA's memory from it | One MPU region, which must cover all descriptors and buffers         |
| Manual cache maintenance        | Code cleans the cache before sending and invalidates it before reading | Easy to get wrong: one missed call causes the bugs above; needs buffers aligned to 32-byte cache lines |

### What we're doing

1. **Keep the data cache off and the instruction cache on.** The instruction cache has no
   coherency problem with the Ethernet DMA, and the demo traffic is light.
2. **Get Ethernet working and measure crypto speed.** Only change this if crypto is
   measurably too slow.
3. **If the data cache is needed, use an MPU non-cacheable region** for the Ethernet part
   of SRAM2, rather than manual maintenance. Check that the region covers every
   descriptor and buffer, and retest all the link demos.

Turning the data cache on may not help as much as expected. DTCM, where
[system_memory.md](system_memory.md) plans to keep stacks and session keys, is never cached and is
already fast.

## To check on hardware

- The FreeRTOS heap has room for the lwIP tasks, mailboxes and application tasks.
- The Pi can ping `10.1.1.123` over the direct cable.

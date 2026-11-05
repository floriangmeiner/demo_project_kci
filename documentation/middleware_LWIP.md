# lwIP Middleware

How lwIP, the network stack, is set up on the STM32F746G-DISCO, what its main
settings do, and a CubeMX labelling problem to watch for.

Values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`), the
generated `LWIP/Target/lwipopts.h`, and lwIP's defaults in `opt.h` where
`lwipopts.h` doesn't set a value. Nothing has been tested on hardware.

> **CubeMX gotcha: `TCPIP_THREAD_STACKSIZE` and `DEFAULT_THREAD_STACKSIZE` are
> labelled "Word(s)" but used as bytes.** Entering 4096 gives a 4096-byte stack,
> not 16,384 bytes. Find them at Pinout & Configuration > Middleware and
> Software Packs > LWIP > Configuration > Key Options > Infrastructure -
> Threading Options. See [Stack size units](#stack-size-units).

## What lwIP is

lwIP ("lightweight IP") is an open-source TCP/IP stack for small systems. It
turns application data into Ethernet frames and back, and handles ARP, IPv4,
ICMP, UDP and TCP along the way. ST's version, 2.1.2_Cube, comes with a port for
FreeRTOS and the F7's Ethernet driver.

```text
linkTask (our code)
   │  netconn or socket API
   ▼
tcpip_thread         lwIP's core: UDP, IP, ARP, ICMP, timers
   ▲
   │  received frames
EthIf thread         wakes on the Ethernet interrupt
   ▲
Ethernet MAC and DMA ── LAN8742 PHY ── RJ45 ── Raspberry Pi 5
```

[peripheral_ETH.md](peripheral_ETH.md) covers the Ethernet hardware, DMA and
which protocols are on, and [middleware_RTOS.md](middleware_RTOS.md) covers how
these threads fit with the application.

## Stack size units

CubeMX's two stack size settings use different units, but show them the same
way:

| Setting, as CubeMX names it | Path in CubeMX | Label shown | Actual unit | Why |
| --------------------------- | -------------- | ----------- | ----------- | --- |
| Stack Size (Words) | Pinout & Configuration > Middleware and Software Packs > FREERTOS > Configuration > Tasks and Queues > double-click a task | Words | **Words** | The generated code multiplies by 4, such as `.stack_size = 1024 * 4` |
| `TCPIP_THREAD_STACKSIZE` (TCPIP Thread Stack Size) | Pinout & Configuration > Middleware and Software Packs > LWIP > Configuration > Key Options > Infrastructure - Threading Options | Word(s) | **Bytes** | `sys_arch.c` passes the number straight to `osThreadNew`, and `cmsis_os2.c` treats `stack_size` as bytes |
| `DEFAULT_THREAD_STACKSIZE` (Default LwIP Thread Stack Size) | Same as `TCPIP_THREAD_STACKSIZE` | Word(s) | **Bytes** | Same code path as `TCPIP_THREAD_STACKSIZE` |

CubeMX's help text for `TCPIP_THREAD_STACKSIZE` also says "Word 32 bits", with
limits of 256 to 8,192 words, so the help text is as misleading as the label.

**What to do:** for the lwIP settings, enter the size you want in bytes, and
ignore the "Word(s)" label. To check, look at the generated `lwipopts.h`: the
number there is passed to the thread as bytes. This affects ST's CubeMX for
FW_F7 V1.17.4 with CMSIS-RTOS v2, and may differ in other versions.

**Why it matters:** a stack a quarter of the expected size overflows easily. The
overflow can corrupt other memory without an obvious error, which is the kind of
bug that looks like a network or crypto fault.

## Threads

| Thread         | Created by     | Stack, set where                      | Stack now   | Recommended | Priority | Job |
| -------------- | -------------- | ------------------------------------- | ----------- | ----------- | -------- | --- |
| `tcpip_thread` | lwIP           | CubeMX, `TCPIP_THREAD_STACKSIZE`      | 4096 bytes  | Keep        | 24 | Runs the whole stack. All lwIP work happens here |
| `EthIf`        | `ethernetif.c` | `INTERFACE_THREAD_STACK_SIZE` in a `USER CODE` block of `ethernetif.c`; not in CubeMX | 350 bytes | 1024 bytes | 48 | Wakes on the Ethernet interrupt and passes received frames to `tcpip_thread` |
| `EthLink`      | `lwip.c`       | `INTERFACE_THREAD_STACK_SIZE` in `lwip.c` | 1024 bytes | Keep      | 16       | Checks the cable link with the PHY and updates lwIP |

### Raising the `EthIf` stack

CubeMX has no setting for this thread, so change it by hand near the top of
`LWIP/Target/ethernetif.c`:

```c
/* USER CODE BEGIN OS_THREAD_STACK_SIZE_WITH_RTOS */
/* Stack size of the interface thread */
#define INTERFACE_THREAD_STACK_SIZE ( 1024 )
/* USER CODE END OS_THREAD_STACK_SIZE_WITH_RTOS */
```

Why this change, and why here:

| Question | Answer |
| -------- | ------ |
| Why raise it? | The generated 350 bytes is only about 87 words. Each time FreeRTOS switches away from the thread, it saves the CPU registers on this stack: about 70 bytes, or about 200 bytes if the thread has used the floating-point unit. That can leave as little as 150 bytes for the HAL receive code and lwIP calls this thread runs. |
| Why 1024? | It gives several times that margin for 674 extra bytes of heap, which the 32,768-byte heap can spare. It's a starting point, not a measurement. |
| Why between the `USER CODE` lines? | CubeMX keeps anything between `USER CODE BEGIN` and `USER CODE END` when it regenerates, and overwrites everything else. A change outside them would quietly return to 350. |
| What unit is it? | Bytes. It's passed to `osThreadNew` as `stack_size`, like the lwIP settings in [Stack size units](#stack-size-units). |
| How to confirm it's enough? | Once frames are flowing, check the thread's high water mark. See [Measuring stacks](middleware_RTOS.md#measuring-stacks). Keep at least 20% free. |

## Key settings

| Setting | Value | Set in | What it does | Why it matters here |
| ------- | ----- | ------ | ------------ | ------------------- |
| `TCPIP_THREAD_STACKSIZE` | 4096 | CubeMX, Key Options | Stack for `tcpip_thread`, in bytes | Too small risks silent overflow. See [Stack size units](#stack-size-units) |
| `TCPIP_THREAD_PRIO` | 24 (`osPriorityNormal`) | CubeMX, Key Options | Priority of `tcpip_thread` | Equal to `defaultTask`, above `canOpenTask` and `linkTask` |
| `TCPIP_MBOX_SIZE` | 6 | CubeMX, Key Options | How many messages can queue for `tcpip_thread` | Messages beyond this are dropped or block the sender |
| `DEFAULT_UDP_RECVMBOX_SIZE` | 6 | CubeMX | How many received UDP packets can wait for `linkTask` | Extra packets are dropped if `linkTask` falls behind |
| `DEFAULT_THREAD_STACKSIZE` | 1024 | CubeMX, Key Options | Stack for other threads lwIP creates through `sys_thread_new` | Not used by this project's threads |
| `LWIP_DHCP` | Off | CubeMX, General Settings | Automatic address assignment | Off, because the direct cable uses static IPs |
| IP address, netmask, gateway | `10.1.1.123`, `255.255.255.0`, `10.1.1.1` | CubeMX, General Settings | The STM32's static network settings | Must match the Pi's subnet |
| `LWIP_TCP` | On (default) | CubeMX | TCP support | Not used; turning it off saves memory and removes code reachable over the link |
| `LWIP_UDP` | On (default) | CubeMX | UDP support | Carries telemetry and commands |
| `LWIP_NETCONN`, `LWIP_SOCKET` | On (default) | CubeMX | Thread-safe APIs for calling lwIP from our threads | `linkTask` uses one of them, never lwIP's raw API |
| `MEM_SIZE` | 1,600 bytes (default) | CubeMX | lwIP's own heap, used for outgoing packets | Telemetry frames are small, so this should be enough; check if sends fail |
| `LWIP_RAM_HEAP_POINTER` | `0x20048000` | CubeMX | Fixes lwIP's heap at that address instead of letting the linker place it | The linker doesn't reserve it. See [Memory placement](peripheral_ETH.md#memory-placement) |
| `PBUF_POOL_SIZE` | 16 (default) | CubeMX | Number of packet buffers lwIP keeps ready | Part of lwIP's fixed RAM use |
| `CHECKSUM_BY_HARDWARE` | 1 | CubeMX | The Ethernet MAC calculates and checks IP, UDP, TCP and ICMP checksums, so lwIP's software checksums are off | Saves CPU time; confirm in Wireshark that outgoing checksums are correct |
| `LWIP_NETIF_LINK_CALLBACK` | 1 | CubeMX | Lets lwIP react when the cable is plugged in or removed | Used by `EthLink` to report link state |
| `LWIP_STATS` | 0 | CubeMX | lwIP's internal counters | Off; turn on to debug dropped packets |
| `RECV_BUFSIZE_DEFAULT` | 2,000,000,000 | CubeMX | Limit on queued received data per connection | Effectively no limit; the mailbox size is the real limit |

The 12 receive buffers and the Ethernet DMA descriptors are set in
`ethernetif.c` and the HAL, not in lwIP. See
[peripheral_ETH.md](peripheral_ETH.md#memory-placement).

## To check

- `INTERFACE_THREAD_STACK_SIZE` in `ethernetif.c` is raised to 1024, and
  survives regenerating.
- Measure each thread's free stack with `uxTaskGetStackHighWaterMark` once
  traffic is flowing. See [Measuring
  stacks](middleware_RTOS.md#measuring-stacks).
- Turn off `LWIP_TCP` once the UDP link works, and confirm the build still
  links.

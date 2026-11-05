# UART Peripheral

What the UART is for in this project, how USART1 and its DMA are set up on the STM32F746G-DISCO,
and what each CubeMX DMA setting means.

Values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`) and the generated code.
DMA facts are from RM0385 Rev 9. Nothing has been tested on hardware.

> **Open issue:** the purpose below is a proposal until it's agreed. The CubeMX setup matches
> [Recommended setup](#recommended-setup).

## What the UART is for

USART1 is wired to the on-board ST-LINK, which now runs J-Link firmware and presents it to the
laptop as a virtual COM port (`/dev/ttyACM0`). No extra wiring is needed: it goes over the same USB
cable as the debugger.

The project already has SEGGER RTT for logging, so the UART needs its own reason to exist:

| Need | RTT | UART |
| ---- | --- | ---- |
| Works without a debugger session attached | No: RTT is read through the debugger | **Yes:** any serial terminal works |
| Works in both bootloader stages | Possible, but needs the RTT code linked into each | **Yes:** a few lines of polled output, no RTOS needed |
| Speed | Very fast, almost no CPU time | 115200 baud, about 11.5 KB/s |
| Shows interrupts and DMA on a classic interface | No | **Yes:** the posting asks for UART and interrupt experience |

**Proposed use: an always-available console.**

- **Output:** boot messages from stage 1 and stage 2 (which image was chosen and why), plus short
  status lines from the application, such as link up, CAN module lost and version.
- **Input:** a few read-only commands typed in a terminal, such as `status` and `version`.
- **Hardware tests:** pytest can read `/dev/ttyACM0` to check the boot result without starting a
  debugger session. RTT stays the main log for detailed debugging.

**Security limits:** a console is an entry point. It must never accept keys, firmware or commands
that change outputs or settings; those only arrive over the authenticated link. Keep input commands
out of release builds, following the plan's guardrail on debug paths, and never print key material.

## Settings

| Setting | Value | Notes |
| ------- | ----- | ----- |
| Instance | USART1, asynchronous | |
| TX pin | `PA9` | To the ST-LINK's virtual COM port |
| RX pin | `PB7` | Not `PA10`, which goes to the USB ID line |
| Baud rate, format | 115200, 8 data bits, no parity, 1 stop bit | The common default for terminals |
| Clock | 108 MHz (APB2) | Plenty for 115200 |
| USART1 global interrupt | On, priority 5 | Needed for idle-line detection and to finish DMA sends |

## DMA

DMA moves received bytes from the USART into a RAM buffer without the CPU. Without it, the CPU takes
an interrupt for every byte, about every 87 µs at 115200 baud. With it, the CPU only hears about
complete lines or full buffers.

### Why the direction can't be changed

Each DMA request is tied to one data flow. `USART1_RX` always moves data from the peripheral into
memory, so CubeMX only offers "Peripheral To Memory" for it. Sending needs a second request,
`USART1_TX`, which is memory to peripheral. Add it with the Add button in the DMA Settings tab.

| Request   | Direction           | DMA stream (channel 4) |
| --------- | ------------------- | ---------------------- |
| `USART1_RX` | Peripheral to memory | DMA2 stream 2 (used) or stream 5 |
| `USART1_TX` | Memory to peripheral | DMA2 stream 7 (used)  |

### Two different priorities

The "priority 5" in the TODO and the Low to Very High list in the DMA tab are **different settings
that control different things**, so one doesn't map onto the other:

| Setting | Where in CubeMX | Values | What it decides |
| ------- | --------------- | ------ | --------------- |
| **Interrupt priority** (NVIC) | System Core > NVIC | 0 (most urgent) to 15 | Which interrupt handler runs first when several are waiting, and whether a handler may call FreeRTOS. 5 to 15 may, 0 to 4 may not |
| **DMA stream priority** | Connectivity > USART1 > DMA Settings > Priority | Low, Medium, High, Very High | Which DMA stream gets the bus first when several streams on the same DMA controller want it at the same moment |

DMA stream priority is a two-bit field in the stream's control register:

| CubeMX label | Register value (`PL`) | HAL name |
| ------------ | --------------------- | -------- |
| Low          | 0                     | `DMA_PRIORITY_LOW` |
| Medium       | 1                     | `DMA_PRIORITY_MEDIUM` |
| High         | 2                     | `DMA_PRIORITY_HIGH` |
| Very High    | 3                     | `DMA_PRIORITY_VERY_HIGH` |

If two streams have the same priority, the lower stream number goes first.

**For this project, use Low.** USART1 is the only user of DMA2 so far: Ethernet has its own DMA, and
QSPI doesn't use DMA. At 11.5 KB/s it barely loads the bus anyway.

The interrupts that need priority 5 are `USART1_IRQn` and the DMA stream interrupts, such as
`DMA2_Stream2_IRQn`. Their callbacks will pass data to a thread with FreeRTOS `FromISR` functions,
which requires 5 or higher in number. See [core_NVIC.md](core_NVIC.md#freertos-limit).

### DMA request settings

| Setting | Options | What it means | Receive (RX) | Transmit (TX) |
| ------- | ------- | ------------- | ------------ | ------------- |
| **Mode** | Normal, Circular | Normal stops after the set number of bytes. Circular wraps to the start of the buffer and keeps going forever | **Circular**, so no byte is missed between transfers | **Normal**: send one message, then stop |
| **Increment address: Peripheral** | On, off | Move to the next peripheral address after each transfer | **Off**: the USART has one data register | **Off** |
| **Increment address: Memory** | On, off | Move to the next RAM address after each transfer | **On**: fill the buffer in order | **On**: read the message in order |
| **Use FIFO** | On, off | Puts the DMA's 16-byte internal FIFO between the two sides. Off is called direct mode, where each byte goes straight through | **Off** | **Off** |
| **Threshold** | 1/4, 1/2, 3/4 full, full | How full the FIFO gets before it's emptied. Only applies with the FIFO on | Not used | Not used |
| **Data width** | Byte, half word, word | Size of each transfer on each side. A half word is 16 bits and a word is 32 | **Byte** on both sides | **Byte** on both sides |
| **Burst size** | Single, 4, 8, 16 increments | Moves several transfers as one locked block. Only applies with the FIFO on | Not used | Not used |

**Why the FIFO stays off:** the FIFO helps when the two sides use different data widths, or when
bursts would make better use of the bus. Here both sides move single bytes at a slow rate, so the
FIFO adds settings without any benefit. With it off, CubeMX ignores the threshold and burst settings.

**Caches:** the data cache is off, so DMA buffers need no cache maintenance. See
[peripheral_ETH.md](peripheral_ETH.md#caches). DMA2 can reach SRAM1, SRAM2 and DTCM, so the buffer
can go anywhere in RAM.

## How receiving works

The HAL's receive-to-idle function suits a console, because commands have no fixed length:

```text
HAL_UARTEx_ReceiveToIdle_DMA(&huart1, rx_buffer, sizeof rx_buffer)    called once, in circular mode
   |
Bytes arrive; DMA2 stream 2 writes them into rx_buffer with no CPU work
   |
The line goes quiet for one character time (the "idle line"), or the buffer is half or completely full
   |
The USART1 or DMA interrupt fires, and HAL_UARTEx_RxEventCallback(huart, position) runs
   |
The callback hands the new bytes to a thread through a queue, then returns
```

The idle-line detection comes from the USART1 interrupt, which is why it has to be enabled.

## Recommended setup

All of these are set in the `.ioc` and match the generated code as of Nov 5:

| Item | Setting |
| ---- | ------- |
| `USART1_RX` DMA | DMA2 stream 2, channel 4, Circular, Low, byte to byte, memory increment, FIFO off |
| `USART1_TX` DMA | DMA2 stream 7, channel 4, Normal, Low, byte to byte, memory increment, FIFO off |
| `DMA2_Stream2_IRQn` priority | 5 |
| `DMA2_Stream7_IRQn` priority | 5 |
| USART1 global interrupt | On, priority 5 |

`MX_DMA_Init` runs before `MX_USART1_UART_Init` in `main.c`, as it must, because the UART setup
links to the DMA streams.

**Simpler alternative:** if the console turns out to be output only, skip RX DMA and send with
`HAL_UART_Transmit_DMA`. That still shows DMA and interrupts, with less code.

# Core: NVIC

How interrupt priorities are set on the STM32F746G-DISCO, using the Cortex-M7's
Nested Vectored Interrupt Controller (NVIC).

Values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`), and the
generated code matches them. Nothing has been tested on hardware.

## How priorities work

- **Lower numbers mean higher priority.** Priority 0 is the highest and 15 the
  lowest.
- **Preemption:** an interrupt can pause a running handler only if its priority
  number is lower.
- **Equal priority:** interrupts at the same priority don't interrupt each
  other. If both are waiting, the one with the lower interrupt number runs
  first.
- **Sub-priority:** always 0 here. `NVIC_PRIORITYGROUP_4` gives all 4 priority
  bits to preemption, which is what FreeRTOS expects, so this setting should
  stay as it is.

## FreeRTOS limit

`configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY` is 5, which divides interrupts
into two groups:

| Priority | FreeRTOS `FromISR` functions | FreeRTOS critical sections   |
| -------- | ---------------------------- | ---------------------------- |
| 0 to 4   | Not allowed                  | Keep running during them     |
| 5 to 15  | Allowed                      | Held off until they finish   |

Calling a `FromISR` function from priority 0 to 4 can corrupt the scheduler, so
a handler in that range mustn't call FreeRTOS at all.

## Priorities

| Interrupt                                 | IRQ number | Priority | Why                                                       |
| ----------------------------------------- | ---------- | -------- | --------------------------------------------------------- |
| `TIM6_DAC_IRQn` (HAL time base)           | 54         | 0        | Keeps the HAL tick running; calls no FreeRTOS functions   |
| `CAN1_TX_IRQn`, `RX0`, `RX1`, `SCE`       | 19 to 22   | 5        | Highest level allowed to use FreeRTOS; little buffering   |
| `ETH_IRQn`                                | 61         | 6        | Can wait, because its data is safe in the DMA buffers     |
| `SysTick_IRQn`, `PendSV_IRQn`             | System     | 15       | FreeRTOS requires these to be lowest                      |

See [HAL time base](middleware_RTOS.md#hal-time-base) for why TIM6 is at
priority 0.

## Why CAN is above Ethernet

Equal priorities would work, but the two peripherals handle waiting differently.

| | CAN | Ethernet |
| ------------------------- | ----------------------------------------- | ------------------------------------------ |
| Where received data waits | Only 3 frames per hardware FIFO           | Several receive buffers in RAM, using DMA  |
| If its handler is delayed | A frame can be lost once the FIFO fills   | Frames keep landing in the buffers         |
| How urgently it needs the CPU | More urgent                           | Less urgent                                |

The risk is small, because the CANopen module is polled every 100 ms and
handlers stay short. Separating them costs nothing, and lets a CAN interrupt run
during an Ethernet handler.

## Rules for handlers

- Keep handlers short: copy data, pass it to a thread through a queue, and
  return.
- Only call FreeRTOS functions ending in `FromISR`, and only at priority 5 or
  lower in urgency (5 to 15).
- Don't call HAL functions that wait on a timeout from a handler.
- Keep protocol and crypto work in threads.

## Related documents

- [peripheral_CAN.md](peripheral_CAN.md): what each CAN interrupt is for
- [peripheral_ETH.md](peripheral_ETH.md): Ethernet DMA and buffers
- [middleware_RTOS.md](middleware_RTOS.md): threads and the HAL time base

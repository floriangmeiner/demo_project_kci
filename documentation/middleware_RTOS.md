# FreeRTOS Middleware

How FreeRTOS threads are organized on the STM32F746G-DISCO.

Application thread names and current values are from the CubeMX project
(`kepler_demo_stm32f746g-disco.ioc`). The code hasn't been regenerated from them yet,
and no stack size has been measured. Recommended sizes are starting points.

## HAL time base

**Decision: the HAL time base uses TIM6, and FreeRTOS keeps SysTick.**

The system has two separate 1 ms ticks:

| Tick           | Timer   | Used for                                       | Priority          |
| -------------- | ------- | ---------------------------------------------- | ----------------- |
| FreeRTOS tick  | SysTick | Task switching, `osDelay` and RTOS timeouts    | 15 (lowest)       |
| HAL tick       | TIM6    | `HAL_GetTick`, `HAL_Delay` and driver timeouts | 0 (highest)       |

CubeMX warns against sharing SysTick because FreeRTOS takes control of it and runs it at
the lowest interrupt priority. HAL timeouts can then stop advancing while interrupts or
critical sections run, and HAL code that needs the tick can run before the scheduler has
started.

**To set it:** in CubeMX, go to Pinout & Configuration > System Core > SYS, and set
Timebase Source to TIM6. Then check the priority below under NVIC.

| TIM6 setting | Value                       | Why                                                   |
| ------------ | --------------------------- | ----------------------------------------------------- |
| Input clock  | 108 MHz                     | APB1 timer clock in the `.ioc`                        |
| Prescaler    | 107                         | 108 MHz / 108 = 1 MHz counter                         |
| Period       | 999                         | 1 MHz / 1000 = 1 kHz, or a 1 ms tick                  |
| Interrupt    | `TIM6_DAC_IRQn`, priority 0 | Keeps the HAL tick running during other interrupts    |

CubeMX generates the prescaler and period, calculating them from the clock at startup in
`stm32f7xx_hal_timebase_tim.c`, so there's nothing to enter by hand. Check them there
after regenerating.

### Why TIM6

TIM6 is a basic timer. It counts up and fires an interrupt, and that's all a 1 ms tick
needs, so it does the job with nothing left over.

| Reason                  | TIM6                                              | TIM1, for comparison                        |
| ----------------------- | ------------------------------------------------- | ------------------------------------------- |
| Type                    | Basic: counts and interrupts                      | Advanced: PWM, complementary outputs, dead time |
| Output pins             | None, so it can't use up or clash with a pin      | Yes, such as `PA8` (D10)                    |
| Cost of reserving it    | Nothing else in this project needs it             | Gives up features we might want later       |
| Clock                   | 108 MHz (APB1 timers)                             | 216 MHz (APB2 timers)                       |
| Shared interrupt        | DAC underrun flag; the DAC isn't used             | TIM10 update interrupt                      |

TIM7 would work just as well, because it's the same type of timer.

CubeMX locks a timer's settings once it's the time base, so TIM6 can't be edited on its
own page. That's expected, because there's nothing to set by hand. Only its interrupt
priority can be changed, under NVIC.

Priority 0 is above the FreeRTOS `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY` limit,
which is fine because this handler only increments a counter and calls no FreeRTOS
functions.

Things to remember:

- In threads, use `osDelay`, because `HAL_Delay` keeps the CPU busy while waiting.
- Both bootloader stages run without FreeRTOS, so they can use plain SysTick. If either
  starts a timer, it must stop that timer and its interrupt before jumping to the next
  image.

## Thread overview

```text
                     Ethernet interrupt
                             |
                             v
Ethernet <--> EthIf <--> tcpip_thread <--> linkTask <--queues--> canOpenTask <--> CAN
                                              ^
                                              |
                                  defaultTask starts everything
```

## Application threads

These are defined in the `.ioc`. One word is 4 bytes.

| Thread        | Entry function     | Priority                | Stack now (words) | Stack now (bytes) | Recommended (words) | Recommended (bytes) |
| ------------- | ------------------ | ----------------------- | ----------------- | ----------------- | ------------------- | ------------------- |
| `defaultTask` | `StartDefaultTask` | 24 (`osPriorityNormal`) | 1024              | 4096              | 1024                | 4096                |
| `canOpenTask` | `StartCanOpenTask` | 8 (`osPriorityLow`)     | 256               | 1024              | 512                 | 2048                |
| `linkTask`    | `StartLinkTask`    | 8 (`osPriorityLow`)     | 256               | 1024              | 2048                | 8192                |

What each one does:

- **`defaultTask`:** calls `MX_LWIP_Init()`, starts the rest of the application, then
  exits or idles. Exiting returns its stack to the heap.
- **`canOpenTask`:** polls the module's inputs over SDO, watches its heartbeat, and
  applies output commands.
- **`linkTask`:** owns the UDP socket and session keys, runs the handshake, encrypts
  telemetry and decrypts commands.

### Recommended changes

- **`linkTask` stack:** 256 words is too small. Handshake crypto (X25519 and signature
  checks) uses a lot of stack. Start at 2048 words and measure.
- **`canOpenTask` stack:** 512 words leaves room for HAL calls and queue handling.
- **`canOpenTask` priority:** raise it to 16 (`osPriorityBelowNormal`) so a slow
  handshake in `linkTask` can't hold up CAN polling.

## lwIP threads

CubeMX creates these when lwIP is generated, so they aren't in the `.ioc`. These values
come from CubeMX 6.18.1's lwIP defaults and templates, and need confirming in the
generated code.

| Thread                 | Created by       | Priority                     | Stack (words)  | Stack (bytes) | Job                                       |
| ---------------------- | ---------------- | ---------------------------- | -------------- | ------------- | ----------------------------------------- |
| `tcpip_thread`         | lwIP             | 24 (`osPriorityNormal`)      | 1024           | 4096          | Runs the network stack                    |
| `EthIf`                | `ethernetif.c`   | 48 (`osPriorityRealtime`)    | About 87       | 350           | Wakes on the interrupt, passes frames up  |
| `EthLink` or `LinkThr` | `lwip.c` or `ethernetif.c` | 16 (`osPriorityBelowNormal`) | 256  | 1024          | Watches the Ethernet cable link state     |

**Check `EthIf` first.** The template sets `INTERFACE_THREAD_STACK_SIZE` to 350, and
CMSIS-RTOS v2 reads `stack_size` in bytes, which leaves about 87 words. That looks too
small. Measure it after regenerating, and raise it to at least 1024 bytes if needed.

## Rules for threads

- **Sockets:** only `linkTask` uses the UDP connection, because an lwIP `netconn` isn't
  safe to share between threads.
- **Keys and nonces:** only `linkTask` touches session keys and the nonce counter, which
  makes it easier to guarantee a nonce never repeats.
- **Interrupts:** handlers copy data, pass it to a thread through a queue, and return.
  Interrupts that call FreeRTOS `FromISR` functions need priority 5 or higher in number.
- **Between threads:** `canOpenTask` and `linkTask` only share data through queues, one
  for input state and one for output commands.

Why `linkTask` is separate from `defaultTask`:

- It can have a larger stack just for crypto.
- A slow handshake can't delay CAN polling.
- Each job shows up as its own task in SystemView.

## Memory

| Item                       | Bytes  | Notes                                         |
| -------------------------- | ------ | --------------------------------------------- |
| Application stacks         | 14,336 | Recommended sizes                             |
| lwIP stacks                | 6,144  | With `EthIf` raised to 1024 bytes             |
| Total stacks               | 20,480 | Before task control blocks and queues         |
| FreeRTOS heap in the current code | 32,768 | `configTOTAL_HEAP_SIZE`; dynamic allocation |

These should fit. Confirm with `xPortGetFreeHeapSize` once everything is running.

The session keys are planned for DTCM in [system_memory.md](system_memory.md). Stacks are allocated
from the FreeRTOS heap, so any key copies on `linkTask`'s stack land wherever that
heap is linked. Check the linker script and wipe key copies after use.

## Settings in FreeRTOSConfig.h

The current file is from before the switch to CMSIS-RTOS v2, so check these after
regenerating:

| Setting                                        | Now        | Needed                                    |
| ---------------------------------------------- | ---------- | ----------------------------------------- |
| `configMAX_PRIORITIES`                         | 7          | 56: priorities above run up to 48 and more |
| `configCHECK_FOR_STACK_OVERFLOW`               | 2          | Keep: catches overflows while developing  |
| `configUSE_MALLOC_FAILED_HOOK`                 | 1          | Keep: catches a full heap                 |
| `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY` | 5          | Keep: matches the CAN and Ethernet interrupts |
| `INCLUDE_uxTaskGetStackHighWaterMark`          | Not set    | 1: needed to measure stack use            |

## Measuring stacks

Call `uxTaskGetStackHighWaterMark` for each thread after the handshake has run and
traffic is flowing. It returns the smallest free stack seen so far, in words. Keep at
least 20% free, and update the table above with the measured values.

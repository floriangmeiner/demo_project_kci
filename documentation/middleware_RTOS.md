# FreeRTOS Middleware

How FreeRTOS threads are organized on the STM32F746G-DISCO.

Application thread names and values are from the CubeMX project
(`kepler_demo_stm32f746g-disco.ioc`), and the generated code matches them. No stack size
has been measured, so they're starting points, and nothing has been tested on hardware.

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

**Where it's set:** in CubeMX, under Pinout & Configuration > System Core > SYS, Timebase
Source is TIM6. Its priority is under NVIC.

| TIM6 setting | Value                       | Why                                                   |
| ------------ | --------------------------- | ----------------------------------------------------- |
| Input clock  | 108 MHz                     | APB1 timer clock in the `.ioc`                        |
| Prescaler    | 107                         | 108 MHz / 108 = 1 MHz counter                         |
| Period       | 999                         | 1 MHz / 1000 = 1 kHz, or a 1 ms tick                  |
| Interrupt    | `TIM6_DAC_IRQn`, priority 0 | Keeps the HAL tick running during other interrupts    |

`stm32f7xx_hal_timebase_tim.c` calculates the prescaler and period from the clock at
startup, so there's nothing to enter by hand.

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

| Thread        | Entry function     | Priority                | Stack (words) | Stack (bytes) |
| ------------- | ------------------ | ----------------------- | ------------- | ------------- |
| `defaultTask` | `StartDefaultTask` | 24 (`osPriorityNormal`) | 1024          | 4096          |
| `canOpenTask` | `StartCanOpenTask` | 16 (`osPriorityBelowNormal`) | 512      | 2048          |
| `linkTask`    | `StartLinkTask`    | 8 (`osPriorityLow`)     | 2048          | 8192          |

What each one does:

- **`defaultTask`:** calls `MX_LWIP_Init()`, starts the rest of the application, then
  exits or idles. Exiting returns its stack to the heap.
- **`canOpenTask`:** polls the module's inputs over SDO, watches its heartbeat, and
  applies output commands.
- **`linkTask`:** owns the UDP socket and session keys, runs the handshake, encrypts
  telemetry and decrypts commands.

Why these stack sizes:

- **`linkTask`:** handshake crypto (X25519 and signature checks) uses a lot of stack, so
  it starts at 2048 words, to be measured.
- **`canOpenTask`:** 512 words leaves room for HAL calls and queue handling.

`canOpenTask` runs above `linkTask` so a slow handshake can't hold up CAN polling.

## lwIP threads

CubeMX creates these when lwIP is generated. These values are from the generated code. See
[middleware_LWIP.md](middleware_LWIP.md) for lwIP's settings and the CubeMX unit problem.

| Thread         | Created by     | Priority                     | Stack now (words) | Stack now (bytes) | Recommended (bytes) | Job                                      |
| -------------- | -------------- | ---------------------------- | ----------------- | ----------------- | ------------------- | ---------------------------------------- |
| `tcpip_thread` | lwIP           | 24 (`osPriorityNormal`)      | 1024              | 4096              | 4096                | Runs the network stack                   |
| `EthIf`        | `ethernetif.c` | 48 (`osPriorityRealtime`)    | About 87          | 350               | 1024                | Wakes on the interrupt, passes frames up |
| `EthLink`      | `lwip.c`       | 16 (`osPriorityBelowNormal`) | 256               | 1024              | 1024                | Watches the Ethernet cable link state    |

**These sizes are in bytes.** CMSIS-RTOS v2 reads `stack_size` in bytes, and `sys_arch.c`
passes `TCPIP_THREAD_STACKSIZE` straight to it. `tcpip_thread` is now 4096 bytes, as
recommended. `EthIf`'s `INTERFACE_THREAD_STACK_SIZE` is still 350 bytes, only about 87 words, so
raise it and measure both. Where to change them:

- **`tcpip_thread`:** Pinout & Configuration > Middleware and Software Packs > LWIP >
  Configuration > Key Options > Infrastructure - Threading Options > `TCPIP_THREAD_STACKSIZE`.
  **CubeMX labels this value in words, but it's used as bytes.** See
  [Stack size units](middleware_LWIP.md#stack-size-units). It's generated into `lwipopts.h`.
- **`EthIf`:** CubeMX has no setting for it. Change `INTERFACE_THREAD_STACK_SIZE` in
  `LWIP/Target/ethernetif.c`, between `USER CODE BEGIN OS_THREAD_STACK_SIZE_WITH_RTOS` and
  `USER CODE END`, so regenerating keeps it. This value is also in bytes.

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

| Item                 | Now (bytes) | Recommended (bytes) | Notes                                 |
| -------------------- | ----------- | ------------------- | ------------------------------------- |
| Application stacks   | 14,336      | 14,336              | Sizes in the `.ioc`                   |
| lwIP stacks          | 5,470       | 6,144               | See [lwIP threads](#lwip-threads)     |
| Total stacks         | 19,806      | 20,480              | Before task control blocks and queues |
| FreeRTOS heap        | 32,768      | 32,768              | `configTOTAL_HEAP_SIZE`, in the FreeRTOS settings in CubeMX |

The heap has room for every thread. About 12.7 KB is left today, and about 12 KB once the
`EthIf` stack is raised, for task control blocks, queues and lwIP's mailboxes. This is a
calculation, so confirm it with `xPortGetFreeHeapSize` once everything is running.

The idle and timer task stacks aren't counted, because they're allocated statically.

The session keys are planned for DTCM in [system_memory.md](system_memory.md). Stacks are allocated
from the FreeRTOS heap, so any key copies on `linkTask`'s stack land wherever that
heap is linked. Check the linker script and wipe key copies after use.

## Settings in FreeRTOSConfig.h

| Setting                                        | Now        | Needed                                    | What it does |
| ---------------------------------------------- | ---------- | ----------------------------------------- | ------------ |
| `configTOTAL_HEAP_SIZE`                        | 32,768     | Keep: see [Memory](#memory)               | Bytes of RAM set aside for FreeRTOS to allocate thread stacks, queues and other objects from |
| `configCHECK_FOR_STACK_OVERFLOW`               | 2          | Keep: catches overflows while developing  | Checks each thread's stack when it's switched out, and calls a hook if it has overflowed. See [Stack overflow check](#stack-overflow-check) |
| `configUSE_MALLOC_FAILED_HOOK`                 | 1          | Keep: catches a full heap, which is otherwise easy to miss | 1 turns it on: FreeRTOS calls `vApplicationMallocFailedHook` whenever it can't allocate memory from the heap |
| `configMAX_PRIORITIES`                         | 56         | Keep: priorities above run up to 48 and more | The number of thread priority levels. Priorities run from 0 to this value minus 1 |
| `configMAX_TASK_NAME_LEN`                      | 30         | Keep, or return to 16 to save RAM          | Longest thread name kept, including the terminating null. It's stored in every thread's control block |
| `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY` | 5          | Keep: CAN is at 5 and Ethernet at 6, so both may use FreeRTOS | The most urgent interrupt priority allowed to call FreeRTOS `FromISR` functions. See [core_NVIC.md](core_NVIC.md#freertos-limit) |
| `INCLUDE_uxTaskGetStackHighWaterMark`          | 1          | Keep: needed to measure stack use         | Includes the function that reports the least free stack a thread has had |

Both checks are set in CubeMX, so they survive regenerating.

### Stack overflow check

FreeRTOS V10.2.0, the version in this project, has three options:

| Value | What it checks | Cost | Catches |
| ----- | -------------- | ---- | ------- |
| 0     | Nothing        | None | Nothing |
| 1     | Whether the stack pointer is past the end of the stack when the thread is switched out | Very small | An overflow that's still in progress at that moment |
| **2 (used)** | Option 1, plus whether the last 16 bytes of the stack still hold the fill value (`0xA5`) written when the thread was created | A little more time on every thread switch | Also an overflow that went deep and then came back, which option 1 misses |

Neither option catches every overflow. Both only check at a thread switch, so an overflow can corrupt
memory, or crash, before the check runs. Newer FreeRTOS versions add an option 3 for interrupt
stacks on some ports, but V10.2.0 doesn't have it.

### What the hooks do now

CubeMX generated both hooks in `freertos.c` with empty bodies. As generated, they **detect a
problem and then let the program carry on**, usually with a corrupted stack or a failed allocation.
Fill them in, in their `USER CODE` section so regenerating keeps the change. While developing, the
simplest version stops everything so the debugger shows the cause:

```c
void vApplicationStackOverflowHook(xTaskHandle xTask, signed char *pcTaskName)
{
  (void)xTask;
  (void)pcTaskName;    /* Visible in the debugger: the overflowing thread */
  taskDISABLE_INTERRUPTS();
  for (;;) { }
}
```

The malloc-failed hook can do the same. Later, these are places to log the fault to the reset log
planned in Week 2.

## Measuring stacks

Call `uxTaskGetStackHighWaterMark` for each thread after the handshake has run and
traffic is flowing. It returns the smallest free stack seen so far, in words. Keep at
least 20% free, and update the table above with the measured values.

## CMSIS-RTOS Priority Numbers and Labels

CMSIS-RTOS v2 gives each thread priority level a label. Each level starts at a multiple
of 8, and the suffix adds to that number, so `osPriorityLow3` is 8 + 3 = 11. These values
come from `cmsis_os2.h`.

**A higher number means a higher priority for threads, which is the opposite of NVIC
interrupts.** See [core_NVIC.md](core_NVIC.md).

| Label                   | Base | 1  | 2  | 3  | 4  | 5  | 6  | 7  |
| ----------------------- | ---- | -- | -- | -- | -- | -- | -- | -- |
| `osPriorityLow`         | 8    | 9  | 10 | 11 | 12 | 13 | 14 | 15 |
| `osPriorityBelowNormal` | 16   | 17 | 18 | 19 | 20 | 21 | 22 | 23 |
| `osPriorityNormal`      | 24   | 25 | 26 | 27 | 28 | 29 | 30 | 31 |
| `osPriorityAboveNormal` | 32   | 33 | 34 | 35 | 36 | 37 | 38 | 39 |
| `osPriorityHigh`        | 40   | 41 | 42 | 43 | 44 | 45 | 46 | 47 |
| `osPriorityRealtime`    | 48   | 49 | 50 | 51 | 52 | 53 | 54 | 55 |

These values have no suffixes and aren't for application threads. The numbers 2 to 7 have
no label.

| Label             | Value | Meaning                              |
| ----------------- | ----- | ------------------------------------ |
| `osPriorityNone`  | 0     | Not initialized                      |
| `osPriorityIdle`  | 1     | Reserved for the idle thread         |
| `osPriorityISR`   | 56    | Reserved for deferred interrupt work |
| `osPriorityError` | -1    | Illegal or unknown priority          |

Application threads in the `.ioc`:

| Thread        | Number | Label                   |
| ------------- | ------ | ----------------------- |
| `defaultTask` | 24     | `osPriorityNormal`      |
| `canOpenTask` | 16     | `osPriorityBelowNormal` |
| `linkTask`    | 8      | `osPriorityLow`         |

# CAN Peripheral

How CAN1 is set up on the STM32F746G-DISCO to talk to the CANopen IO module.

These values are from the CubeMX project (`kepler_demo_stm32f746g-disco.ioc`),
and `MX_CAN1_Init` matches them. Nothing has been tested on hardware.

## Settings

| Setting               | Value        | Result                                        |
| --------------------- | ------------ | --------------------------------------------- |
| CAN1 RX               | `PB8`        | CN7 pin 10 (D15)                              |
| CAN1 TX               | `PB9`        | CN7 pin 9 (D14)                               |
| APB1 clock            | 54 MHz       | Clock source for CAN1                         |
| Prescaler             | 6            | 111.1 ns per time quantum (TQ)                |
| Time segment 1        | 15 TQ        | With the 1 TQ sync segment, 16 TQ before the sample |
| Time segment 2        | 2 TQ         | 2 TQ after the sample                         |
| Sync jump width       | 1 TQ         | CubeMX default; fine for a short bus          |
| Bit time              | 18 TQ, 2 µs  | Exactly 500 kbit/s                            |
| Sample point          | 16/18        | 88.9%                                         |
| Mode                  | Normal       | Sends and receives on the real bus            |
| Automatic retransmission | Enabled   | A frame that hits an error or loses arbitration is sent again |
| Automatic bus-off management | Enabled | The controller can rejoin the bus after heavy errors |

PB8 and PB9 also go to CN2 and the camera connector, with 2.7 kohm pull-ups to
3.3 V. Both connectors stay empty, and the transceiver needs 3.3 V logic. See
[Pin assignments](../PLAN.md#pin-assignments).

The CANopen module must use the same bitrate. Its setting hasn't been confirmed
yet. Other standard rates keep the same segments and change only the prescaler:

| Bitrate    | Prescaler |
| ---------- | --------- |
| 500 kbit/s | 6         |
| 250 kbit/s | 12        |
| 125 kbit/s | 24        |

## Sample point

The sample point is the moment in each bit when a node reads the bus as 0 or 1.
Sampling late gives the signal time to travel the bus and settle. Sampling too
late leaves little time after the sample to correct for clock differences
between nodes.

This matters for CANopen for three reasons:

- **Every node reads the same bus.** Nodes acknowledge and arbitrate within a
  single bit, so their timing has to line up. Very different sample points eat
  into that margin, and can show up as error frames that are hard to diagnose.
- **CANopen sets a common target.** CAN itself doesn't fix a sample point, so
  devices from different vendors could disagree. CiA 301 is reported to
  recommend 87.5%, and CANopen devices are normally set close to that. Published
  tables give 85% to 90% as the valid range at 500 kbit/s. This comes from
  secondary sources, not CiA 301 itself.
- **The module's value is fixed by its vendor.** We can only adjust our side, so
  staying near 87.5% is the best way to match a module we don't control.

We use 88.9% because exactly 87.5% isn't available with this clock. The 54 MHz
clock gives 108 clock cycles per bit, and 87.5% needs a TQ count divisible by 8,
which can't divide 108 evenly. 18 TQ can, and 88.9% is within the published
range. A short bench bus has plenty of margin either way.

## Clock accuracy

Every CAN bit is timed from the APB1 clock, so nodes need accurate clocks to
stay in step. The PLL now runs from HSE, fed by X2, the board's 25 MHz
oscillator, rather than HSI, the chip's internal RC oscillator, which is much
less accurate. The system clock stays at 216 MHz and APB1 at 54 MHz, so the
settings above didn't change. See [core_oscillators.md](core_oscillators.md).

- **HSE mode:** choose "BYPASS Clock Source". In the B-04 schematic
  (`mb1191-f746ngh6-b04-schematic.pdf`, PDF page 3), X2 is a complete oscillator
  module (NZ2520SB) whose output drives `PH0` through R30, and `PH1` isn't
  connected. Crystal mode expects a crystal across both pins. See
  [core_oscillators.md](core_oscillators.md).
- **PLL values:** M = 25, N = 432, P = 2 and Q = 9 give 216 MHz, and 48 MHz on
  the PLLQ output.

## Interrupts

All four CAN1 interrupts are enabled at priority 5, under System Core > NVIC.
Priority 5 is the limit set by `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`,
so their handlers may call FreeRTOS `FromISR` functions.

The firmware's use of each one is planned, and node ID values depend on the
module.

| Interrupt       | Fires when                          | What it's for                                                  | HAL callback                                  |
| --------------- | ----------------------------------- | -------------------------------------------------------------- | --------------------------------------------- |
| `CAN1_TX_IRQn`  | A transmit mailbox finishes         | Tells the CANopen task it can send the next NMT or SDO request | `HAL_CAN_TxMailbox0CompleteCallback` (also 1, 2) |
| `CAN1_RX0_IRQn` | A frame is waiting in FIFO 0        | SDO responses from the module (`0x580` + node ID), carrying input states | `HAL_CAN_RxFifo0MsgPendingCallback`  |
| `CAN1_RX1_IRQn` | A frame is waiting in FIFO 1        | Heartbeats from the module (`0x700` + node ID), used to detect a lost module | `HAL_CAN_RxFifo1MsgPendingCallback` |
| `CAN1_SCE_IRQn` | The error state or bus status changes | Counts errors and reports bus-off in telemetry, such as during a wiring fault | `HAL_CAN_ErrorCallback`            |

Using two receive FIFOs keeps heartbeats separate, so a burst of SDO traffic
can't delay or overflow the frames that show the module is still alive.

Handlers should stay short: copy the frame, pass it to the CANopen task through
a queue, and return. CANopen logic runs in the task, not the interrupt.

## Code needed beyond CubeMX

CubeMX enables the interrupts in the NVIC, but the firmware still has to:

1. Call `HAL_CAN_ConfigFilter` to send SDO responses to FIFO 0 and heartbeats to
   FIFO 1. **Without a filter, CAN1 receives nothing.**
2. Call `HAL_CAN_ActivateNotification` for each interrupt source used.
3. Call `HAL_CAN_Start`.

## How the `.ioc` stores these settings

`MX_CAN1_Init` has both of these on:

- **`AutoRetransmission = ENABLE`.** The `.ioc` stores this as `NART=ENABLE`,
  which looks backwards. The name comes from the hardware's "no automatic
  retransmission" bit, but CubeMX labels the setting "Automatic Retransmission",
  and the HAL clears that bit when this is enabled.
- **`AutoBusOff = ENABLE`.** The `.ioc` stores this as `ABOM=ENABLE`.

## Sources

- [Beckhoff: CANopen baud rate and bit
  timing](https://infosys.beckhoff.com/content/1033/el6751/2519212043.html)
- [ST community: bxCAN bit time configuration on
  STM32](https://community.st.com/t5/stm32-mcus/can-bxcan-bit-time-configuration-on-stm32-mcus/ta-p/689864)
- [CANpie: CAN bit timing
  reference](https://canpie.sourceforge.net/page.api_bitiming.html)
- [Zephyr commit on CiA 301 sample point
  defaults](https://mirrors.sustech.edu.cn/git/12411711/zephyr/-/commit/fba27b4bde47e97175adf87c8bcd06aadcd8a43b)

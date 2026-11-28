/*
 * SEGGER SystemView tracing: setup, interrupt tracing and timing markers.
 *
 * Built in when FW_SYSVIEW is 1, which app/Makefile sets by default. With
 * FW_SYSVIEW 0, for example in a release build, everything here becomes a
 * no-op. Recording needs the J-Link and the SystemView app; without them the
 * firmware runs normally and the events are dropped.
 *
 * See documentation/tracing_systemview.md.
 */
#ifndef TRACE_H
#define TRACE_H

#if FW_SYSVIEW

#include "SEGGER_SYSVIEW.h"

/* Call once after SystemClock_Config(), before any FreeRTOS object exists */
void trace_init(void);

/* Call once from the first thread, after the scheduler has started. Starts
 * recording without the app if TRACE_RECORD_FROM_BOOT is 1. */
void trace_start(void);

/* Call regularly from a thread; samples the plotted values and logs status */
void trace_periodic(void);

/* Put at the very start and end of an interrupt handler */
#define TRACE_ISR_ENTER()     SEGGER_SYSVIEW_RecordEnterISR()
#define TRACE_ISR_EXIT()      SEGGER_SYSVIEW_RecordExitISR()

/* Time a section of code; shows as a marker span in SystemView */
#define TRACE_MARK_START(id)  SEGGER_SYSVIEW_MarkStart(id)
#define TRACE_MARK_STOP(id)   SEGGER_SYSVIEW_MarkStop(id)

#else

static inline void trace_init(void) {}
static inline void trace_start(void) {}
static inline void trace_periodic(void) {}
#define TRACE_ISR_ENTER()     ((void)0)
#define TRACE_ISR_EXIT()      ((void)0)
#define TRACE_MARK_START(id)  ((void)(id))
#define TRACE_MARK_STOP(id)   ((void)(id))

#endif /* FW_SYSVIEW */

#endif /* TRACE_H */

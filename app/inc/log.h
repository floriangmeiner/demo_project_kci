/*
 * Logging through SEGGER SystemView.
 *
 *   LOG("Link up, %u ms", ms);        message
 *   LOG_WARN("Replay rejected, seq %u", seq);  warning
 *   LOG_ERROR("Bad tag on frame %u", n);       error
 *
 * Messages appear in SystemView's Terminal and Events windows, on the same
 * timeline as thread switches and interrupts. They only exist while
 * SystemView is recording through the J-Link; there is no output otherwise.
 *
 * Rules:
 *   - Never log key material, nonces or session secrets. The trace is
 *     readable by anyone with the debugger attached.
 *   - Prefer %d, %u, %x, %c and %p: the PC formats those, which is fast.
 *     %s works, but formats the message on the target, which is slower.
 *   - At most 16 arguments, and no "%%".
 *
 * With FW_SYSVIEW 0, for example in a release build, every LOG call is
 * removed. See documentation/tracing_systemview.md.
 */
#ifndef LOG_H
#define LOG_H

#if FW_SYSVIEW

#include "SEGGER_SYSVIEW.h"

#define LOG(...)        SEGGER_SYSVIEW_PrintfHost(__VA_ARGS__)
#define LOG_WARN(...)   SEGGER_SYSVIEW_WarnfHost(__VA_ARGS__)
#define LOG_ERROR(...)  SEGGER_SYSVIEW_ErrorfHost(__VA_ARGS__)

#else

#define LOG(...)        ((void)0)
#define LOG_WARN(...)   ((void)0)
#define LOG_ERROR(...)  ((void)0)

#endif /* FW_SYSVIEW */

#endif /* LOG_H */

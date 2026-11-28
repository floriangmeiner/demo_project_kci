/*
 * SEGGER SystemView settings for the Kepler demo.
 *
 * This file replaces vendors/segger/systemview/Config/SEGGER_SYSVIEW_Conf.h,
 * because app/config/ comes first on the include path; the submodule's files
 * stay unmodified. Only settings that differ from SEGGER's defaults go here.
 * The defaults and their descriptions are in SEGGER_SYSVIEW_ConfDefaults.h.
 *
 * See documentation/tracing_systemview.md.
 */
#ifndef SEGGER_SYSVIEW_CONF_H
#define SEGGER_SYSVIEW_CONF_H

/*
 * SystemView V4.10 reads RTT's settings from SEGGER_RTT_Conf.h, but RTT 8.58
 * moved its defaults, such as the number of buffers, to
 * SEGGER_RTT_ConfDefaults.h. Without this, SystemView sees no buffers and
 * stops the build. SystemView V4.12.0 includes this file itself, so drop this
 * line when moving to it.
 */
#include "SEGGER_RTT_ConfDefaults.h"

/*
 * RTT buffer for SystemView events, in RAM. The default 1 KB overflows while
 * Ethernet traffic is traced; overflows show as gaps in the recording. RAM is
 * about 22% used, so 8 KB is affordable.
 */
#define SEGGER_SYSVIEW_RTT_BUFFER_SIZE        8192

/*
 * Let LOG() messages contain %s. By default SystemView sends every argument
 * as a number for the PC to format, so %s would print an address. With this
 * on, a message containing %s is formatted on the target instead.
 */
#define SEGGER_SYSVIEW_PRINTF_IMPLICIT_FORMAT 1

/* From SEGGER's original file: keep SystemView's buffer in RTT's section */
#if !(defined SEGGER_SYSVIEW_SECTION) && (defined SEGGER_RTT_BUFFER_SECTION)
  #define SEGGER_SYSVIEW_SECTION SEGGER_RTT_BUFFER_SECTION
#endif

#endif /* SEGGER_SYSVIEW_CONF_H */

# app/Makefile: the application firmware.
#
# Builds the CubeMX code (HAL, FreeRTOS, lwIP, startup) plus our own code in
# app/src/, and SEGGER SystemView with RTT from the submodules in
# vendors/segger/. Normally run from the repo root with `make`; running
# `make` in this folder works too. Output goes to build/app/ at the repo root.
#
# Settings, on the command line:
#   FW_SYSVIEW=0   build without SystemView tracing and logging
# Run `make clean` after changing a setting; see documentation/build_system.md.
#
# See documentation/build_system.md.

ROOT := ..

# First, so our settings below replace the generated ones. The generated
# Makefile sets TARGET, BUILD_DIR, CC and others, so nothing that shares a
# name with them may be set above this line.
include $(ROOT)/mk/cube.mk

OUT    := $(ROOT)/build/app
TARGET := kepler_demo_app

# --- SEGGER SystemView and RTT ------------------------------------------------

FW_SYSVIEW ?= 1

SEGGER := $(ROOT)/vendors/segger

ifeq ($(FW_SYSVIEW),1)
  SEGGER_SRC := \
    $(SEGGER)/rtt/RTT/SEGGER_RTT.c \
    $(SEGGER)/rtt/RTT/SEGGER_RTT_ASM_ARMv7M.S \
    $(SEGGER)/systemview/SYSVIEW/SEGGER_SYSVIEW.c \
    $(SEGGER)/systemview/Sample/FreeRTOSV10/SEGGER_SYSVIEW_FreeRTOS.c

  # app/config/ comes first, so our SEGGER_SYSVIEW_Conf.h replaces the
  # submodule's.
  SEGGER_INC := \
    -I$(ROOT)/app/config \
    -I$(SEGGER)/systemview/SYSVIEW \
    -I$(SEGGER)/systemview/SEGGER \
    -I$(SEGGER)/systemview/Config \
    -I$(SEGGER)/systemview/Sample/FreeRTOSV10 \
    -I$(SEGGER)/rtt/RTT \
    -I$(SEGGER)/rtt/Config

  SEGGER_MISSING := $(filter-out $(wildcard $(SEGGER_SRC)),$(SEGGER_SRC))
  ifneq ($(SEGGER_MISSING),)
    $(error SEGGER sources missing: $(SEGGER_MISSING). Run: git submodule update --init)
  endif
endif

# --- Firmware version -----------------------------------------------------------

# FW_VERSION comes from `git describe`, written to a generated header that
# only changes when the version does. So a new commit rebuilds the one file
# that includes it, and an unchanged version rebuilds nothing.
GEN        := $(OUT)/gen
FW_VERSION := $(shell git -C $(ROOT) describe --tags --always --dirty 2>/dev/null || echo unknown)
$(shell mkdir -p $(GEN) && \
  printf '#define FW_VERSION "%s"\n' '$(FW_VERSION)' > $(GEN)/fw_version.h.new && \
  (cmp -s $(GEN)/fw_version.h.new $(GEN)/fw_version.h || \
   mv $(GEN)/fw_version.h.new $(GEN)/fw_version.h); \
  rm -f $(GEN)/fw_version.h.new)

# --- Sources -------------------------------------------------------------------

APP_C := $(wildcard $(ROOT)/app/src/*.c)

SRCS     := $(CUBE_C) $(APP_C) $(SEGGER_SRC) $(CUBE_ASM)
INCLUDES := $(CUBE_INC) -I$(ROOT)/app/inc -I$(GEN) $(SEGGER_INC)
LDSCRIPT_FILE := $(CUBE_LDSCRIPT)

# Defines for every file, CubeMX's included: FreeRTOSConfig.h, main.c and
# stm32f7xx_it.c only hook SystemView in when FW_SYSVIEW is 1.
FW_DEFS := -DFW_SYSVIEW=$(FW_SYSVIEW)

include $(ROOT)/mk/common.mk

# Stricter warnings for our own code only. The HAL, lwIP and SEGGER code
# produce many -Wextra warnings that ours would get lost among.
$(OBJDIR)/app/%: FW_WARN := -Wextra

.DEFAULT_GOAL := firmware
.PHONY: firmware
firmware: $(OUT)/$(TARGET).elf $(OUT)/$(TARGET).hex $(OUT)/$(TARGET).bin

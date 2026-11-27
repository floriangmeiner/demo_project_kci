# app/Makefile: the application firmware.
#
# Builds the CubeMX code (HAL, FreeRTOS, lwIP, startup) plus our own code in
# app/src/. Normally run from the repo root with `make`; running `make` in
# this folder works too. Output goes to build/app/ at the repo root.
#
# See documentation/build_system.md.

ROOT := ..

# First, so our settings below replace the generated ones. The generated
# Makefile sets TARGET, BUILD_DIR, CC and others, so nothing that shares a
# name with them may be set above this line.
include $(ROOT)/mk/cube.mk

OUT    := $(ROOT)/build/app
TARGET := kepler_demo_app

APP_C := $(wildcard $(ROOT)/app/src/*.c)

SRCS     := $(CUBE_C) $(APP_C) $(CUBE_ASM)
INCLUDES := $(CUBE_INC) -I$(ROOT)/app/inc
LDSCRIPT_FILE := $(CUBE_LDSCRIPT)

include $(ROOT)/mk/common.mk

# Stricter warnings for our own code only. The HAL and lwIP produce many
# -Wextra warnings that ours would get lost among.
$(OBJDIR)/app/%: FW_WARN := -Wextra

.DEFAULT_GOAL := firmware
.PHONY: firmware
firmware: $(OUT)/$(TARGET).elf $(OUT)/$(TARGET).hex $(OUT)/$(TARGET).bin

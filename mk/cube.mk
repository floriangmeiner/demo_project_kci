# mk/cube.mk: read the CubeMX-generated Makefile as a list of files and flags.
#
# CubeMX owns kepler_demo_stm32f746g-disco/Makefile and rewrites it on every
# Generate Code. We never run it as part of our build. Instead we include it,
# copy the variables we need into CUBE_* names, and add the CubeMX folder in
# front of every path, because its paths are relative to that folder.
#
# Include this file first, before mk/common.mk, so that our own settings
# replace the generated ones (TARGET, BUILD_DIR, CC and so on).
#
# Needs: ROOT, the repo root relative to the folder make runs in.
# See documentation/build_system.md.

CUBE ?= $(ROOT)/kepler_demo_stm32f746g-disco

include $(CUBE)/Makefile

# The generated Makefile's first target is `all`, which would build into a
# build/ folder next to the including makefile. Clear it so the including
# makefile can set its own default goal.
.DEFAULT_GOAL :=

CUBE_C        := $(addprefix $(CUBE)/,$(C_SOURCES))
CUBE_ASM      := $(addprefix $(CUBE)/,$(ASM_SOURCES) $(ASMM_SOURCES))
CUBE_INC      := $(patsubst -I%,-I$(CUBE)/%,$(C_INCLUDES))
CUBE_DEFS     := $(C_DEFS)
CUBE_MCU      := $(MCU)
CUBE_LDSCRIPT := $(CUBE)/$(LDSCRIPT)
CUBE_LIBS     := $(LIBS)

# Stop with a clear error if CubeMX ever renames these variables or lists a
# file that doesn't exist, instead of failing later with a confusing link error.
ifeq ($(strip $(CUBE_C)),)
  $(error mk/cube.mk: no C_SOURCES found in $(CUBE)/Makefile)
endif
ifeq ($(strip $(CUBE_MCU)),)
  $(error mk/cube.mk: no MCU flags found in $(CUBE)/Makefile)
endif
CUBE_MISSING := $(filter-out $(wildcard $(CUBE_C) $(CUBE_ASM) $(CUBE_LDSCRIPT)),$(CUBE_C) $(CUBE_ASM) $(CUBE_LDSCRIPT))
ifneq ($(CUBE_MISSING),)
  $(error mk/cube.mk: files listed in $(CUBE)/Makefile are missing: $(CUBE_MISSING))
endif

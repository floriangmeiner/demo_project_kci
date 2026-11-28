# mk/common.mk: toolchain, flags and build rules shared by every program.
#
# The including makefile sets, before including this file:
#   ROOT       repo root, relative to the folder make runs in
#   OUT        output folder for this program
#   TARGET     output file name, without extension
#   SRCS       every .c, .s and .S file to build, as paths under $(ROOT)
#   INCLUDES   -I flags
#   LDSCRIPT_FILE  linker script
#   FW_DEFS    optional -D flags for every file
# and includes mk/cube.mk first, for the CUBE_* variables.
#
# See documentation/build_system.md.

# Toolchain. GCC_PATH works as it does in the generated Makefile.
PREFIX  := $(if $(GCC_PATH),$(GCC_PATH)/)arm-none-eabi-
CC      := $(PREFIX)gcc
AS      := $(PREFIX)gcc -x assembler-with-cpp
OBJCOPY := $(PREFIX)objcopy
SIZE    := $(PREFIX)size

# Build type. Same as the generated Makefile's defaults: debug info, -Og.
FW_DEBUG ?= 1
FW_OPT   ?= -Og

OBJDIR := $(OUT)/obj

# Flags shared by C and assembly. The same as the generated Makefile, which
# also compiles the startup file with its C flags.
FW_COMMON := $(CUBE_MCU) $(CUBE_DEFS) $(FW_DEFS) $(FW_OPT) -Wall \
             -fdata-sections -ffunction-sections

# Shorten source paths in __FILE__, which lwIP's assert messages store in
# flash: CubeMX files show as in the generated build (LWIP/Target/...), and
# ours relative to the repo root (app/src/...). GCC checks the last map first.
FW_COMMON += -fmacro-prefix-map=$(ROOT)/= -fmacro-prefix-map=$(CUBE)/=
ifeq ($(FW_DEBUG),1)
  FW_COMMON += -g -gdwarf-2
endif

# gnu17 is GCC 13's default, so stating it changes nothing; it keeps the
# standard fixed if the compiler's default changes.
FW_CFLAGS  = $(FW_COMMON) -std=gnu17 $(FW_WARN) $(INCLUDES) -MMD -MP
FW_ASFLAGS = $(FW_COMMON) $(INCLUDES) -MMD -MP

# Extra warnings, set per folder by the including makefile, for example for
# our own code only.
FW_WARN ?=

FW_LDFLAGS = $(CUBE_MCU) -specs=nano.specs -T$(LDSCRIPT_FILE) $(CUBE_LIBS) \
             -Wl,-Map=$(OUT)/$(TARGET).map,--cref -Wl,--gc-sections \
             -Wl,--print-memory-usage

# Object files mirror the source tree under $(OBJDIR), and keep the source
# extension (main.c -> main.c.o), so two files with the same name can't
# collide.
OBJS := $(patsubst $(ROOT)/%,$(OBJDIR)/%.o,$(SRCS))

# Rebuild everything if a makefile changes, including the generated one.
FW_MAKEFILES := $(MAKEFILE_LIST)

$(OBJDIR)/%.c.o: $(ROOT)/%.c $(FW_MAKEFILES)
	@mkdir -p $(@D)
	$(CC) -c $(FW_CFLAGS) $< -o $@

$(OBJDIR)/%.s.o: $(ROOT)/%.s $(FW_MAKEFILES)
	@mkdir -p $(@D)
	$(AS) -c $(FW_ASFLAGS) $< -o $@

$(OBJDIR)/%.S.o: $(ROOT)/%.S $(FW_MAKEFILES)
	@mkdir -p $(@D)
	$(AS) -c $(FW_ASFLAGS) $< -o $@

$(OUT)/$(TARGET).elf: $(OBJS) $(LDSCRIPT_FILE)
	$(CC) $(OBJS) $(FW_LDFLAGS) -o $@
	$(SIZE) $@

$(OUT)/%.hex: $(OUT)/%.elf
	$(OBJCOPY) -O ihex $< $@

$(OUT)/%.bin: $(OUT)/%.elf
	$(OBJCOPY) -O binary -S $< $@

-include $(OBJS:.o=.d)

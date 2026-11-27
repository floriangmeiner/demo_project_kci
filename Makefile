# Top-level build for the STM32 Secure Telemetry Link firmware.
#
#   make          build the application into build/app/
#   make flash    build, then flash it through the J-Link
#   make size     show the application's section sizes
#   make clean    delete build/
#
# The CubeMX-generated Makefile in kepler_demo_stm32f746g-disco/ is only read
# for its file lists, never run. See documentation/build_system.md.

APP_ELF := build/app/kepler_demo_app.elf

# Build in parallel by default, unless -j was given on the command line.
ifeq ($(filter -j%,$(MAKEFLAGS)),)
  JOBS := -j$(shell nproc)
endif

.PHONY: all app flash size clean

all: app

app:
	$(MAKE) -C app $(JOBS)

# Runs from the repo root, where the script's relative .hex path resolves.
flash: app
	JLinkExe -CommandFile tools/debug/flash_app.jlink

size: app
	arm-none-eabi-size $(APP_ELF)

clean:
	rm -rf build

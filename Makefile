HEAP_SIZE      = 8388208
STACK_SIZE     = 61800

PRODUCT = ldpbsgcfpd.pdx

# Locate the SDK
SDK = ${PLAYDATE_SDK_PATH}
ifeq ($(SDK),)
	SDK = $(shell egrep '^\s*SDKRoot' ~/.Playdate/config | head -n 1 | cut -c9-)
endif

ifeq ($(SDK),)
$(error SDK path not found; set ENV value PLAYDATE_SDK_PATH)
endif

VPATH += src

SRC = src/main.c src/physics.c

UINCDIR = src
UASRC =
UDEFS =
UADEFS =
ULIBDIR =
ULIBS = -lm

include $(SDK)/C_API/buildsupport/common.mk

# The toolchain the Playdate installer links into /usr/local/bin is x86_64
# only. Prefer the native Arm GNU Toolchain when it's installed; override with
# `make ARM_TOOLCHAIN=/path/to/bin/`.
ARM_TOOLCHAIN ?= $(lastword $(sort $(wildcard /Applications/ArmGNUToolchain/*/arm-none-eabi/bin/)))

ifneq ($(ARM_TOOLCHAIN),)
GCC := $(ARM_TOOLCHAIN)
OJBCPY := $(ARM_TOOLCHAIN)
endif

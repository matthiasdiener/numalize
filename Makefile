# PIN_ROOT must point to the Pin kit root.

# Specify Pin path manually:
# override PIN_ROOT = /path/to/pin

# Do not edit below this line


# Try to detect Pin installation directory in user's /home and /opt
ifeq ($(PIN_ROOT), )
  override PIN_ROOT = $(shell dirname $$(find ~ /opt -type f -name pin -path '*/*pin' -print -quit))
endif

ifeq ($(PIN_ROOT), )
  $(error Could not detect Pin installation directory, please specify PIN_ROOT manually in the Makefile)
endif

ifeq ($(MAKECMDGOALS), )
  $(info PIN_ROOT is ${PIN_ROOT})
  $(shell echo ${PIN_ROOT} > .pin_root)
endif

ifdef PIN_ROOT
CONFIG_ROOT := $(PIN_ROOT)/source/tools/Config
else
CONFIG_ROOT := ../Config
endif
include $(CONFIG_ROOT)/makefile.config

TOOL_CXXFLAGS += -Wall -g -std=c++0x -Wno-error -Wextra -Wno-unused-parameter -pedantic
# TOOL_LDFLAGS += -Wl,-rpath,$PIN_ROOT/intel64/runtime

TEST_TOOL_ROOTS := numalize

include $(TOOLS_ROOT)/Config/makefile.default.rules

# PIN_ROOT must point to the Pin kit root.

override PIN_ROOT = /opt/pin

# Do not edit below this line

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

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

TOOL_NAME = a5vm
a5vm_FILES = src/memory.c src/cpu8086.c src/main.c
a5vm_CFLAGS = -Iinclude -std=c11 -Wall -Wextra

include $(THEOS_MAKE_PATH)/tool.mk

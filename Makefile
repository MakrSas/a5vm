TARGET := iphone:clang:6.1:6.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

TOOL_NAME = a5vm
a5vm_FILES = src/memory.c src/cpu8086.c src/cpu386.c src/vga_text.c src/keyboard.c \
             src/floppy.c src/disk.c src/ide.c src/bios.c src/pic8259.c src/pit8253.c \
             src/machine.c src/main.c
a5vm_CFLAGS = -Iinclude -std=c11 -Wall -Wextra

include $(THEOS_MAKE_PATH)/tool.mk

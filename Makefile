# 确保 THEOS 变量存在（优先环境变量，若没有则使用默认路径）
THEOS ?= $(HOME)/theos

TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = fipad
fipad_FILES = Tweak.x
fipad_CFLAGS = -fobjc-arc

SUBPROJECTS += fipadsettings

include $(THEOS)/makefiles/tweak.mk
include $(THEOS)/makefiles/aggregate.mk
# 确保 THEOS 变量存在
THEOS ?= $(HOME)/theos

TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

# ===== 新增：编译前自动缩放图标 =====
before-all::
	@echo "Resizing icon to 29x29..."
	@sips -Z 29 fipadsettings/Resources/icon.png 2>/dev/null || echo "⚠️  sips failed (ignore if icon not found)"

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = fipad
fipad_FILES = Tweak.x
fipad_CFLAGS = -fobjc-arc

SUBPROJECTS += fipadsettings

include $(THEOS)/makefiles/tweak.mk
include $(THEOS)/makefiles/aggregate.mk
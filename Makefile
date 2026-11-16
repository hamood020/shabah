TARGET := iphone:clang:latest:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = Shabah

Shabah_FILES = $(wildcard Source/*.m)
Shabah_CFLAGS = -fobjc-arc -ISource -Wno-deprecated-declarations
Shabah_FRAMEWORKS = Foundation UIKit CoreLocation MapKit QuartzCore
# The dylib is injected into an app bundle and loaded from its Frameworks folder.
Shabah_INSTALL_PATH = @executable_path/Frameworks

include $(THEOS_MAKE_PATH)/library.mk

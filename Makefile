TARGET := iphone:clang:16.5:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = Shabah

Shabah_FILES = $(wildcard Source/*.m)
Shabah_CFLAGS = -fobjc-arc -ISource -Wno-deprecated-declarations -Wno-error
Shabah_FRAMEWORKS = Foundation UIKit CoreLocation MapKit QuartzCore AVFoundation UserNotifications UniformTypeIdentifiers
# The dylib is injected into an app bundle and loaded from its Frameworks folder.
Shabah_INSTALL_PATH = @executable_path/Frameworks

include $(THEOS_MAKE_PATH)/library.mk

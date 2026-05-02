APP_NAME := TrayPulsy
BINARY := .build/release/$(APP_NAME)
APP_BUNDLE := $(APP_NAME).app
SKINS := $(shell git ls-files 'Sources/Resources/*.png' | sed 's|Sources/Resources/\([^/]*\)/.*|\1|' | sort -u)
SPARKLE_FW := .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
SPARKLE_DIR := $(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
VERSION := $(or $(VERSION),0.0.0)

.PHONY: all app clean run

all: app

app: $(BINARY)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/
	strip -u -r $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Sources/Resources/Info.plist $(APP_BUNDLE)/Contents/
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	cp Sources/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@for skin in $(SKINS); do \
		cp -r Sources/Resources/$$skin $(APP_BUNDLE)/Contents/Resources/; \
	done
	# Copy Sparkle framework preserving symlinks, then thin to arm64 only
	cp -R -P $(SPARKLE_FW) $(APP_BUNDLE)/Contents/Frameworks/
	@find $(SPARKLE_DIR)/Versions -perm +111 -type f | while read f; do \
		lipo -info "$$f" 2>/dev/null | grep -q "are:" && lipo "$$f" -thin arm64 -output "$$f" || true; \
	done
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	codesign --deep --force -s - $(APP_BUNDLE)
	@echo "✅ $(APP_BUNDLE)"

$(BINARY):
	swift build -c release

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf $(APP_BUNDLE)
	rm -rf .build/release

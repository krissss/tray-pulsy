APP_NAME := TrayPulsy
PROJECT := $(APP_NAME).xcodeproj
SCHEME := $(APP_NAME)
CONFIGURATION := Release
DERIVED_DATA := .build/xcode-app
BUILT_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
APP_BUNDLE := $(APP_NAME).app
SPARKLE_SIGN_UPDATE := $(DERIVED_DATA)/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
VERSION := $(or $(VERSION),0.0.0)

.PHONY: all app build clean run print-sparkle-sign-update

all: app

app: build
	@rm -rf $(APP_BUNDLE)
	@ditto "$(BUILT_APP)" "$(APP_BUNDLE)"
	@codesign --verify --deep --strict --verbose=1 "$(APP_BUNDLE)"
	@echo "✅ $(APP_BUNDLE)"

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-destination 'platform=macOS,arch=arm64' \
		TRAYPULSY_VERSION="$(VERSION)" \
		build

print-sparkle-sign-update:
	@test -x "$(SPARKLE_SIGN_UPDATE)"
	@printf '%s\n' "$(SPARKLE_SIGN_UPDATE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf "$(APP_BUNDLE)"
	rm -rf "$(DERIVED_DATA)"

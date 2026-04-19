APP_NAME := TrayPulsy
BINARY := .build/release/$(APP_NAME)
APP_BUNDLE := $(APP_NAME).app
SKINS := $(shell git ls-files 'Sources/Resources/*.png' | sed 's|Sources/Resources/\([^/]*\)/.*|\1|' | sort -u)

.PHONY: all app clean run

all: app

app: $(BINARY)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/
	cp Sources/Resources/Info.plist $(APP_BUNDLE)/Contents/
	cp Sources/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@for skin in $(SKINS); do \
		cp -r Sources/Resources/$$skin $(APP_BUNDLE)/Contents/Resources/; \
	done
	@echo "✅ $(APP_BUNDLE)"

$(BINARY):
	swift build -c release

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf $(APP_BUNDLE)
	rm -rf .build/release

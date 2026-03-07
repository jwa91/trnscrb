.PHONY: all build app sign dmg install clean verify test

APP_NAME     := trnscrb
VERSION      := $(shell cat VERSION)
BUILD_NUMBER := $(shell git rev-list --count HEAD)
IDENTITY     ?= -

APP_BUNDLE   := build/$(APP_NAME).app
CONTENTS     := $(APP_BUNDLE)/Contents
MACOS_DIR    := $(CONTENTS)/MacOS

all: sign

build:
	swift build -c release

app: build
	@BIN_PATH=$$(swift build -c release --show-bin-path) && \
	rm -rf $(APP_BUNDLE) && \
	mkdir -p $(MACOS_DIR) && \
	cp "$$BIN_PATH/$(APP_NAME)" $(MACOS_DIR)/ && \
	sed -e 's/$${VERSION}/$(VERSION)/' -e 's/$${BUILD_NUMBER}/$(BUILD_NUMBER)/' \
		Support/Info.plist > $(CONTENTS)/Info.plist && \
	chmod +x $(MACOS_DIR)/$(APP_NAME) && \
	echo "Assembled $(APP_BUNDLE) v$(VERSION) ($(BUILD_NUMBER))"

sign: app
	codesign --force --sign "$(IDENTITY)" \
		--entitlements Support/trnscrb.entitlements \
		--options runtime --timestamp \
		$(APP_BUNDLE)
	@echo "Signed $(APP_BUNDLE) with identity: $(IDENTITY)"

dmg: test sign
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		build/$(APP_NAME)-$(VERSION).dmg
	@if [ "$(IDENTITY)" != "-" ]; then \
		codesign --force --sign "$(IDENTITY)" --timestamp build/$(APP_NAME)-$(VERSION).dmg; \
		echo "Signed build/$(APP_NAME)-$(VERSION).dmg with identity: $(IDENTITY)"; \
	else \
		echo "Created build/$(APP_NAME)-$(VERSION).dmg (disk image not signed for distribution)"; \
	fi

install: sign
	@rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	rm -rf build/
	swift package clean

test:
	xcodebuild test -scheme $(APP_NAME) \
		-destination 'platform=macOS,arch=arm64' \
		-test-timeouts-enabled YES \
		-default-test-execution-time-allowance 30

verify: sign
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)

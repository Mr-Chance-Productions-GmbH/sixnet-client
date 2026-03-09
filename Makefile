PROJECT   = app/SixnetClient.xcodeproj
SCHEME    = SixnetClient
BUILD_DIR = build
APP_NAME  = SixnetClient

# DerivedData (module cache, index) stays in Xcode's default ~/Library/Developer/Xcode/DerivedData/
# — not cloud-synced, no path issues. Only the final .app is redirected to build/.
BUILD_REAL = $(shell realpath "$(BUILD_DIR)")

.PHONY: build release dist run clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build

dist:
ifndef VERSION
	$(error VERSION is required: make dist VERSION=0.1.0)
endif
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build
	hdiutil create \
		-volname "Sixnet Client" \
		-srcfolder "$(BUILD_REAL)/$(APP_NAME).app" \
		-ov -format UDZO \
		"$(BUILD_REAL)/$(APP_NAME)-$(VERSION).dmg"
	@echo "Built: $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"
	@shasum -a 256 "$(BUILD_REAL)/$(APP_NAME)-$(VERSION).dmg"

run: build
	-pkill -x "$(APP_NAME)" 2>/dev/null; sleep 0.3
	open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	rm -rf "$(BUILD_DIR)"/*

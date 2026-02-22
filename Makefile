PROJECT   = app/SixnetClient.xcodeproj
SCHEME    = SixnetClient
BUILD_DIR = build
APP_NAME  = SixnetClient

.PHONY: build release run clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

run: build
	open "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR)

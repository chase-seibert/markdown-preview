PROJECT := MarkdownPreview.xcodeproj
SCHEME := MarkdownPreview
CONFIGURATION ?= Debug
DERIVED_DATA := build
APP_NAME := Markdown Preview
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
INSTALL_PATH := $(HOME)/Applications/$(APP_NAME).app
REFERENCE_MARKDOWN := $(CURDIR)/docs/editing-example.md
BUNDLE_IDENTIFIER := com.cseibert.MarkdownPreview

.PHONY: setup format lint test build run install clean

setup:
	swift package resolve

format:
	swift format --in-place --recursive MarkdownCore MarkdownPreviewApp MarkdownPreviewQuickLook Tests

lint:
	swift build
	plutil -lint MarkdownPreviewApp/Info.plist MarkdownPreviewQuickLook/Info.plist

test:
	swift test

build:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO build

run: install
	open -a "$(INSTALL_PATH)" "$(REFERENCE_MARKDOWN)"

install:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" build
	@/usr/bin/osascript -e 'tell application "System Events" to set isRunning to exists (processes where bundle identifier is "$(BUNDLE_IDENTIFIER)")' -e 'if isRunning then tell application id "$(BUNDLE_IDENTIFIER)" to quit'
	@/usr/bin/osascript -e 'repeat 50 times' -e 'tell application "System Events" to set isRunning to exists (processes where bundle identifier is "$(BUNDLE_IDENTIFIER)")' -e 'if not isRunning then return' -e 'delay 0.1' -e 'end repeat' -e 'error "Markdown Preview did not quit in time"'
	@mkdir -p "$(HOME)/Applications"
	ditto "$(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app" "$(INSTALL_PATH)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALL_PATH)"

clean:
	swift package clean
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -derivedDataPath "$(DERIVED_DATA)" clean

PROJECT := MarkdownPreview.xcodeproj
SCHEME := MarkdownPreview
CONFIGURATION ?= Debug
DERIVED_DATA := build
APP_NAME := Markdown Preview
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
RELEASE_APP_PATH := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_PATH ?= $(HOME)/Applications/$(APP_NAME).app
REFERENCE_MARKDOWN := $(CURDIR)/docs/editing-example.md
BUNDLE_IDENTIFIER := com.cseibert.MarkdownPreview
DEVELOPMENT_TEAM ?= 96NAC4VTEN
SIGNING_MODE ?= team

.PHONY: setup format lint test build run install sign-app clean

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
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGNING_ALLOWED=NO build

run: install
	open -a "$(INSTALL_PATH)" "$(REFERENCE_MARKDOWN)"

install:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGNING_ALLOWED=$(if $(filter team,$(SIGNING_MODE)),YES,NO) build
	$(MAKE) sign-app
	@/usr/bin/killall "$(APP_NAME)" 2>/dev/null || true
	@/usr/bin/osascript -e 'repeat 50 times' -e 'tell application "System Events" to set isRunning to exists (processes where bundle identifier is "$(BUNDLE_IDENTIFIER)")' -e 'if not isRunning then return' -e 'delay 0.1' -e 'end repeat' -e 'error "Markdown Preview did not quit in time"'
	@mkdir -p "$(HOME)/Applications"
	ditto "$(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app" "$(INSTALL_PATH)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALL_PATH)"

sign-app:
	@set -eu; \
	case "$(SIGNING_MODE)" in \
	  team) expected_team="$(DEVELOPMENT_TEAM)" ;; \
	  adhoc) expected_team=; \
	    codesign --force --deep --sign - "$(RELEASE_APP_PATH)"; \
	    codesign --verify --deep --strict "$(RELEASE_APP_PATH)"; \
	    ;; \
	  unsigned) echo "Skipping code signing (SIGNING_MODE=unsigned)."; exit 0 ;; \
	  *) echo "Unsupported SIGNING_MODE=$(SIGNING_MODE); use team, adhoc, or unsigned." >&2; exit 2 ;; \
	esac; \
	if [ -n "$${expected_team:-}" ]; then \
	 codesign --verify --deep --strict "$(RELEASE_APP_PATH)"; \
	 actual_team=$$(codesign -dvvv "$(RELEASE_APP_PATH)" 2>&1 | awk -F= '/^TeamIdentifier=/{print $$2}'); \
	 if [ "$$actual_team" != "$$expected_team" ]; then echo "Expected TeamIdentifier=$$expected_team, got $${actual_team:-none}." >&2; exit 1; fi; \
	fi

clean:
	swift package clean
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -derivedDataPath "$(DERIVED_DATA)" clean

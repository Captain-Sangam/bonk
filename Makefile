SHELL := /bin/zsh

.PHONY: all build test check validate verify app run screenshots clean

all: app

build:
	swift build -Xswiftc -warnings-as-errors

test:
	@xcrun --find xctest >/dev/null 2>&1 || { \
		echo "XCTest is unavailable. Install full Xcode and select it with xcode-select before running make verify." >&2; \
		exit 1; \
	}
	swift test

check:
	swift run BonkChecks

validate: build check

verify: validate test

app: validate
	Scripts/build-app.sh
	codesign --verify --deep --strict dist/Bonk.app

run: app
	open dist/Bonk.app

screenshots:
	swift run BonkCharacterGallery \
		docs/images/reaction-gallery.png \
		docs/images/guard-mode-preview.png

clean:
	swift package clean
	/bin/rm -rf -- dist/Bonk.app

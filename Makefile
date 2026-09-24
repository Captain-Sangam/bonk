SHELL := /bin/zsh

.PHONY: all build test check verify app run screenshots clean

all: app

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

check:
	swift run BonkChecks

verify: build test check

app: verify
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

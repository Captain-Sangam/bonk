# Thin wrappers over Swift Package Manager and Scripts/build-app.sh.
# The packaging script stays the source of truth for the app bundle.

SHELL := /bin/zsh

.DEFAULT_GOAL := help
.PHONY: help all install build test check validate verify app run export screenshots clean

# Override for a custom destination: make export INSTALL_DIR=/path/to/Applications
INSTALL_DIR ?=

help: ## Show available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  make %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

all: app ## Build and package Bonk.app

install: ## Resolve Swift package dependencies
	swift package resolve

build: ## Build with compiler warnings treated as errors
	swift build -Xswiftc -warnings-as-errors

test: ## Run the XCTest suite (requires full Xcode)
	@xcrun --find xctest >/dev/null 2>&1 || { \
		echo "XCTest is unavailable. Install full Xcode and select it with xcode-select before running make verify." >&2; \
		exit 1; \
	}
	swift test

check: ## Run executable checks
	swift run BonkChecks

validate: build check ## Build and run executable checks

verify: validate test ## Run the build, executable checks, and XCTest suite

app: validate ## Package and verify the signed app in dist/Bonk.app
	Scripts/build-app.sh
	codesign --verify --deep --strict dist/Bonk.app

run: app ## Build and launch Bonk.app
	open dist/Bonk.app

export: app ## Build and install Bonk.app into Applications for Spotlight
	@set -e; \
	install_directory="$(INSTALL_DIR)"; \
	if [ -z "$$install_directory" ]; then \
		if [ -w /Applications ]; then install_directory=/Applications; \
		else install_directory="$$HOME/Applications"; fi; \
	fi; \
	/bin/mkdir -p "$$install_directory"; \
	/bin/rm -rf -- "$$install_directory/Bonk.app"; \
	/usr/bin/ditto dist/Bonk.app "$$install_directory/Bonk.app"; \
	/usr/bin/codesign --verify --deep --strict "$$install_directory/Bonk.app"; \
	echo "Installed $$install_directory/Bonk.app — launch it from Spotlight (⌘Space → Bonk)"

screenshots: ## Regenerate character gallery and guard-mode screenshots
	swift run BonkCharacterGallery \
		docs/images/reaction-gallery.png \
		docs/images/guard-mode-preview.png

clean: ## Remove Swift build output and dist/Bonk.app
	swift package clean
	/bin/rm -rf -- dist/Bonk.app

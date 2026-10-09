SWIFT_FORMAT_PATHS = Sources Tests Package.swift

.DEFAULT_GOAL := help
.PHONY: help build release test fmt fmt-check lint lint-actions lint-scripts bundle bundle-universal run check clean

help:
	@echo "Targets:"
	@echo "  build             debug build"
	@echo "  release           release build"
	@echo "  test              run unit tests"
	@echo "  fmt               format sources in place"
	@echo "  fmt-check         verify formatting (strict)"
	@echo "  lint              fmt-check + jactionlint + shellcheck"
	@echo "  bundle            build dist/QuartzDrop.app (host arch) and zip"
	@echo "  bundle-universal  same, arm64 + x86_64"
	@echo "  run               run quartz-drop with verbose logging"
	@echo "  check             lint + build + test (CI)"
	@echo "  clean             remove .build and dist"

build:
	swift build

release:
	swift build -c release

test:
	swift test

fmt:
	swift format --in-place --recursive $(SWIFT_FORMAT_PATHS)

fmt-check:
	swift format lint --strict --recursive $(SWIFT_FORMAT_PATHS)

# jactionlint and shellcheck are installed by mise (see mise.toml).
lint-actions:
	jactionlint

lint-scripts:
	shellcheck scripts/*.sh

lint: fmt-check lint-actions lint-scripts

bundle:
	scripts/bundle.sh

bundle-universal:
	ARCHS=universal scripts/bundle.sh

run:
	swift run quartz-drop -v

check: lint build test

clean:
	swift package clean
	rm -rf dist

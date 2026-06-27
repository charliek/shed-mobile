.PHONY: get fmt check analyze test build-macos build-linux

get:
	flutter pub get

fmt:
	dart format .

# The CI gate (mirrors .github/workflows/ci.yml).
check: get
	dart format --output=none --set-exit-if-changed .
	flutter analyze
	flutter test

analyze:
	flutter analyze

test:
	flutter test

build-macos:
	flutter build macos --debug

build-linux:
	flutter build linux --debug

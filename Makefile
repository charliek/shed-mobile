.PHONY: get fmt check analyze test build-macos build-linux docs docs-serve

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

# Build the documentation site (output: site-build/).
docs:
	uv sync --group docs
	uv run mkdocs build

# Serve the documentation locally (http://127.0.0.1:7072).
docs-serve:
	uv sync --group docs
	uv run mkdocs serve

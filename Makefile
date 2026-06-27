.PHONY: get fmt check analyze test build-macos build-linux icons docs docs-serve

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

# Regenerate the owl app icons from the SVG and deploy them into android/ + macos/.
# Edit the color constants in scripts/generate_app_icons.py, then run this.
# cairosvg loads native libcairo via ctypes, which doesn't search Homebrew's
# prefix on macOS — add it to the dyld fallback path so the render works there.
icons:
	@if [ "$$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then \
		export DYLD_FALLBACK_LIBRARY_PATH="$$(brew --prefix)/lib:$${DYLD_FALLBACK_LIBRARY_PATH:-/usr/local/lib:/usr/lib}"; \
	fi; \
	uv run --with cairosvg --with pillow python scripts/generate_app_icons.py
	dart run flutter_launcher_icons

# Build the documentation site (output: site-build/).
docs:
	uv sync --group docs
	uv run mkdocs build

# Serve the documentation locally (http://127.0.0.1:7072).
docs-serve:
	uv sync --group docs
	uv run mkdocs serve

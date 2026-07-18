.PHONY: get fmt check check-lock analyze test build-macos build-linux icons docs docs-serve frb-gen

get:
	flutter pub get

# TWO-STEP Rust-bridge codegen (plan D2 — FRB 2.13 renders fielded Rust enums as
# Dart sealed classes via freezed). ALWAYS run both, in this order, after any
# change to rust/src/api/*.rs:
#   1. flutter_rust_bridge_codegen generate  — Rust API -> lib/src/rust/*.dart
#      (emits `@freezed sealed class …` sources + frb_generated.rs/.dart)
#   2. dart run build_runner build           — expands the @freezed sources into
#      the committed *.freezed.dart (the sealed-class machinery)
# Both outputs are committed; CI re-runs step 1 from a clean checkout and asserts
# no diff (the drift guard). NOTE: build_runner 2.15 dropped
# `--delete-conflicting-outputs` (now the default; passing it is a harmless no-op).
frb-gen: get
	flutter_rust_bridge_codegen generate
	dart run build_runner build

fmt:
	dart format .

# The CI gate (mirrors .github/workflows/ci.yml).
check: get
	dart format --output=none --set-exit-if-changed .
	flutter analyze
	flutter test

# Assert the committed Cargo.lock resolves the shed core deps to the exact
# git rev pinned in rust/Cargo.toml (the gitignored local [patch] must never
# leak a local path into the lock). CI runs the same script; CI is the
# authority — this is a convenience mirror for local pre-push checks.
check-lock:
	bash scripts/check-lock-rev.sh

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

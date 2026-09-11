.PHONY: get fmt check check-lock analyze test cargo-test build-macos build-linux icons docs docs-serve frb-gen test-integration-linux

# The CI Flutter pin (.github/workflows/ci.yml). `test-integration-linux` warns
# when the local SDK differs, because that gap is where an integration harness
# passes locally and fails on the PR.
CI_FLUTTER_VERSION := 3.44.2

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

# The CI gate (mirrors .github/workflows/ci.yml). The Rust bridge crate is part
# of it: half this app's behaviour (the whole credential/transport layer) lives
# in `rust/src/api/`, and `flutter test` cannot see any of it.
check: get check-lock
	dart format --output=none --set-exit-if-changed .
	flutter analyze
	flutter test
	$(MAKE) cargo-test

# Unit-test the Rust bridge crate.
#
# `--locked` is the canonical (CI) form: it proves the committed Cargo.lock
# resolves with no drift, which `check-lock` alone cannot — that one compares
# text, this one resolves.
#
# A sibling-checkout dev is the awkward case, and the awkwardness is inherent:
# the gitignored rust/.cargo/config.toml [patch] resolves the shed deps to LOCAL
# PATHS, and cargo can only apply that by REWRITING Cargo.lock to name those
# paths — the exact leak `check-lock` exists to catch. So `--locked` there is
# guaranteed to fail for a reason that says nothing about the code, and a plain
# `cargo test` leaves a dirty, uncommittable lock behind.
#
# Handle it explicitly: point the lock at the local crates, run the tests, and
# restore the canonical lock on the way out (trap, so a failing or interrupted
# run restores it too). Local dev and CI then run the same tests against
# different resolutions, which is precisely what the [patch] is for.
cargo-test:
	@set -u; \
	if [ -f rust/.cargo/config.toml ]; then \
	  echo "NOTE: local sibling [patch] active (rust/.cargo/config.toml) — testing"; \
	  echo "      against the LOCAL shed crates and restoring the canonical Cargo.lock"; \
	  echo "      afterwards. CI runs 'cargo test --locked' with no patch."; \
	  root=$$(pwd); \
	  cp "$$root/rust/Cargo.lock" "$$root/rust/.Cargo.lock.canonical"; \
	  trap 'mv -f "$$root/rust/.Cargo.lock.canonical" "$$root/rust/Cargo.lock"' EXIT INT TERM; \
	  ( cd rust && cargo update --offline -q -p shed-core -p shed-app -p shed-opencode -p shed-gx && cargo test ); \
	else \
	  cd rust && cargo test --locked; \
	fi

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

# The hermetic integration harness on the Flutter LINUX DESKTOP build
# (integration_test/ — the agent-lane cells plus the two FRB-surface files).
#
# It drives the real bridge against shed's own gx/opencode fakes, hosted by
# $(SHED_CHECKOUT)/desktop/tools/shedtest/fake_lane_server.py — so it needs a
# shed checkout (a sibling by default) and `python3`, but no sshd, no network
# and no agent.
#
# `dbus-run-session` is unconditional rather than a fallback: the cells never
# touch flutter_secure_storage (no `main()`, no MachineStore), but plugin
# registration at app start may still want a session bus, and a gate that
# depends on the environment is not a gate.
#
# **ONE `flutter test` PER FILE, and that is not a preference.** A single
# invocation naming several files launches the app once per file, and on the
# Linux desktop device the SECOND launch always fails with "Unable to start the
# app on the device" / "the log reader stopped unexpectedly". It is positional,
# not file-specific (either of the two pre-existing files fails when it is
# second, and passes when it is first), so it is a property of the device
# runner. The loop runs every file even after one fails — a first failure that
# hid the rest would make the harness worth less.
#
# The two-file restore is the point of the recipe. Local Flutter drifts from the
# CI pin, and `flutter pub get` (which `flutter test` runs implicitly) rewrites
# pubspec.lock and analysis_options.yaml on a newer SDK. So: record whether each
# was clean BEFORE the run, and restore ONLY the ones that were — a developer's
# own edit to either file is never reverted.
SHED_CHECKOUT ?= ../shed
test-integration-linux:
	@set -u; \
	if ! command -v xvfb-run >/dev/null 2>&1 || ! command -v dbus-run-session >/dev/null 2>&1; then \
	  echo "test-integration-linux needs xvfb-run + dbus-run-session (apt install xvfb dbus-x11)" >&2; \
	  exit 1; \
	fi; \
	if [ ! -f "$(SHED_CHECKOUT)/desktop/tools/shedtest/fake_lane_server.py" ]; then \
	  echo "no shed checkout at $(SHED_CHECKOUT) — set SHED_CHECKOUT=/path/to/shed" >&2; \
	  exit 1; \
	fi; \
	have=$$(flutter --version 2>/dev/null | head -1 | awk '{print $$2}'); \
	if [ "$$have" != "$(CI_FLUTTER_VERSION)" ]; then \
	  echo "WARNING: local Flutter $$have != the CI pin $(CI_FLUTTER_VERSION)."; \
	  echo "         The harness runs on the pin in CI; a green run here is not a green run there."; \
	fi; \
	clean_lock=0; clean_opts=0; \
	git diff --quiet -- pubspec.lock 2>/dev/null && clean_lock=1; \
	git diff --quiet -- analysis_options.yaml 2>/dev/null && clean_opts=1; \
	restore() { \
	  if [ "$$clean_lock" = "1" ]; then git checkout -- pubspec.lock 2>/dev/null || true; fi; \
	  if [ "$$clean_opts" = "1" ]; then git checkout -- analysis_options.yaml 2>/dev/null || true; fi; \
	}; \
	trap restore EXIT INT TERM; \
	export SHED_CHECKOUT="$$(cd "$(SHED_CHECKOUT)" && pwd)"; \
	failed=""; \
	for f in integration_test/*_test.dart; do \
	  echo "=== $$f"; \
	  xvfb-run -a dbus-run-session -- flutter test "$$f" -d linux || failed="$$failed $$f"; \
	done; \
	if [ -n "$$failed" ]; then echo "FAILED:$$failed" >&2; exit 1; fi; \
	echo "integration_test: all files green"

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

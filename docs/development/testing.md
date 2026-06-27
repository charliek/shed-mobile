# Testing & Drive Harness

Four tiers of validation: **(a)** pure unit · **(b)** vs. a fake server · **(c)**
a real test shed · **(d)** manual / hardware.

## The gate

```bash
make check   # pub get + dart format --set-exit-if-changed + flutter analyze + flutter test
```

This mirrors CI. New pure logic gets unit tests **before** the UI; ported
TypeScript logic translates its test tables case-for-case.

## Unit tests (tier a/b)

`test/` mirrors `lib/`. Heaviest coverage sits on the pure ports — the SSE
parser, fingerprints, POSIX quoting, the control-token FSM, RC DTO decoding, and
keygen. Notable golden checks:

- `test/rc/rc_models_test.dart` decodes a fixture byte-identical to
  shed-extensions' `rcSessionDto.golden.json` (the cross-tool DTO contract).
- `test/keys/key_manager_test.dart` asserts the in-app keygen output matches the
  real `ssh-keygen -y`/`-l` (skipped if `ssh-keygen` is absent).

## Real-shed probes (tier c)

Command-line end-to-end tools under `tool/` (not run in CI). They default to
`shed-mobile-test@localhost:2222`:

```bash
dart run tool/e2e_list.dart   # mint -> pin -> GET /api/sheds
dart run tool/e2e_rc.dart     # shed-ext-rc create/list/kill (+ idempotent kill)
dart run tool/e2e_pty.dart    # attach PTY, echo round-trip, resize, detach
```

These verify the transport against reality before any UI is involved — the same
"verify the model before writing the widget" discipline used throughout.

## Drive harness (tier c/d, UI)

The `drive-shed-mobile` skill drives a **debug** build headlessly via the
[Marionette](https://pub.dev/packages/marionette_cli) CLI over the Dart VM
Service — tap, type, screenshot, read structured logs.

```bash
./.claude/skills/drive-shed-mobile/scripts/launch-and-connect.sh macos
#   or an Android device/emulator id, e.g.:  … emulator-5554
M="marionette -i shed-mobile"
$M tap --key servers-add
$M get-logs | grep -E 'MSTATE|MRESULT' | tail -1
$M take-screenshots --output ./shot.png
```

Rules that matter:

- Verify the **effect** via `MSTATE`/`MRESULT` (poll, don't sleep). Marionette
  reports a command dispatched, not that the app reacted.
- A disabled control is a silent no-op — confirm `onPressed` is non-null first.
- Provider-type changes don't hot-reload cleanly; relaunch.
- The xterm canvas isn't introspectable — verify the terminal via `MSTATE`
  (`state=ready`) + a screenshot, and the PTY I/O via `tool/e2e_pty.dart`.

Instrumentation (`logDriveState` / `logDriveResult`, `ValueKey`s on every
control) is `kDebugMode`-gated and tree-shaken from release builds.

## Per-phase loop

Each phase is shipped through: working + unit-tested + `flutter analyze` /
`dart format` → drive-smoke (UI phases) → `/simplify` → `/codex:rescue` →
commit. See [For AI Agents](agents.md).

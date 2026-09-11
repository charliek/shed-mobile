# Testing & Drive Harness

Five tiers of validation: **(a)** pure unit · **(b)** vs. a fake server ·
**(b2)** the hermetic integration harness on the Linux desktop build · **(c)**
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

## The hermetic integration harness (tier b2)

`integration_test/` runs on the **Flutter Linux desktop build**, which is what
lets it load the real Rust bridge:

```bash
make test-integration-linux              # sibling shed checkout (../shed)
SHED_CHECKOUT=/path/to/shed make test-integration-linux
```

Three files, **one `flutter test` invocation each** — and that is a constraint,
not a style choice. A single invocation naming several files relaunches the app
per file, and on the Linux desktop device the *second* launch always fails with
`Unable to start the app on the device`. It is positional rather than
file-specific (either pre-existing file passes when it runs first and fails when
it runs second), so `make test-integration-linux` and the CI step both loop, and
both run every file even after one fails.

| File | What it proves |
|---|---|
| `shed_probe_test.dart` | a Rust→Dart call into shed-core round-trips at runtime |
| `slices_test.dart` | the five FRB bridge surfaces (mint inversion, watcher, RcRunner, create-stream, sealed errors) + the leak counters |
| `lane_test.dart` | the agent lanes, end to end against shed's own gx/opencode fakes |

`lane_test.dart` is the one with an external dependency. It drives a real
`LaneController` and a pumped `LaneScreen` through the **real** FRB bridge
(`BridgeLaneSource`, never a stub) against shed's own
`desktop/tools/shedtest/fake_lane_server.py`, spawned per cell over a loopback
control port. So it needs a **shed checkout** and `python3` — and nothing else:

- **No sshd, no forward, no network.** The harness overrides `laneReachProvider`
  with `LaneReach.local`, so `dial_url == reported_url`. It is an explicit
  override, never inferred from the fake's loopback host — production is
  `LaneReach.machine` for every machine, including `localhost` (a shed VM is
  dialled at `localhost:2222` and its agent is inside the VM). The refcounted
  forward has its own hermetic tests.
- **gx credentials are real.** The fake writes a `$GROK_HOME` (a discovery
  record plus a `0600` token) into a temp dir; the `ProbeRunner` seam's local
  implementation runs `gxProbeRemoteCommand()` verbatim through `sh -c` with
  `GROK_HOME` set. The wire string, the POSIX script and Rust's `parse_probe`
  are all exercised.
- **The fakes are never re-derived in Dart.** Every envelope comes from the
  Python builders by name (`POST /_/envelope/<name>`), because the gx/opencode
  wire vocabularies belong next to the adapters they were recorded from.
- **The shed checkout must be the pinned rev.** The fakes and the adapters under
  test are one tree; CI checks out
  `scripts/check-lock-rev.sh --print-shed-rev` and asserts the sha.

Rules that matter when adding a cell:

- **Never `pumpAndSettle`.** A working lane pulses its activity badge, and a
  repeating animation never settles. Poll with the rig's `pumpUntil`.
- Every cell carries a 60 s timeout, and every fake is stopped from a
  `tearDown` — so a failing cell leaves nothing bound to a loopback port. The
  fake also watches its own stdin, so a killed run leaks nothing either.
- **Both halves of a gx approval are reachable, and so is every gx body.** Two
  knobs on shed's control-door allowlist (`GX_METHODS` in
  `fake_lane_server.py`) carry it: `add_approval`, which writes a REAL approval
  into the fake's store — the copy gx's `answer()` re-reads before it translates
  a decision, so an approval the rig creates can be answered as well as rendered
  — and `bodies_to(suffix)`, which returns every recorded body for a path suffix
  as a LIST (a cell may post to one path twice, and the first body is not always
  the one it means). So a gx cell presses an option and asserts the posted
  `optionId`, answers a question and asserts its `annotations` map, and asserts
  `mode: "interject"` on the wire. `requests()` still carries no body, on
  purpose: its shape is pinned by a cell, and a body there would put a
  token-bearing payload into the one ledger a failure prints.

`make test-integration-linux` also warns when the local Flutter differs from the
CI pin, and restores `pubspec.lock` / `analysis_options.yaml` after the run —
**but only if they were clean before it**, so it never reverts an edit you made.

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

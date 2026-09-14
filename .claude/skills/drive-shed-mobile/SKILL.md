---
name: drive-shed-mobile
description: >-
  Drive, debug, and visually verify the shed-mobile Flutter client (macOS/Linux
  desktop or Android) the way a user would — launch it, tap, type, scroll,
  screenshot, read logs and live state — via the Marionette CLI over the Dart VM
  Service. Use whenever asked to run, launch, drive, operate, or smoke-test the
  app; to verify a UI change; to reproduce a client-side bug; to manually test a
  screen or flow; or to confirm a feature works end to end — even if Marionette
  is not named. Headless (no display/computer-use needed). Debug builds only.
---

# Drive the shed-mobile Flutter app

Marionette attaches to a **debug** build's Dart VM Service and drives it like a
user. Cloned from tapper's drive skill. Headless — portable to containers/CI.

## Preconditions

1. **A reachable secure shed to add** (shed v0.7+, `auth.ssh.mode: enforce`, your
   key trusted via `auth.ssh.github_users` or `authorized_keys`). Dev default:
   `shed-mobile-test@localhost:2222` (and `@mini3:2222`).
2. **Desktop SSH key**: the app reuses `~/.ssh/id_ed25519`. It must be
   **unencrypted** (a passphrase prompt isn't drivable). macOS is sandboxed with
   `network.client` + keychain entitlements (already set in `macos/Runner/*.entitlements`).
3. **Marionette CLI** on PATH (`~/.pub-cache/bin`), else set `MARIONETTE=/path`.

## Launch + connect

```bash
.claude/skills/drive-shed-mobile/scripts/launch-and-connect.sh macos    # or: linux
```

Launches the debug build, parses the `ws://` VM Service URI, and registers an
instance named `shed-mobile`.

It launches `flutter` **from PATH** and passes the process environment through to
the app, which is the hook for both of the things a Linux drive usually wants:

```bash
PATH="$HOME/apps/flutter-3.44.2/bin:$PATH" \        # CI's pin; the default here is 3.47.2
DISPLAY=:77 \                                        # your own Xvfb, not the owner's desktop
ROOST_SESSION_INSTALL_BIN=/path/to/roost-session \   # the bootstrap ladder's first rung
  .claude/skills/drive-shed-mobile/scripts/launch-and-connect.sh linux my-instance
```

Use the **pinned** SDK: a `flutter run` on the local 3.47.2 rewrites
`pubspec.lock` and `analysis_options.yaml`, and those must not enter a diff.
`Xvfb :77 -screen 0 1280x1000x24 &` first if you want a private display; the
screenshots come from the engine, so headless loses nothing.

**Reap the portals when you are done.** Launching under Xvfb activates
`xdg-desktop-portal-*` over D-Bus, and those processes outlive the app at ~200 MB
each — they accumulated to 110 processes and ~15 GB across one day of plan-020
runs, until background commands started being killed for low memory. Kill only
processes whose own `DISPLAY` matches the Xvfb you started; the owner's desktop
session is on a different display and must not be touched. `docs/development/testing.md`
carries the exact loop, under the integration harness.

Put `~/.pub-cache/bin` on PATH for the `marionette` calls that follow — the
script prints absolute paths but every example below assumes the short name.

## Drive reliably — the rules that matter

Marionette reports success when it *dispatches* a command, NOT when the app
reacts. **Always verify the state change via MSTATE/MRESULT; never assume a tap
or text entry worked.**

- **Type-then-tap races**: after `enter-text`, the value may not have committed
  before a `tap` fires. Verify the field via `get-interactive-elements` (or wait
  on an MSTATE transition) before tapping a submit button.
- **A disabled control is a silent no-op**: submit buttons disable while busy
  (`_busy`/`_running`). Confirm `onPressed` is non-null before tapping.
- **Poll MSTATE, not a fixed sleep**, to know when an async step finished.
- **`press-back-button` on the root route KILLS the desktop app.** There is no
  system back stack to fall through to, so the pop exits the process and the
  next marionette call answers `Connection refused`. The trap is that several
  screens pop themselves when they succeed — `CreateRcScreen` does, right after
  `MRESULT rc-create ok` — so a reflexive back press lands on the root route and
  ends the run. Check the last MSTATE line for which screen you are actually on
  before pressing back; on desktop, prefer tapping `nav-*` to navigate.

## Live state via get-logs (MSTATE / MRESULT)

Debug-only structured lines (tree-shaken from release):

- `MSTATE screen=hosts hosts=N` · `MSTATE layout=mobile|desktop section=…`
  · `MSTATE screen=add-server step=input|confirm`
  · `MSTATE screen=sheds server=X count=N` · `MSTATE screen=create lines=N done=…`
- `MRESULT add-server ok` · `MRESULT shed-start ok` · `MRESULT shed-delete ok` · …

`marionette -i shed-mobile get-logs | grep -E 'MSTATE|MRESULT' | tail -1`. Logs
are cumulative + capped; `hot-reload` clears them.

## Canonical flow (add a server, manage sheds)

```bash
M="marionette -i shed-mobile"
$M tap --key servers-add
$M enter-text --key addserver-host --input localhost
$M enter-text --key addserver-port --input 2222
$M tap --key addserver-connect
until $M get-logs | grep -q 'screen=add-server step=confirm'; do sleep 1; done
$M tap --key addserver-confirm                    # confirm the two fingerprints
until $M get-logs | grep -q 'MRESULT add-server ok'; do sleep 1; done
$M tap --key host-card-localhost                   # tile -> ShedListScreen (key = host-card-<name>)
$M get-logs | grep MSTATE | tail -1                # screen=sheds count=N
$M take-screenshots --output ./shed-mobile.png
```

The full key map per screen is in `references/shed-mobile-context.md`; every
Marionette command/flag is in `references/marionette-commands.md`.

## Instrumenting new features so they stay drivable

When you add or change UI, make it drivable in the same change: stable
`ValueKey`s on every control, and `logDriveState`/`logDriveResult` for state the
tree can't show. See `references/instrumenting-new-features.md`.

## When something fails

- `marionette doctor` checks connectivity; `unregister` + a fresh `register`
  recovers a stale instance after a restart.
- Add-server hangs at `step=input` after connect → SSH mint failed: key not
  trusted, host unreachable, or the `~/.ssh` key is passphrase-encrypted. Check
  the `flutter run` log and `MRESULT add-server-connect error=…`.
- `get-interactive-elements` returns 0 → app mid-transition or crashed;
  screenshot, then relaunch.

Cleanup: kill the `flutter run` PID the script printed, then
`marionette unregister shed-mobile`.

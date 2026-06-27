# shed-mobile

A native Flutter fat-client for [shed](https://github.com/charliek/shed) servers.
The device talks **directly** to shed servers over Tailscale — there is no
orchestrator process to run. Targets: macOS + Linux desktop, and Android.

- Pinned-TLS HTTPS to each shed's control API (self-signed cert, sha256 leaf pin)
- SSH (dartssh2) for control-token mint (`_bootstrap`), RC lifecycle
  (`shed-ext-rc`), and an in-app terminal (`tmux attach`)
- One per-device ed25519 key (generated in-app on mobile, or reuse `~/.ssh` on
  desktop), trusted via GitHub (`auth.ssh.github_users`)

See [`docs/PLAN.md`](docs/PLAN.md) for the architecture + milestone plan and
[`PROGRESS.md`](PROGRESS.md) for live build status.

## Status

| Milestone | What | State |
|---|---|---|
| M0 | SSH mint + pinned-TLS transport | ✅ |
| M1 | Server management + shed CRUD + create (SSE) | ✅ |
| M2 | RC sessions via `shed-ext-rc` (create/list/kill, claude.ai URL) | ✅ |
| M3 | In-app terminal (xterm ↔ `tmux attach` PTY) | ✅ |
| M4 | Android port + in-app keygen + foreground service | ✅ code · ⛔ on-device accept |
| M5 | Release builds + signing scaffold + docs | ✅ (signing/notarization = human gate) |

## Develop

```bash
make check          # pub get + format check + analyze + test (the CI gate)
flutter run -d macos          # or: -d linux
```

Requires Flutter 3.44.2 (Dart 3.12).

### Drive / smoke-test (desktop)

A headless Marionette skill drives the debug app like a user:

```bash
./.claude/skills/drive-shed-mobile/scripts/launch-and-connect.sh macos
# then: marionette -i shed-mobile tap --key servers-add   (etc.)
```

Real-shed end-to-end probes (not run in CI):

```bash
dart run tool/e2e_list.dart   # mint → pin → list sheds
dart run tool/e2e_rc.dart     # shed-ext-rc create/list/kill
dart run tool/e2e_pty.dart    # attach a PTY, echo round-trip, resize, detach
```

## Build & release

Debug/release builds for each platform:

```bash
flutter build macos --release        # build/macos/Build/Products/Release/shed_mobile.app
flutter build linux --release
flutter build apk   --release        # build/app/outputs/flutter-apk/app-release.apk
```

Release builds tree-shake the debug-only Marionette instrumentation
(`kDebugMode`-gated) out of the binary.

### Android signing (release)

Without a keystore, release builds fall back to the **debug** key (installable for
personal sideloading). To sign with your own key, create a keystore and an
`android/key.properties` (both are gitignored):

```properties
storeFile=/absolute/path/to/release.jks
storePassword=…
keyAlias=…
keyPassword=…
```

`android/app/build.gradle.kts` picks it up automatically.

### ⛔ Human gates (need credentials / hardware)

- **Android on-device acceptance:** generate the device key in-app → paste its
  public half into GitHub (Settings → SSH and GPG keys; ~1h propagation) →
  connect to a `github_users`-trusting shed → full flow on a real device. The
  in-app keygen output is verified byte-identical to `ssh-keygen` in unit tests,
  but the GitHub-paste + device run can't be automated.
- **macOS signing / notarization:** needs an Apple Developer certificate.
- **Foreground-service background survival:** the keep-alive FGS can only be
  validated on a real Android device (battery-opt prompt, doze behavior).

### Deferred (not in scope)

GitHub repo picker (OAuth / public), `machine:` SSH targets, and iOS — the
architecture leaves seams for these, but they are not built.

Private, sideload-only — not for any app store.

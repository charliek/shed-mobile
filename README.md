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

Signed with the same upload keystore as tapper. `android/app/build.gradle.kts`
(pattern copied from tapper) resolves a release key from two sources, both
gitignored; with neither, release falls back to the **debug** key so local
sideload builds still work.

- **Local:** `android/app/upload-keystore.jks` + `android/key.properties`:

  ```properties
  storeFile=upload-keystore.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```

- **CI:** `KEYSTORE_PATH` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`
  environment variables.

### ⛔ Human gates (need credentials / hardware)

- **Android on-device acceptance:** generate the device key in-app → trust its
  public half on the shed → connect → full flow on a real device. Two ways to
  trust the key:
  - **GitHub:** paste it into Settings → SSH and GPG keys (~1h propagation); the
    shed pulls it via `auth.ssh.github_users`.
  - **Local (no GitHub):** add it to the shed-server's `auth.ssh.authorized_keys`
    (e.g. `/opt/homebrew/etc/shed/server.yaml`) and `brew services restart shed`.
    Validated end-to-end on the Pixel 8 emulator (onboarding keygen → key in local
    config → mint → list → start → RC → terminal), reaching the host shed at
    `10.0.2.2:2222`.
- **macOS signing / notarization (deployment only, NOT needed now):** needs an
  Apple Developer certificate, and only to distribute the `.app` to other Macs
  (Gatekeeper) or to use the macOS Keychain. Local use runs unsigned via
  `flutter run` — the app deliberately uses a 0600 `FileSecretStore` (not the
  Keychain) so no signing cert is required for development.
- **Foreground-service background survival:** the keep-alive FGS can only be
  validated on a real Android device (battery-opt prompt, doze behavior).

### Deferred (not in scope)

GitHub repo picker (OAuth / public), `machine:` SSH targets, and iOS — the
architecture leaves seams for these, but they are not built.

Private, sideload-only — not for any app store.

# Building & Releasing

## Builds

```bash
flutter build macos --release
flutter build linux --release
flutter build apk   --release
```

Release builds tree-shake the debug-only Marionette/drive instrumentation
(`kDebugMode`-gated) out of the binary — verified by zero `MSTATE`/`MRESULT`/
`marionette` symbols in the release AOT.

## Android signing

App ID `ai.stridelabs.shed`, signed with a **dedicated** Shed upload keystore
(`CN=Shed`, alias `upload`) — not tapper's. `android/app/build.gradle.kts`
resolves a release key from two sources, both gitignored; with neither, release
falls back to the **debug** key so local sideload builds still work.

| Source | How |
|---|---|
| Local | `android/app/upload-keystore.jks` + `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). |
| CI | `KEYSTORE_PATH` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` env vars. |

Verify which key signed the artifact (the `.aab` is what Play wants):

```bash
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep -E 'Owner|SHA256'
```

## Play Store release

Full flow (first manual upload + the automated `Release Android` workflow + the
GitHub secrets it needs) is in [Android release](android-release.md).

## CI

`.github/workflows/ci.yml` runs the gate on every push: `dart format`
(`--set-exit-if-changed`), `flutter analyze`, `flutter test`, and a Linux desktop
build (with `ninja-build`, `libgtk-3-dev`, `libsecret-1-dev`, `libjsoncpp-dev`).

## Documentation site

```bash
make docs         # build to site-build/
make docs-serve   # serve at http://127.0.0.1:7072
```

Requires [uv](https://docs.astral.sh/uv/); deps are the `docs` group in
`pyproject.toml`. `site-build/` is gitignored.

## Human gates (need credentials)

| Item | When | Why |
|---|---|---|
| macOS signing / notarization | Deployment only | Required only to distribute the `.app` to other Macs (Gatekeeper) or use the Keychain. Local use runs unsigned via `flutter run`; the app uses `FileSecretStore` to avoid the keychain entitlement. |
| Android on-device acceptance | Release validation | Generate key → trust it → full flow + foreground-service survival on a real device. |

## Deferred

GitHub repo picker (OAuth / public), `machine:` SSH targets, and iOS — the
architecture leaves seams, but they are not built.

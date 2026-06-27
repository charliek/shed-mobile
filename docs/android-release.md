# Android release (Google Play)

shed-mobile ships to Google Play as **Shed** (`ai.stridelabs.shed`). The release
path mirrors tapper: the **first** upload is manual, then the automated
`Release Android` workflow builds a signed AAB and uploads it as a **draft** via
fastlane. You promote drafts to testers in the Play Console.

## Signing

- App ID: `ai.stridelabs.shed` (permanent once published).
- A **dedicated** Shed upload keystore (`CN=Shed, O=Stride Labs`, alias `upload`),
  separate from tapper's key. Generated with:
  ```bash
  keytool -genkeypair -v -keystore android/app/upload-keystore.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias upload \
    -dname "CN=Shed, O=Stride Labs, C=US"
  ```
- The keystore and `android/key.properties` (passwords + alias) are **gitignored**.
  `android/app/build.gradle.kts` reads them locally, or the `KEYSTORE_*`/`KEY_*`
  env vars in CI.
- Play uses **Play App Signing**: this upload key only authenticates uploads;
  Google holds the real app-signing key. Verify the AAB's upload cert with:
  ```bash
  keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep -E 'Owner|SHA256'
  ```

### Keystore backup / restore (envsecrets)

The keystore and `key.properties` are gitignored but backed up encrypted via
[envsecrets](https://github.com/charliek/envsecrets) — they're listed in the
`# envsecrets` section of the repo's root `.gitignore`. On a new machine:

```bash
envsecrets pull        # restores android/key.properties + android/app/upload-keystore.jks
```

After changing either file, `envsecrets push -m "…"`. This is the durable backup
of the upload key — without it, a lost keystore means you can't ship updates.

## One-time Play Console setup

1. Create the app in the [Play Console](https://play.google.com/console): name
   **Shed**. (The store-listing title is independent of the package name.)
2. The package name `ai.stridelabs.shed` is fixed by the **first AAB you upload** —
   there is nothing to type for it, and it can never change afterward.
3. Enrol in **Play App Signing** (default for new apps). On the first upload Play
   registers this AAB's upload certificate automatically.
4. Create a **service account** (Play Console → Setup → API access) with permission
   to upload to release tracks; download its JSON key for the automated flow.

## First release — manual upload

```bash
flutter build appbundle --release
# -> build/app/outputs/bundle/release/app-release.aab  (signed with the Shed key)
```

Upload that `.aab` at **Play Console → Shed → Testing → Internal testing →
Create new release**, add release notes, review, and roll out to your internal
testers. `pubspec.yaml` is `1.0.0+1` (versionCode 1) for this first build; every
later upload needs a strictly higher versionCode.

## Automated releases

`.github/workflows/release-android.yml` (manual `workflow_dispatch`):

```bash
gh workflow run release-android.yml --ref main \
  -f track=internal -f release_notes="what changed"
```

It runs the Flutter checks, computes `versionCode = run_number + offset` (default
offset 100, so it stays above the manual `+1`), builds a signed AAB, and runs
`bundle exec fastlane deploy` (`android/fastlane/`) to upload a **draft** to the
chosen track. Promote the draft in the Play Console to actually release it.

### Required GitHub secrets

Add these to the shed-mobile repo (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | `base64 -i android/app/upload-keystore.jks \| pbcopy` |
| `KEYSTORE_PASSWORD` | the store password (see `android/key.properties`) |
| `KEY_PASSWORD` | the key password (same as store) |
| `KEY_ALIAS` | `upload` |
| `PLAY_STORE_SERVICE_ACCOUNT_JSON` | full contents of the service-account JSON |

The workflow decodes the keystore from `KEYSTORE_BASE64` at build time and deletes
it (and the credentials file) afterward.

# Android

Android adds an in-app key generator, a paste-to-trust onboarding flow, and a
foreground service that keeps the SSH session alive when backgrounded.

Application ID: `ai.stridelabs.shed` (display name **Shed**). Releasing to the
Play Store is documented in [Android release](../android-release.md).

## In-app key generation

On first run the app routes to onboarding (gated by `needsOnboardingProvider`,
which is mobile-only). **Generate device key** creates an ed25519 key:

- pinenacl `SigningKey` → dartssh2 `OpenSSHEd25519KeyPair`.
- The private PEM is stored in `flutter_secure_storage` (Android Keystore-backed);
  only the public `authorized_keys` line + `SHA256:` fingerprint are shown/copied.
- The output is verified **byte-identical to `ssh-keygen -y`/`-l`** by a unit test.

`IdentityStore` writes the private key before advertising the public one, rolls
back on a partial write, and resets to a clean state (rather than crashing the
gate) if an `Android Keystore` read fails — e.g. the key was invalidated by a new
biometric enrollment.

## Key trust

Add the shown public key to the server's SSH allowlist before connecting.

### GitHub

Paste it into **Settings → SSH and GPG keys**; the server pulls it via
`auth.ssh.github_users` (propagation up to ~1 hour).

### Local key trust

For fast local testing without GitHub, add it to the shed-server's
`auth.ssh.authorized_keys` and restart (`brew services restart shed`). See
[Transport & Security](../architecture/transport-security.md#key-trust).

This was validated end-to-end on the **Pixel 8 emulator**: onboarding keygen → key
added to the host shed's local config → add server at `10.0.2.2:2222`
(emulator → host) → mint → list → start → RC create → terminal. The TLS pin makes
the raw-IP host work despite the hostname mismatch.

## Foreground service

Attaching a terminal starts a `specialUse` foreground service
(`flutter_foreground_task`) so Android doesn't kill the live SSH session when the
app is backgrounded. `ShedForegroundService` (`lib/services/foreground_service.dart`):

- Android-only and best-effort — any failure (permission denied, OEM killer) is
  swallowed; the foreground terminal is unaffected.
- Starts on attach, stops on detach, with a `_wantRunning` intent flag re-checked
  after each `await` so a detach racing the permission dialog can't orphan the
  service.
- Requests notification + battery-optimization-exemption permissions. The
  notification text is generic so the shed name/slug never reaches the lock screen.

The manifest declares the `specialUse` service with
`PROPERTY_SPECIAL_USE_FGS_SUBTYPE`, plus `FOREGROUND_SERVICE(_SPECIAL_USE)`,
`POST_NOTIFICATIONS`, `WAKE_LOCK`, and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
`allowBackup=false` keeps Keystore-wrapped secrets out of cloud backups.

## Networking

MagicDNS `100.x` Tailscale addresses can be entered directly in the add-server
host field (no special handling needed). From the emulator, the host machine is
`10.0.2.2`.

## Remaining manual check

On-device acceptance on a real device — full flow + foreground-service background
survival — can't be automated (the drive harness can't background-and-wait).

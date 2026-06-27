# Desktop (macOS / Linux)

Desktop is the primary development target. The app reuses your existing SSH key
and stores secrets in 0600 files, so no signing certificate or keychain
entitlement is needed to run locally.

## SSH identity

Desktop reuses `~/.ssh/id_ed25519` directly (no in-app keygen). The key must be
**unencrypted** — a passphrase prompt is not part of the desktop flow. The app
routes straight to the server list (onboarding is mobile-only).

`KeyManager.importFromFile` accepts OpenSSH (incl. passphrase-encrypted
ed25519/RSA), PKCS#1 RSA, and SEC1 EC; it throws on PKCS#8 or an encrypted legacy
EC key (dartssh2 limitations).

## Secret storage

Desktop uses `FileSecretStore` — one 0600 file per key under `~/.shed-mobile`,
written atomically (temp + rename) with the directory enforced to 0700.

This is a deliberate choice: the macOS Keychain backend of `flutter_secure_storage`
needs a developer signing certificate the ad-hoc local build lacks (it fails with
`errSecMissingEntitlement`). The device already holds the SSH private key on disk
(`~/.ssh`) and the shed CLI keeps its token in plaintext `~/.shed/config.yaml`, so
a 0600 file is a consistent trust model for a personal desktop tool.

## macOS app sandbox

The app sandbox entitlement is **removed** (`com.apple.security.app-sandbox`).
The sandbox redirects `$HOME` and blocks `~/.ssh`, which breaks the desktop SSH
flow. As a personal, locally-built tool this is acceptable; see
[Building & Releasing](../building-and-releasing.md) for the signing/notarization
deployment gate.

## Run

```bash
flutter run -d macos      # or: -d linux
```

CI builds the Linux desktop target; local development is typically on macOS.

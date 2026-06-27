# Transport & Security

The device is the trust authority. Every server connection rests on three pinned
secrets — the SSH host key, the TLS certificate, and a short-lived control token
— plus the device's own SSH identity. This page is the reference for those
invariants; treat them as load-bearing.

## Trust establishment (add-server)

When a server is added:

1. The app SSHes to `_bootstrap@host` (host key **TOFU** on first contact) and
   runs the mint command. The returned bundle carries the control token, the TLS
   certificate pin, and the HTTPS port.
2. Both fingerprints — the SSH host key and the TLS cert — are shown to the user
   for confirmation, then **pinned and persisted**.

After that, the server record stores `host`, `sshPort`, `apiUrl`,
`tlsCertFingerprint`, and `hostKeyPin`. All later connections run **non-TOFU**:
the pins are required and a mismatch is a hard, fail-closed error.

## SSH host-key pinning

`HostKeyStore` (`lib/ssh/host_key_store.dart`) compares the key dartssh2 reports
against the stored pin, keyed by `host:port`.

- Add-server uses TOFU (`tofu: true`) for first contact, then persists the pin.
- Every later connection uses a store seeded with the stored pin and
  `tofu: false` — an unknown or changed key is rejected.
- The fingerprint format is `SHA256:<base64nopad>` (the `ssh-keygen` form).

## TLS certificate pinning

`PinnedHttpClient` (`lib/net/pinned_http_client.dart`) builds a `SecurityContext`
with `withTrustedRoots: false` and a `badCertificateCallback` that compares
`sha256` of the certificate DER against the stored pin. It is **always checked
and fail-closed**: an empty pin or a mismatch rejects the connection. Hostname
mismatch is intentionally irrelevant — the pin is the sole authority — which is
why connecting by raw IP (e.g. `10.0.2.2` from an emulator) works.

!!! warning "Two fingerprint formats — never cross-compare"
    - **TLS pin:** `sha256:<hex>` (lowercase hex of the cert DER).
    - **SSH host-key pin:** `SHA256:<base64nopad>`.

    They are different encodings of different bytes and live in separate stores.
    `lib/core/fingerprint.dart` documents this; do not unify them.

## Control token lifecycle

`ControlTokenProvider` (`lib/control/control_token_provider.dart`) is an FSM:

- Single-flight mint bound to the transport identity (a host/port/identity change
  drops an in-flight mint rather than handing it to the wrong server).
- Proactive refresh before expiry; reactive `401` invalidate-and-retry-once with
  a *distinct* token.
- The minted bundle's TLS pin must equal the configured pin — no silent re-pin.

The mint runs over the reserved `_bootstrap` SSH user (wire string
`control shed-mobile`).

## Secret handling

- The control token and the SSH private key live only in secure storage
  (Keychain/Keystore on mobile) or 0600 files (desktop) — never in logs.
- `BootstrapService.mint` **never surfaces SSH stdout/stderr on failure** — mint
  output can contain token bytes. `SshRunner` does not log, and on empty or
  unparseable output the mint throws without echoing it.
- `AppError` messages are deliberately generic and carry no token or key material.
- On mobile, only the **public** key half is ever shown, copied, or returned past
  the keygen call (`PublicIdentity`); the private PEM is scoped to the
  store-to-secure-storage call.

## Shell-injection safety

Commands are sent as a single string the remote `bash -lc` re-parses, so every
argv token is POSIX-quoted via `wireCmd`/`shellQuote` (`lib/core/shell_quote.dart`).
Kickoff prompts are delivered over **stdin** (`--prompt-stdin`), never as an argv
token. A malicious shed name, workdir, slug, or prompt cannot break out.

## Key trust

The device's public key must be in the server's SSH allowlist:

=== "GitHub (recommended)"

    Add it under **Settings → SSH and GPG keys**; the server pulls it via
    `auth.ssh.github_users`. Propagation can take up to ~1 hour.

=== "Local (no GitHub)"

    Add it to the shed-server's `auth.ssh.authorized_keys` and restart:

    ```yaml
    auth:
      mode: secure
      ssh:
        github_users: [you]
        authorized_keys:
          - "ssh-ed25519 AAAA… shed-mobile"
    ```

    ```bash
    brew services restart shed   # picks up inline authorized_keys at start
    ```

Both paths were validated end-to-end; the local path is the fast option for
testing (see [Android](../platforms/android.md#local-key-trust)).

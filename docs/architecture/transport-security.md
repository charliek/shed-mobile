# Transport & Security

The device is the trust authority. Every server connection rests on two pinned
values — the SSH host key and the TLS certificate — plus a short-lived
credential the server issues, plus the device's own SSH identity. This page is
the reference for those invariants; treat them as load-bearing.

Since the move to the shared Rust core, **all HTTP/TLS/credential logic lives in
Rust** (`shed-core`, reached over `flutter_rust_bridge`). Dart owns the SSH
transport (dartssh2), storage, and the UI. Where this page names a mechanism, it
names where it actually lives.

## Auth modes

A shed server runs in one of three `auth.mode`s; the client **learns** which,
never configures it.

| Mode | Credential | Client story |
|---|---|---|
| `token` (legacy alias `secure`) | Short-lived bearer token | Minted over SSH; seeded once at add time, re-minted in Rust as it nears expiry. |
| `mtls` | Short-lived **client certificate** | The certificate *is* the credential — no bearer exists. The key is generated in Rust, never persisted, never crosses the bridge. |
| `open` | None | Not used by the mobile add-server flow. |

The mode is decided by the **server at every mint**, so an operator flipping
`auth.mode` needs no client reconfiguration: the next mint moves the Rust
provider to the other shape and the transport is never rebuilt. The learned mode
is written back to `ServerRecord.authMode` by the credential-event listener
(`lib/bridge/credential_sink.dart`), which is what makes a live flip survive an
app restart. A stored mode is only ever a **hint** on the next launch: it decides
whether a stored seed token is worth planting. Decoding is deliberately tolerant —
missing, empty, `secure`, and any unrecognized value all read as `token`
(`normalizeAuthMode`, matching `shed_core::token::AuthMode::from_wire`); there is
no schema-version field on the record, tolerance *is* the migration.

## Trust establishment (add-server)

When a server is added:

1. Dart calls the Rust preview op (`previewAddServer`). Rust generates an
   ephemeral keypair and emits a mint request carrying its CSR; Dart runs
   `ssh _bootstrap@host control shed-mobile csr=<base64>` (host key **TOFU** on
   first contact) and submits the raw stdout back. Rust parses the bundle and
   returns a sanitized DTO: the auth mode, the TLS pin, the HTTPS port, and — in
   token mode only — the seed token and its expiry.
2. Both fingerprints — the SSH host key and the TLS cert — are shown to the user
   for confirmation, then **pinned and persisted**.

Rust owns the request *data* because an `auth.mode: mtls` server rejects a
CSR-less bootstrap *before* returning any JSON, so the side that supplies the
request has to be the side that can generate a keypair. Concretely: Rust
generates the keypair and CSR and hands back the `csr=<base64>` argument, while
Dart composes the final `_bootstrap` command line from it
(`BootstrapService.requestLine`) and puts it on the SSH channel. In mtls mode the certificate the
preview receives is **discarded** with its key — the user has not confirmed the
server yet, and the first real client mints its own. That costs two SSH
round-trips per mtls add, accepted deliberately.

After that, the server record stores `host`, `sshPort`, `apiUrl`,
`tlsCertFingerprint`, `hostKeyPin`, `authMode`, and (token mode only) the seed
token. All later connections run **non-TOFU**: the pins are required and a
mismatch is a hard, fail-closed error.

## SSH host-key pinning

`HostKeyStore` (`lib/ssh/host_key_store.dart`) compares the key dartssh2 reports
against the stored pin, keyed by `host:port`.

- Add-server uses TOFU (`tofu: true`) for first contact, then persists the pin.
- Every later connection uses a store seeded with the stored pin and
  `tofu: false` — an unknown or changed key is rejected.
- The fingerprint format is `SHA256:<base64nopad>` (the `ssh-keygen` form).

## TLS certificate pinning

TLS is **Rust-side** (`shed-core`'s rustls transport, reached through
`BridgeClient.connect`, which takes the stored `sha256:<hex>` pin). The leaf's
DER digest is compared against that pin; verification is **always on and
fail-closed** — an empty pin or a mismatch rejects the connection. Hostname
mismatch is intentionally irrelevant — the pin is the sole authority — which is
why connecting by raw IP (e.g. `10.0.2.2` from an emulator) works. There is no
Dart `SecurityContext` / `badCertificateCallback` path any more, and none should
be reintroduced: session resumption on a second TLS stack would defeat
certificate rotation and revocation.

In mtls mode the same transport also presents a **client** certificate, resolved
dynamically per handshake. The resolver is installed unconditionally, in every
mode, so a `token` ⇄ `mtls` flip is a pure credential-state change and never
rebuilds the client.

!!! warning "Two fingerprint formats — never cross-compare"
    - **TLS pin:** `sha256:<hex>` (lowercase hex of the cert DER).
    - **SSH host-key pin:** `SHA256:<base64nopad>`.

    They are different encodings of different bytes and live in separate stores.
    `lib/core/fingerprint.dart` documents this; do not unify them.

## Credential lifecycle

`shed_core::token::ControlTokenProvider` (Rust) is the FSM:

- Single-flight mint bound to the transport identity (a host/port/identity change
  drops an in-flight mint rather than handing it to the wrong server).
- Proactive refresh before expiry; reactive `401` invalidate-and-retry-once with
  a *distinct* credential.
- The minted bundle's TLS pin must equal the configured pin — no silent re-pin.
- In mtls mode it generates a fresh keypair per mint attempt (key lifetime ==
  certificate lifetime) and verifies that the issued certificate belongs to the
  key it just made.

The mint itself is **inverted** across the bridge, because only Dart has the SSH
transport: Rust emits a `BridgeMintRequest`, the app-scoped listener
(`lib/bridge/mint_sink.dart`) runs the `_bootstrap` round-trip, and the RAW
stdout goes back to Rust, which parses it. Both listeners — the mint sink and the
credential-event sink — are registered in `main()` **before any client is built**;
a mint emitted with no listener fails fast, and a credential event with no
listener is dropped.

The request grammar is `<scope> [<kind>] [csr=<std base64 DER>]`. The
`control shed-mobile` prefix is Dart's; anything after it comes from Rust and is
appended **verbatim** — see [Shell-injection safety](#shell-injection-safety).

## Key containment

- The control-scope private key is generated inside the Rust provider, held for
  the process lifetime, and **never persisted, never logged, and never crossing
  the bridge**. No FRB DTO has a field that could carry one.
- The only sanctioned crossings are the **CSR** (Rust → Dart, a public artifact)
  and the **raw bootstrap stdout** (Dart → Rust, which includes the issued public
  certificate).
- A cold launch therefore re-mints in mtls mode. That is the cost of not
  persisting key material, and it is why the app has an explicit "enrolling
  certificate" state (see below) rather than a longer silent spinner.
- "Dropped" is not "zeroized" — zeroization is out of scope.

## Enrollment latency

An mtls host's first authenticated call of a session is blocked on a whole
`_bootstrap` SSH round-trip. Three bounds are stacked, deliberately ordered so
the innermost one is what actually fires:

| Bound | Value | Where |
|---|---|---|
| SSH mint round-trip | 15 s | `BootstrapService.timeout` |
| Add-server preview | 20 s | `kAddServerPreviewTimeout` |
| First host overview of a session | 30 s | `providers.dart` |
| Steady-state host overview | 12 s | `providers.dart` |
| Rust background mint | 45 s | `shed-core` (backstop only) |

The host card shows **"Enrolling certificate…"** (key
`host-card-enrolling-<name>`) while an mtls host has no adopted credential yet,
so a healthy-but-enrolling host does not read as a hung one. It clears the moment
Rust announces the adoption, not when the request finishes.

## Secret handling

- The seed control token and the SSH private key live only in secure storage
  (Keychain/Keystore on mobile) or 0600 files (desktop) — never in logs. The
  control-scope *certificate* key is never stored at all (see Key containment).
- A flip to mtls **deletes** the stored seed token: it can authenticate nothing
  against the server any more, so keeping it is pure liability.
- `BootstrapService.mintRaw` **never surfaces SSH stdout/stderr on failure** —
  mint output can contain credential bytes. `SshRunner` does not log, and on
  empty output the mint throws without echoing it. The mint listener reports a
  fixed `MINT_FAILED` code back to Rust, never exception detail.
- `AppError` messages are deliberately generic and carry no token or key material.
- On mobile, only the **public** key half is ever shown, copied, or returned past
  the keygen call (`PublicIdentity`); the private PEM is scoped to the
  store-to-secure-storage call.

## Shell-injection safety

Commands are sent as a single string the remote `bash -lc` re-parses, so every
argv token is POSIX-quoted via `wireCmd`/`shellQuote` (`lib/core/shell_quote.dart`).
Kickoff prompts are delivered over **stdin** (`--prompt-stdin`), never as an argv
token. A malicious shed name, workdir, slug, or prompt cannot break out.

!!! warning "The `_bootstrap` channel is the one exception — and must stay that way"
    shed-server reads the `_bootstrap` request with `sess.RawCommand()` and
    splits it on whitespace. **There is no shell on that path.** Standard base64
    contains `+`, `/` and `=`, none of which `shellQuote` treats as bare-safe, so
    routing a `csr=…` argument through `wireCmd` would send `'csr=…'` *with* the
    quotes, the server's `csr=` prefix match would miss, and an mtls server would
    answer "this server requires auth.mode: mtls; upgrade shed".

    So `BootstrapService.requestLine` **composes** that line: the quoted
    `control shed-mobile` prefix plus Rust's extra args appended verbatim. Nothing
    user-supplied reaches it (the only extra arg is a CSR the Rust provider just
    generated), and it rejects any argument containing whitespace so it cannot be
    split into two. `test/ssh/bootstrap_service_test.dart` asserts the exact wire
    string.

## Key trust

The device's public key must be in the server's SSH allowlist:

=== "GitHub (recommended)"

    Add it under **Settings → SSH and GPG keys**; the server pulls it via
    `auth.ssh.github_users`. Propagation can take up to ~1 hour.

=== "Local (no GitHub)"

    Add it to the shed-server's `auth.ssh.authorized_keys` and restart:

    ```yaml
    auth:
      mode: token   # or mtls; `secure` is the permanent legacy alias for token
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

# Quick Start

## Prerequisites

| Requirement | Notes |
|---|---|
| Flutter 3.44.2 (Dart 3.12) | Pinned; matches CI. |
| A reachable shed server | shed v0.7+, `auth.mode: secure`, `auth.ssh.mode: enforce`. |
| A trusted SSH key | Desktop reuses `~/.ssh/id_ed25519`; mobile generates one in-app (see [Android](../platforms/android.md)). |

The device's public key must be trusted by the server — via GitHub
(`auth.ssh.github_users`) or a local `auth.ssh.authorized_keys` entry. See
[Transport & Security](../architecture/transport-security.md#key-trust).

## Run (desktop)

```bash
flutter pub get
flutter run -d macos      # or: -d linux
```

On desktop the app reuses `~/.ssh/id_ed25519` (must be **unencrypted**), so it
goes straight to the server list.

## Add a server

1. Tap **Add server**, enter the host (a Tailscale name or a `100.x` IP) and SSH
   port (default `2222`), then **Connect & verify**.
2. The app SSHes to `_bootstrap@host` to mint a control token and learns the
   server's TLS pin and HTTPS port. It shows the **SSH host-key** and **TLS
   certificate** fingerprints.
3. Verify both fingerprints, then **Trust & add**. They are pinned and persisted.

From there: browse sheds, open one to manage [RC sessions](../features/rc-sessions.md),
and attach the [in-app terminal](../features/terminal.md).

## Verify the transport (no UI)

Real-shed probes, handy for confirming connectivity or debugging the transport
layer (not run in CI):

```bash
dart run tool/e2e_list.dart   # mint -> pin -> list sheds
dart run tool/e2e_rc.dart     # shed-ext-rc create/list/kill
dart run tool/e2e_pty.dart    # attach a PTY, echo round-trip, resize, detach
```

Each defaults to `shed-mobile-test@localhost:2222`; pass `user@host:port` to
target another shed.

# shed-mobile

A native Flutter fat-client for [shed](https://github.com/charliek/shed) servers.
The device talks **directly** to shed servers over Tailscale — there is no
orchestrator process to run. Targets: macOS + Linux desktop first, then Android.

- Pinned-TLS HTTPS to each shed's control API (self-signed cert, sha256 leaf pin)
- SSH (dartssh2) for control-token mint (`_bootstrap`), RC lifecycle
  (`shed-ext-rc`), and an in-app terminal (`tmux attach`)
- One per-device ed25519 key (generate in-app or reuse `~/.ssh`), trusted via
  GitHub (`auth.ssh.github_users`)

See [`docs/PLAN.md`](docs/PLAN.md) for the architecture + milestone plan and
[`PROGRESS.md`](PROGRESS.md) for live build status.

## Develop

```bash
make check          # pub get + format check + analyze + test (the CI gate)
flutter run -d macos
```

Requires Flutter 3.44.2 (Dart 3.12). Private, sideload-only — not for any app store.

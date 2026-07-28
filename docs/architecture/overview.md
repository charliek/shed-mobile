# Architecture Overview

shed-mobile is a **fat client**: the device does everything the
`shed-remote-agent` orchestrator used to do. There is no server process to run —
the app SSHes to each shed server itself, mints its own control tokens, and calls
the control API over pinned TLS.

## Layers

| Layer | Directory | Responsibility |
|---|---|---|
| UI | `lib/features/` | Riverpod-driven screens (servers, sheds, RC, terminal, onboarding). |
| Providers | `lib/providers.dart` | Wires stores, clients, and per-target services. |
| Shed API + credentials | `rust/src/api/` | The Rust core (`shed-core`) over `flutter_rust_bridge`: pinned-TLS HTTP, create-SSE, and the credential FSM (token **and** mtls). |
| Bridge listeners | `lib/bridge/` | App-scoped `MintSink` (runs the SSH mint Rust asks for) + `CredentialSink` (persists the learned auth mode). |
| Shed API glue | `lib/shed/` | Formatting + adapters over the bridge DTOs. |
| RC | `lib/rc/` | `RcService` + DTOs — drives `shed-ext-rc` over SSH. |
| SSH | `lib/ssh/` | Connection primitive, one-shot exec, bootstrap mint, PTY, host-key store. |
| Keys | `lib/keys/` | Key import (desktop) and in-app keygen + identity store (mobile). |
| Storage | `lib/storage/` | `SecretStore` — secure storage (mobile) / 0600 files (desktop). |
| Core | `lib/core/` | Pure ports: POSIX quoting, fingerprints, SSE parser, `AppError`. |

## Request flow

A shed API call (e.g. *list sheds*):

1. `BridgeClient` asks the Rust `ControlTokenProvider` for a valid credential —
   a bearer token, or a client certificate in `auth.mode: mtls`.
2. If none is cached/valid, the provider **mints** one: it emits a request that
   Dart answers by running the `_bootstrap` SSH round-trip (host-key pinned),
   and Rust parses the returned bundle. The credential shape is the SERVER's
   choice, learned at every mint.
3. The Rust transport issues the HTTPS request, verifying the server cert against
   the stored pin (hostname is irrelevant — the pin is authoritative) and
   presenting the client certificate when one is held.
4. A `401` invalidates the credential and retries once with a freshly minted,
   distinct one.

An RC or terminal action instead SSHes as `<shed>@host` (the shed name is the SSH
username) and runs `shed-ext-rc …` or `tmux attach …`.

## Shared SSH primitive

All SSH paths funnel through `withSshClient` (`lib/ssh/ssh_connection.dart`),
which owns connect → host-key verify → auth → teardown. Three consumers build on
it: the one-shot `SshRunner` (RC + mint), the bootstrap mint, and the long-lived
`PtySession` (terminal). Transport failures are mapped to `AppError` by the
shared `classifySshException`.

## Riverpod model

Providers are hand-written (no codegen), matching the tapper conventions.
Per-target providers are `autoDispose.family`, keyed by a named record:

- `shedClientProvider(serverName)` / `shedsProvider(serverName)`
- `rcServiceProvider(ShedRef)` / `rcSessionsProvider(ShedRef)` where
  `ShedRef = ({String serverName, String shedName})`

The terminal owns its live `PtySession` directly in widget state (built via the
`buildPtySession` factory) rather than through a provider, because a long-lived,
imperatively-driven connection is not cacheable async data.

See [Transport & Security](transport-security.md) for the trust model and the
[Implementation Plan](../PLAN.md) for the full design and milestone breakdown.

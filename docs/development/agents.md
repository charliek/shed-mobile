# For AI Agents

This page orients an agent picking up shed-mobile. Read it, then
[`PROGRESS.md`](https://github.com/charliek/shed-mobile/blob/main/PROGRESS.md)
(the live source of truth) and the [Implementation Plan](../PLAN.md).

## Orientation

shed-mobile is a Flutter **fat client** for shed servers — see
[Architecture Overview](../architecture/overview.md). It ports the
`shed-remote-agent` orchestrator's transport logic into Dart; when in doubt about
intended behavior, the TypeScript original is the reference.

Reference repos (siblings on disk):

| Repo | Use |
|---|---|
| `shed-remote-agent` | Source of truth for transport logic (`controlToken.ts`, `shedClient.ts`, `rc.ts`, `shedRc.ts`, `ssh.ts`, `rcAttach.ts`, `sse.ts`) and their tests as golden tables. |
| `shed` | Server (Go): SSH gateway, `auth.ssh`, control API. |
| `shed-extensions` | `shed-ext-rc` guest binary + the RC Session Convention + the golden DTO fixture. |
| `tapper` | The drive-skill and Android-signing patterns were cloned from here. |

## Code map

| Area | Path |
|---|---|
| Pure ports | `lib/core/` (shell quoting, fingerprints, SSE parser, `AppError`) |
| SSH | `lib/ssh/` (`ssh_connection` primitive, `ssh_runner`, `bootstrap_service`, `pty_session`, `host_key_store`) |
| Control token | `lib/control/` (`control_token_provider`, `token_bundle`) |
| Shed API | `lib/shed/` (`shed_client`, `shed_dtos`) |
| RC | `lib/rc/` (`rc_service`, `rc_models`) |
| Keys / identity | `lib/keys/` (`key_manager`, `identity_store`) |
| Storage | `lib/storage/secret_store.dart` |
| Net | `lib/net/pinned_http_client.dart` |
| Providers | `lib/providers.dart` |
| UI | `lib/features/{servers,sheds,rc,terminal,onboarding}/` |
| Drive instrumentation | `lib/marionette/` |
| Real-shed probes | `tool/e2e_*.dart` |

## Per-phase loop

The project is built one phase per commit. Each phase:

1. **Implement** — working code; new pure logic gets unit tests first.
2. **Gate 1** — `make check` (format + analyze + test) green.
3. **Gate 1.5** (UI phases) — drive-smoke via the `drive-shed-mobile` skill;
   verify effects via `MSTATE`/`MRESULT` + a screenshot.
4. **Gate 2** — `/simplify` on the diff (4 reuse/simplify/efficiency/altitude
   agents); apply fixes.
5. **Gate 3** — `/codex:rescue` on the diff (correctness/security); apply fixes.
6. **Commit** — Conventional Commit, **no PR**, push to `main`; confirm CI green.

Docs/config-only phases skip Gates 2–3 (no logic to review).

## Conventions

- **Verify the model against a real shed before building UI.** The transport was
  proven with `ssh-keygen`, `_bootstrap` mint, and `shed-ext-rc` probes before any
  Dart was written; keep this discipline.
- **Drivability is part of the change.** Every control gets a stable `ValueKey`;
  state the widget tree can't show gets `logDriveState`/`logDriveResult`. Both are
  `kDebugMode`-gated.
- Riverpod is hand-written (no codegen). Per-target providers are
  `autoDispose.family`; a one-shot `ref.read` of an autoDispose family disposes its
  `Ref` mid-flight — read the stable providers directly instead (see
  `buildPtySession`).
- Commit trailers: `Co-Authored-By: Claude …` and `Claude-Session: …`.

## Security invariants (do not regress)

These are covered in [Transport & Security](../architecture/transport-security.md);
the short list:

- TLS pinning is always-checked and fail-closed; host keys are pinned non-TOFU
  after add. The two fingerprint formats (`sha256:<hex>` TLS vs
  `SHA256:<base64>` SSH) are never cross-compared.
- `BootstrapService.mint` never surfaces SSH stdout/stderr on failure (token
  bytes); secrets live only in secure storage / 0600 files, never in logs.
- Only the public key half is shown/copied on mobile.
- Every SSH argv token is POSIX-quoted; prompts go over stdin, not argv.

## Resuming

State lives in git. Read `PROGRESS.md` for the milestone checklist and the per-phase
log (with commit SHAs), then continue the next unchecked item through the loop
above. The `docs/PLAN.md` design and the §13 corrections capture the rationale
behind non-obvious choices.

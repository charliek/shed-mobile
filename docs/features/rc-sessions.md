# RC Sessions

Remote-control (RC) sessions are `rc-<slug>` tmux sessions running inside a shed,
following the cross-tool **RC Session Convention v2**. shed-mobile manages them by
invoking the `shed-ext-rc` guest binary over SSH (as `<shed>@host`), a port of the
orchestrator's `shedRc.ts`.

## Kinds

| Kind | Wire value | Runs |
|---|---|---|
| Claude RC | `claude-rc` | An interactive `claude` REPL with `/rc` (the create-time default). |
| Claude Broker | `claude-broker` | The `claude remote-control` multiplexer/broker. |
| Shell | `shell` | A plain login bash. |

`claude-rc` and `shell` accept a kickoff line (a prompt / a command);
`claude-broker` does not (its input is the remote URL).

## States

State is **derived by the binary** from the tmux pane and reported in the DTO —
shed-mobile never re-classifies panes. Values: `starting`, `ready`,
`reconnecting`, `needs-trust`, `needs-auth`, `dead`. The shed-detail screen shows
each as a colored chip.

!!! note "No client-side `rc_classify`"
    Because `shed-ext-rc` classifies server-side and returns `state`/`url`, a
    client pane classifier would be dead code. The machine/inline-tmux path that
    would need one is deferred.

## Operations

`RcService` (`lib/rc/rc_service.dart`):

| Op | Command | Notes |
|---|---|---|
| List | `shed-ext-rc list` | `<shed>/<slug>` display fallback applied app-side. |
| Create | `shed-ext-rc create --kind … --wait` | App generates the slug; prompt via stdin (`--prompt-stdin`). |
| Kill | `shed-ext-rc kill --slug …` | Idempotent (binary exits 0 if already gone). |
| Prompt | `shed-ext-rc prompt --slug …` | Text on stdin; optional `--session-id` guard. |

Create runs with `--wait`, so the returned DTO already carries the final state
and (for claude kinds) the `claude.ai` URL.

### Error mapping

The binary's exit codes map to typed `AppError`s, domain codes checked **before**
the missing-binary check:

| Exit | Error | Status |
|---|---|---|
| 3 | `RC_SLUG_TAKEN` | 409 |
| 4 | `RC_NOT_FOUND` | 404 |
| 2 | `RC_BAD_REQUEST` | 400 |
| 127 / "command not found" | `SHED_EXT_RC_MISSING` | 502 |
| other | `RC_FAILED` | 500 |

Non-JSON or wrong-shape stdout (a stale binary) → `RC_FAILED` 502, never a raw
type error.

## UI

The shed-detail screen lists sessions with their state chip and offers, per
session: **open terminal**, **copy URL**, **open URL** in the browser (when
present), and **kill**. The create screen has a kind picker, optional workdir,
optional kickoff prompt, and a "skip permission prompts" toggle
(`--permission-mode bypassPermissions`). Provenance is stamped as
`SHED_RC_CREATED_BY = shed-mobile/<version>`.

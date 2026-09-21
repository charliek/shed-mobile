# Agent sessions

An agent session is a **roost tab** — a pane on the `roost-session` daemon
running on a shed or on a machine. The phone opens one SSH tunnel per origin,
hands the shared Rust core a loopback port, and reads tabs off roost's own IPC.

!!! note "This page used to describe the RC hub"
    Until shed 0.9.0 a shed's sessions were `rc-<slug>` tmux panes driven by the
    `shed-ext-rc` guest binary over SSH, with a server-side activity hub
    enriching `GET /api/overview`. The hub, the guest binary and the enrichment
    were all retired in shed#328 (plan 022, S6). A shed and a machine now read
    the same way; where a session runs is a label, not a different code path.

## Where the rows come from

| Origin | Feed key | SSH login | Host key |
|---|---|---|---|
| Machine | `<name>` | the machine's configured user | TOFU, shared store |
| Shed | `shed:<server>/<shed>` | `<shed>` on the server's sshd | pinned to the saved fingerprint |

Both resolve through `roostDialFor` (`lib/providers.dart`) into one
`MachineFeed`, which owns the SSH connection, the tunnel, and the Rust roost
watcher. `tab.list` is authoritative, so a reconnect is a complete resync and
backgrounding is a stop rather than a stall.

A shed with no `roost-session` is **unreachable, not empty**: the feed keeps its
last-known rows dimmed and shows roost's own reason ("…is reachable but has no
roost session running…"), because "nothing is running here" and "this device's
key is not authorized" have different fixes.

## Kinds

What a target can launch comes from `roostCapabilities()` — **synthesized, not
probed**: roost is a terminal multiplexer with agent adapters, not shed's guest
agent, so there is nothing to ask. The launchable set is `claude-rc`, `codex`,
`opencode`, `cursor`, `gx` and `grok`; `shell` and `claude-broker` have no launch
recipe and are refused by name rather than opening an empty tab.

## States

A row's lifecycle state (`starting`, `ready`, `reconnecting`, `needs-trust`,
`needs-auth`, `dead`) and its live activity dimension are folded by the shared
Rust core out of roost's `agent_lifecycle` and its adapter detail. Lifecycle
trumps activity: a blocking state hides the activity badge *and* the
last-message line.

## Operations

| Op | roost verb | Notes |
|---|---|---|
| List | `tab.list` (pushed) | The watcher publishes whole snapshots; nothing polls. |
| Launch | `tab.open` | Kind + workdir only, and `activate: false` — a launch from a pocket must not yank whoever is sitting at the machine onto a new tab. |
| Close | `tab.close` | Addressed by roost's numeric tab id, never by the slug string. |
| Peek | `tab.dump` | A read-only viewport, polled every 2 s over one held connection. |

`tab.open` titles the tab itself and takes no kickoff prompt and no permission
posture, so the create form offers neither — a field whose contents would be
dropped on the floor is worse than no field at all.

## UI

The shed-detail screen and the cross-host Sessions view render the same card: a
lifecycle badge, a live activity badge, roost's sticky attention dot, the kind
chip, a meta line, and the actions.

* **Transcript** appears only when the ROW carries an agent-lane stamp
  (`agentLane`). The capability block's `feed: "messages"` is a per-**kind**
  ceiling and is allowed to disagree with it — a card that read the ceiling would
  offer a transcript the lane refuses to open.
* **Peek** is gated on `attachKind == "native-remote"` plus a tab id to address.
  That is what every roost row of a KNOWN kind advertises — but not every row:
  roost's `ownership.source` is an open string, so shed maps `manual`, `legacy`
  and any future agent to `RcKind::Other`, and those kinds are absent from
  `roost_capabilities()`' `kind_features`. A row that misses the map reads
  `attachKind(null)`, which is **`none`** — neither Peek nor the xterm attach.
  That is shed's stated policy for `RcKind::Other`: "renders the raw kind with
  no affordances".
* **`>_ open`** (the xterm `tmux attach`) is the `attachKind == "tmux"` arm.
  **Nothing produces it any more** — S6 deleted the last producer, and the
  unknown-kind fallback is `none`, not `tmux`. It is kept because the
  discriminator is the capability rather than the origin, and because removing
  the xterm attach and the Android foreground service is a product decision
  rather than part of the S6 re-base.

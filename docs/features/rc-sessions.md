# Agent sessions

An agent session is a **roost tab** — a pane on the `roost-session` daemon
running on a shed or on a machine — or a **craze session**, listed by the
machine's craze hub (see [Craze sessions](#craze-sessions)). The phone opens one
SSH tunnel per origin for roost and a second one for craze, hands the shared
Rust core a loopback port for each, and reads tabs off roost's own IPC and
sessions off craze's hub.

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

## Craze sessions

craze is the provider abstraction for cursor, grok, gx and native sessions
(plan 025): one hub per machine lists every session there. The feed opens a
second tunnel beside roost's, whose every accepted connection runs
`craze bridge --hub` over the feed's one SSH connection — craze's published
ladder, composed by shed-core and passed verbatim (`crazeRemoteCommand()`) —
and the shared Rust core reads the hub through a craze source on that port.
Both tunnels have the same lifecycle: they live while the feed has listeners,
and die with it. The phone is **not** attach-only: viewing a machine with craze
starts a hub there if none runs, which idles out about a minute after the phone
lets go.

**One row per session.** A craze session's status is craze's (plan 025 D4): with
the craze feed live, a roost tab running a craze TUI is folded into the hub
row it names (the rule is shed's own `shed_app::craze_rows::fold_plan`, called
over the bridge — never re-derived in Dart), and its terminal actions — Peek and
End tab — act on that tab by its id. With the feed down, nothing is folded:
roost's tab stands alone again beside the hub row's last-known, dimmed copy.

A craze row shows the provider and model, what the session is doing (or the head
of its last reply), the asks it is blocked on with the first one's summary, how
many clients are attached, and why it failed to start. Every craze row offers
**Transcript**: the lane opens through the machine's craze source by the row's
hostId, with no forward. It follows that source: when the feed restarts (a roost
install completing does one), an open transcript leaves the retired source at
once and re-opens through its replacement as soon as that one has read the
roster.

**Not installed is quiet; too old says so.** Rust, reading a loopback port, sees
both as a connection that ended before `hello`, so the craze tunnel's stderr
classifies them on the Dart side (`lib/ssh/craze_reach.dart`): the ladder's
`craze: command not found` is not installed and shows nothing; craze v0.0.1's
`unknown flag: --hub` is too old and the machine says "craze on this machine is
too old for shed; update it". A live hub that cannot create (its `hello` lacks
`createOptions` or `sessionCreate`) still lists, and the machine says "update
craze on this machine to create sessions here".

### Creating a craze session

The create screen offers **craze** beside Claude and opencode wherever the
target's craze source is live and its hub can create (a machine with craze and
no roost offers craze alone). Choosing it shows craze's own sheet
(`lib/features/craze/craze_create_sheet.dart`, the desktop's create sheet as
rules — `lib/features/craze/craze_create.dart`): a provider, a directory and an
optional first prompt, nothing else — no model, effort or permission mode
(craze's defaults; a sheet-created session runs `bypass`, which its transcript
header says).

| Part | Behaviour |
|---|---|
| Providers | Read from craze (`sessions.createOptions`) every time the sheet opens, in craze's order. A provider that is not `ready` is dimmed with craze's reason and fix and cannot be picked. craze's default is preselected only if it is ready, else the first ready one; with none ready the sheet says so and Create is disabled. |
| Directory | craze's recent directories, one tap each, or a typed path, which must be absolute (craze checks that it exists and says so beside the field). |
| First prompt | Optional, multi-line, sent exactly as typed. A prompt craze refused, or whose answer was lost, is said once the session exists. |
| Request id | Minted per submission and **kept only while its outcome is unknown** (a lost answer): "Try again" then resumes the same request, so a lost answer never makes a second session. Any definite answer — a refusal, a start failure — ends it, because craze would replay that answer under the same id; the next try mints a new one. |
| The form | Held per machine above the screen. No state clears it — loading, a failed options read, craze going offline or turning out too old, a refusal, an unknown outcome. Leaving the screen while a create runs keeps it running (the session simply appears as a row); coming back finds the same form and id. |
| Created | The screen gives way to the session's transcript at once: the feed folds the created row in before the create returns, so the lane finds it before craze's roster has listed it. |

A start failure shows craze's cause verbatim (monospace); craze's
`bad_request` is shown beside the directory.

## Kinds

What a target can launch as a roost tab comes from `roostCapabilities()` —
**synthesized, not probed**: roost is a terminal multiplexer with agent
adapters, not shed's guest agent, so there is nothing to ask. The create form
offers exactly `claude-rc` and `opencode` as roost tabs, plus `craze` where the
target's craze source can create (plan 025 O3; see
[Creating a craze session](#creating-a-craze-session)). A row running any other
kind directly (`codex`, `cursor`, `gx`, `grok`) still shows up and reads as a
plain row when it was launched some other way (the CLI, the desktop app);
`shell` and `claude-broker` have no launch recipe and are refused by name
rather than opening an empty tab.

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

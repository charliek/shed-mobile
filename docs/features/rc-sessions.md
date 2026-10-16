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
and die with it. A craze half that fails to come up (its port will not bind,
its source will not open) leaves roost running, and the feed's next start
retries craze alone. The phone is **not** attach-only: viewing a machine with
craze starts a hub there if none runs, which idles out about a minute after the
phone lets go.

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
| Request id | Minted per submission and **kept only while its outcome is unknown** (a lost answer): "Try again" then resumes the same request, so a lost answer never makes a second session. The sheet keeps that request's provider even if a later open reads it as not ready: craze answers the id with the session the first attempt started, or starts it then. Only an edit makes a new request. Any definite answer — a refusal, a start failure — ends it, because craze would replay that answer under the same id; the next try mints a new one. |
| The form | Held per machine above the screen. No state clears it — loading, a failed options read, craze going offline or turning out too old, a refusal, an unknown outcome. Leaving the screen while a create runs keeps it running (the session simply appears as a row); coming back finds the same form and id. |
| Created | The screen gives way to the session's transcript at once: the feed folds the created row in before the create returns, so the lane finds it before craze's roster has listed it. |

A start failure shows craze's cause verbatim (monospace); craze's
`bad_request` is shown beside the directory.

### A craze session's transcript

The transcript screen is the same one an opencode lane opens, and it takes
everything a session can do from what the lane's stream last said about that
session — its capabilities, its settings and its row — never from a copy taken
when it opened.

| Part | Behaviour |
|---|---|
| Header | The session's title and its permission posture, from the live session row: a session the create sheet started runs `bypass`, and says "runs tools without asking". |
| Stop | Offered only when the session's capabilities say `stop` (a session hosted by a craze TUI has none), and never in one tap: it asks "Stop this session? The agent ends; the transcript stays." first — and if the session ended, or stopped offering Stop, while it was asking, the answer is moot and nothing is sent. It ends the SESSION — craze's `session.stop` — and the lane ends with it, its transcript kept; the row leaves. A refusal is said under the header. |
| Cancel | Offered only when the capabilities say `cancel`, and only while a turn is running. |
| Interject | Offered only when the capabilities say `interject`, and live only while a turn is running. |
| Reconnecting | The lane's own connection dropped and craze is resuming it from where it was: the banner says "reconnecting…", the transcript stays on screen, and when the resume lands the banner goes — the same transcript, nothing re-read. |
| Ended | The banner says why the lane ended. A session that is gone (`unknown_session`), was stopped (`session_closed`) or never started (`start_failed: <cause>`) is never re-opened, and the banner is all the screen says: the composer is off and nothing adds "given up on". Any other end is re-opened on a backoff ("Reconnecting…"). |
| A stopped session's last rows | craze 0.2.0 drops a stopping session from its list at once, ahead of the session's last events. So when a craze session's row leaves while its transcript is open and live, the transcript keeps its own connection for a 10-second grace: the closing rows still arrive, and the stop's `session_closed` ends it as above. A row listed again in that time changes nothing. While the grace runs, an end that is not final and a restart of the machine's craze connection re-open nothing; the grace decides. If it runs out with no end, the transcript reads once more and is given up on: "This lane has been given up on — its row or session is gone." A lane given up on an error says "This lane has been given up on: <error>". An opencode row that leaves gives its lane up at once, as before. |
| A lost answer | A send whose answer was lost — the connection dropped while it was in flight — may or may not have started a turn and is never resent: the typed text stays, and the screen says to check the transcript before sending again. |
| Settings | The settings chip and sheet, below. |

### A craze session's settings

A session whose capabilities say `settings` carries a chip under the transcript
header — the current model, effort and fast (`Grok 4.6 · High · fast`; "fast"
only when it is on) — and tapping it opens the session's settings sheet
(`lib/features/lanes/lane_settings_sheet.dart`, the desktop's sheet as rules —
`lib/lanes/lane_settings.dart`). A session that does not offer settings (every
opencode one) has no chip at all: hidden, never disabled, and an open sheet
leaves if the session stops offering them.

| Part | Behaviour |
|---|---|
| Rows | The model (a list, in craze's order: the current one first, then the ones used recently), then the current model's own options (four values or fewer side by side, more as a list), then the mode. A context meter shows when the session reports both its tokens and its window. |
| A change | Applies at once: the row says "applying…" until craze answers, and shows no value of its own meanwhile — what it shows next is the session's. An option is sent bound to the model the sheet shows, so a session that has already moved to another model refuses it rather than applying it there. |
| Live | The sheet is drawn from the session's own settings, so a model change redraws the options as the new model offers them, and a change made elsewhere (another device, an attached TUI) appears in the open sheet. |
| A refusal | Shown on its own row; an option refused because the model changed under it says "the model changed; try again". Trying again is a new change. |
| A lost answer | The connection dropped before craze answered: the change may have run, and it is never resent. The row says "not confirmed" until the session next says what its settings are (when the lane resumes), which replaces the mark with the real value. |
| Closing | The marks belong to the transcript, not the sheet: closing the sheet while a change is in flight loses nothing. |
| Where a model's effort lands | On a native session (craze 0.2.0's per-model effort facts), every model in the list but the current one carries a dim `effort → <level>` under its name: the level a switch to that model lands on — the session's last choice on it, else craze's memory of that model, else its default. A native model switch moves the effort with the model, so this says where to before the press. The current model shows none (its effort row does), and an ACP session (cursor, grok) states no facts, so its models show none. |

**Which option is the effort** is not the phone's call: the shared core reads
it (craze's own `EffortOption` rule) and the lane's snapshot names it, and the
chip shows that option's value — the same reading the `/effort` command is
judged by. A model whose options name none has no effort in its chip.

### A craze session's `/` menu

On a session whose capabilities say `slash`, a `/` draft opens a menu above the
composer listing the commands the session can run (an empty draft offers a `/`
button that starts one). What it lists, what a typed command does, and when a
command is refused are the shared core's rules (`shed_app::slash_menu`, reached
over the bridge — the phone decides none of it): a rename, a mode, Stop (behind
its confirm), `/model` (the settings sheet), and the agent's own commands sent
as prompts. A command that waits for the turn is dimmed while one runs, and
refused "runs after this turn".

| `/effort` | Behaviour |
|---|---|
| Shown | craze 0.2.0's builtin `/effort`, only while the session's current model has an effort option. A model switch is a settings change alone, the session's commands unchanged, and the row follows it: gone on a model with no effort (typed, it is refused "the current model has no effort setting"), back on one that has. |
| Bare | `/effort` (Enter, or a tap on the row) opens the settings sheet, as `/model` does; the draft clears and nothing is sent. |
| `/effort <level>` | Sets the effort from the composer: one `session.set` of the effort option, bound to the model the menu was resolved on, so a session that has moved to another model refuses it (shown in the composer, as a mode's refusal is). The level matches craze's way: its id exactly, else its id in any case, else its name; `default` is the model's default level, which only a native session's effort facts state. An inline level is **always sent**, even the current one — craze's rule, since a dropped no-op could lose a change made elsewhere at the same moment — where a press on the sheet's current value sends nothing. |
| A level naming nothing | Refused in craze's own words (`no effort bogus: one of low, medium, high, xhigh`), the draft kept. It is judged before the turn: mid-turn, a level naming nothing is refused for that, a valid one "runs after this turn". |

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

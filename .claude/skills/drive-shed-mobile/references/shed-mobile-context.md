# shed-mobile driving context

## Dev identity / test targets
- Desktop reuses `~/.ssh/id_ed25519` (must be **unencrypted**).
- Test sheds: `shed-mobile-test@localhost:2222` (mac-mini), `@mini3:2222` (mini3).
- Quick raw-transport check (no UI): `dart run tool/e2e_list.dart`.

## Screen key map

### Hosts screen (home) — Scaffold key `servers-screen`
The mobile Hosts tab (`ServerListScreen`). Absorbed the old System section: each
host is a merged `HostCard` (status + disk usage). Bottom tabs are `nav-hosts` /
`nav-sheds` / `nav-sessions` — **no `nav-system`**. The desktop Hosts pane
(sidebar `nav-hosts`) renders the same cards.

| Key | What |
|---|---|
| `servers-add` | FAB → AddServerScreen |
| `hosts-empty` | empty-state text (from the shared HostGroups body) |
| `host-card-<name>` | host card (mobile: tap → ShedListScreen) |
| `host-card-error-<name>` | host card when the host is unreachable |
| `server-remove-<name>` | remove host (mobile card) |
| `desktop-server-remove-<name>` | remove host (desktop pane card) |

MSTATE: `screen=hosts hosts=N`; per card `host-card host=<name> reachable=t|f|-
df=ok|error|loading sheds=N`; shell `layout=mobile|desktop section=hosts`.
MRESULT: `server-remove ok`.

### AddServerScreen — `add-server-screen`
| Key | What |
|---|---|
| `addserver-host` | host field (Tailscale name / 100.x IP) |
| `addserver-port` | SSH port (default 2222) |
| `addserver-connect` | mint + fetch fingerprints |
| `addserver-name` | display name (appears after connect) |
| `addserver-confirm` | trust fingerprints + persist |
| `addserver-error` | error text |

MSTATE: `screen=add-server step=input|confirm`. MRESULT: `add-server ok|error`,
`add-server-connect error=…`.

### ShedListScreen — `sheds-screen`
| Key | What |
|---|---|
| `sheds-refresh` | refetch |
| `sheds-create` | FAB → CreateShedScreen |
| `sheds-empty` / `sheds-error` | states |
| `shed-<name>` | shed tile |
| `shed-start-<name>` / `shed-stop-<name>` / `shed-delete-<name>` | actions |
| `shed-delete-confirm` | confirm delete dialog |

MSTATE: `screen=sheds server=X count=N`. MRESULT: `shed-start|shed-stop|shed-delete ok|error`.

### ShedDetailScreen (one shed's sessions) — `rc-screen`
Reached by tapping a shed tile. The session list comes from `rcSessionsProvider`
(SSH `shed-ext-rc list`); each row now renders the shared **`SessionCard`** (see
its section below) keyed `all-session-<server>-<shed>-<slug>`, so the per-shed list
gains the watch eye and the claude URL copy/open actions. Each card additionally
reads the host `GET /api/overview` (for the watch capability); an overview
error/404 only hides the eye — it does **not** blank the SSH-backed list.

The old per-shed `_SessionCard` keys are **retired** — use the `all-session-*`
keys instead:

| Retired key | Replaced by |
|---|---|
| `rc-session-<slug>` | `all-session-<server>-<shed>-<slug>` (row identity) |
| `rc-terminal-<slug>` | `all-session-open-<base>` (terminal pill) |
| `rc-copy-<slug>` | `all-session-url-copy-<base>` |
| `rc-open-<slug>` | `all-session-url-open-<base>` |
| `rc-kill-<slug>` | `all-session-delete-<base>` |
| `rc-state-<wire>` | (folded into the card's lifecycle badge — no discrete key) |

| Key | What |
|---|---|
| `rc-refresh` | app-bar refetch (re-list over SSH) |
| `rc-create` | FAB → CreateRcScreen |
| `rc-empty` / `rc-error` | states |

MSTATE: `screen=rc server=X shed=Y count=N`. MRESULT: the shared SessionCard tokens
(`session-delete`, `session-url-copy`, `session-url-open`).

### CreateShedScreen — `create-shed-screen`
| Key | What |
|---|---|
| `create-name` | shed name |
| `create-repo` | `owner/repo` (optional) |
| `create-submit` | start create (disabled until name non-empty) |
| `create-error` | error text |
| `create-log` | streamed progress lines |

MSTATE: `screen=create lines=N done=…`. MRESULT: `shed-create ok|error`.

### Cross-host create (from the Sheds / Sessions tabs)
The top-level Sheds/Sessions views can create without drilling in. Mobile: a FAB
(`allsheds-create` / `allsessions-create`). Desktop: a pane-header button
(`desktop-new-shed` / `desktop-new-session`). Each opens a target picker, then
pushes the existing CreateShedScreen / CreateRcScreen.

| Key | What |
|---|---|
| `allsheds-create` / `allsessions-create` | mobile FAB → picker |
| `desktop-new-shed` / `desktop-new-session` | desktop header button → picker |
| `desktop-add-host-header` | desktop Hosts-pane header → AddServerScreen |
| `pick-host-<name>` | host picker row (New shed; skipped when only one host) |
| `pick-shed-<server>-<shed>` | running-shed picker row (New session) |
| `pick-empty` | "start a shed first" hint (no running sheds) |

MRESULT: `pick-host ok`, `pick-shed ok`.

### CreateRcScreen — `create-rc-screen`
Kind chips are **capability-gated** from the target shed's `rc_capabilities`
(read via the host's single `GET /api/overview`): absent caps → `claude-rc` +
`shell` only; present caps → the shed's installed/advertised creatable kinds
(claude-broker is never offered — it's URL-driven); present-but-empty → no chips.

| Key | What |
|---|---|
| `createrc-kind-<wire>` | a kind chip — `claude-rc` / `codex` / `opencode` / `cursor` / `shell` (only the gated ones render) |
| `createrc-no-kinds` | note shown when the shed offers no creatable kinds |
| `createrc-name` / `createrc-workdir` / `createrc-prompt` | optional fields (prompt only for prompt-accepting kinds) |
| `createrc-permission-mode` | permission dropdown — **claude kinds only** (codex/cursor/opencode default to `auto`, no dropdown). The generic `skip` mode is offered only when the shed's capabilities are present (an old binary rejects it); absent caps → the historical claude set |
| `createrc-submit` | create (disabled while busy or when no kind is offered) |
| `createrc-error` | error text |

MSTATE: `screen=create-rc kind=<wire|-> offered=<csv>`. MRESULT: `rc-create ok|error`.

### Cross-host Sessions view
Reads one `GET /api/overview` per host (server-rc-enriched; no SSH fan-out). A
server too old for `/api/overview` (404) is a hard-require. When the host's
overview `server.features` includes `rc-events`, the view subscribes to
`GET /api/rc/events` (SSE, via `liveActivityProvider`) and patches each card's
activity badge / last-message live — no per-event overview invalidation, one
overview refetch per SSE reconnect. Without `rc-events` it's today's manual
refresh (no polling).

| Key | What |
|---|---|
| `all-sessions-unreachable-<server>` | host unreachable banner (warn) |
| `all-sessions-needs-upgrade-<server>` | old server — "needs upgrade for the sessions view" (err) |

MSTATE: `all-sessions host=<name> reachable=true|false|needs-upgrade count=N live=t|f`
(`live=t` when the `rc-events` SSE subscription is active for that host).

### Session card (shared: cross-host Sessions view AND per-shed `rc-screen`) — `SessionCard`
Base is `<server>-<shed>-<slug>` (e.g. `h-web-abc123`). The **same** card renders on
the cross-host Sessions tab and on the per-shed session list (`ShedDetailScreen`),
so both surfaces expose the identical `all-session-*` keys.

| Key | What |
|---|---|
| `all-session-open-<base>` | "›_ open" pill → in-app terminal (TUI) |
| `all-session-watch-<base>` | "watch" (eye) → CodexWatchScreen; **only** when caps `kind_features[kind].watch` |
| `all-session-url-copy-<base>` | copy the claude.ai URL to the clipboard (MRESULT `session-url-copy ok`); **only** when the session carries a non-empty `url` (claude-rc/claude-broker) |
| `all-session-url-open-<base>` | open that URL in an external browser via the safe-launch helper (http/https only; a rejected/failed launch snackbars "Could not open URL"); MRESULT `session-url-open ok\|error`; same `url`-present gate |
| `all-session-delete-<base>` | delete/kill the session |
| `all-session-activity-<base>` | live activity badge — present only when lifecycle permits (ready-ish) AND activity is `working` (pulsing) / `needs_input` (steady) / `idle` (quiet); absent for `unknown`, and suppressed for needs-*/dead |
| `all-session-lastmsg-<base>` | one-line last-message preview (when the hub reports one; suppressed with the activity badge for needs-*/dead — whole-dimension suppression) |

### Codex watch view — `CodexWatchScreen` (Scaffold `codex-watch-screen`)
The codex-first non-TUI message feed + gated input. Reached from
`all-session-watch-<base>`. Renders `GET …/rc/v1/sessions/{slug}/messages`
(plain Text, no markdown), live-appends on `message.appended`, and posts
`.../input` when gated + waiting. Lifecycle needs-auth/dead or a 503 hands off
to the TUI terminal.

| Key | What |
|---|---|
| `codex-watch-refresh` | app-bar refresh (re-drain the feed) |
| `codex-watch-activity` | app-bar live activity badge (same rules as the card badge) |
| `codex-watch-loading` | initial-load spinner |
| `codex-watch-list` | the message feed ListView |
| `codex-watch-msg-<seq>` | one feed message (per `seq`) |
| `codex-watch-truncated` | "earlier history truncated" divider (first page `truncated:true`) |
| `codex-watch-empty` | "No messages yet" |
| `codex-watch-input` | reply TextField — enabled only when `kind_features.input=="gated"` AND activity `needs_input` AND lifecycle permits |
| `codex-watch-send` | send button (`onPressed: null` when input disabled) |
| `codex-watch-banner` | needs-auth/dead TUI-handoff banner (warn) |
| `codex-watch-open-tui-banner` | one-tap → in-app terminal (the banner's button) |
| `codex-watch-open-tui` | one-tap → in-app terminal (the error/unavailable body's button; distinct from the banner key — both can be on screen together) |
| `codex-watch-unavailable` | "Live view unavailable on this shed" (hub 503 / RC_HUB_UNAVAILABLE) |
| `codex-watch-error` | generic feed-load error text |
| `codex-watch-retry` | retry the feed load |

MSTATE: `screen=codex-watch server=<name> shed=<shed> slug=<slug> state=<wire>
activity=<wire|none> msgs=N truncated=t|f input=enabled|disabled|blocked`.
MRESULT: `codex-watch-input ok|error=…` (a 409 send → snackbar "Session is no
longer waiting for input" + a state refresh); `codex-watch-handoff ok` (opened
the TUI).

### Terminal screen — `TerminalScreen` (Scaffold `terminal-screen`)
The in-app xterm TUI, attached to a shed rc session's tmux pane over pinned SSH.
Reached from `all-session-open-<base>` (the "›_ open" pill) and the codex-watch
TUI handoff. Always dark chrome (the terminal is dark regardless of app theme).

| Key | What |
|---|---|
| `terminal-back` | app-bar back (Detach — leaves the rc session running) |
| `terminal-font-dec` / `terminal-font-inc` | shrink / grow the text (8–28pt) |
| `terminal-paste` | paste the clipboard into the PTY (bracketed-paste aware) |
| `terminal-copy` | copy the current xterm selection (MRESULT `terminal-copy ok`); `onPressed:null` (disabled) when there's no selection; the copied text is **never** logged (a login URL carries an auth token) |
| `terminal-reconnect` | re-attach after the session ended/errored (only shown then) |
| `terminal-connecting` / `terminal-error` / `terminal-ended` | connect spinner / connect-error text / "session ended (exit N)" banner |
| `terminal-view` | the xterm `TerminalView` |
| `term-key-ctrl`, `term-key-<id>` | the virtual-key toolbar (sticky-Ctrl + esc/tab/arrows/^C/…), hidden once the session ends |
| `terminal-url-banner` | dismissible "Link detected" banner above the view — auto-detected login/any http(s) URL in the output (ANSI/OSC-stripped, bounded rolling tail, de-duped, hidden once the session ends). Shown only while the session is live |
| `terminal-url-copy` | copy the detected URL to the clipboard (MRESULT `terminal-url-copy ok`; snackbar "Copied") |
| `terminal-url-open` | open it in an external browser via the safe-launch helper (http/https only; a rejected/failed launch snackbars "Could not open URL"); MRESULT `terminal-url-open ok\|error` |
| `terminal-url-dismiss` | X → hide the banner; a redraw re-emitting the SAME URL won't re-surface it (a reconnect clears the memory) |

MSTATE: `screen=terminal slug=<slug> state=ready|exited keyboardVisible=t|f
inset=N font=N` (`state=ready` while live, `state=exited` after the pane closes);
`terminal-url detected=t` when a URL banner is raised — the **URL itself is never
logged**. MRESULT: `terminal-connect ok|error=…`, `terminal-copy ok`,
`terminal-url-copy ok`, `terminal-url-open ok|error`.

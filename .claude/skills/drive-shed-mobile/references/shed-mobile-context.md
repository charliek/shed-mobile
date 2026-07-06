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
| `pick-host-<name>` | host picker row (New shed; skipped when only one host) |
| `pick-shed-<server>-<shed>` | running-shed picker row (New session) |
| `pick-empty` | "start a shed first" hint (no running sheds) |

MRESULT: `pick-host ok`, `pick-shed ok`.

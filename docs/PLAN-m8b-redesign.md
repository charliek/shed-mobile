# PLAN — M8b: redesign iteration (merge Hosts+System · create-from-tab)

Iteration on the shipped M8 responsive shell (PR #2, branch `feat/m8-multished-nav`),
driven by two updated claude.ai/design mockups (`Shed App.dc.html` mobile,
`Shed Desktop.dc.html` desktop, in the claude.ai/design project
`f9ea6c7f-…`) in the same design language as M8. The visual contract for D1–D4 is
inlined below (the generated mock HTML is not vendored into the repo).

## Context

M8 shipped a responsive shell with four sections — **Hosts · Sheds · Sessions ·
System** — mobile bottom-tabs (4) and a desktop sidebar (Sheds/Sessions/System +
a host list). Two usability gaps surfaced in testing, each mocked up in claude
design:

1. **The main nav can't create.** The cross-host **Sheds** and **Sessions** tabs
   are browse-only. Creating requires drilling into a host (Sheds → host → *Create
   shed*) or shed (Sessions → shed → *New session*). Now that the bottom tabs are
   the primary way to browse, the top-level Sheds and Sessions views need a create
   affordance too.

2. **Hosts and System overlap.** Both are per-host lists keyed by host; System just
   adds disk usage. They should be **one** section. The merged **Hosts** view shows
   each host's status *and* its disk usage (images / sheds / snapshots / orphans),
   and keeps a way to add a host — on both mobile and desktop.

Intended outcome: mobile bottom-tabs 4 → **3** (Hosts · Sheds · Sessions); desktop
sidebar nav → **Sheds · Sessions · Hosts**; the Sheds/Sessions views gain create
entry points; no capability is lost (host add/remove, per-host drill-in, per-shed
drill-in all still work).

Non-goals: no change to the drill-in create screens (CreateShedScreen,
CreateRcScreen), the terminal, onboarding, or the SSH/HTTP data layer. This is a
navigation + composition change.

## Design decisions (judgement calls the mocks left open)

- **D1 — Host removal stays; desktop delete is additive.** The mock Hosts cards
  show a chevron, not a delete control. **Mobile** keeps the existing trailing
  delete on the host row (key `server-remove-<name>`, log `server-remove`). **Desktop**
  *adds* a delete icon-button to the Hosts-pane card (new capability — desktop had
  no host-remove before; not a regression to guard, but wired for parity). A host
  card's delete is available in **every** async state (incl. unreachable).
- **D2 — Desktop default section = Hosts; remove `sectionForDesktop`.** With a real
  desktop Hosts pane, the hosts→sheds fold is gone. `appSectionProvider` still
  defaults to `hosts`, so desktop lands on the Hosts overview. Every `_NavItem`
  active-state check uses the section directly. The desktop sidebar keeps **both** a
  `Hosts` nav item (selects the pane) and the bottom host list (`desktop-host-<name>`,
  a non-interactive quick-reference) — intentional; noted so the redundancy reads as
  deliberate.
- **D3 — Create-from-tab = pick target, then reuse the existing create screen.**
  - **New shed** (Sheds tab): pick a **host**. Candidates come from `serversProvider`
    (local, instant) — so a single host **auto-skips** the picker; >1 opens a bottom
    sheet. → `CreateShedScreen(serverName)` unchanged.
  - **New session** (Sessions tab): pick a **running shed**. Candidates require
    `shedsProvider` per host. To avoid a blocking pre-fetch, the sheet **opens
    immediately** and loads each host's running sheds **progressively + tolerantly**
    (one unreachable host never stalls it); there is **no** global auto-skip for
    sessions (resolved R3 in favor of progressive over pre-resolve). → `CreateRcScreen(serverName, shedName)` unchanged.
  - **Zero candidates** is never a silent no-op: the New-session sheet shows "Start a
    shed first" when no running sheds exist; New-shed with zero hosts can't arise from
    a populated tab but the picker returns null + a snackbar defensively.
  - Pickers are fully instrumented: `logDriveResult('pick-host'|'pick-shed', ok:…)` on
    selection **and** on an auto-skip (so a skipped sheet is still drive-observable).
- **D4 — Keep Navigator-route drill-in.** Drill-in (ShedListScreen, ShedDetailScreen,
  create screens, terminal) stays full-screen routes over the shell. We do NOT port
  the mock's single-widget `screen`-state machine.

## Accepted trade-off — landing-screen fan-out (reverses an M8 P6 deferral)

M8 P6 deferred host-tile shed/running badges because per-host counts "force eager
fan-out and defeat the lazy per-section loading" (PROGRESS.md M8 P6). This plan
**intentionally reverses that**: the merged mobile Hosts tab (today `ServerListScreen`,
*purely local* — `serversProvider` only, no network) now shows disk + shed summary,
so it fans out `N × (SSH-mint + GET /api/sheds + GET /api/system/df)` on the default
landing screen. This is the feature the user asked for. It is bounded so it never
regresses the landing experience:

- **Host identity renders immediately** from the local `ServerRecord` (name, URL) —
  no provider await for the row to appear.
- **Disk + shed-summary are per-card progressive async** (each `HostCard` watches its
  own per-host families); there is **never** an all-or-nothing spinner on the Hosts
  screen.
- **Offline degrades per-card, independently** (12s `_hostFanoutTimeout` per host):
  an unreachable host shows "Unreachable" on its own card while others fill in.
- Future optimization (not this PR): a lightweight server overview/count endpoint
  (the same class of server-side gap as shed issue #242) would let this be one call
  per host instead of two.

## Merged Hosts card — combined async state contract (resolves R2)

`HostCard(serverName, mobile)` renders identity synchronously, then composes two
`FutureProvider.autoDispose.family` values with a defined precedence:

- **Reachability gate = `shedsProvider(serverName)`** (the primary HTTP call):
  - loading → neutral dot, summary "Loading…"
  - error → **warn** dot, summary "Unreachable"
  - data → **ok** dot, summary "N sheds · M running"
- **Disk (best-effort) = `hostSystemDfProvider(serverName)`**:
  - loading → disk area shows a small spinner
  - error → "unavailable" (host may still be reachable — the old-agent case)
  - data → Images/Sheds/Snapshots/Orphans + bold total (via `DiskUsageBlock`)
- **Runtime badge**: from `df.backend` when df=data; else fall back to the first shed's
  `backend` from `shedsProvider` data; else no badge (`RuntimeBadge` already no-ops on
  null).
- **Delete** (D1): present in **every** state.
- **Drive log**: `logDriveState('host-card host=<name> reachable=<t|f> df=<ok|error|loading> sheds=<n>')`.
- **Keys**: `host-card-<name>`, `host-card-error-<name>` (unreachable), delete keeps
  the existing `server-remove-<name>` (mobile) / adds `desktop-server-remove-<name>`.

## Approach — two gated phases

Each phase runs the established per-phase loop: implement → unit/widget tests →
`make check` → drive-verify (macOS + Pixel-8 emulator) → `/simplify` →
`/codex:rescue` → commit on `feat/m8-multished-nav` (updates PR #2). **Phase 1 ships
the 4→3 nav before Phase 2 adds create-from-tab; during that window the drill-in
create paths still work — documented in PROGRESS so the temporary top-level gap reads
as intentional.**

### Phase 1 — Merge Hosts + System into one Hosts section

**Model / nav**
- `lib/app/app_section.dart`: `AppSection` → `{ hosts, sheds, sessions }` (drop
  `system`); remove `sectionForDesktop`; keep `isDesktopWidth`/`kDesktopBreakpoint`;
  update the doc comment.
- `lib/providers.dart`: update `appSectionProvider` doc (drop the hosts→sheds note);
  update the `hostSystemDfProvider` doc (no longer "for the System view").

**Extraction + merged card**
- `lib/widgets/disk_usage_block.dart` — extract the Images/Sheds/Snapshots/Orphans
  row (+ optional bold total) from `SystemCard`. `formatBytes` stays in `shed_dtos.dart`
  (no move needed).
- `lib/features/hosts/host_card.dart` — `HostCard` per the state contract above
  (mobile: tappable → `ShedListScreen(serverName)` + chevron + trailing delete;
  desktop: not tappable + delete icon-button).
- `lib/features/hosts/hosts_view.dart` — `HostsView` = `HostGroups(section: 'hosts',
  header: false, onRefresh: invalidate serversProvider + shedsProvider +
  hostSystemDfProvider, hostBuilder: HostCard(mobile:false))`. Used by the **desktop**
  Hosts pane.

**Mobile scaffold** (`lib/app/mobile_scaffold.dart`)
- Bottom tab bar → three tabs: Hosts / Sheds / Sessions (drop System). Keep
  `nav-<section>` keys. Hosts tab body = the **refactored `ServerListScreen`**.

**Mobile Hosts screen** — refactor `ServerListScreen` **in place** (preserve git
history + keys):
- Keep the brand app bar (owl + "Shed" + count chip + `servers-theme-toggle` +
  `servers-identity`), the `servers-add` FAB, and `servers.when` with the
  `servers-empty` empty state and `servers-screen` scaffold key, and the
  `MSTATE screen=servers count=N` line. (This keeps `test/widget_test.dart`,
  `SKILL.md`, `launch-and-connect.sh`, `testing.md` green unchanged.)
- Replace the `_ServerTile` list with a `ListView` of `HostCard(mobile:true)` (each
  card is its own ConsumerWidget → independent per-host loading; no HostGroups needed
  here so the `servers-empty` key is retained at the screen level). Count chip copy →
  "N hosts".

**Desktop scaffold** (`lib/app/desktop_scaffold.dart`)
- Sidebar nav → Sheds / Sessions / **Hosts** (`Icons.dns_outlined`); drop System.
  Keep the sidebar host list + `desktop-add-host`. Use `appSectionProvider` directly.
- `_MainPane`: `hosts → ('Hosts', HostsView)`, `sessions → AllSessionsView`, default
  `→ AllShedsView`. Remove the System pane. Header keeps the theme toggle (P2 adds
  create buttons).

**Delete**
- Remove `lib/features/system/system_view.dart`. `system_card.dart` is removed after
  its disk row moves to `DiskUsageBlock` (the header/total/badge logic folds into
  `HostCard`).

### Phase 2 — Create sheds & sessions from the cross-host tabs

- `lib/widgets/target_picker.dart`:
  - `pickHost(context, ref) → Future<String?>` — hosts from `serversProvider`
    (local). One host → return it (no sheet, `logDriveResult('pick-host', ok:true)`);
    >1 → bottom sheet of lightweight `ListTile`-style rows (`StatusDot` + mono name),
    keys `pick-host-<name>`; cancel → null.
  - `pickShed(context, ref) → Future<(String,String)?>` — bottom sheet opens
    immediately; per host, load `shedsProvider` progressively + tolerantly, list only
    running sheds grouped by host, keys `pick-shed-<server>-<shed>`; zero running →
    "Start a shed first" note; cancel → null. No global auto-skip.
- `_Section` (mobile) gains an optional `floatingActionButton`; the Sheds/Sessions
  tab bodies pass a `New shed` (`allsheds-create`) / `New session` (`allsessions-create`)
  FAB. New shed → `pickHost` → `CreateShedScreen`; New session → `pickShed` →
  `CreateRcScreen`. On a **non-null** create return, invalidate the relevant family
  (`shedsProvider` / **`hostSessionsProvider`** — load-bearing: `CreateRcScreen` pops
  the session but does not self-invalidate `hostSessionsProvider`).
- `HostGroups` gains FAB-aware bottom padding (a `bottomInset`, default 40, ~96 for
  the Sheds/Sessions FAB tabs) so the last card isn't covered.
- Desktop (`_MainPane` header): accent `New shed` (`desktop-new-shed`) / `New session`
  (`desktop-new-session`) buttons beside the theme toggle for the Sheds/Sessions panes,
  same picker + reuse.

## Files

**Created**
- `lib/features/hosts/host_card.dart`, `lib/features/hosts/hosts_view.dart`
- `lib/widgets/disk_usage_block.dart` *(P1)* · `lib/widgets/target_picker.dart` *(P2)*
- `test/features/hosts/host_card_test.dart` — disk-ok / df-error / **sheds-error
  (unreachable) with delete still present** / summary / drill-in push (mobile) /
  desktop delete-button variant.
- `test/widgets/disk_usage_block_test.dart` — the extracted 4-column + total.
- `test/widgets/target_picker_test.dart` — single-host skip; multi-host sheet;
  running-only + grouped; **one host errors, others still contribute**; zero-running
  message; cancel → null.
- `test/app/mobile_tabs_test.dart` — 3 tabs present, `nav-system` absent.
- `test/app/desktop_nav_test.dart` — sidebar shows `nav-sheds/nav-sessions/nav-hosts`,
  `nav-system` absent, `desktop-host-<name>` rows present.

**Modified**
- `lib/app/app_section.dart`, `lib/app/mobile_scaffold.dart`,
  `lib/app/desktop_scaffold.dart`, `lib/providers.dart`
- `lib/features/servers/server_list_screen.dart` (refactor in place)
- `lib/features/system/system_card.dart` → extracted, then removed
- `lib/widgets/host_groups.dart` (bottom-inset param, P2)
- `test/app/app_section_test.dart` (drop the whole `sectionForDesktop` group incl. the
  `AppSection.system` line)
- `test/features/system/system_card_test.dart` → re-point at `DiskUsageBlock`
- `PROGRESS.md`; drive-skill `references/shed-mobile-context.md` (new keys; keep
  `servers-*` + `screen=servers`)
- `test/widget_test.dart` — expected to stay **green unchanged** (keys preserved);
  listed so the reviewer sees it was considered.
- `test/app/app_shell_test.dart` — stays green (asserts only shell keys); desktop now
  lands on the empty Hosts pane instead of the folded Sheds pane.

**Removed**
- `lib/features/system/system_view.dart` (+ `system_card.dart` after extraction)

## Acceptance criteria

- Mobile shows **three** bottom tabs (Hosts, Sheds, Sessions); no System tab.
  `MSTATE layout=mobile section=hosts|sheds|sessions`.
- Mobile **Hosts** tab: host **names/URLs render immediately** (offline too); each
  card fills in disk (Images/Sheds/Snapshots/Orphans + total) + shed summary
  progressively; an **unreachable host shows "Unreachable" on its own card without
  stalling the others**; `Add host` FAB works; tapping a host drills into its sheds;
  a host can still be removed **in every state**.
- Desktop sidebar nav = **Sheds · Sessions · Hosts** (no System); the **Hosts** pane
  shows the same merged cards with a working delete; sidebar host list + `Add` still
  work. `MSTATE layout=desktop section=hosts`.
- Mobile **Sheds** tab `New shed` → (host picker if >1; straight in if 1) →
  CreateShedScreen → new shed visible on return.
- Mobile **Sessions** tab `New session` → shed picker (running sheds only, progressive,
  tolerant); **zero running sheds → "Start a shed first"** (not a silent no-op) →
  CreateRcScreen → new session visible on return.
- Desktop Sheds/Sessions panes have working `New shed` / `New session` header buttons.
- No System-section code remains; disk rendering is shared via `DiskUsageBlock`.
- Per-host drill-in create (`sheds-create`, `rc-create`) unchanged and still works.
- `make check` green (format + analyze + all tests, incl. new ones). Drive passes on
  macOS and the Pixel-8 emulator, including the offline-host and zero-running-shed
  paths.

## Test plan

- **Unit/widget** (`flutter test`): the Created/Modified test files above.
  Emphasis on the combined-state matrix (`host_card_test`: df-ok, df-error+sheds-ok,
  sheds-error+delete-present, sheds-loading), the tolerant/zero-candidate picker cases,
  and `nav-system` absent on both layouts. `app_shell_test` and `widget_test` expected
  green unchanged.
- **`make check`**: `dart format` + `flutter analyze` + `flutter test`.
- **Drive (both targets)** via drive-shed-mobile:
  - macOS: `nav-hosts` → Hosts pane disk cards; `nav-sheds` → `New shed` → picker →
    CreateShedScreen; `nav-sessions` → `New session` → shed picker; theme toggle.
    Screenshot the Hosts pane.
  - Pixel-8 emulator: three tabs; Hosts card disk + drill-in; single-host `New shed`
    goes straight in; `New session` shed picker; **offline host shows Unreachable
    without stalling**; screenshots per tab; confirm `MSTATE`/`MRESULT`.

## Repo conventions

- Riverpod 3 provider families for per-host data; `Notifier` for section state; stable
  `ValueKey`s + `logDriveState`/`logDriveResult` on every new control **including the
  picker sheets** (open/select/none); theme via `context.shed`, `sansStyle`/`monoStyle`,
  cards via `CardShell`. Conventional Commits; per-phase gated loop; commits land on
  `feat/m8-multished-nav` (no separate PR).

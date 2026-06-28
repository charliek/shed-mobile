# shed-mobile — M8: Multi-shed navigation + cross-host views (Sheds / Sessions / System)

> **Panel-reviewed** (Codex + Kimi K2.6 + CodeRabbit, 2026-06-28). Their blockers and
> high-confidence findings are folded in below; see the *Panel resolutions* note at
> the end of each major section.

## Context

shed-mobile (M0–M7) is a working client: transport, host (server) management, shed
CRUD + create-SSE, RC sessions over `shed-ext-rc`, in-app terminal, Android
keygen/FGS, and the M7 design-system retheme (orange `#F2541B`, IBM Plex, owl,
light/dark, `ShedColors` ThemeExtension + `lib/widgets/` atoms).

Today the app is **pure drill-down** with no persistent navigation and no
cross-host aggregation:

```
ServerList (home) ─push→ ShedList (one host) ─push→ ShedDetail/sessions (one shed) ─push→ Terminal
```

Charlie mocked a new direction in two claude.ai/design files — **one app, two
responsive layouts** sharing a design system:

- **`Shed App.dc.html`** — mobile: a **bottom tab bar** (Hosts · Sheds · Sessions ·
  System) over the existing drill-down, plus three new cross-host views.
- **`Shed Desktop.dc.html`** — desktop: a **left sidebar** (owl + wordmark; nav
  Sheds · Sessions · System with count chips; a HOSTS list + Add) and a main pane.

(The third file `Shed Redesign.dc.html` is exploratory and **out of scope**.)

This milestone makes it easy to see sheds and sessions **across all hosts** and adds
a scalable nav shell so future features have a home. The rendered HTML is the source
of truth; the concrete spec is **vendored inline below** (design tokens + the
`stat()`/`agent()` tables) so this plan is reconstructable without the HTML.

### What the server already gives us — verified live (2026-06-28)

The aggregate views need almost no new server work. Probed against the real test
servers (`mac-mini`, `mini3`) with the `shed` CLI:

- **`GET /api/system/df`** → `{ server_name, backend, generated_at, images[],
  sheds[], snapshots[], orphans[], totals{ images, sheds, snapshots, orphans, all
  : { logical_bytes, physical_bytes } }, notes }`. **Confirmed** `totals.all`
  exists. The System cards render **`physical_bytes`** (matches the mock's numbers —
  mac-mini `all.physical_bytes` ≈ 14.5 GB).
- **`GET /api/sessions`** → all rc sessions on a host in one call. Each row:
  `{ name (= "rc-<slug>"), shed_name, server_name, created_at, attached,
  window_count?, rc:{ kind, state, managed, display_name, url?, created_by } }`.
  **Confirmed**: `rc.state` is meaningfully classified server-side (saw
  `starting` and `ready`, `attached:true`) — so the HTTP path's status badges
  agree with the SSH view (resolves the panel's "verify state semantics" ask).
  **Two quirks confirmed live**: (1) `created_at` is frequently the zero value
  `"0001-01-01T00:00:00Z"` → "age" must degrade to nothing; (2) the CLI returns a
  **bare array** but the HTTP API wraps it as `{ sessions:[…], warnings? }` — the
  DTO parse must accept both.
- **`GET /api/sheds`** → `Shed` carries `name, status, backend, image, repo, cpus,
  memory_mb, started_at, extensions, …` (today kept in `Shed.raw`).
- **start/stop** exist; **restart is not atomic** (client does stop→start). **images**
  and **snapshots** endpoints exist.

The shed-desktop reference (Swift/SwiftUI macOS app, `../shed-desktop`) implements the
same three views: `systemDF()` per host, `GET /api/sheds` per host grouped by host,
and — for sessions — SSH probes per shed. We deliberately diverge to HTTP for the
mobile aggregate (Decision 1).

### Conventions (acceptance vocabulary)

- **Drive harness** `drive-shed-mobile`: Marionette drives a **debug** build
  headlessly; tests assert *effects* via `logDriveState(…)`→`MSTATE …` /
  `logDriveResult(name, ok:)`→`MRESULT …` (both `kDebugMode`-gated, tree-shaken from
  release — `lib/marionette/drive_state.dart`). Every control carries a `ValueKey`.
- **Validation tiers**: **(a)** pure unit · **(b)** fake-HTTPS server · **(c)** real
  test shed · **(d)** manual/hardware (Pixel-8 emulator/device).
- **Mirror-the-server** ports as pure, unit-tested functions.
- **Per-phase commit flow** (no PR, feature branch): implement → unit tests →
  `make check` → drive-smoke → `/simplify` on the diff → `/codex:rescue` on the diff
  → commit (Conventional Commit + `Co-Authored-By`/`Claude-Session` trailers).

Test targets: `shed-mobile-test@localhost:2222` (mac-mini) · `…@mini3:2222`.

---

## Current-code touchpoints (what each phase actually edits)

- `lib/main.dart` — `_Home` (onboarding gate) **stays**; its `data:`/non-onboarding
  branch returns `const AppShell()` instead of `ServerListScreen` (Kimi blocker —
  do **not** move the gate into the shell).
- `lib/features/servers/server_list_screen.dart` — a full `Scaffold` owning the
  AppBar (`servers-theme-toggle`, `servers-identity`) + FAB (`servers-add`). Its
  **body** is extracted into a reusable `HostsView`; the three affordances are
  **re-homed into shell chrome in P2** (mobile Hosts header / desktop sidebar+header)
  so none are orphaned (CodeRabbit).
- `lib/features/sheds/shed_list_screen.dart:25` — `toneFor(String)` (no `err` case)
  → **refactored onto** the new shared `shed_status.dart` (which adds `error→err`).
- `lib/features/rc/shed_detail_screen.dart:20-34` — `rcStateTone(RcState)` +
  `rcKindColor(ShedColors, RcKind)` → `rcStateTone` reuses the shared status mapper;
  a **new string-keyed** `kindColor` (below) serves the HTTP path.
- `lib/shed/shed_dtos.dart` — existing `Shed`, `Session` (per-shed), `ImageInfo`.
  New DTOs added here; the cross-host session DTO is named **`HostSession`** to avoid
  colliding with `Session` (CodeRabbit).
- `lib/ssh/pty_session.dart:20` — `rcAttachCommand(slug)` = `tmux attach -t rc-<slug>`.
  The slug↔tmux helpers live **next to it** and are round-trip tested against it.
- `lib/theme/shed_colors.dart` — `ShedStatusTone{ok,warn,idle,err}` + `toneBg/Fg/Dot`
  and tokens already exist (incl. `kindClaude/kindCodex/kindShell`, `dotOk…`,
  `btnDark`). New tokens added via constructor + `light`/`dark` + `copyWith` + `lerp`.
- `lib/providers.dart` — existing `serversProvider`, `shedClientProvider` (family),
  `shedsProvider` (family), `imagesProvider` (family, the graceful-fallback model),
  `rcServiceProvider`/`rcSessionsProvider` (family). New per-host + section providers.

---

## Vendored design spec (source of truth, inline)

### Color tokens (already in `ShedColors` unless marked **NEW**)

Light: `bg #FAFAF8 · surface #FFF · surface2 #F0EEE9 · line #ECEAE5 · fg #15181E ·
fg2 #6B6F77 · fg3 #9AA0A8 · accent #F2541B`. Status quad `ok #DEF5EB/#117B52 · warn
#FBF1D2/#8A6D0F · idle #EEECE7/#71757E · err #FBE3E3/#C0392B`. Dots (theme-constant)
`ok #1FB87A · warn #E0A300 · idle #A0A4AC · err #E5484D`. `btnDark #15181E/#fff`.
Dark: `bg #15181E · surface #1B1F27 · surface2 #23272F · line #272C35 · fg #ECEEF2 ·
fg2 #9AA0A8 · fg3 #7E848D`; status `ok #10342A/#3FD99A · warn #33290F/#E0B23C · idle
#23272F/#9AA0A8 · err #3A1E1E/#F08C8C`; `btnDark #000/#ECEEF2`.

**NEW tokens** (desktop sidebar/titlebar + runtime badges):
- `sidebar`  L `#F2F0EB`  D `#171A21`
- `titlebar` L `#F4F2EE`  D `#1B1F27`
- `countBg`  L `#EBE9E3`  D `#262B33`
- runtime **vz**: bg L `#DCE9FB` D `#1B2A44`, fg L `#2A6FDB` D `#86B2F5`
- runtime **firecracker**: bg L `#FBE6CF` D `#3A2A18`, fg L `#B5641A` D `#E0A86A`
- agent kinds (extend the mapper; `kindCursor`/`kindOpencode` are **NEW** tokens):
  claude `#F2541B` · codex `#10A37F` · cursor `#6E56CF` · opencode `#3B82F6` ·
  shell `#7A828C`

### `stat()` — status string → (tone, dot glyph, pulse) [mirror verbatim]

| status | tone | dot | pulse |
|---|---|---|---|
| running, ready, online | ok | ● | no |
| working, starting (+ creating, provisioning) | warn | ◐ | **yes** (starting) |
| stopped, idle, offline | idle | ○ | no |
| error | err | ▲ | no |

### `agent()` — kind wire string → color [string-keyed, NOT the `RcKind` enum]

`claude-rc`/`claude-broker` → claude · `codex-rc` (and `codex*`) → codex · `cursor`
→ cursor · `opencode` → opencode · `shell` → shell · **unknown → shell-grey**
(never collapse to Claude — fixes `RcKind.fromWire`'s `_ → claudeBroker`).

---

## Architecture decisions

**Decision 1 — Cross-host Sessions over HTTP `GET /api/sessions` (list *and* delete).**
One call/host vs SSH-probing every running shed (battery/latency murder on mobile).
The aggregate view shows **rc sessions only** (rows with an `rc` block; their `name`
is always `rc-<slug>`), so kind/state/slug are well-defined.
- **List**: `client.listAllSessions()` per host.
- **Open**: derive slug from the tmux `name` (helper below) → `buildPtySession`.
- **Delete**: `client.killSession(shedName, name)` over HTTP (`shed_client.dart:41`) —
  uses the tmux `name` directly, **no SSH, no slug needed**, consistent with the
  HTTP-list decision (CodeRabbit flagged the original "list HTTP / delete SSH" split).
SSH `RcService` stays the source for the **per-shed detail** + create/kill/prompt.
*API-gap ticket:* expose `slug`, `workdir`, `target_label` in `/api/sessions.rc`.

**Decision 1a — Slug helper, next to `rcAttachCommand`, round-trip tested.**
`removePrefix` is **not Dart** (panel blocker). In `pty_session.dart`:
```dart
String rcSlugFromTmux(String name) =>
    name.startsWith('rc-') ? name.substring(3) : name; // tolerant fallback
```
Tested so `rcSlugFromTmux(<target of rcAttachCommand(slug)>) == slug`, and a
non-`rc-` name passes through (open is **disabled** if the derived slug is empty).

**Decision 2 — Responsive `AppShell`, one breakpoint, lazy sections (no IndexedStack).**
A `LayoutBuilder` branches on width (`isDesktopWidth(w) => w >= 900`; pure + tested).
A shared `appSectionProvider` (`StateProvider<AppSection>`:
`hosts|sheds|sessions|system`, default `hosts`) drives the selected section.
- **Render the active section on demand** (a `switch(section)` that builds only the
  current body) — **not** an `IndexedStack`. `IndexedStack` builds all children
  eagerly, so all three fan-out sections would fetch `3×N hosts` at launch even on
  the Hosts tab (Codex + CodeRabbit blocker). Cost: switching tabs rebuilds the
  section (brief reload; `autoDispose` caches briefly). Scroll position resets — fine.
- **Mobile**: custom bottom tab bar (Hosts · Sheds · Sessions · System) + the active
  body. Drill-in screens (per-host ShedList, per-shed sessions, create flows,
  Terminal) **push onto the root Navigator above the shell**, covering the tab bar.
  While a route is pushed, **the tab bar is hidden and tab taps are disabled**
  (driven by a `NavigatorObserver` → `showTabs` bool). A root `PopScope` routes
  Android back: pop drill-in first; from a non-Hosts tab, back returns to Hosts
  before exit (Kimi/CodeRabbit).
- **Desktop**: sidebar (owl + "Shed"; nav Sheds · Sessions · System with count
  chips; HOSTS list with online/offline dots; footer: **Add host** + **SSH
  identity**) + main pane (header: section title + **theme toggle**; body). Desktop
  **default = Sheds** and has **no Hosts pane**; `SectionMapper` maps `hosts → sheds`
  (and highlights Sheds) so a cross-breakpoint resize while on `hosts` is defined
  (panel). Drill-in on desktop also **pushes a full route over the shell** for v1
  (terminal/per-host detail); master-detail-in-pane is a noted future.
- **macOS title-bar dead zone** (~top 28px Marionette can't tap, per M7): the desktop
  header (theme toggle etc.) sits **inside** the sidebar/main layout, never in an
  `AppBar` riding into the title-bar safe area (Kimi).

**Decision 3 — Per-host providers + per-host `AsyncValue` (no monolithic aggregate).**
Each cross-host section iterates `serversProvider` and renders **one group per host**,
each watching its **own** per-host family provider — so a host fills in (or errors)
**independently**; a slow/offline host only spins/errs its own group, never the whole
view (CodeRabbit "all-or-nothing" fix). Per-host providers (all `autoDispose.family`,
each wraps its call in `.timeout(<budget>)` so a hung mint can't pin a group):
- `shedsProvider(server)` — **exists**; reused.
- `hostSessionsProvider(server)` → `client.listAllSessions()`.
- `hostSystemDfProvider(server)` → `client.getSystemDf()` (best-effort; old agent /
  404 / 501 → typed "unavailable", mirroring `imagesProvider`).
Group **order** follows `serversProvider`; items sort deterministically within a host.
Refresh = invalidate the per-host families for the saved hosts **and** rebuild the
section. Nav **count chips** are best-effort: they reflect *already-cached* per-host
values (populate after a section is first visited) — eager counting would defeat
lazy loading; noted as acceptable divergence from the mock.

**Decision 4 — Named group/row models (testable).** `HostShedGroup`,
`HostSessionGroup`, `HostDiskRow`, each `{ server, items, reachable, error? }` — so
fan-out/grouping is unit-testable, not "ordered groups" prose (Codex).

**Decision 5 — One shared status mapper replaces the duplicates.**
`lib/shed/shed_status.dart`: `shedStatusTone(String) -> (ShedStatusTone, String dot,
bool pulse)` per the `stat()` table. `ShedListScreen.toneFor` and the `rcStateTone`
label path **refactor onto it** (today they disagree — `toneFor` has no `err` case),
killing the drift the mirror-the-server rule exists to prevent (CodeRabbit).

**Decision 6 — Theme additions** (Decision-2 NEW tokens) added to `ShedColors`'
constructor + `light`/`dark` + `copyWith` + `lerp`, projected onto the scheme like the
rest. A `copyWith()`-identity + `lerp(self,self,.5)`-equality test covers the new
fields (CodeRabbit — `copyWith`/`lerp` silently drop a forgotten field). New widgets:
`RuntimeBadge(backend)` and `HostDot(online)`.

---

## Phases (each = one gated commit on the feature branch)

> Each phase lists its **Done-when** acceptance as concrete `MSTATE`/`MRESULT`
> contracts (the drive asserts on these strings), plus its test tier.

### Phase 1 — Data layer, DTOs, pure mappers (no UI) · (a)(b)
**Build:** `shed_dtos.dart` — `SystemDiskUsage`/`DiskTotals`/`DiskSize`
(`logical_bytes`/`physical_bytes`) + pure `formatBytes`; **`HostSession`** (tolerant;
accepts bare-array *or* `{sessions:[…]}`; skips rows without an `rc` block; `created_at`
zero-value → null age). Extend `Shed` to surface `image, repo, cpus, memoryMb,
startedAt` + pure `shedMetaLine(...)` / `uptimeLabel(startedAt)` (null when absent /
zero). `shed_client.dart` — `getSystemDf()`, `listAllSessions()` (pinned client +
401-retry). `shed_status.dart` — shared mapper (+ refactor `toneFor`/`rcStateTone`).
`kindColor(ShedColors, String)` string mapper. `pty_session.dart` — `rcSlugFromTmux`.
`providers.dart` — `appSectionProvider`, `hostSessionsProvider`,
`hostSystemDfProvider`, `isDesktopWidth`, `SectionMapper`.
**Tests (a):** DTO parse incl. missing `totals`/null lists/old-agent-404→unavailable,
bare-vs-wrapped sessions, null `rc`, unknown kind/state, zero `created_at`;
`formatBytes`; `uptimeLabel`; `shedStatusTone` (incl. `error→err`); `kindColor`
(`codex-rc`→codex, unknown→shell, **never** Claude); `rcSlugFromTmux` round-trip vs
`rcAttachCommand`; `isDesktopWidth(899)=false/(900)=true`; `SectionMapper`
(`hosts→sheds` desktop); per-host tolerant fan-out via `ProviderContainer` overrides
(N hosts, one throws → others survive, error captured, order stable). **(b):**
fake-server `getSystemDf`/`listAllSessions` mirroring `shed_client_test.dart`.
**Done-when:** `make check` green; new tests green; **no UI** committed.

### Phase 2a — Desktop AppShell + chrome re-home · (a)(c)(d-macOS)
**Build:** `lib/app/app_shell.dart` (LayoutBuilder), `lib/app/desktop_scaffold.dart`
(sidebar + main pane). `main.dart` `_Home` data-branch → `AppShell`. Extract
`HostsView` from `ServerListScreen`. Re-home chrome: sidebar **Add host** (pushes the
existing `AddServerScreen` for now — inline modal is P6) + **SSH identity** (pushes
`IdentityScreen`); main-pane header **theme toggle**. Theme NEW tokens +
`RuntimeBadge`/`HostDot`. Sidebar renders Sheds/Sessions/System nav (chips may be
absent until visited) + HOSTS list (status dots). Active section bodies are minimal
(provider-backed lists/empties; full styling in P3–P5). Widget test: pump `AppShell`
at 900px → `shell-desktop` key present.
**Keys:** `shell-desktop`, `nav-sheds|sessions|system`, `desktop-add-host`,
`desktop-identity`, `desktop-theme-toggle`, `desktop-host-$host`.
**Done-when (drive macOS):** `MSTATE layout=desktop section=sheds`; tapping
`nav-system` → `MSTATE layout=desktop section=system`; `desktop-theme-toggle` flips
`MSTATE theme=dark`→`light`; `desktop-add-host` opens (`MRESULT add-open ok`);
onboarding gate still intercepts. `make check` green.

### Phase 2b — Mobile AppShell + drill-in regression · (a)(c)(d-Pixel8)
**Build:** `lib/app/mobile_scaffold.dart` (bottom tab bar + active body switch +
`NavigatorObserver`-driven `showTabs` + root `PopScope`). Hosts tab = `HostsView`
with its header affordances preserved (theme toggle, identity, add). Keep the
existing drill-down pushing **above** the shell. Widget test: pump at 899px →
`shell-mobile` key present.
**Keys:** `shell-mobile`, `nav-hosts|sheds|sessions|system`, `mobile-theme-toggle`,
`mobile-identity`, `mobile-add`.
**Done-when (drive Pixel-8):** `MSTATE layout=mobile section=hosts`; tab taps switch
`section=` and `MSTATE tabs-visible=true`; Hosts→host→shed→session→terminal drill
still works and logs `MSTATE tabs-visible=false` on a pushed route; Android back from
`section=sheds` → `section=hosts` (not exit). `make check` green.

### Phase 3 — Cross-host Sheds view · (a)(c)(d)
**Build:** per-host groups (`HostShedGroup`); rich cards — status dot (+`starting`
pulse via `StatusDot(animate:)`), name, `RuntimeBadge`, image chip, meta
`repo · N vCPU · mem · up Nh` (`shedMetaLine`). Per-host unreachable card/banner
(warn). **Desktop**: inline open + restart + stop/start (square, tinted). **Mobile**:
tap-to-drill into the per-host shed→sessions (actions stay in the existing per-host
drill-in). **Restart** = `stop`→`start` with a busy flag in a local
`ConsumerStatefulWidget` (no optimistic mutation; invalidate `shedsProvider(server)`
on completion). **Failure semantics**: if `stop` succeeds but `start` fails, the card
reflects the now-**stopped** state + surfaces the error; the busy flag guards
double-tap (panel).
**Keys:** `all-shed-$host-$shed`, `all-shed-open|restart|stop|start-$host-$shed`,
`all-sheds-unreachable`.
**Done-when:** `MSTATE screen=all-sheds hosts=$n reachable=$r` (with one offline test
host: a reachable host renders cards **and** the offline host shows an error card,
`reachable` < `hosts`); desktop `MRESULT shed-restart ok` (and a forced
start-failure path → `MRESULT shed-restart err` leaving `state=stopped`). Card-model
derivation pure-tested. Drive both layouts.

### Phase 4 — Cross-host Sessions view · (a)(c)(d)
**Build:** per-host groups (`HostSessionGroup`); cards — status badge
(`shedStatusTone`), kind chip with `kindColor` left accent, meta
`host · tmux rc-… · made Nh ago` (age omitted on zero `created_at`), dark `>_ open`
pill, delete. Owl-ghost empty state. **Open** → derive slug (`rcSlugFromTmux`) →
`buildPtySession(server, shed_name, slug)`; **disabled** if slug empty. **Delete** →
`client.killSession(shed_name, name)` (HTTP) → invalidate `hostSessionsProvider` +
`rcSessionsProvider((server,shed))` if alive.
**Keys:** `all-session-$host-$shed-$slug`, `all-session-open|delete-$host-$shed-$slug`,
`all-sessions-empty`.
**Done-when:** `MSTATE screen=all-sessions hosts=$n sessions=$c`; `all-session-open`
pushes terminal (`MSTATE tabs-visible=false`); `MRESULT session-delete ok` and the
row disappears. `HostSession`→card-model + slug derivation pure-tested. Drive both.

### Phase 5 — System (disk per host) · (a)(c)(d)
**Build:** per-host cards (`HostDiskRow`) — name + `RuntimeBadge` + bold **total**
(`totals.all.physical_bytes`); Images/Sheds/Snapshots/Orphans columns (`formatBytes`
of each `.physical_bytes`); error/unavailable state for old-agent/offline (shows the
transport error, like the mock). Refresh action.
**Keys:** `system-host-$host`, `system-refresh`, `system-host-error-$host`.
**Done-when:** `MSTATE screen=system hosts=$n ok=$k`; with one offline host its card
shows `system-host-error-$host`; `MRESULT system-refresh ok`. `formatBytes` +
card-model pure-tested. Drive both (against live test servers; record any tier-d gap).

### Phase 6 — Polish & aux · (a)(c)(d)
**Build:** desktop **Add-host inline modal** (upgrade from the P2 route; reuse
`AddServerFlow`). Live-ish nav **count chips** from cached per-host values. Final
theme-toggle/identity placement. Audit: every new control has a `ValueKey` +
`logDriveState/Result`. Light + dark visual pass both platforms. **Release tree-shake
check**: `flutter build apk --release` + macOS, then symbol-scan = 0 for
`MSTATE|MRESULT|marionette|logDrive`. Update `PROGRESS.md` + `docs/` + this plan's
status.
**Done-when:** `MRESULT add-host ok` (desktop modal); release scan = 0; `make check`
green; PROGRESS updated.

---

## Test matrix (additions beyond per-phase lists)
- **Provider fan-out** (`ProviderContainer` + overridden `serversProvider`/clients):
  one host throws → others survive; stable order; refresh re-fires the right family.
- **Breakpoint** widget test (899→`shell-mobile`, 900→`shell-desktop`).
- **`ShedColors`** `copyWith`/`lerp` round-trip on the NEW tokens.
- **Slug** round-trip vs `rcAttachCommand`; no-prefix passthrough; empty → open off.
- **`kindColor`** string mapper (codex/cursor/opencode/shell/unknown; never Claude).
- **Restart** action helper: stop-ok→start-fail leaves `stopped` + error.

## API gaps → potential tickets to the `shed` project
1. **`/api/sessions` richness**: expose `slug` (retire the prefix-strip derivation),
   plus `workdir` and `target_label`, in the `rc` block.
2. **Atomic restart**: `POST /api/sheds/{name}/restart` (client does stop→start
   today; a "stopped" window is visible mid-restart, and stop-ok/start-fail leaves it
   stopped).
3. **Uptime**: `started_at` is VM-backend-only; stopped / firecracker-without-boot
   sheds can't show uptime (we omit it).

## Risks
- **Old-agent `/api/system/df` / `/api/sessions`**: tolerant best-effort per-host
  providers + the live probe above; an unsupported host degrades to "unavailable".
- **Parallel fan-out on a weak radio**: per-host `try/catch` + `.timeout()` bound it;
  a concurrency cap is a noted future if needed.
- **Shell regressions** to the existing drill-down: M7 screens reused unchanged;
  drill-in pushes above the shell; `_Home` gate preserved; widget + drive coverage.
- **macOS title-bar dead-zone**: keep tappable nav out of the top strip; verify
  AppBar-ish actions on Android (M7 note).

## Acceptance
Tiers (a)(b) self-certified each phase; (c) real test shed for the new client calls
+ drive on macOS and the Pixel-8 emulator with the concrete `MSTATE`/`MRESULT`
contracts above; **(d)** on-device Pixel-8 remains the standing human gate (from M4).

---

## Panel review — disposition (2026-06-28)
**Blockers fixed:** lazy section render (no `IndexedStack` fan-out); `removePrefix`→
tested `rcSlugFromTmux`; string-keyed `kindColor` (codex-rc never collapses to
Claude). **High-confidence (multi-reviewer) fixed:** split P2→P2a/P2b; preserve
`_Home` gate; per-host `AsyncValue`+timeouts (no all-or-nothing spinner); concrete
`MSTATE`/`MRESULT` acceptance; embed design tokens; `SectionMapper` for `hosts` on
desktop; re-home `ServerListScreen` chrome in P2; `shed_status.dart` replaces the
drifting mappers; rename `SessionInfo`→`HostSession`; restart busy/failure semantics;
delete via HTTP `killSession` (consistent with Decision 1); macOS title-bar dead-zone;
breakpoint + fan-out + `copyWith`/`lerp` tests. **Confirmed by live probe (not just
assumed):** `/api/sessions` `rc.state` is server-classified; `created_at` zero value;
df `totals.all.physical_bytes`. **Deferred (noted, not in scope):** master-detail
terminal-in-pane on desktop; sidebar host-click→filter; fan-out concurrency cap.

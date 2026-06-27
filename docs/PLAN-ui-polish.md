# shed-mobile — UI Polish & Feature-Gap Plan (M6)

## Context

shed-mobile reached a working MVP (M0–M5: transport, server management, shed CRUD,
RC sessions, in-app terminal, Android keygen/FGS, docs). A comparison against the
`shed-remote-agent` web app (`apps/web/src/pages/*`, `components/TerminalKeys.tsx`),
the `shed` CLI/Go API, and `shed-ext-rc` surfaced **field gaps** (options the mobile
UI doesn't expose) and **feature gaps** (missing or broken capabilities). This plan
closes the gaps that make sense on mobile, in phases executed in order as separate
gated commits.

It also fixes two issues hit in real use:

- **Create-shed Create button never enables.** `create_shed_screen.dart:106` gates
  `onPressed` on `_name.text.trim().isEmpty`, but no listener calls `setState` when
  the name field changes — so the widget never rebuilds on input and the button
  stays disabled. Shed creation via the UI has never worked end-to-end (an earlier
  manual test against the `mini2` server appeared to "hang"; in fact the submit tap
  landed on this permanently-disabled button — a silent no-op).
- **No way to view/copy the device SSH key after onboarding.** The onboarding
  screen shows the generated public key once; afterward there is no screen to
  re-view/copy it, or to see the desktop `~/.ssh` identity.

### Conventions referenced by this plan

This repo's established patterns (used as acceptance vocabulary below):

- **Drive harness** `drive-shed-mobile`: a Marionette CLI drives a **debug** build
  headlessly. Tests assert *effects* via structured debug logs
  `logDriveState(...)` → `MSTATE …` and `logDriveResult(...)` → `MRESULT …`, both
  `kDebugMode`-gated (tree-shaken from release). Every control carries a stable
  `ValueKey`. Validation tiers: **(a)** pure unit · **(b)** fake server · **(c)**
  real shed · **(d)** manual/hardware (e.g. the Pixel 8 emulator).
- **Mirror-the-server** ports: client logic that must match the server is ported as
  a pure, unit-tested function (e.g. `certFingerprint`, `rcPermissionModes`,
  `kTlsFingerprintRe`). New validation here follows that pattern.
- **Per-phase commit flow** (no PR): implement → unit tests → `make check` →
  drive-smoke → `/simplify` on the diff → `/codex:rescue` on the diff → commit
  (Conventional Commit + `Co-Authored-By`/`Claude-Session` trailers) → push → CI
  green.

## Feature-gap analysis (current state)

| Gap | Severity | Disposition |
|---|---|---|
| Create-shed button never enables (no rebuild on name input) | **Bug, blocking** | Phase 0a |
| Create-shed: no client-side name validation; no feedback on disabled submit | Gap | Phase 0a |
| No screen to view/copy the device SSH public key + fingerprint | **Gap** | Phase 0b |
| No way to regenerate / rotate the device key | Gap (risky) | Phase 0b (guarded) |
| Create-shed: no Image picker (web has it; model supports `image`) | Gap | Phase 2 |
| Create-shed: no cpus / memory / no_provision (model supports all three) | Gap | Phase 2 |
| Create-RC: no explicit session-name field; only a skip toggle (not full mode set) | Gap | Phase 3 |
| Terminal: no on-screen keys, font size, or paste | **Gap, high** | Phase 1 |
| View a saved server's pins; rename/edit a server; "test connection"; send-prompt to existing RC | Minor gap | Out of scope (noted) |

Where mobile already **exceeds** the web: in-app add/remove server (web has none);
RC create exposes workdir + skip-permissions (web sheds expose neither).

## Phases

### Phase 0a — Fix the create-shed Create button

- Add a listener on `_name` (disposed in `dispose`) so the submit button re-evaluates
  on input; keep disabled-when-invalid, but gate on a **ported validator**
  (below), not just non-empty, and show the validation message inline so the
  disabled state is explained.
- **Port `ValidateShedName` to Dart** as a pure function mirroring the server
  (`shed/internal/config/types.go`): `^[a-z][a-z0-9-]*[a-z0-9]$ | ^[a-z]$`, max 63
  chars — lowercase alphanumeric + hyphen, must start with a letter, no
  leading/trailing hyphen, no dots/underscores/uppercase. Validate before POST so
  a bad name fails fast (not as a mid-create SSE error).
- **Auto-suggest the name from the repo** via a pure `suggestShedName(repo)`:
  take the basename, strip a trailing `.git`, lowercase, collapse invalid runs to
  `-`, drop leading non-letters, trim trailing `-`, truncate to 63; yield empty if
  nothing valid remains. Handles `owner/repo`, `https://…/owner/repo(.git)`,
  `git@host:owner/repo.git`, trailing slash, and inputs like `owner/My_Repo`,
  `owner/repo.git`, `owner/2048`. Track `_nameEdited`; only populate the name field
  while it is empty / still an unedited suggestion, never overwriting a typed name.
- **Extract a pure `buildCreateShedRequest(...)`** from the inline `_create()` body
  so request shaping (trim, empty→null) is unit-testable; reused by Phase 2.

### Phase 0b — SSH identity screen (view / copy / regenerate)

- A `publicIdentityProvider` returning a **`PublicIdentity`** (public material only,
  never `List<SSHKeyPair>`), platform-resolved in the provider (not in the widget):
  - Mobile: read `IdentityStore.authorizedKey()` (public line) — **do not** call
    `IdentityStore.load()` (which returns the private keypair).
  - Desktop: derive from the loaded `~/.ssh` keypair via `.toPublicKey().encode()`
    only; display the **first** identity and document that assumption.
- `PublicIdentity.fromAuthorizedKeyLine(String)` — a real parser: skip any
  `options` prefix, take the `ssh-ed25519 <base64> [comment…]` fields, base64-decode
  the blob, and compute the fingerprint with the **shared** helper below. Render an
  error (never throw) on a malformed/empty line.
- **DRY the fingerprint:** extract `fingerprintOfBlob(Uint8List) → 'SHA256:…'`
  (unpadded base64 of `sha256(blob)`) and use it in **both** `KeyManager`
  generation and the from-line path so they cannot drift.
- `lib/features/identity/identity_screen.dart` (read-only): shows the
  `ssh-ed25519 …` line + `SHA256:` fingerprint + Copy; reached from a new
  settings/overflow entry on the server-list screen. Must never display, copy, or
  log the private PEM.
- **Regenerate (mobile only, guarded — highest-risk item):** behind a destructive
  confirm dialog whose copy states the new key must be re-trusted **on every server
  AND in GitHub**. On confirm: `IdentityStore.generateAndStore()`, then
  `ref.invalidate(identitiesProvider)` so new connections use the new key (note:
  already-open `PtySession`s captured the old `identities` by value and need a
  reconnect), then immediately show + offer Copy on the new public key so re-trust
  is one step. (If this proves too risky to land cleanly, ship view/copy only and
  defer regenerate.)

### Phase 1 — Terminal mobile keys

Port `TerminalKeys` (web `apps/web/src/components/TerminalKeys.tsx`) to a Flutter
toolbar above the terminal:

- A horizontally-scrolling key row with a `ValueKey` per button (`term-key-esc`,
  `term-key-ctrl`, `term-key-tab`, `term-key-up/down/left/right`, `term-key-c/d/l`,
  `term-key-pgup/pgdn/home/end`): **sticky Ctrl**, `Esc`, `Tab`, arrows, `^C`, `^D`,
  `^L`, `PgUp`, `PgDn`, `Home`, `End`. The control keys (`^C/^D/^L`) and escape
  sequences write **directly** to `PtySession.write` (bypassing `onOutput`).
- **Sticky Ctrl** as a pure `applyStickyCtrl(armed, data) → (bytes, stillArmed)`
  filter applied to the terminal's outgoing `onOutput` *before* `PtySession.write`:
  transform **only** when armed and `data` is exactly one ASCII `[A-Za-z]`
  (`codeUnit & 0x1f`), then disarm; anything else (multi-rune, IME-composed text,
  `\x1b…` reports, bracketed-paste payloads — `onOutput` carries all of these)
  passes through unchanged and disarms. Toolbar keys deliberately bypass this.
- **Focus preservation (primary mechanism = non-focusable buttons):** toolbar
  buttons use `canRequestFocus: false` so a tap can't steal focus from the terminal
  (the Flutter analog of the web's `preventDefault` on mousedown). Give
  `TerminalView` an owned `FocusNode` created/disposed in the State and a
  `GlobalKey<TerminalViewState>`; if a tap still drops the IME, call
  `terminalViewKey.currentState?.requestKeyboard()` in a post-frame callback as a
  backstop (avoid fighting the existing `autofocus`). Emit
  `MSTATE terminal keyboardVisible=<bool> inset=<n>` after toolbar taps so the
  emulator drive can assert the keyboard stayed up. **Spike this on the Pixel 8** —
  xterm 4.0.0 Android IME handling is historically flaky.
- **Font size** +/- via `TerminalStyle(fontSize:)`, bounded (e.g. 8–28, default 13);
  the existing resize path re-sends PTY dims.
- **Paste** button → read clipboard → `Terminal.paste(text)` (honors bracketed
  paste), not a raw `PtySession.write`.

### Phase 2 — Create-shed fields

- **Image** picker (primary field): `DropdownButton` populated by
  `imagesProvider = FutureProvider.autoDispose.family<List<ImageInfo>, String>`
  (mirrors `shedsProvider`), wrapping `ShedClient.listImages()`. First option
  "(server default)" → omits `image`. The picker must **never block creation**:
  on list error, keep "(server default)" selectable.
- **Advanced** (`ExpansionTile`): `cpus` and `memory_mb` (numeric `TextField`s,
  parsed as positive ints, empty/zero → omitted, non-positive/non-integer →
  inline validation error before POST) and `no_provision` (`Switch`). All three
  already exist on `CreateShedRequest`. Shaping goes through the
  `buildCreateShedRequest` helper from Phase 0a so it is unit-tested.

### Phase 3 — Create-RC polish

- **Session name** (optional text) → `RcService.create(displayName:)`; blank maps to
  `null` (preserving the `<shed>/<slug>` default), not `''`.
- **Permission mode** picker over `rcPermissionModes`
  (`default`/`acceptEdits`/`plan`/`auto`/`dontAsk`/`bypassPermissions`), default
  none → no flag; the existing "skip" behavior maps to `bypassPermissions`.
  `RcService.create` already takes `permissionMode` and validates the set.

## Out of scope / deferred (with rationale)

- Repo picker (OAuth/public) and local-dir/workspace picker — deferred
  enrollment/listing seams; text entry works for the MVP.
- `machine:` targets, `add_dirs`, `from_snapshot`, `upper_size`, `interactive-shell`,
  `backend` select — power-user/rare or wrong-fit for mobile.
- Server rename/edit, view-pins, test-connection, send-prompt-to-existing-RC —
  minor; revisit after these phases if wanted.

## File list

- Phase 0a: `lib/features/sheds/create_shed_screen.dart` (edit),
  `lib/shed/shed_name.dart` (new: `validateShedName`, `suggestShedName`,
  `buildCreateShedRequest`), `test/shed/shed_name_test.dart` (new).
- Phase 0b: `lib/keys/key_manager.dart` (edit: `fingerprintOfBlob`,
  `PublicIdentity.fromAuthorizedKeyLine`), `lib/features/identity/identity_screen.dart`
  (new), `lib/features/servers/server_list_screen.dart` (edit: settings entry),
  `lib/providers.dart` (edit: `publicIdentityProvider`),
  `test/keys/{key_manager,identity_store}_test.dart` (extend), provider test.
- Phase 1: `lib/features/terminal/terminal_keys.dart` (new: toolbar + pure key map +
  `applyStickyCtrl`), `lib/features/terminal/terminal_screen.dart` (edit),
  `test/features/terminal/terminal_keys_test.dart` (new).
- Phase 2: `lib/features/sheds/create_shed_screen.dart` (edit), `lib/providers.dart`
  (edit: `imagesProvider`), `test/shed/shed_name_test.dart` (extend builder tests).
- Phase 3: `lib/features/rc/create_rc_screen.dart` (edit),
  `test/rc/rc_service_test.dart` (extend UI-mapping/argv coverage).

## Acceptance criteria

**Phase 0a (create fix) — independent of 0b:**
- Typing a valid name enables Create; **clearing it disables Create again**;
  an invalid name (uppercase/underscore/dot/leading-hyphen/>63) shows the inline
  validator message and keeps Create disabled.
- Entering a repo auto-suggests a valid name; an "ugly" repo
  (`owner/My_Repo`, `owner/repo.git`, `owner/2048`, a full https/ssh URL, trailing
  slash) yields a **valid** suggestion or empties it — never an invalid one; the
  suggestion never overwrites a name the user has edited.
- A shed creates end-to-end via the UI on the emulator (`MRESULT shed-create ok`).

**Phase 0b (identity screen):**
- The screen shows + copies the public key and `SHA256:` fingerprint on **both**
  platforms; the fingerprint equals `ssh-keygen -l` for the same key.
- **Security-negative:** the screen never displays, copies, or logs the private PEM
  (verified by code review + a test asserting the provider yields `PublicIdentity`).
- Regenerate replaces the key, the warning names GitHub + servers, a subsequent
  connection uses the **new** key (old key now fails), and the new key is shown +
  copyable immediately.

**Phase 1 (terminal keys):**
- On the Pixel 8 emulator: each toolbar key reaches a live session (Esc cancels,
  arrows move history, `^C` interrupts, etc.); **after tapping any toolbar key the
  soft keyboard stays up** (`MSTATE terminal keyboardVisible=true`, inset > 0).
- Sticky-Ctrl transforms exactly one ASCII letter into its control code and
  auto-disarms; multi-char/IME/paste/escape-report input passes through unchanged.
- Font +/- changes size within bounds and the PTY tracks the new dims; paste
  inserts clipboard text via bracketed paste.

**Phase 2:** the Image picker lists images (and stays usable if listing fails),
creating on the chosen image; cpus/memory parse as positive ints with empty/zero
omitted and invalid values blocked before POST; `no_provision` flows through.

**Phase 3:** a named session is created with the chosen permission mode; blank name
→ `<shed>/<slug>`; "skip" → `bypassPermissions`.

**All phases:** `make check` green; CI green per commit; debug instrumentation stays
`kDebugMode`-gated.

## Test plan

- **Pure unit (tier a):** `validateShedName` (valid/invalid table incl. boundary 63,
  single-letter, leading/trailing hyphen, case); `suggestShedName` (the repo-format
  table above, incl. URLs and `.git`); `buildCreateShedRequest` (empty/zero →
  omitted for repo/image/cpus/memory/no_provision); `applyStickyCtrl` + the static
  key-byte map; `PublicIdentity.fromAuthorizedKeyLine` incl. a **golden** check vs
  `ssh-keygen -l` (gated on its presence, like `key_manager_test`) and a round-trip
  (generate → derive-from-line == original fingerprint) and malformed-line handling.
- **Provider (tier b):** `publicIdentityProvider` on mobile vs desktop via
  `ProviderScope` overrides (in-memory secret store / a fake key), asserting it
  exposes only public material; `imagesProvider` decode incl. the null-list case.
- **Drive (tier c/d):** the acceptance flows on macOS and the Pixel 8 emulator,
  asserted via `MSTATE`/`MRESULT` + screenshots (terminal keyboard-visible
  assertion; create-shed end-to-end; identity view/copy; regenerate).
- **Regression:** existing `tool/e2e_*.dart` remain green.

## Execution & CI

Per-phase commit flow (no PR), order **0a → 0b → 1 → 2 → 3**. Keep all new debug
logging through `logDriveState`/`logDriveResult`; **do not** import marionette in new
code; keep platform branches (`Platform.isAndroid/isIOS`) in providers, not widget
build methods, so tests can override them. Run `flutter build linux --debug` in the
local gate for any phase touching `providers.dart` or platform imports, and one
explicit **release** build + tree-shake check (no `marionette`/`MSTATE`/`MRESULT`
symbols) after Phase 1 (terminal/focus changes are the most likely to pull
unexpected platform code). CI runs `make check` + the Linux build per push.

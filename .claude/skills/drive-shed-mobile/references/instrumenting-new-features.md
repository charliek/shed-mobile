# Instrumenting new features so they stay agent-drivable

When you add or change UI in `apps/flutter_client`, make it drivable in the same
change. Marionette (and CI integration tests later) can only drive what's
targetable and verifiable. Five rules, in priority order.

## 1. Key every interactive element

Add a `ValueKey('<screen>-<element>')` (kebab-case) to anything an agent taps,
types into, or selects: buttons, text fields, list rows, toggles, dropdowns,
dialog actions, menu items. Id-suffix anything that repeats:
`convlist-row-<id>`, `memory-row-<id>`, `card-action-<action>`,
`voice-option-<voiceId>`.

- **Built-in Material widgets** (`ElevatedButton`, `FilledButton`, `OutlinedButton`,
  `TextButton`, `IconButton`, `FloatingActionButton`, `TextField`, `Switch`,
  `Checkbox`, `Radio`, `Dropdown`, `Slider`, `SegmentedButton`, `Text`) are
  auto-detected by Marionette — but **add a key anyway** when more than one of the
  same type is on screen (e.g. several `IconButton`s), or matching by text/type is
  ambiguous. Two `IconButton`s with no keys are indistinguishable.
- **Custom interactive widgets** are invisible to Marionette unless they wrap a
  built-in or carry a key. Key them.
- **Dialog buttons** with generic labels ("Cancel", "Save", "Delete") repeat across
  dialogs — key each (`memory-add-cancel`, `memory-edit-cancel`) so they're
  unambiguous even though only one dialog shows at a time.

Document new keys in `references/tapper-context.md`.

## 2. Make outcomes readable — never rely only on a SnackBar

An agent must be able to confirm an action worked. A transient `SnackBar`
("Preferences saved") may auto-dismiss before it's read and isn't keyed, so it is
**not** a reliable signal. For any save/create/edit/delete, do one of:

- Emit a structured log: `logDriveResult('settings-save', ok: true)` (from
  `lib/marionette/drive_state.dart`) → an agent reads `get-logs | grep MRESULT`.
  Preferred — works headless and survives the SnackBar dismissing.
- Or render a durable, **keyed** result widget (like `login-error` on the login
  screen), not just a SnackBar.

## 3. Expose non-rendered state via MSTATE

If a new screen has state an agent needs but that isn't shown as text — an in-flight
flag, a selection, a mode, an id — emit it from `build()` with `logDriveState(...)`
(see `conversation_screen.dart` for the pattern). It logs `MSTATE …` only on change,
so an agent can read current state and wait on transitions via
`get-logs | grep MSTATE`. Keep it to one concise line per screen; both helpers are
`kDebugMode`-gated and tree-shaken from release.

## 4. Don't create driving traps

- **Disabling a control drops focus and silently swallows taps.** If you disable a
  text field while busy (as the chat input does during a turn), restore focus when
  it re-enables (`didUpdateWidget`, see `text_input_bar.dart`) — otherwise the next
  input goes nowhere. If you disable a button, an agent's tap is a silent no-op, so
  the disabled state must be readable (key + `onPressed: null`, or an MSTATE flag).
- **Auto-scroll matters:** `get-interactive-elements` returns only *visible* nodes.
  If new content can land off-screen, scroll it into view (the app already
  auto-scrolls the message list).
- **Avoid hard-to-drive surfaces** for anything that needs automated coverage: real
  OAuth popups, native permission dialogs, and the mic/voice path can't be driven by
  Marionette (Patrol covers native dialogs later). Provide a debug bypass (like the
  dev-login) for flows gated behind them.

## 5. Validate it's drivable before you're done

After the change, drive it once: `hot-reload`, `get-interactive-elements` to confirm
your new keys appear, exercise the flow, and check the outcome via
`get-logs`/screenshot. If you can't drive it from the keys + logs alone, an agent
(or a CI test) can't either — fix the instrumentation, not the test.

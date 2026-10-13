import 'package:flutter/services.dart';

import '../../src/rust/api/dto_lane.dart';

/// The transcript composer's `/` menu — its KEYS (plan 029 §3.5; P9, P28).
///
/// Every rule about the MENU itself — which rows show, what a typed token
/// matches, what accepting a row does, when a command is refused — is
/// `shed_app::slash_menu`'s, reached through `SlashRules` (P5); nothing here
/// filters, parses or decides a command. What is left for the phone is what
/// only a keyboard and a screen have: which key does what to the menu on
/// screen, where the highlight goes, and when an Esc dismissal ends. The
/// desktop's `slashKeys.ts`, on Flutter's logical keys — pure, so a plain
/// unit test pins the table.
enum ComposerKey {
  /// Not the composer's: the key does what it always does (the caret moves,
  /// Tab moves focus, an IME takes it).
  none,

  /// Shift+Enter: a newline at the caret — never a send.
  newline,

  /// Enter with no menu up: the draft is SENT (through the shared dispatch
  /// when the session has a menu, as text when it has none).
  send,

  /// Enter with the menu up: the highlighted row is accepted with Enter (the
  /// shared rule then decides — a token that already spells the row sends,
  /// anything else selects it, P9).
  accept,

  /// Tab with the menu up: the highlighted row completes.
  complete,

  /// Esc with the menu up: the menu closes, and the Esc stops here.
  dismiss,

  /// ↑ with the menu up: the highlight moves instead of the caret (P28).
  up,

  /// ↓ with the menu up.
  down,
}

/// **The key table** (P9). [menuUp] is the menu as it is ON SCREEN — open,
/// with rows, and not dismissed. EVERY key is ignored while an IME composes
/// ([composing]: an IME's Enter commits its composition, never a send) — the
/// composer's own Enter-to-send included. Shift+Enter is always a newline.
/// With no menu up, Enter sends (zero matches included), and Tab, Esc and the
/// arrows are the field's own.
ComposerKey composerKey({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool composing,
  required bool menuUp,
}) {
  if (composing) return ComposerKey.none;
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    if (shift) return ComposerKey.newline;
    return menuUp ? ComposerKey.accept : ComposerKey.send;
  }
  if (key == LogicalKeyboardKey.tab) {
    return menuUp && !shift ? ComposerKey.complete : ComposerKey.none;
  }
  if (key == LogicalKeyboardKey.escape) {
    return menuUp ? ComposerKey.dismiss : ComposerKey.none;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return menuUp ? ComposerKey.up : ComposerKey.none;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return menuUp ? ComposerKey.down : ComposerKey.none;
  }
  return ComposerKey.none;
}

/// Whether an IME composition is in progress on [value]: a non-empty
/// composing range (Flutter's own `isComposing` signal).
bool isComposing(TextEditingValue value) =>
    value.composing.isValid && !value.composing.isCollapsed;

/// Whether the menu is ON SCREEN: the shared filter says it is open (with
/// rows), and it has not been dismissed with Esc for this very token.
bool slashMenuUp(BridgeSlashFilter? filter, String? dismissed) =>
    filter != null &&
    filter.open &&
    filter.rows.isNotEmpty &&
    filter.token != dismissed;

/// **An Esc dismissal lasts until the token changes** (P9): the token it was
/// given for, kept while the token is still that one, and gone for good once
/// it is not — so typing on reopens the menu, and typing back does not
/// re-close it.
String? dismissalAfter(String? dismissed, String token) =>
    dismissed == token ? dismissed : null;

/// The highlight after ↑ (`-1`) or ↓ (`+1`) over [count] rows, wrapping at
/// either end.
int moveHighlight(int index, int delta, int count) =>
    count <= 0 ? 0 : (index + delta) % count;

/// The caret the shared filter reads (P28), in UTF-16 code units — what
/// [TextSelection] reports, so nothing converts. A field that has never had a
/// selection reads as its end.
int slashCaret(TextEditingValue value) =>
    value.selection.isValid ? value.selection.extentOffset : value.text.length;

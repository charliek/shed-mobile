import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/lane.dart';

/// **The `/` menu's rules, as one seam** (plan 029 §3.4, P5).
///
/// Every rule about a session's `/` menu — which rows it lists for a draft and
/// caret, what a typed command does, what choosing a row does, whether a turn
/// is running — is `shed_app::slash_menu`'s, in shared Rust, and reached here
/// through four FRB `#[frb(sync)]` calls. The phone RENDERS what they answer
/// and handles keys; it filters, parses and decides nothing itself. That is
/// the whole point of the module (the dispatch guard is exactly where two
/// ports drift), so there is no Dart rule anywhere in `lib/`.
///
/// It is a seam, like [LaneSource] beside it, for one reason: a widget test
/// runs with no native library loaded, and it can only drive the composer if
/// there is somewhere to hand it a stand-in. The production implementation is
/// [BridgeSlashRules] and is a pure pass-through. The menu handed in is the
/// one the lane's snapshot carried (`BridgeLaneSnapshot.slashMenu`), as read.
abstract interface class SlashRules {
  /// What the menu panel shows for [draft] with the caret at [caret] (UTF-16
  /// code units — what `TextSelection` reports, so nothing converts):
  /// whether it is open, its first token, and its rows in order, each marked
  /// `dimmed` while [working].
  BridgeSlashFilter filter(
    BridgeSlashMenu menu,
    String draft,
    int caret,
    bool working,
  );

  /// What SENDING [draft] does: not a command (send it as text), a prompt
  /// row's canonical text, a command to run, or a refusal with its reason.
  BridgeSlashDispatch dispatch(
    BridgeSlashMenu menu,
    String draft,
    bool working,
  );

  /// What choosing the row named [rowName] with [key] does — complete the
  /// draft, or act as a Send would. Null when there is nothing to accept (the
  /// menu moved under the highlight: re-filter).
  BridgeSlashAccept? accept(
    BridgeSlashMenu menu,
    String draft,
    String rowName,
    BridgeSlashAcceptKey key,
    bool working,
  );

  /// Whether a turn is running, for the dim-and-refuse rule (P23).
  bool isWorking(BridgeRcActivity activity);
}

/// The production [SlashRules]: the generated FRB functions, unadorned.
class BridgeSlashRules implements SlashRules {
  const BridgeSlashRules();

  @override
  BridgeSlashFilter filter(
    BridgeSlashMenu menu,
    String draft,
    int caret,
    bool working,
  ) => slashFilter(menu: menu, draft: draft, caret: caret, working: working);

  @override
  BridgeSlashDispatch dispatch(
    BridgeSlashMenu menu,
    String draft,
    bool working,
  ) => slashDispatch(menu: menu, draft: draft, working: working);

  @override
  BridgeSlashAccept? accept(
    BridgeSlashMenu menu,
    String draft,
    String rowName,
    BridgeSlashAcceptKey key,
    bool working,
  ) => slashAccept(
    menu: menu,
    draft: draft,
    rowName: rowName,
    key: key,
    working: working,
  );

  @override
  bool isWorking(BridgeRcActivity activity) =>
      slashIsWorking(activity: activity);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../core/app_error.dart';
import '../../lanes/lane_controller.dart';
import '../../lanes/lane_settings.dart';
import '../../lanes/lane_state.dart';
import '../../lanes/slash_rules.dart';
import '../../providers.dart';
import '../../rc/rc_ui.dart';
import '../../shed/shed_status.dart';
import '../../src/rust/api/dto_lane.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/status_badge.dart';
import '../rc/feed_rows.dart';
import 'lane_settings_sheet.dart';
import 'slash_keys.dart';
import 'slash_menu_panel.dart';

/// **One agent lane, on a phone** (plan 018 §3.12).
///
/// The transcript of an agent session running on a machine (an `opencode` lane
/// today; plan 025 adds craze's), the asks it is blocked on, and the two things
/// a person does about them: answer, or say something. Reached from a machine
/// session row that carries an `agentLane` stamp — and ONLY from such a row,
/// because [laneControllerProvider] refuses a row with no stamp rather than
/// opening a lane that can never connect.
///
/// The layout follows [SessionWatchScreen] deliberately: a lane's rows ARE
/// `RcFeedMessage`s, so the same [RcMessageTile] renders them and a transcript
/// reads the same wherever it came from. What is NEW here is everything below
/// the transcript — the approvals — because an agent lane is the first surface
/// in this app that can answer one.
///
/// ## Nothing here decides anything
///
/// Three rules, each of which is a real bug if it is broken, and each of which
/// this screen keeps by NOT doing the obvious thing:
///
/// * **An option button posts [BridgeLaneAnswer.choice] with the offered id.**
///   Never a [BridgeLaneDecision]: a live gx permission offers FIVE options of
///   which TWO declare `allow_once`, so "the allow-once one" does not name a
///   single option and `lane_option_for` correctly answers `None` for it. The
///   id is opaque and round-tripped; `kind` is read for COLOUR and nothing
///   else.
/// * **A permission with no options renders no allow button.** gx announces
///   every approval twice — first as a placeholder with a null method and no
///   request — so a card that inferred "permission ⇒ allow/deny" would offer to
///   approve something it cannot describe. The placeholder falls to the raw
///   card, which says it is waiting for details and offers only Reject.
/// * **A refusal is state, not an exception.** [LaneController]'s verbs never
///   throw; a refusal lands on [LaneState.composerError] /
///   [LaneState.approvalErrors] / [LaneState.stopError] and renders beside the
///   control that raised it, because `not_accepting` on a cancel means "the
///   turn ended between the render and the tap" and that is only legible next
///   to the button. Whether a composer verb TOOK is never read back off that
///   state, though: the verb answers its own outcome ([LaneVerbOutcome]), and
///   a draft is settled from that — a lane that moved on mid-call keeps
///   nothing on its state, which is not a success.
///
/// ## What the session can do is the SNAPSHOT's (plan 025 §3.7.3)
///
/// Every affordance below is gated on the capabilities the lane's stream last
/// stated ([LaneState.capabilities]), never on the kind and never on a copy
/// taken at open: **Stop** exists only when they say `stop` (a TUI-hosted craze
/// session, every opencode one, has none) and is never one tap — it ends the
/// SESSION, so it asks first; **Cancel** exists only when they say `cancel`,
/// and only while a turn is running; **Interject** only when they say
/// `interject`. And the banner tells a lane that is RECONNECTING on its own
/// (`stale`, not `ended`: a craze lane resuming from its cursor) from one that
/// is over (`ended`) — [laneStaleBannerText].
///
/// **The settings chip** (plan 025 §3.10) rides the AppBar on a session whose
/// capabilities say `settings` — and nowhere else, hidden, never disabled: the
/// current model, effort and fast ([settingsChip]) — the effort being the
/// option the snapshot names ([LaneState.effortOption], the shared core's
/// reading, plan 032 PC14h), never a guess made here — and a tap opens the
/// session's settings sheet ([LaneSettingsSheet]).
///
/// ## The `/` menu (plan 029 §3.5, D17)
///
/// On a session whose capabilities say `slash` and whose view carries a
/// resolved menu ([LaneState.slashMenu]), a `/` draft opens a menu above the
/// composer ([SlashMenuPanel]), and an empty draft offers a `/` button that
/// starts one. The screen only RENDERS the menu and handles keys: what it
/// lists, what a typed token matches, what Enter / Tab / a tap does and when a
/// command is refused are the shared core's ([SlashRules] — P5), and which key
/// does what to the menu on screen is `slash_keys.dart`'s. Send goes through
/// the same dispatch as Enter, so a typed `/help` is refused inline rather than
/// sent as text. Each command runs on the lane's own verb: a rename
/// (`LaneController.setTitle`), a mode (`LaneController.setMode` — the
/// composer's verb, errors in the composer, P7), Stop behind its existing
/// confirm, the model picker (the existing settings sheet), a prompt row as a
/// prompt of its canonical spelling (E8). `/effort` (plan 032 §3.2): bare, it
/// opens the settings sheet as `/model` does; with a level the shared
/// dispatch matched, it is a set of that effort bound to its model
/// (`LaneController.setEffort` — the composer's verb, errors in the composer
/// as a mode's are), sent even at the current level (craze's rule: a dropped
/// no-op could lose a concurrent change), where the sheet's press on its
/// current value sends nothing. The draft's fate after each is §3.5's
/// table, from the verb's own outcome ([LaneVerbOutcome]): cleared on success
/// and when the picker opens; kept on a refusal (said inline), an unknown
/// outcome ("may have applied — check the session"; a call whose lane moved
/// on before it answered is one) and a cancelled Stop — and only for the
/// draft the command was made FROM: each Send / Enter / tap captures the
/// draft with a revision before anything else, a verb whose draft was edited
/// before it was sent is dropped, and an outcome clears (or completes) the
/// box only while that revision still holds, so a newer draft is never erased
/// (its note still shows). One command at a time, guarded before its first
/// await. No menu on the view → the composer is as it always was (every
/// opencode session, D11).
class LaneScreen extends ConsumerStatefulWidget {
  const LaneScreen({
    required this.machine,
    required this.kind,
    required this.slug,
    required this.title,
    super.key,
  });

  /// The machine whose feed owns the SSH connection this lane rides.
  final String machine;

  /// The lane's kind — the row's stamp kind (`opencode`), or `craze` for a
  /// craze row. Part of the lane's address ([LaneRef]): it is what keeps a
  /// craze hostId and a roost tab id spelled alike from sharing a lane.
  final String kind;

  /// The ROW's slug (roost's tab id) — the lane's identity, and deliberately
  /// not the agent session id, which is part of the stamp being reconciled.
  final String slug;

  /// The row's display name, from the machine feed — the header's title until
  /// the lane's LIVE session row has one.
  ///
  /// Since plan 025 the snapshot carries the session row the stream last sent
  /// ([LaneState.session]), and the header reads its title from there once it
  /// is seeded (see [laneHeaderTitle]). This is what renders before that, and
  /// what a row whose session has no title of its own keeps.
  final String title;

  @override
  ConsumerState<LaneScreen> createState() => _LaneScreenState();
}

/// A draft as a command captured it: its text, and the revision it had then
/// (`_LaneScreenState._draftRev`) — what decides whether the command's outcome
/// may still touch the box.
typedef _Draft = ({String text, int rev});

/// What only the screen is left to say for a verb whose lane MOVED ON before
/// it answered ([LaneVerbSuperseded]) — and the agent session it was said
/// for: the session id of the stamp the verb was addressed to. Shown only
/// while the lane is still addressed to that session (`_said`).
typedef _Lost = ({String session, String text});

class _LaneScreenState extends ConsumerState<LaneScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// The composer's own focus: what a completion, a `/` button tap and a kept
  /// draft hand the caret back to.
  final _inputFocus = FocusNode(debugLabel: 'lane-input');

  /// The Interject intent, as a toggle. **Not the send mode** — that is
  /// recomputed from the live state at send time, because a turn can end
  /// between the render that enabled this and the tap that used it.
  bool _interject = false;

  bool _sending = false;

  /// An answer is in flight. Every card's controls go quiet, not just the one
  /// that was tapped: the guard in [_answer] refuses a second answer anyway, so
  /// leaving the others enabled would offer a tap that silently does nothing.
  bool _answering = false;

  /// A Stop is in flight — the confirm's own button, and the header's, go
  /// quiet until the receipt (or the refusal) is back.
  bool _stopping = false;

  /// What the transcript was showing last frame, so a new row scrolls the view
  /// only when the reader was already at the bottom.
  int _renderedRows = -1;
  BigInt? _renderedGeneration;

  // ---- the `/` menu's screen state (plan 029 §3.5) ------------------------

  /// The highlighted row — an index into the open menu's rows. Every reset
  /// puts it on the filter's `start` — the first row that is not dimmed — so
  /// a menu opened mid-turn starts on a row Enter acts on (plan 030 FU8).
  int _highlight = 0;

  /// Bumped on every edit of the draft's text. A command captures the draft
  /// with its revision ([_Draft]) before anything else, and its outcome clears
  /// the draft — or writes a completion — only while the revision is still
  /// that one: a newer draft the person typed meanwhile is never erased or
  /// overwritten (its note, warning or refusal still shows).
  int _draftRev = 0;

  /// A command — a Send, an Enter, a tap on a row — is between its first
  /// decision and its outcome. One at a time, guarded synchronously before
  /// its first await ([_command]): two fast Enters cannot dispatch twice.
  bool _commanding = false;

  /// The token the menu was dismissed for with Esc; the menu stays closed
  /// until the token changes (P9).
  String? _dismissed;

  /// What the last `/` command left to say beside the composer: a refusal
  /// (the draft kept to fix) or a rename's warning (it took, with a caveat).
  /// Gone with the next edit of the draft, and said only while the lane is on
  /// the SESSION it was said for ([_onSession]) — a rename's caveat about
  /// session A is not session B's, whatever stamp the row moves to.
  ({String? session, String text, bool warning})? _note;

  /// What a composer verb said whose lane MOVED ON before it answered
  /// ([LaneVerbSuperseded] — a re-open, or the lane's provider rebuilt and
  /// closed the controller the verb ran on): the request may have reached
  /// craze, so the draft stays, and this screen is the only one left to say
  /// so — the lane has let the answer go. Shown where the lane's own
  /// [LaneState.composerError] is, and lives as that does: until the next
  /// composer verb runs — and only on the SESSION it was said for (a new
  /// stamp on the row is another session, where the lane clears its own
  /// error too; a reconnect to the same one keeps it). Cancel is a composer
  /// verb, and says it here too.
  _Lost? _lost;

  /// What the HEADER's Stop said whose lane moved on before it answered — the
  /// [_lost] of the Stop banner: shown in it while the lane's own
  /// [LaneState.stopError] is null and the lane is still on the session it
  /// was said for, and gone when the header's Stop next runs (as that is).
  _Lost? _stopLost;

  /// The draft as last seen — so an EDIT, not a caret move, clears [_note].
  String _lastDraft = '';

  /// The last filter and what it answered for: re-asked of the shared rules
  /// only when the draft, the caret, the menu or the turn moved — never for a
  /// streamed frame alone (the menu instance is stable while its value is,
  /// [LaneState.slashMenu]).
  ({
    BridgeSlashMenu menu,
    String draft,
    int caret,
    bool working,
    BridgeSlashFilter filter,
  })?
  _filtered;

  BridgeRcActivity? _workingFor;
  bool _workingNow = false;

  LaneRef get _ref =>
      (machine: widget.machine, kind: widget.kind, slug: widget.slug);

  @override
  void initState() {
    super.initState();
    _input.addListener(_onDraft);
  }

  @override
  void dispose() {
    _input.removeListener(_onDraft);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// An EDIT of the draft — not a caret move — moves its revision and clears
  /// what the last command said. (What reads the draft re-renders on its own:
  /// [_dock], under a builder on [_input].)
  void _onDraft() {
    final text = _input.text;
    if (text == _lastDraft) return;
    _lastDraft = text;
    _draftRev++;
    _note = null;
  }

  /// Whether the transcript is parked at the tail. True before the first
  /// layout, which is what lands a freshly-opened lane on its newest row.
  bool get _atBottom =>
      !_scroll.hasClients ||
      _scroll.position.pixels >= _scroll.position.maxScrollExtent - 32;

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// The lane, for a verb or a key — or null when the row has no lane any
  /// more ([readLaneController]): a machine-feed rebuild can leave this screen
  /// up on the last state it drew while the provider now refuses every read,
  /// and an action then has nothing to act on.
  LaneController? _laneController() => readLaneController(ref, _ref);

  /// The shared shape behind every verb the screen runs: guard against a
  /// second tap while one is in flight, run it on the lane, log whatever it
  /// left on the state, and clear the busy flag — on every way out, a throw
  /// included, so a control is never left busy. Answers that error (null:
  /// none, or nothing ran — no lane, nothing to run it on).
  ///
  /// The lane is read ONCE, here, before anything is marked busy, and [run]
  /// gets that instance and reads its error back off it after the await —
  /// never a fresh read, which could resolve to a different lane if the row
  /// was torn down and rebuilt mid-call (or to none at all).
  Future<AppError?> _guarded({
    required bool busy,
    required void Function(bool value) setBusy,
    required String logKey,
    required Future<AppError?> Function(LaneController controller) run,
    void Function()? onSuccess,
  }) async {
    if (busy) return null;
    final controller = _laneController();
    if (controller == null) return null;
    setState(() => setBusy(true));
    try {
      final error = await run(controller);
      // The log line goes out either way — a driver needs the MRESULT even
      // for a verb whose screen has since gone.
      logDriveResult(logKey, ok: error == null, error: error?.message);
      // INSIDE the mounted guard: `_sendText` clears the input, and a
      // disposed `TextEditingController` throws when touched. Anything
      // `onSuccess` does is by definition a change to this widget's own
      // state, so there is nothing for it to do once the widget is gone.
      if (error == null && mounted) onSuccess?.call();
      return error;
    } finally {
      if (mounted) setState(() => setBusy(false));
    }
  }

  /// Send [draft] as a prompt — a draft that is not a command, or any draft
  /// on a session with no menu. Exactly today's send: cleared once the agent
  /// took it ([_clearIfCurrent]), kept on a refusal and on a LOST answer
  /// ([laneSendOutcomeUnknown]) — and on one the lane moved on from before
  /// it answered ([_composerCall]).
  Future<void> _sendText(_Draft draft) async {
    final text = draft.text.trim();
    if (text.isEmpty) return;
    await _composerCall(
      draft,
      busy: _sending,
      setBusy: (v) => _sending = v,
      logKey: 'lane-send',
      verb: (controller) =>
          controller.send(text, mode: _sendMode(controller.state)),
    );
  }

  /// **A composer verb, settled from ITS OWN outcome** ([LaneVerbOutcome],
  /// §3.5's table) — never from the lane's state read back after the await.
  /// A lane that moved on while the call was out (a re-open; the provider
  /// rebuilt and closed the controller it ran on) lands nothing on its state,
  /// and a state that says nothing is not "it took".
  ///
  /// [LaneVerbDone] clears [draft] while it still owns the box
  /// ([_clearIfCurrent]), then [onDone]; a refusal and a lost answer keep it,
  /// said by the lane ([LaneState.composerError]); a superseded call keeps it
  /// too, and is said HERE ([_lost]) — the request may have reached craze.
  /// [_guarded] around it all. Answers the outcome — null when nothing ran
  /// (busy, or no lane to run it on).
  Future<LaneVerbOutcome?> _composerCall(
    _Draft draft, {
    required bool busy,
    required void Function(bool value) setBusy,
    required String logKey,
    required Future<LaneVerbOutcome> Function(LaneController controller) verb,
    void Function(LaneVerbDone done, String session)? onDone,
  }) => _outcomeCall(
    busy: busy,
    setBusy: setBusy,
    logKey: logKey,
    // A new composer verb, as the lane clears its own composer error.
    lost: (lost) => _lost = lost,
    verb: verb,
    // Reached only when the outcome has no error: a [LaneVerbDone].
    onSuccess: (outcome, session) {
      _clearIfCurrent(draft);
      if (outcome case final LaneVerbDone done) onDone?.call(done, session);
    },
  );

  /// **A verb whose own outcome is the screen's to settle** — [_guarded]
  /// around [verb], answering the outcome (null when nothing ran). A
  /// [LaneVerbSuperseded] landed nothing on the lane's state, so this screen
  /// says it, through [lost]: cleared as the verb starts (the lane clears its
  /// own error then too) and set to the outcome's "may have run" wording when
  /// the lane moved on before it answered — tagged with the session the verb
  /// was addressed to ([_Lost]), the stamp's as the verb started. [onSuccess]
  /// runs only for an outcome with no error (a [LaneVerbDone]), while
  /// mounted, with that session.
  Future<LaneVerbOutcome?> _outcomeCall({
    required bool busy,
    required void Function(bool value) setBusy,
    required String logKey,
    required void Function(_Lost? lost) lost,
    required Future<LaneVerbOutcome> Function(LaneController controller) verb,
    void Function(LaneVerbOutcome outcome, String session)? onSuccess,
  }) async {
    LaneVerbOutcome? outcome;
    String? session;
    await _guarded(
      busy: busy,
      setBusy: setBusy,
      logKey: logKey,
      run: (controller) async {
        session = controller.stamp.sessionId;
        setState(() => lost(null));
        final answered = outcome = await verb(controller);
        return answered.error;
      },
      onSuccess: () => onSuccess?.call(outcome!, session!),
    );
    if (outcome case LaneVerbSuperseded(:final error) when mounted) {
      setState(() => lost((session: session!, text: error.message)));
    }
    return outcome;
  }

  /// The agent session the lane is addressed to NOW — its stamp's session
  /// id; null when the row has no lane. What a screen-local note is said for.
  String? _session() => _laneController()?.stamp.sessionId;

  /// Whether the lane is still addressed to [session]: a re-open, a
  /// reconnect, the lane's provider rebuilding, or the same session on a new
  /// port keeps it; a new stamp naming another session does not, and that
  /// session never hears the old one's notes. The lane is read only when
  /// there is a session to compare.
  bool _onSession(String? session) => session != null && session == _session();

  /// [lost]'s words while the lane is still on the session they were said
  /// for ([_onSession]); null otherwise.
  String? _said(_Lost? lost) =>
      lost != null && _onSession(lost.session) ? lost.text : null;

  /// **Recomputed at send time**, from the freshest state — the toggle records
  /// an intent, not a mode. An adapter that cannot interject answers
  /// `not_accepting`, and an interject aimed at an idle session is a refusal
  /// too, so a mode captured when the button was drawn is a mode that can have
  /// expired by the time it is used.
  BridgeSendMode _sendMode(LaneState state) =>
      _interject &&
          (state.capabilities?.interject ?? false) &&
          state.activity == BridgeRcActivity.working
      ? BridgeSendMode.interject
      : BridgeSendMode.queue;

  /// Cancel the turn — a composer verb: a refusal is the lane's to say
  /// ([LaneState.composerError]), and a cancel whose lane moved on before it
  /// answered is this screen's ([_lost]) — it may have reached craze.
  Future<void> _cancel() => _outcomeCall(
    busy: _sending,
    setBusy: (v) => _sending = v,
    logKey: 'lane-cancel',
    lost: (lost) => _lost = lost,
    verb: (controller) => controller.cancel(),
  );

  /// **Stop the SESSION — after asking.** Stop ends the agent, not just this
  /// transcript, so it is never one tap: a dialog says what it does and
  /// offers Keep. The stop's completion is the lane ending (`session_closed`,
  /// the banner's); a refusal or a lost receipt lands beside the header.
  ///
  /// **The answer is checked against the lane as it is AFTER the dialog**, not
  /// as it was when the dialog opened: the dialog can sit open for as long as
  /// the person likes, and meanwhile another client may stop the session (the
  /// lane ends) or the session may stop offering `stop` (a new incarnation's
  /// capabilities). Either way a "Stop session" tap is moot, and nothing is
  /// sent ([laneStopOffered], the same rule the header's button reads).
  ///
  /// [draft]: the stop is `/exit`'s, made from that draft, and its outcome is
  /// the composer's COMMAND lifecycle (§3.5, the desktop's `slashVerb`), not
  /// the header's: a stop that goes through clears the draft (only while it
  /// is still the one in the box); a refusal keeps it with craze's words, and
  /// a lost receipt keeps it with "may have applied — check the session" —
  /// both in the composer ([LaneController.stop]'s `command`); Keep and a
  /// moot answer keep it with nothing said. A draft changed while the dialog
  /// was up calls the stop off.
  Future<void> _confirmStop({_Draft? draft}) async {
    if (_stopping) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('lane-stop-confirm'),
        title: const Text('Stop this session?'),
        content: const Text('The agent ends; the transcript stays.'),
        actions: [
          TextButton(
            key: const ValueKey('lane-stop-keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('lane-stop-session'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.shed.errBg,
              foregroundColor: context.shed.errFg,
            ),
            child: const Text('Stop session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // A row that is gone (null) has nothing to stop.
    final live = _live();
    if (live == null || !laneStopOffered(live)) return;
    if (draft == null) {
      // The header's Stop: a refusal or a lost receipt is the lane's banner
      // ([LaneState.stopError]); a stop whose lane moved on before it
      // answered is this screen's ([_stopLost]), in the same banner.
      await _outcomeCall(
        busy: _stopping,
        setBusy: (v) => _stopping = v,
        logKey: 'lane-stop',
        lost: (lost) => _stopLost = lost,
        verb: (controller) => controller.stop(),
      );
      return;
    }
    if (!_current(draft)) return;
    await _composerCall(
      draft,
      busy: _stopping,
      setBusy: (v) => _stopping = v,
      logKey: 'lane-stop',
      verb: (controller) => controller.stop(command: true),
    );
  }

  Future<void> _answer(String approvalId, BridgeLaneAnswer answer) => _guarded(
    busy: _answering,
    setBusy: (v) => _answering = v,
    logKey: 'lane-answer',
    run: (controller) async {
      await controller.answer(approvalId, answer);
      return controller.state.approvalErrors[approvalId];
    },
  );

  // ---- the `/` menu (plan 029 §3.5) ----------------------------------------

  SlashRules get _rules => ref.read(slashRulesProvider);

  /// The lane's state as it is NOW, for a key or a tap — the freshest the
  /// controller holds, which a frame may not have drawn yet. Null once the
  /// row is gone ([_laneController]).
  LaneState? _live() => _laneController()?.state;

  /// The session's `/` menu, when it offers one (D11): its capabilities say
  /// `slash` AND its view carries a resolved menu. Null — no menu, no `/`
  /// button, no note — otherwise: every opencode session, a craze session
  /// whose catalog has not arrived (or was truncated away), an older craze.
  static BridgeSlashMenu? _menuOf(LaneState? state) =>
      (state?.capabilities?.slash ?? false) ? state!.slashMenu : null;

  /// Whether a turn is running, by the shared rule (P23) — asked again only
  /// when the activity moves.
  bool _working(BridgeRcActivity activity) {
    if (activity != _workingFor) {
      _workingFor = activity;
      _workingNow = _rules.isWorking(activity);
    }
    return _workingNow;
  }

  bool _composerEnabled(LaneState state) => !state.abandoned && !_sending;

  /// What the shared filter answers for the draft and caret as they stand,
  /// on [state]'s menu — null when the session has no menu. Synchronous, so a
  /// key always acts on the draft as it is now (the desktop has to re-read a
  /// stale answer; this one cannot be stale). A new answer that lists
  /// something else ([_sameEntries]), or one from a new catalog — the menu
  /// changed by value ([sameSlashMenu]), whatever its rows are called — puts
  /// the highlight back on the answer's `start`: its first row that is not
  /// dimmed (P9, plan 030 FU8). A working flip alone lists the same entries,
  /// so it moves no highlight.
  BridgeSlashFilter? _filterNow(LaneState state) {
    final menu = _menuOf(state);
    if (menu == null) return null;
    final value = _input.value;
    final caret = slashCaret(value);
    final working = _working(state.activity);
    final last = _filtered;
    if (last != null &&
        identical(last.menu, menu) &&
        last.draft == value.text &&
        last.caret == caret &&
        last.working == working) {
      return last.filter;
    }
    final filter = _rules.filter(menu, value.text, caret, working);
    // A new catalog — the menu changed BY VALUE, even with every row's name
    // the same (`plan` now behind another mode id) — or a new filter answer.
    // The controller keeps one instance while the menu is equal
    // ([LaneState.slashMenu]), so the common case is one identity check.
    if (last == null ||
        !sameSlashMenu(last.menu, menu) ||
        !_sameEntries(last.filter, filter)) {
      _highlight = filter.start;
    }
    _filtered = (
      menu: menu,
      draft: value.text,
      caret: caret,
      working: working,
      filter: filter,
    );
    return filter;
  }

  /// Whether two filter answers list the same thing — the token AND the
  /// rows' names, so `/r` → `/re` differs even when the rows are the same
  /// ones; a row's dimming alone does not.
  static bool _sameEntries(BridgeSlashFilter a, BridgeSlashFilter b) {
    if (a.token != b.token || a.rows.length != b.rows.length) return false;
    for (var i = 0; i < a.rows.length; i++) {
      if (a.rows[i].row.name != b.rows[i].row.name) return false;
    }
    return true;
  }

  /// The menu as it stands for [state]: the filter, and the two things only
  /// the screen keeps (P9) —
  ///
  /// * an Esc dismissal ends once a filter reports a DIFFERENT token; no
  ///   filter at all (the session's menu gone for a moment — a reseed, a
  ///   catalog on its way back) changes nothing;
  /// * the highlight goes back to the filter's `start` (its first live row)
  ///   on every filter or catalog change ([_filterNow], [_sameEntries],
  ///   [sameSlashMenu]); a caret move inside the token, a working flip, or a
  ///   frame that changes none of them, keeps it.
  ///
  /// `up`: the panel is on screen.
  ({BridgeSlashMenu? menu, BridgeSlashFilter? filter, bool up}) _slashView(
    LaneState state,
  ) {
    final filter = _filterNow(state);
    if (filter != null) {
      _dismissed = dismissalAfter(_dismissed, filter.token);
    }
    return (
      menu: _menuOf(state),
      filter: filter,
      up: slashMenuUp(filter, _dismissed),
    );
  }

  /// **The composer's keys** (`slash_keys.dart`'s table, P9) — every hardware
  /// key the field sees, before the field does. An IME composition owns every
  /// key; with the menu up, Enter / Tab accept, Esc dismisses (and goes no
  /// further), ↑/↓ move the highlight; Enter with no menu up sends; Shift+Enter
  /// is a newline.
  KeyEventResult _onComposerKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final state = _live();
    if (state == null || !_composerEnabled(state)) {
      return KeyEventResult.ignored;
    }
    final view = _slashView(state);
    final action = composerKey(
      key: event.logicalKey,
      shift: HardwareKeyboard.instance.isShiftPressed,
      composing: isComposing(_input.value),
      menuUp: view.up,
    );
    // A held key repeats the highlight and the newline, never a send.
    final once = event is KeyDownEvent;
    final filter = view.filter;
    switch (action) {
      case ComposerKey.none:
        return KeyEventResult.ignored;
      case ComposerKey.newline:
        _insertNewline();
      case ComposerKey.send:
        if (once) unawaited(_submit());
      case ComposerKey.accept:
        if (once) _acceptHighlighted(filter!, BridgeSlashAcceptKey.enter);
      case ComposerKey.complete:
        if (once) _acceptHighlighted(filter!, BridgeSlashAcceptKey.tab);
      case ComposerKey.dismiss:
        // One Esc closes one thing: the menu. Handled, so nothing an Esc
        // handler further out would close sees it.
        if (once) setState(() => _dismissed = filter!.token);
      case ComposerKey.up:
      case ComposerKey.down:
        setState(
          () => _highlight = moveHighlight(
            _highlight,
            action == ComposerKey.up ? -1 : 1,
            filter!.rows.length,
          ),
        );
    }
    return KeyEventResult.handled;
  }

  /// The field's editing-complete step, run on a submit just BEFORE
  /// [_onSubmitted]: the composition the IME held is COMMITTED — its
  /// composing range cleared — and the focus STAYS (a completion, `/re` →
  /// `/rename `, is typed on; a refusal is fixed in place). Flutter's own
  /// step commits and then drops the focus; overriding it without the commit
  /// left a refused or kept draft "composing" with no IME update coming to
  /// end it, and every menu key ignored after it (P9's IME guard).
  void _completeComposition() => _input.clearComposing();

  /// The field's submit action — the soft keyboard's Send (and any platform
  /// that delivers Enter as one): the SAME rule as a hardware Enter. No IME
  /// guard here: the Send ends the composition ([_completeComposition]).
  void _onSubmitted() {
    final state = _live();
    if (state == null || !_composerEnabled(state)) return;
    final view = _slashView(state);
    if (view.up) {
      _acceptHighlighted(view.filter!, BridgeSlashAcceptKey.enter);
    } else {
      unawaited(_submit());
    }
  }

  /// Shift+Enter: a newline at the caret (replacing any selection).
  void _insertNewline() {
    final value = _input.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _input.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, '\n'),
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  /// The `/` button (P24): an empty draft becomes `/`, the caret after it, the
  /// field focused — which opens the menu on every row.
  void _insertSlash() {
    _input.value = const TextEditingValue(
      text: '/',
      selection: TextSelection.collapsed(offset: 1),
    );
    _inputFocus.requestFocus();
  }

  /// Enter or Tab with the menu up: the highlighted row. [_slashView] resets
  /// the highlight on every change of rows, so it is inside them — clamped
  /// anyway, so no index can outlive the rows it was taken on.
  void _acceptHighlighted(BridgeSlashFilter filter, BridgeSlashAcceptKey key) {
    final rows = filter.rows;
    if (rows.isEmpty) return;
    _acceptRow(rows[_highlight.clamp(0, rows.length - 1)].row.name, key);
  }

  /// The draft in the box now, with its revision.
  _Draft _capture() => (text: _input.text, rev: _draftRev);

  /// Whether [draft] is still the one in the box.
  bool _current(_Draft draft) => draft.rev == _draftRev;

  /// Clear [draft] — only while it is still the one in the box.
  void _clearIfCurrent(_Draft draft) {
    if (_current(draft)) _input.clear();
  }

  /// **One command at a time** (Send, Enter, a tap on a row): refused while
  /// another is between its first decision and its outcome — checked and set
  /// synchronously, before [body]'s first await — and [body] gets the draft it
  /// owns, captured here.
  Future<void> _command(Future<void> Function(_Draft draft) body) async {
    if (_commanding || _sending) return;
    _commanding = true;
    try {
      await body(_capture());
    } finally {
      _commanding = false;
    }
  }

  /// Accept the row [name] with [key] — the shared rule decides whether that
  /// completes the draft, runs the row, or refuses it (P9, §3.5's select).
  void _acceptRow(String name, BridgeSlashAcceptKey key) => unawaited(
    _command((draft) async {
      final state = _live();
      final menu = _menuOf(state);
      if (state == null || menu == null || !_composerEnabled(state)) return;
      final answer = _rules.accept(
        menu,
        draft.text,
        name,
        key,
        _working(state.activity),
      );
      switch (answer) {
        case null:
          // The menu moved under the highlight: the next frame re-filters.
          return;
        case BridgeSlashAccept_Complete(draft: final completed, :final caret):
          if (!_current(draft)) return;
          _input.value = TextEditingValue(
            text: completed,
            selection: TextSelection.collapsed(offset: caret),
          );
          setState(() => _note = null);
          _inputFocus.requestFocus();
        case BridgeSlashAccept_Dispatch(:final dispatch):
          await _runDispatch(dispatch, draft);
      }
    }),
  );

  /// **Send the draft** — the Send button, and Enter with no menu up: through
  /// the shared dispatch when the session has a menu (the guard serves Send
  /// as it serves Enter, P5: a typed `/help` is refused here, never sent as
  /// text), as text — exactly today's send — when it has none. A row whose
  /// lane is gone has nothing to send to: nothing happens.
  Future<void> _submit() => _command((draft) async {
    final text = draft.text.trim();
    if (text.isEmpty) return;
    final state = _live();
    if (state == null) return;
    final menu = _menuOf(state);
    if (menu == null) return _sendText(draft);
    return _runDispatch(
      _rules.dispatch(menu, draft.text, _working(state.activity)),
      draft,
    );
  });

  /// Act on what the shared dispatch answered for [draft] — Send's, Enter's,
  /// or a chosen row's — by §3.5's table. A [draft] no longer in the box is
  /// dropped, silently.
  Future<void> _runDispatch(BridgeSlashDispatch dispatch, _Draft draft) async {
    if (!_current(draft)) return;
    switch (dispatch) {
      case BridgeSlashDispatch_NotCommand():
        return _sendText(draft);
      case BridgeSlashDispatch_Refuse(:final reason):
        // Refused HERE, nothing sent: the reason inline, the draft kept.
        logDriveResult('lane-slash', ok: false, error: reason);
        setState(
          () => _note = (session: _session(), text: reason, warning: false),
        );
      case BridgeSlashDispatch_Prompt(:final text):
        // A prompt row (`/research deep dive`): its CANONICAL text (E8) as a
        // prompt — queued during a turn like any prompt, an interject when the
        // toggle says so.
        return _commandVerb(
          draft,
          logKey: 'lane-send',
          verb: (c) => c.send(text, mode: _sendMode(c.state), command: true),
        );
      case BridgeSlashDispatch_Run(:final action, :final arg):
        switch (action) {
          case BridgeSlashAction_SetTitle():
            return _rename(arg ?? '', draft);
          case BridgeSlashAction_SetMode(:final id):
            // From the COMPOSER (P7): re-selecting the current mode sends.
            return _commandVerb(
              draft,
              logKey: 'lane-mode',
              verb: (c) => c.setMode(BridgeLaneSettingChange.mode(id: id)),
            );
          case BridgeSlashAction_Stop():
            return _stopFromComposer(draft);
          case BridgeSlashAction_ModelPicker():
          case BridgeSlashAction_EffortPicker():
            // `/model`, bare `/effort`: the settings sheet, whose model list
            // and effort row are those pickers.
            return _openPicker(draft);
          case BridgeSlashAction_SetEffort(:final change):
            // `/effort <level>` (plan 032 §3.2): the composer's verb, its
            // errors here as a mode's — a `stale_model` (the model moved
            // since the menu) included. Always sent, the current level too.
            return _commandVerb(
              draft,
              logKey: 'lane-effort',
              verb: (c) => c.setEffort(change),
            );
          case BridgeSlashAction_Prompt():
            // Never answered as a Run: a prompt row's answer is Prompt.
            return;
        }
    }
  }

  /// A `/` command run on one of the composer's verbs (a prompt row, a
  /// rename, a mode): the last note cleared, then [_composerCall] on
  /// `_sending` — settled from the verb's own outcome: its error on the
  /// composer (a lost answer, or one the lane moved on from, in the command
  /// wording, [laneCommandOutcomeUnknown]), and on success [draft] cleared
  /// ([_clearIfCurrent]), then [onDone]. The field is disabled while the verb
  /// runs, which drops its focus, so a draft kept (to fix, or to check)
  /// hands the caret back.
  Future<void> _commandVerb(
    _Draft draft, {
    required String logKey,
    required Future<LaneVerbOutcome> Function(LaneController controller) verb,
    void Function(LaneVerbDone done, String session)? onDone,
  }) async {
    setState(() => _note = null);
    final hadFocus = _inputFocus.hasFocus;
    final outcome = await _composerCall(
      draft,
      busy: _sending,
      setBusy: (v) => _sending = v,
      logKey: logKey,
      verb: verb,
      onDone: onDone,
    );
    if (outcome?.error != null && hadFocus && mounted) {
      // After the frame that re-enables the field: a disabled one takes no
      // focus.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  /// `/rename <title>` (the header shows the new title once craze's delta
  /// says so, P19). A rename that took but craze could not record clears the
  /// draft too, and shows the warning.
  Future<void> _rename(String title, _Draft draft) => _commandVerb(
    draft,
    logKey: 'lane-rename',
    verb: (c) => c.setTitle(title),
    // After the clear, whose edit wipes the note — and shown whether or not
    // the draft was still this one: the rename took.
    onDone: (done, session) {
      if (done.warning case final text?) {
        _note = (session: session, text: text, warning: true);
      }
    },
  );

  /// `/exit`: the session's Stop, behind the SAME confirm the header's button
  /// opens ([_confirmStop]) — never one key — with the outcome settled as a
  /// COMMAND's: Keep sends nothing and keeps the draft; a stop that goes
  /// through clears it; a refused or lost one keeps it and is said in the
  /// composer, in the command wording (the desktop's `slashVerb`). A draft
  /// changed while the dialog was up calls the stop off.
  Future<void> _stopFromComposer(_Draft draft) {
    setState(() => _note = null);
    return _confirmStop(draft: draft);
  }

  /// `/model`, and a bare `/effort`: the model picker and the effort picker
  /// ARE the session's settings sheet (X2 — no inline model; the effort row is
  /// the option the menu was resolved on): the draft clears and the sheet
  /// opens on this lane.
  void _openPicker(_Draft draft) {
    _clearIfCurrent(draft);
    setState(() => _note = null);
    unawaited(showLaneSettingsSheet(context, _ref));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(laneStateProvider(_ref));
    // A lane whose row vanished takes its provider down with it — an honest
    // sentence, not a screen frozen on the last transcript it saw.
    final state = async.value;
    if (state == null) {
      return _shell(
        state: null,
        child: async.hasError
            ? _centered(
                'lane-unavailable',
                'This lane is gone: ${laneFailureText(async.error!)}',
              )
            : const Center(
                key: ValueKey('lane-loading'),
                child: CircularProgressIndicator(),
              ),
      );
    }

    _noteRows(state);

    // Built once per frame of the LANE, outside the draft's builder below,
    // and handed into it as they are: a keystroke never rebuilds them.
    final transcript = _transcript(context, state);
    final approvals = state.approvals.isEmpty
        ? null
        : _approvalList(context, state);
    return _shell(
      state: state,
      child: Column(
        children: [
          _statusStrip(context, state),
          // The provider itself failed AFTER handing over a state — the row's
          // machine record changed and the controller cannot be rebuilt. The
          // rows below are the last thing anyone read; say so rather than
          // rendering them as if they were live.
          if (async.hasError)
            _banner(
              context,
              'lane-unavailable',
              ShedStatusTone.err,
              'This lane is gone: ${laneFailureText(async.error!)}',
            ),
          if (state.stale != null) _staleBanner(context, state),
          // The lane's refusal or lost receipt — or, for a header Stop whose
          // lane moved on before it answered, what only this screen is left
          // to say ([_stopLost]), on the session it was said for.
          if (state.stopError?.message ?? _said(_stopLost) case final message?)
            _banner(context, 'lane-stop-error', ShedStatusTone.err, message),
          if (laneNoteText(state) case final note?) _noteBanner(context, note),
          // Only the `/` menu and the composer read the draft: a keystroke
          // or a caret move rebuilds them, never the transcript.
          Expanded(
            child: ListenableBuilder(
              listenable: _input,
              builder: (context, _) => _dock(
                context,
                state,
                transcript: transcript,
                approvals: approvals,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The pending approvals, scrolling — capped at 45 % of the viewport: the
  /// composer and some transcript must stay visible, and five gx options
  /// plus a question form is taller than a phone.
  Widget _approvalList(BuildContext context, LaneState state) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
    ),
    child: SingleChildScrollView(
      key: const ValueKey('lane-approvals'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in state.approvals) _approvalCard(context, state, a),
        ],
      ),
    ),
  );

  Widget _shell({required LaneState? state, required Widget child}) => Scaffold(
    key: const ValueKey('lane-screen'),
    appBar: AppBar(
      // Stop exists only when the session's streamed capabilities offer it,
      // and goes quiet once the lane is over — there is nothing left to stop.
      actions: [
        if (state != null && (state.capabilities?.stop ?? false))
          IconButton(
            key: const ValueKey('lane-stop'),
            tooltip: 'Stop the session',
            color: context.shed.errFg,
            icon: const Icon(Icons.dangerous_outlined),
            onPressed: !_stopping && laneStopOffered(state)
                ? _confirmStop
                : null,
          ),
      ],
      // The settings chip, under the title so a long model name never
      // squeezes it: only where the session's capabilities say `settings`.
      bottom: state != null && settingsOffered(state.capabilities)
          ? _settingsChip(state)
          : null,
      // Two lines: the session's name is what you came looking for — from the
      // LIVE session row once the stream has sent one (plan 025 §3.6.5) — and
      // the slug (a craze hostId, a roost tab id) rides under it, small, for
      // telling two alike-named sessions apart.
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            laneHeaderTitle(state?.session, widget.title),
            key: const ValueKey('lane-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17),
          ),
          Text(
            widget.slug,
            key: const ValueKey('lane-slug'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(fontSize: 11.5, color: context.shed.fg3),
          ),
        ],
      ),
    ),
    body: child,
  );

  /// The AppBar's settings chip: `<model> · <effort> · fast` from the current
  /// values ([settingsChip]), "Settings" before the first `Settings` arrives.
  /// A tap opens the sheet, which reads this same lane.
  PreferredSizeWidget _settingsChip(LaneState state) => PreferredSize(
    preferredSize: const Size.fromHeight(40),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: ActionChip(
          key: const ValueKey('lane-settings-chip'),
          avatar: Icon(Icons.tune, size: 16, color: context.shed.accent),
          label: Text(
            settingsChip(state.settings ?? noSettings, state.effortOption),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sansStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.shed.accent,
            ),
          ),
          backgroundColor: context.shed.accentSoft,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          tooltip: 'Session settings: model, options, mode',
          onPressed: () => showLaneSettingsSheet(context, _ref),
        ),
      ),
    ),
  );

  Widget _centered(String key, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        key: ValueKey(key),
        textAlign: TextAlign.center,
        style: sansStyle(fontSize: 14, color: context.shed.fg2),
      ),
    ),
  );

  /// Remember the transcript's shape, and scroll only if the reader was parked
  /// at the tail. Read BEFORE this frame lays out, which is why it happens in
  /// build: the controller still holds the previous frame's offsets here.
  void _noteRows(LaneState state) {
    if (state.rows.length == _renderedRows &&
        state.generation == _renderedGeneration) {
      return;
    }
    final wasAtBottom = _atBottom;
    _renderedRows = state.rows.length;
    _renderedGeneration = state.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && wasAtBottom) _scrollToBottom();
    });
  }

  /// `departing=t`: a craze lane whose row left, waiting out its grace on its
  /// own connection ([LaneState.departing]) — nothing on screen says so.
  /// `slash=<shown>/<open>`: how many rows the session's menu shows (`-` — no
  /// menu at all), and how many the panel lists right now (0 — closed).
  void _log(LaneState state, BridgeSlashMenu? menu, int open) {
    // No lane (the row's lane stamp went away between the snapshot and this
    // line): the state is still worth reporting; the session id is not
    // knowable.
    final session = _laneController()?.stamp.sessionId ?? '-';
    logDriveState(
      'screen=lane machine=${widget.machine} session=$session '
      'generation=${state.generation} stale=${state.stale ?? '-'} '
      'approvals=${state.approvals.length} activity=${state.activity.wire} '
      'departing=${state.departing ? 't' : 'f'} '
      'slash=${menu == null ? '-/-' : '${menu.rows.length}/$open'}',
    );
  }

  // ---- header --------------------------------------------------------------

  /// The activity strip, in the SHARED activity colours (`rcActivityDisplay`,
  /// the same mapping `activityOf` feeds on a session card) — a lane row and an
  /// RC row must never disagree about what "working" looks like.
  ///
  /// A lane has no lifecycle dimension of its own, so there is no
  /// lifecycle-trumps-activity gate to apply here: `stale` is the lane's answer
  /// to "is this current", and it has its own banner.
  ///
  /// The session's permission posture rides here too, from the LIVE row
  /// (plan 025 §3.6.5): a session the craze create sheet started runs
  /// `bypass`, and this is where that consequence is visible. A row that
  /// states no posture (every opencode row) renders nothing for it.
  Widget _statusStrip(BuildContext context, LaneState state) {
    final c = context.shed;
    final display = rcActivityDisplay(state.activity);
    final permission = lanePermissionLine(state.session?.permissionMode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (display != null)
            StatusBadge(
              key: const ValueKey('lane-activity'),
              tone: display.tone,
              label: display.label,
              pulse: display.pulse,
            )
          else
            Text(
              'activity unknown',
              key: const ValueKey('lane-activity-unknown'),
              style: monoStyle(fontSize: 11, color: c.fg3),
            ),
          const Spacer(),
          if (permission != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  permission,
                  key: const ValueKey('lane-permission'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sansStyle(fontSize: 11.5, color: c.fg2),
                ),
              ),
            ),
          if (state.capabilities?.kind case final kind?)
            Text(kind, style: monoStyle(fontSize: 11, color: c.fg3)),
        ],
      ),
    );
  }

  /// The transport is gone and these rows are the last complete generation.
  /// **With the reason** — "the machine is asleep" and "the agent restarted"
  /// are different problems, and flattening them to "disconnected" throws away
  /// the only actionable part — and with WHICH kind of gone it is
  /// ([laneStaleBannerText]): reconnecting on its own, or over.
  Widget _staleBanner(BuildContext context, LaneState state) => _banner(
    context,
    'lane-stale',
    ShedStatusTone.warn,
    laneStaleBannerText(state.stale!, ended: state.ended),
  );

  Widget _noteBanner(BuildContext context, String text) =>
      _banner(context, 'lane-note', ShedStatusTone.warn, text);

  Widget _banner(
    BuildContext context,
    String key,
    ShedStatusTone tone,
    String text,
  ) {
    final c = context.shed;
    return Container(
      key: ValueKey(key),
      width: double.infinity,
      color: c.toneBg(tone),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(
        text,
        style: monoStyle(
          fontSize: 12,
          color: c.toneFg(tone),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---- transcript ---------------------------------------------------------

  Widget _transcript(BuildContext context, LaneState state) {
    if (state.rows.isEmpty) {
      return _centered(
        'lane-empty',
        state.abandoned ? 'Nothing was read from this lane' : 'No messages yet',
      );
    }
    return ListView.builder(
      key: const ValueKey('lane-list'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: state.rows.length,
      itemBuilder: (context, i) {
        final msg = state.rows[i];
        // The SAME tile the watch screen renders — a lane's rows are
        // `RcFeedMessage`s, so there is one transcript styling in this app.
        return RcMessageTile(key: ValueKey('lane-msg-${msg.seq}'), msg: msg);
      },
    );
  }

  // ---- approvals ----------------------------------------------------------

  /// **Branch on `kind`, and then on whether there is anything to offer.**
  ///
  /// The second half is the one that matters: `kind` alone would render a gx
  /// placeholder permission — announced with a null method and no options — as
  /// an answerable allow/deny, which is a button that approves something the
  /// screen cannot describe.
  Widget _approvalCard(
    BuildContext context,
    LaneState state,
    BridgeLaneApproval approval,
  ) {
    final busy = _answering;
    final error = state.approvalErrors[approval.id];
    final kind = approval.kind;
    final offersOptions =
        (kind is BridgeLaneApprovalKind_Permission ||
            kind is BridgeLaneApprovalKind_PlanApproval) &&
        approval.options.isNotEmpty;

    if (offersOptions) {
      return _ApprovalShell(
        approval: approval,
        error: error,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in approval.options)
              _OptionButton(
                key: ValueKey('lane-option-${option.id}'),
                option: option,
                onPressed: busy
                    ? null
                    // The OFFERED ID, round-tripped. Never a decision: two of
                    // gx's five options declare `allow_once`, so no decision
                    // names one of them.
                    : () => _answer(
                        approval.id,
                        BridgeLaneAnswer.choice(optionId: option.id),
                      ),
              ),
          ],
        ),
      );
    }

    if (kind is BridgeLaneApprovalKind_Question &&
        approval.questions.isNotEmpty) {
      return _ApprovalShell(
        approval: approval,
        error: error,
        child: _QuestionForm(
          // Keyed by approval id so a new ask gets a fresh form rather than
          // inheriting the previous one's selections and typed text.
          key: ValueKey('lane-question-${approval.id}'),
          questions: approval.questions,
          busy: busy,
          onAnswer: (answer) => _answer(approval.id, answer),
        ),
      );
    }

    return _ApprovalShell(
      approval: approval,
      error: error,
      child: _RawApproval(
        approval: approval,
        busy: busy,
        onReject: () => _answer(approval.id, const BridgeLaneAnswer.reject()),
      ),
    );
  }

  // ---- composer -----------------------------------------------------------

  /// **Everything under the banners** — the [transcript], the [approvals],
  /// the `/` menu and the composer — and the MSTATE line (its `slash=` moves
  /// with the draft). The menu shows above the composer, only on a session
  /// whose view carries one, only while the shared filter says it is open,
  /// and not once Esc dismissed it for this token.
  ///
  /// **The composer is never pushed off the screen** by what sits above it:
  /// it is laid out first, and the approvals and the menu take only what is
  /// left of the body — the Scaffold's body is already what the keyboard,
  /// the header and the banners left — each also within its own share of the
  /// viewport (45 %, 40 %: P24), and each scrolling inside whatever it gets.
  /// With both up, neither takes more than half of what is left, so a long
  /// menu never hides the approvals entirely, nor they it. The transcript
  /// takes the rest, down to nothing.
  Widget _dock(
    BuildContext context,
    LaneState state, {
    required Widget transcript,
    required Widget? approvals,
  }) {
    final slash = _slashView(state);
    _log(state, slash.menu, slash.up ? slash.filter!.rows.length : 0);
    final panel = slash.up
        ? SlashMenuPanel(
            rows: slash.filter!.rows,
            highlight: _highlight,
            onPick: (name) => _acceptRow(name, BridgeSlashAcceptKey.pick),
          )
        : null;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, room) {
              final share = approvals != null && panel != null
                  ? room.maxHeight / 2
                  : room.maxHeight;
              return Column(
                children: [
                  Expanded(child: transcript),
                  // Keyed: one coming or going must not remount the other.
                  if (approvals != null)
                    ConstrainedBox(
                      key: const ValueKey('lane-dock-approvals'),
                      constraints: BoxConstraints(maxHeight: share),
                      child: approvals,
                    ),
                  if (panel != null)
                    ConstrainedBox(
                      key: const ValueKey('lane-dock-slash'),
                      constraints: BoxConstraints(maxHeight: share),
                      child: panel,
                    ),
                ],
              );
            },
          ),
        ),
        _composer(context, state, menu: slash.menu),
      ],
    );
  }

  /// [menu]: the session's `/` menu ([_menuOf]) — the `/` button's gate, with
  /// rows and an EMPTY draft (P24), and the note's: no menu, no note (D11).
  Widget _composer(
    BuildContext context,
    LaneState state, {
    required BridgeSlashMenu? menu,
  }) {
    final offersMenu = menu?.rows.isNotEmpty ?? false;
    final c = context.shed;
    final working = state.activity == BridgeRcActivity.working;
    final canInterject = state.capabilities?.interject ?? false;
    final canCancel = laneCancelOffered(state.capabilities, state.activity);
    final enabled = _composerEnabled(state);
    // The lane's own refusal or lost answer — or, for a verb whose lane moved
    // on before it answered, what only this screen is left to say ([_lost]).
    final error = state.composerError?.message ?? _said(_lost);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canInterject || canCancel)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    // Rendered only when the ADAPTER advertises it (opencode
                    // answers false and never gets one), and enabled only
                    // while a turn is actually running — an interject with
                    // nothing to interject is a refusal.
                    if (canInterject)
                      FilterChip(
                        key: const ValueKey('lane-interject'),
                        label: const Text('Interject'),
                        selected: _interject,
                        onSelected: working && enabled
                            ? (v) => setState(() => _interject = v)
                            : null,
                      ),
                    const Spacer(),
                    // Offered only when the session's capabilities say
                    // `cancel`, and only while a turn is running
                    // ([laneCancelOffered]) — a button whose only outcome is
                    // a refusal is worse than none.
                    if (canCancel)
                      OutlinedButton.icon(
                        key: const ValueKey('lane-cancel'),
                        onPressed: enabled ? _cancel : null,
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: const Text('Cancel'),
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The `/` button (P24): only on a session with a menu, and
                // only on an EMPTY draft — it starts a command, it never
                // edits one. Gone on an ABANDONED lane (nothing can run
                // there), not on an ended one: `ended` stays set through a
                // transient re-open, and the button would blink while Send
                // stays enabled (plan 030 FU9). Disabled only while sending.
                if (offersMenu && _input.text.isEmpty && !state.abandoned)
                  IconButton(
                    key: const ValueKey('lane-slash-button'),
                    tooltip: 'Commands',
                    onPressed: enabled ? _insertSlash : null,
                    icon: Text(
                      '/',
                      style: monoStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: enabled ? c.accent : c.fg3,
                      ),
                    ),
                  ),
                Expanded(
                  // Keyed: the `/` button coming or going beside it must not
                  // remount the field (and drop its editing state).
                  key: const ValueKey('lane-input-slot'),
                  // Every hardware key reaches the composer's own table
                  // first (`_onComposerKey`); what it does not take goes on
                  // to the field as it always did.
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onComposerKey,
                    child: TextField(
                      key: const ValueKey('lane-input'),
                      controller: _input,
                      focusNode: _inputFocus,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _onSubmitted(),
                      // The caret STAYS on a submit, the composition
                      // committed: a completion (`/re` → `/rename `) is typed
                      // on, and a refusal is fixed in place. (A verb that
                      // runs disables the field, which drops it anyway.)
                      onEditingComplete: _completeComposition,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: offersMenu
                            ? 'What should it do next? / for commands'
                            : 'What should it do next?',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : IconButton.filled(
                        key: const ValueKey('lane-send'),
                        onPressed: enabled ? _submit : null,
                        icon: const Icon(Icons.send, size: 20),
                        tooltip: 'Send',
                      ),
              ],
            ),
            // What a `/` command left to say: a refusal (the draft kept to
            // fix) or a rename that took with a caveat — said only while the
            // session offers the menu it was said against (no catalog, or no
            // `slash`, no note: D11), and only on the session it was said for.
            if ((menu != null && _onSession(_note?.session) ? _note : null)
                case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  note.text,
                  key: ValueKey(
                    note.warning ? 'lane-slash-warning' : 'lane-slash-refusal',
                  ),
                  style: sansStyle(
                    fontSize: 12,
                    color: note.warning ? c.warnFg : c.errFg,
                  ),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  key: const ValueKey('lane-composer-error'),
                  style: sansStyle(fontSize: 12, color: c.errFg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The header's title: the LIVE session row's, once the stream has sent one
/// with a title, and the machine feed's row name until then.
///
/// **The live row, not the one the lane was opened from** (plan 025 §3.6.5):
/// a session opened the moment it was created was opened from the create's
/// own row, and only the stream's row carries what the session says about
/// itself now. A live row with an EMPTY title falls back too — an empty
/// subtitle says less than the row's own name.
@visibleForTesting
String laneHeaderTitle(BridgeLaneSession? live, String rowTitle) {
  final title = live?.title ?? '';
  return title.isEmpty ? rowTitle : title;
}

/// **What the stale banner says** (plan 025 §3.7.3): a lane that is
/// RECONNECTING on its own — `stale` and not `ended`, a craze lane resuming
/// from its cursor — says "reconnecting…" (with the reason, when it names one):
/// nothing is over, and the transcript catches up by itself. A lane that ENDED
/// says its reason, as it always has, and the note below it says whether it is
/// re-opening or given up on. Collapsing the two would tell a person who is
/// watching a resume that the session went away, or one whose session closed
/// that it is coming back.
@visibleForTesting
String laneStaleBannerText(String stale, {required bool ended}) {
  if (ended) return stale;
  final reason = stale.trim();
  // A craze lane's own `Stale` says just this (shed-craze's watcher, and a
  // lane that left a retired craze source), and saying it twice
  // ("reconnecting… · reconnecting") would be noise.
  if (reason.isEmpty || reason == 'reconnecting') return 'reconnecting…';
  return 'reconnecting… · $reason';
}

/// **The lane-level note** — what is not staleness: an open that was
/// refused, a credential refresh that failed, a re-open waiting out its
/// backoff, or a lane that has been given up on. Null when there is nothing
/// to say.
///
/// **A lane that ENDED for good says so in its ended banner, and only
/// there** (plan 032 §3.1.2): a session stopped (`session_closed`), gone
/// (`unknown_session`) or never started (`start_failed: …`) is given up on
/// too — nothing re-opens it — but the banner's reason is the whole story,
/// and "given up on" under a normal Stop would say something went wrong. The
/// note stays for a lane given up on WITHOUT a final `Down` (its row left and
/// no end came — a craze lane's departure grace ran out), and for one given
/// up on an error.
@visibleForTesting
String? laneNoteText(LaneState state) {
  final error = state.error;
  if (state.abandoned) {
    if (state.ended && laneDownIsFinal(state.stale ?? '')) return null;
    return error == null
        ? 'This lane has been given up on — its row or session is gone.'
        : 'This lane has been given up on: ${error.message}';
  }
  if (error != null) {
    return state.retrying ? 'Reconnecting: ${error.message}' : error.message;
  }
  return state.retrying ? 'Reconnecting…' : null;
}

/// **Whether Stop can be pressed** — the header's button, and the confirm's
/// answer re-checked after its dialog closes: the session's streamed
/// capabilities say `stop`, and the lane has not ended (or been given up on) —
/// there is nothing left to stop then.
@visibleForTesting
bool laneStopOffered(LaneState state) =>
    (state.capabilities?.stop ?? false) && !state.ended && !state.abandoned;

/// **Whether Cancel is offered**: the session's streamed capabilities say
/// `cancel` (null — no seed yet — says nothing), and a turn is running — a
/// cancel with nothing to cancel is a refusal the agent would make. The
/// desktop's `laneVerbs` gate, with the phone's "only while working" shape.
@visibleForTesting
bool laneCancelOffered(
  BridgeLaneCapabilities? capabilities,
  BridgeRcActivity activity,
) => (capabilities?.cancel ?? false) && activity == BridgeRcActivity.working;

/// The header's line for a session's permission posture (craze's `bypass` |
/// `prompt`, plan 025 §3.6.5) — the desktop's `permissionLine`, word for word,
/// so a sheet-created session says out loud on both clients that it runs tools
/// without asking. An unknown word renders as itself; none at all renders
/// nothing.
@visibleForTesting
String? lanePermissionLine(String? mode) {
  final m = (mode ?? '').trim();
  if (m.isEmpty) return null;
  return switch (m) {
    'bypass' => 'runs tools without asking',
    'prompt' => 'asks before running tools',
    _ => 'permissions: $m',
  };
}

/// The frame every approval card shares: the agent's own title and detail, the
/// card's controls, and the refusal THIS card earned.
///
/// One shell for all three shapes so a permission, a question form and a raw
/// body cannot drift apart visually — the difference between them is what can
/// be answered, not how urgent they look.
class _ApprovalShell extends StatelessWidget {
  const _ApprovalShell({
    required this.approval,
    required this.error,
    required this.child,
  });

  final BridgeLaneApproval approval;
  final AppError? error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Container(
      key: ValueKey('lane-approval-${approval.id}'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.dotWarn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approval.title,
            style: sansStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          if (approval.detail case final detail?) ...[
            const SizedBox(height: 4),
            Text(detail, style: sansStyle(fontSize: 12, color: c.fg2)),
          ],
          const SizedBox(height: 10),
          child,
          if (error case final err?) ...[
            const SizedBox(height: 8),
            Text(
              err.message,
              key: ValueKey('lane-approval-error-${approval.id}'),
              style: sansStyle(fontSize: 12, color: c.errFg),
            ),
          ],
        ],
      ),
    );
  }
}

/// One offered option, **labelled by the agent and coloured by `kind`**.
///
/// `kind` is a string the contract tolerates open, and it is read here for
/// exactly one thing: whether this button is a refusal, so a rejection does not
/// look like an approval. The four known values are
/// `allow_once`/`allow_always`/`reject_once`/`reject_always`; anything else
/// renders neutral rather than guessed at.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.option,
    required this.onPressed,
    super.key,
  });

  final BridgeLaneApprovalOption option;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final rejects = option.kind?.startsWith('reject') ?? false;
    final button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: rejects ? c.errBg : c.accentSoft,
        foregroundColor: rejects ? c.errFg : c.accent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 36),
        textStyle: sansStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(option.label),
    );
    final description = option.description;
    return description == null
        ? button
        : Tooltip(message: description, child: button);
  }
}

/// **A structured question form** — one header, chips, and free text per
/// question, and ONE Send answer for the lot.
///
/// One-click is offered only for a SINGLE non-multiple non-custom question,
/// which is the whole of what "tap the answer and be done" can safely mean. gx
/// now advertises `custom: true` on its questions, so gx loses one-click: with
/// a text field on screen, posting on the first chip tap would throw away
/// whatever the person was still typing.
class _QuestionForm extends StatefulWidget {
  const _QuestionForm({
    required this.questions,
    required this.busy,
    required this.onAnswer,
    super.key,
  });

  final List<BridgeLaneQuestion> questions;
  final bool busy;
  final void Function(BridgeLaneAnswer answer) onAnswer;

  @override
  State<_QuestionForm> createState() => _QuestionFormState();
}

class _QuestionFormState extends State<_QuestionForm> {
  /// What is chosen, and what was typed, per QUESTION INDEX — maps rather
  /// than lists sized once from `widget.questions`. An approval is a live
  /// value that a later snapshot can replace under the same id (gx announces
  /// every one twice), and a list sized for the old shape would index out of
  /// range the moment the new one had one more question.
  final _selected = <int, Set<String>>{};
  final _typed = <int, TextEditingController>{};

  Set<String> _chosen(int i) => _selected.putIfAbsent(i, () => <String>{});

  TextEditingController _text(int i) =>
      _typed.putIfAbsent(i, TextEditingController.new);

  /// One question, single-choice, no text box: the only shape where the first
  /// tap IS the whole answer.
  bool get _oneClick =>
      widget.questions.length == 1 &&
      !widget.questions.first.multiple &&
      !widget.questions.first.custom;

  @override
  void dispose() {
    for (final c in _typed.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(int i, BridgeLaneApprovalOption option) {
    if (_oneClick) {
      widget.onAnswer(
        BridgeLaneAnswer.question(
          answers: [
            [option.id],
          ],
          customText: const [],
        ),
      );
      return;
    }
    setState(() {
      final chosen = _chosen(i);
      if (widget.questions[i].multiple) {
        chosen.contains(option.id)
            ? chosen.remove(option.id)
            : chosen.add(option.id);
      } else {
        chosen
          ..clear()
          ..add(option.id);
      }
    });
  }

  /// The custom text for question [i], or `null` for a non-custom question or
  /// an unfilled one — computed once so the loop below does not trim twice.
  String? _customText(int i) {
    if (!widget.questions[i].custom) return null;
    final typed = _text(i).text.trim();
    return typed.isEmpty ? null : typed;
  }

  void _submit() {
    // Positional, per question — the adapter maps them; a client never files
    // an answer by key even when `id` carries one.
    final answers = [
      for (var i = 0; i < widget.questions.length; i++) _chosen(i).toList(),
    ];
    final text = [
      for (var i = 0; i < widget.questions.length; i++) _customText(i),
    ];
    widget.onAnswer(
      BridgeLaneAnswer.question(
        answers: answers,
        // A `null` and a `Some("")` are different answers, so the hole is
        // preserved; nothing anywhere means the empty list.
        customText: text.every((t) => t == null) ? const [] : text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          if (widget.questions[i].header.isNotEmpty)
            Text(
              widget.questions[i].header,
              key: ValueKey('lane-question-header-$i'),
              style: sansStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
          if (widget.questions[i].question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.questions[i].question,
                style: sansStyle(fontSize: 12.5, color: c.fg2),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in widget.questions[i].options)
                FilterChip(
                  // Scoped by question index: two questions in one form can
                  // offer the same option id ("yes"/"no"), and an unscoped key
                  // would be ambiguous to find and to drive.
                  key: ValueKey('lane-option-$i-${option.id}'),
                  label: Text(option.label),
                  selected: _chosen(i).contains(option.id),
                  onSelected: widget.busy ? null : (_) => _toggle(i, option),
                ),
            ],
          ),
          // Gated on `custom`: the adapter REFUSES text aimed at a question
          // that did not ask for any, rather than dropping it.
          if (widget.questions[i].custom)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: ValueKey('lane-custom-$i'),
                controller: _text(i),
                enabled: !widget.busy,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Something else…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
        ],
        if (!_oneClick) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('lane-question-send'),
              onPressed: widget.busy ? null : _submit,
              child: const Text('Send answer'),
            ),
          ),
        ],
      ],
    );
  }
}

/// **The card for an ask this build cannot offer buttons for**: an unknown
/// kind, or — the case that matters — a permission with no options at all.
///
/// gx announces every approval TWICE: first a placeholder with a null method
/// and no request, then the real thing. The placeholder is a live pending
/// approval with an empty option list, so a card that assumed "permission ⇒
/// allow/deny" would show an Allow button for an ask whose contents have not
/// arrived. This says so instead, shows the raw request for anyone who wants to
/// read it, and offers the one answer that is always safe.
class _RawApproval extends StatefulWidget {
  const _RawApproval({
    required this.approval,
    required this.busy,
    required this.onReject,
  });

  final BridgeLaneApproval approval;
  final bool busy;
  final VoidCallback onReject;

  @override
  State<_RawApproval> createState() => _RawApprovalState();
}

class _RawApprovalState extends State<_RawApproval> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final approval = widget.approval;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _note(approval),
          key: ValueKey('lane-waiting-${approval.id}'),
          style: sansStyle(fontSize: 12.5, color: c.fg2),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: ValueKey('lane-raw-${approval.id}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: c.fg3,
              ),
              const SizedBox(width: 4),
              Text('request', style: monoStyle(fontSize: 11, color: c.fg3)),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              approval.requestJson,
              key: ValueKey('lane-raw-body-${approval.id}'),
              style: monoStyle(fontSize: 11, color: c.fg2),
            ),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            key: ValueKey('lane-reject-${approval.id}'),
            onPressed: widget.busy ? null : widget.onReject,
            style: OutlinedButton.styleFrom(foregroundColor: c.errFg),
            child: const Text('Reject'),
          ),
        ),
      ],
    );
  }

  /// What this card is, in a sentence. A placeholder permission is the common
  /// case and reads as such; an unknown kind names itself so a newer build's
  /// vocabulary is visible rather than mysterious.
  static String _note(BridgeLaneApproval approval) => switch (approval.kind) {
    BridgeLaneApprovalKind_Permission() ||
    BridgeLaneApprovalKind_PlanApproval() =>
      'waiting for details — the agent has not said what it is asking yet',
    BridgeLaneApprovalKind_Question() =>
      'waiting for details — this ask carries no questions yet',
    BridgeLaneApprovalKind_McpElicitation() =>
      'this app cannot render an MCP elicitation — answer it in the agent',
    BridgeLaneApprovalKind_Other(:final raw) =>
      'this app has no form for a "$raw" ask',
  };
}

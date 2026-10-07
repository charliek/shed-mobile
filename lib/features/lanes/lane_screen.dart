import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../core/app_error.dart';
import '../../lanes/lane_controller.dart';
import '../../lanes/lane_settings.dart';
import '../../lanes/lane_state.dart';
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
///   throw; the screen reads [LaneState.composerError] /
///   [LaneState.approvalErrors] / [LaneState.stopError] after the await and
///   renders it beside the control that raised it, because `not_accepting` on
///   a cancel means "the turn ended between the render and the tap" and that is
///   only legible next to the button.
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
/// current model, effort and fast ([settingsChip]), and a tap opens the
/// session's settings sheet ([LaneSettingsSheet]).
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

class _LaneScreenState extends ConsumerState<LaneScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

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

  LaneRef get _ref =>
      (machine: widget.machine, kind: widget.kind, slug: widget.slug);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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

  /// The lane, for the verbs. Safe only where [laneStateProvider] has data:
  /// that provider watches this one, so data means the controller built.
  LaneController get _controller => ref.read(laneControllerProvider(_ref));

  /// The shared shape behind [_send], [_cancel] and [_answer]: guard against a
  /// second tap while one is in flight, run it, log whatever it left on the
  /// state, and clear the busy flag.
  ///
  /// [run] captures its own `controller` and reads the error back off that
  /// SAME instance after the await — never a fresh [_controller] read, which
  /// could resolve to a different lane if the row was torn down and rebuilt
  /// mid-call. That capture-once discipline is the point of taking a closure
  /// here rather than a plain future.
  Future<void> _guarded({
    required bool busy,
    required void Function(bool value) setBusy,
    required String logKey,
    required Future<AppError?> Function() run,
    void Function()? onSuccess,
  }) async {
    if (busy) return;
    setState(() => setBusy(true));
    final error = await run();
    // The log line goes out either way — a driver needs the MRESULT even for a
    // verb whose screen has since gone.
    logDriveResult(logKey, ok: error == null, error: error?.message);
    if (!mounted) return;
    // INSIDE the mounted guard: `_send` passes `_input.clear`, and a disposed
    // `TextEditingController` throws when touched. Anything `onSuccess` does is
    // by definition a change to this widget's own state, so there is nothing
    // for it to do once the widget is gone.
    if (error == null) onSuccess?.call();
    setState(() => setBusy(false));
  }

  Future<void> _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return Future.value();
    return _guarded(
      busy: _sending,
      setBusy: (v) => _sending = v,
      logKey: 'lane-send',
      run: () async {
        final controller = _controller;
        await controller.send(text, mode: _sendMode(controller.state));
        // Never threw: the refusal is on the state, read after the await.
        return controller.state.composerError;
      },
      onSuccess: _input.clear,
    );
  }

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

  Future<void> _cancel() => _guarded(
    busy: _sending,
    setBusy: (v) => _sending = v,
    logKey: 'lane-cancel',
    run: () async {
      final controller = _controller;
      await controller.cancel();
      return controller.state.composerError;
    },
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
  Future<void> _confirmStop() async {
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
    final LaneState live;
    try {
      live = _controller.state;
    } on StateError {
      // The row is gone (laneControllerProvider's refusal): nothing to stop.
      return;
    }
    if (!laneStopOffered(live)) return;
    await _guarded(
      busy: _stopping,
      setBusy: (v) => _stopping = v,
      logKey: 'lane-stop',
      run: () async {
        final controller = _controller;
        await controller.stop();
        return controller.state.stopError;
      },
    );
  }

  Future<void> _answer(String approvalId, BridgeLaneAnswer answer) => _guarded(
    busy: _answering,
    setBusy: (v) => _answering = v,
    logKey: 'lane-answer',
    run: () async {
      final controller = _controller;
      await controller.answer(approvalId, answer);
      return controller.state.approvalErrors[approvalId];
    },
  );

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
            ? _centered('lane-unavailable', 'This lane is gone: ${async.error}')
            : const Center(
                key: ValueKey('lane-loading'),
                child: CircularProgressIndicator(),
              ),
      );
    }

    _noteRows(state);
    _log(state);

    final approvals = state.approvals;
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
              'This lane is gone: ${async.error}',
            ),
          if (state.stale != null) _staleBanner(context, state),
          if (state.stopError case final error?)
            _banner(
              context,
              'lane-stop-error',
              ShedStatusTone.err,
              error.message,
            ),
          if (_laneNote(state) case final note?) _noteBanner(context, note),
          Expanded(child: _transcript(context, state)),
          if (approvals.isNotEmpty)
            ConstrainedBox(
              // The composer and some transcript must stay visible: five gx
              // options plus a question form is taller than a phone.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SingleChildScrollView(
                key: const ValueKey('lane-approvals'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in approvals) _approvalCard(context, state, a),
                  ],
                ),
              ),
            ),
          _composer(context, state),
        ],
      ),
    );
  }

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
      // Two lines, like the watch screen: the slug is what you came looking
      // for, and the session's name answers "which session is this" — from the
      // LIVE session row once the stream has sent one (plan 025 §3.6.5).
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.slug, style: const TextStyle(fontSize: 17)),
          Text(
            laneHeaderTitle(state?.session, widget.title),
            key: const ValueKey('lane-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: context.shed.fg3),
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
            settingsChip(state.settings ?? noSettings),
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

  void _log(LaneState state) {
    String session;
    try {
      session = _controller.stamp.sessionId;
    } on StateError {
      // laneControllerProvider throws StateError when the row's lane stamp
      // is gone: the row went away between the snapshot and this line. The
      // state is still worth reporting; the session id is not knowable.
      session = '-';
    }
    logDriveState(
      'screen=lane machine=${widget.machine} session=$session '
      'generation=${state.generation} stale=${state.stale ?? '-'} '
      'approvals=${state.approvals.length} activity=${state.activity.wire}',
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

  /// A lane-level note that is not staleness: an open that was refused, a
  /// credential refresh that failed, a re-open waiting out its backoff, or a
  /// lane that has been given up on. Null when there is nothing to say.
  String? _laneNote(LaneState state) {
    final error = state.error;
    if (state.abandoned) {
      return error == null
          ? 'This lane has been given up on — its row or session is gone.'
          : 'This lane has been given up on: ${error.message}';
    }
    if (error != null) {
      return state.retrying ? 'Reconnecting: ${error.message}' : error.message;
    }
    return state.retrying ? 'Reconnecting…' : null;
  }

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

  Widget _composer(BuildContext context, LaneState state) {
    final c = context.shed;
    final working = state.activity == BridgeRcActivity.working;
    final canInterject = state.capabilities?.interject ?? false;
    final canCancel = laneCancelOffered(state.capabilities, state.activity);
    final enabled = !state.abandoned && !_sending;
    final error = state.composerError;
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
                Expanded(
                  child: TextField(
                    key: const ValueKey('lane-input'),
                    controller: _input,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => enabled ? _send() : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'What should it do next?',
                      border: OutlineInputBorder(),
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
                        onPressed: enabled ? _send : null,
                        icon: const Icon(Icons.send, size: 20),
                        tooltip: 'Send',
                      ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error.message,
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

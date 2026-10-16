/// **The craze create sheet** (plan 025 §3.8, CM4) — provider + directory + an
/// optional first prompt, nothing else (D6: no model, no effort, no permission
/// mode; craze's own defaults).
///
/// The create screen's craze choice renders it in place of the roost launch
/// form. What it holds and what it does not — the desktop's
/// `CrazeCreateDialog`, as rules rather than as React:
///
/// - **The options are read on every open** (D8: nothing cached) — providers
///   in craze's order, the default, the recent directories — through
///   `MachineFeed.crazeOptions`, on a connection of their own.
/// - **The draft is NOT the sheet's**: the typed form, the request id and the
///   submission's phase live in [crazeDraftProvider], per machine, so leaving
///   the screen keeps a submission running — its session simply appears as a
///   row — and a re-open finds the same form and the same id.
/// - **No state clears the typed form**: loading, a failed options read, the
///   machine's craze going offline or turning out too old, a refusal, an
///   unknown outcome — each says its piece and leaves what was typed alone.
///   Only a created session spends the draft.
///
/// Every rule it applies is `craze_create.dart`'s (pure, unit-tested); this
/// file is the draft's owner and the rendering.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../machines/machine_feed.dart';
import '../../providers.dart';
import '../../src/rust/api/craze.dart';
import '../../src/rust/api/dto_lane.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';
import 'craze_create.dart';
import 'craze_resume.dart';

/// How a submission's request id is minted — `crazeNewRequestId`
/// (`shed_craze::new_request_id`: `shed-` and a UUID v4 in its simple form).
/// A provider so a widget test, which has no native library, can count them.
final crazeRequestIdMintProvider = Provider<String Function()>(
  (ref) => crazeNewRequestId,
);

/// **One machine's craze create draft** — keyed by the feed origin.
///
/// Deliberately NOT `autoDispose`: the draft outlives the sheet (and the
/// screen). Leaving while a submission runs keeps it running, and coming back
/// — even after the outcome turned out unknown — finds the same form and the
/// same request id, which is what makes "Try again" resume the request rather
/// than start a second session. One small value per machine visited, for the
/// app's run.
final crazeDraftProvider =
    NotifierProvider.family<CrazeDraftController, CrazeDraft, String>(
      CrazeDraftController.new,
    );

/// The draft's owner: edits, and the one submission at a time.
class CrazeDraftController extends Notifier<CrazeDraft> {
  CrazeDraftController(this.origin);

  /// The machine's feed key — a machine's name, or `shed:<server>/<shed>`.
  final String origin;

  @override
  CrazeDraft build() => CrazeDraft.empty;

  /// An edit of the form ([CrazeDraft.edit]'s rule: any change mints a new id
  /// next time; nothing while a submission is in flight).
  void edit({
    Object? provider = _keepProvider,
    String? cwd,
    String? prompt,
    String? title,
  }) {
    state = identical(provider, _keepProvider)
        ? state.edit(cwd: cwd, prompt: prompt, title: title)
        : state.edit(
            provider: provider,
            cwd: cwd,
            prompt: prompt,
            title: title,
          );
  }

  /// **Run one submission of this machine's draft.** The request id is the
  /// draft's: reused while an outcome is unknown, minted anew after any
  /// definite one ([CrazeDraft.beginSubmit] / [CrazeDraft.settle]). Created:
  /// the draft is spent, carrying what was created for the sheet on screen
  /// ([CrazeDraft.lastCreated]) — whether a transcript opens is that sheet's
  /// call, not this one's.
  ///
  /// **The feed is held for as long as the create runs**, because the feed
  /// owns the create's connection and closes it when it is torn down. Without
  /// this hold, leaving the screen would let the machine's feed go (it lives
  /// only while something listens) and cut the create short — and a create cut
  /// short is an outcome nobody knows. With it, leaving the screen leaves the
  /// create running and its session appears as a row.
  ///
  /// [home] is the machine's home directory, which a `~` directory is
  /// expanded against when a NEW request begins ([CrazeDraft.beginSubmit]); a
  /// replay resends the directory it expanded the first time.
  ///
  /// **A replay goes as one** (plan 026 §3.1, plan 029 P11): a submission
  /// that re-sends the id held from an unknown outcome ([replaysHeldRequest],
  /// read BEFORE the submission starts — the desktop's `held`) is a held
  /// create, so a hub that cannot take the request now (say, a titled one
  /// where the hub no longer says `createTitle`) leaves the outcome unknown
  /// and the id kept, rather than a definite refusal that would drop it and
  /// let a later submission start a second session.
  Future<void> submit({String? home}) async {
    final current = state;
    if (current.phase == CrazePhase.submitting) return;
    final held = replaysHeldRequest(current);
    final started = current.beginSubmit(
      ref.read(crazeRequestIdMintProvider),
      home: home,
    );
    state = started;
    final hold = _FeedHold(ref, origin);
    try {
      final feed = hold.feed;
      final created = await feed.crazeCreateSession(
        started.request(),
        held: held,
      );
      // The feed folds the created row in before the create returns
      // (`MachineFeed.crazeCreateSession`), so a row it does NOT list now is a
      // session craze answered for that has already ended (a replayed answer).
      final listed = _lists(feed, created.session.id);
      logDriveResult('craze-create', ok: true);
      if (ref.mounted) {
        state = state.spent(CrazeCreated(created, ended: !listed));
      }
    } catch (e) {
      logDriveResult('craze-create', ok: false, error: e);
      if (ref.mounted) state = state.settle(crazeRefusalOf(e, held: held));
    } finally {
      hold.close();
    }
  }
}

const Object _keepProvider = Object();

/// **One machine's Resume state** (plan 032 §3.4, M3) — the sheet's Resume
/// half, keyed by the feed origin.
///
/// NOT `autoDispose`, for [crazeDraftProvider]'s reason: a reopen runs on
/// behind a sheet the person left (minutes, at worst), its session then simply
/// appearing as a row, and a re-open finds it still running. Every rule is
/// `craze_resume.dart`'s.
final crazeResumeProvider =
    NotifierProvider.family<CrazeResumeController, CrazeResume, String>(
      CrazeResumeController.new,
    );

/// The Resume state's owner: the half chosen, the saved list's reads, and
/// the one reopen at a time — each bound to the machine's feed incarnation
/// ([observeSource]).
class CrazeResumeController extends Notifier<CrazeResume> {
  CrazeResumeController(this.origin);

  /// The machine's feed key — a machine's name, or `shed:<server>/<shed>`.
  final String origin;

  /// The token each saved-list read is fenced by ([settleList]), and the
  /// attempt number each reopen is ([reopenLanding] / [settleResume]).
  int _reads = 0;
  int _attempts = 0;

  @override
  CrazeResume build() => CrazeResume.empty;

  /// An answer about the machine came through its feed incarnation
  /// [incarnation] ([observeSource]: a newer one starts afresh).
  void observe(int incarnation) => state = observeSource(state, incarnation);

  /// [observe], a microtask later — for a feed rebuilt under a listener: a
  /// provider rebuild may be flushed while widgets build, where no provider
  /// may change.
  void observeSoon(int incarnation) => unawaited(
    Future.microtask(() {
      if (ref.mounted) observe(incarnation);
    }),
  );

  /// The sheet opened, on the feed incarnation [incarnation]: observed first,
  /// then [onSheetOpen] — a reopen still running there is shown as it was
  /// left, anything else starts on New with nothing read.
  void sheetOpened(int incarnation) =>
      state = onSheetOpen(observeSource(state, incarnation));

  /// A half chosen; the saved list is read the first time Resume is.
  void choose(CrazeSheetMode mode) {
    state = chooseMode(state, mode);
    if (listNeeded(state)) unawaited(readSaved());
  }

  /// Read the saved list — on the first choice of Resume, and on its Retry.
  /// Only THIS read's answer lands ([settleList]).
  Future<void> readSaved() async {
    final token = ++_reads;
    state = beginList(state, token);
    final hold = _FeedHold(ref, origin);
    try {
      final feed = hold.feed;
      final list = await feed.crazeSavedSessions();
      logDriveResult('craze-saved', ok: true);
      if (ref.mounted) {
        state = settleList(
          state,
          token,
          SavedListed(list, gen: feed.incarnation),
        );
      }
    } catch (e) {
      logDriveResult('craze-saved', ok: false, error: e);
      if (ref.mounted) {
        state = settleList(state, token, SavedListRefused(crazeRefusalOf(e)));
      }
    } finally {
      hold.close();
    }
  }

  /// **Run one reopen of the saved session [id]** — one at a time
  /// ([canResume]), as its own attempt. **Every effect follows
  /// [reopenLanding]**, decided on the state the answer lands ON: an attempt a
  /// newer incarnation forgot is dropped whole (no state change, no landing),
  /// a `superseded` answer opens nothing, and otherwise the row leaves the
  /// list and the landing is recorded ([CrazeResume.landed]) for the sheet on
  /// screen, if any, to open. A refusal lands by its code ([settleResume]).
  ///
  /// **The feed is held for as long as the reopen runs** — the create's
  /// reason ([CrazeDraftController.submit]): the feed owns the reopen's
  /// connection, so leaving the screen must not let it go. And the hold
  /// follows the feed: a feed rebuilt meanwhile is a new incarnation, which
  /// resets this state (the old reopen's answer is then dropped).
  Future<void> resume(String id) async {
    if (!canResume(state, id)) return;
    final attempt = ++_attempts;
    state = beginResume(state, id, attempt);
    // A feed rebuilt meanwhile is observed at once ([observeSoon]).
    final hold = _FeedHold(
      ref,
      origin,
      onFeed: (feed) => observeSoon(feed.incarnation),
    );
    try {
      final feed = hold.feed;
      final answer = await feed.crazeReopenSession(id);
      logDriveResult('craze-resume', ok: true);
      if (!ref.mounted) return;
      final outcome = (
        // A feed the machine no longer has answered: nothing is opened on it.
        superseded: answer.superseded || !identical(hold.feed, feed),
        // The feed folds the reopened row in before the reopen returns
        // (`MachineFeed.crazeReopenSession`), so a row it does NOT list now is
        // a session that has already ended again.
        ended: !_lists(feed, answer.reopened.session.id),
      );
      final landing = reopenLanding(state, id, attempt, outcome);
      if (landing == ReopenLanding.dropped) return;
      state = settleResume(
        state,
        id,
        attempt,
        Resumed(outcome),
      ).copyWith(landed: CrazeResumed(answer.reopened, landing));
    } catch (e) {
      logDriveResult('craze-resume', ok: false, error: e);
      if (ref.mounted) {
        state = settleResume(
          state,
          id,
          attempt,
          ResumeRefused(reopenRefusalOf(e)),
        );
      }
    } finally {
      hold.close();
    }
  }
}

/// **The machine's feed, held for one call** — a create's or a reopen's (or a
/// saved-list read's), whose connection the feed owns: the feed provider and
/// its state stream (which keeps the feed started) are listened to until
/// [close], so leaving the screen cannot let the feed go — and cut the call
/// short — while it runs. [feed] is the one the provider holds NOW; [onFeed]
/// hears every feed it builds meanwhile.
class _FeedHold {
  _FeedHold(Ref ref, String origin, {void Function(MachineFeed feed)? onFeed})
    : _feed = ref.listen(
        machineFeedControllerProvider(origin),
        (_, next) => onFeed?.call(next),
      ),
      _stream = ref.listen(machineFeedProvider(origin), (_, _) {});

  final ProviderSubscription<MachineFeed> _feed;
  final ProviderSubscription<AsyncValue<MachineFeedState>> _stream;

  MachineFeed get feed => _feed.read();

  void close() {
    _feed.close();
    _stream.close();
  }
}

/// Whether [feed] lists the craze session [hostId] now.
bool _lists(MachineFeed feed, String hostId) =>
    feed.state.rows.any((r) => r is CrazeMachineRow && r.session.id == hostId);

/// Where the options read stands.
sealed class _OptionsLoad {
  const _OptionsLoad();
}

final class _Loading extends _OptionsLoad {
  const _Loading();
}

final class _Failed extends _OptionsLoad {
  const _Failed(this.message);
  final String message;
}

final class _Ready extends _OptionsLoad {
  const _Ready(this.options);
  final BridgeLaneCreateOptions options;
}

/// The craze create sheet for one machine — the create screen's craze choice.
class CrazeCreateSheet extends ConsumerStatefulWidget {
  const CrazeCreateSheet({
    required this.origin,
    required this.machine,
    required this.onCreated,
    required this.onResumed,
    super.key,
  });

  /// The machine's feed key (what the draft and the feed are addressed by).
  final String origin;

  /// What to call the machine in a sentence.
  final String machine;

  /// A submission created a session WHILE this sheet was on screen — mounted,
  /// its route the current one (not one Back already dismissed and still
  /// animating away): the screen decides what follows (open its transcript,
  /// say why not). Called once per created session, and never for a sheet
  /// left.
  final void Function(CrazeCreated created) onCreated;

  /// A reopen landed WHILE this sheet was on screen (plan 032 §3.4) — as
  /// [onCreated] means it: the screen opens its transcript, or says it ended;
  /// a `superseded` one is said on its row and needs nothing more. Called
  /// once per landing, and never for a sheet left.
  final void Function(CrazeResumed resumed) onResumed;

  @override
  ConsumerState<CrazeCreateSheet> createState() => _CrazeCreateSheetState();
}

class _CrazeCreateSheetState extends ConsumerState<CrazeCreateSheet> {
  late final TextEditingController _cwd;
  late final TextEditingController _prompt;
  late final TextEditingController _title;
  _OptionsLoad _load = const _Loading();

  /// The machine's home directory — what a typed `~` expands to; null until
  /// (or unless) the feed learns it.
  String? _home;

  /// Bumped by every read, so an answer that lost to a Retry is dropped.
  int _attempt = 0;

  /// The sheet has opened and [CrazeResumeController.sheetOpened] has not run
  /// yet: it runs a microtask after [initState] (no provider may change while
  /// widgets build), and until then the sheet renders the state through the
  /// same rule ([_opening]), so the first frame is never a stale half.
  bool _opened = false;

  CrazeDraftController get _draft =>
      ref.read(crazeDraftProvider(widget.origin).notifier);

  CrazeResumeController get _resume =>
      ref.read(crazeResumeProvider(widget.origin).notifier);

  /// The feed incarnation this sheet is on now.
  int get _incarnation =>
      ref.read(machineFeedControllerProvider(widget.origin)).incarnation;

  /// **Whether a completion may navigate from this sheet** — a create's or a
  /// reopen's landing ([CrazeCreateSheet.onCreated],
  /// [CrazeCreateSheet.onResumed]): the sheet is mounted AND its route is the
  /// current one. Back pops the route at once, but the sheet stays mounted —
  /// its listeners live — through the route's reverse animation, and a
  /// landing then would push the transcript in place of the screen now on
  /// top (or, for a session that has already ended, pop it). A dismissed
  /// sheet never navigates: the landing is still recorded in its provider,
  /// so the row (or the Retry) reads as it settled when the sheet opens
  /// again — the session simply appears as a row.
  bool get _navigable => mounted && ModalRoute.isCurrentOf(context) == true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(crazeDraftProvider(widget.origin));
    _cwd = TextEditingController(text: draft.cwd);
    _prompt = TextEditingController(text: draft.prompt);
    _title = TextEditingController(text: draft.title);
    final incarnation = _incarnation;
    unawaited(
      Future.microtask(() {
        if (!mounted) return;
        _resume.sheetOpened(incarnation);
        setState(() => _opened = true);
      }),
    );
    _read();
  }

  /// What the sheet shows of the Resume state before [_opened]: the state as
  /// [CrazeResumeController.sheetOpened] is about to leave it.
  CrazeResume _opening(CrazeResume r) =>
      _opened ? r : onSheetOpen(observeSource(r, _incarnation));

  @override
  void dispose() {
    _cwd.dispose();
    _prompt.dispose();
    _title.dispose();
    super.dispose();
  }

  /// Read what a create can start here NOW — on every open and every Retry.
  Future<void> _read() async {
    final attempt = ++_attempt;
    setState(() => _load = const _Loading());
    try {
      final feed = ref.read(machineFeedControllerProvider(widget.origin));
      final options = await feed.crazeOptions();
      if (!mounted || attempt != _attempt) return;
      // The options came through this feed: the Resume state is bound to it
      // (plan 032 §3.4 — a newer incarnation starts it afresh).
      _resume.observe(feed.incarnation);
      setState(() => _load = _Ready(options));
      _reconcile();
      _readHome(attempt);
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() => _load = _Failed(_message(e)));
    }
  }

  /// Learn the machine's home beside the options; a failure leaves `~` refused
  /// and costs nothing else.
  Future<void> _readHome(int attempt) async {
    if (_home != null) return;
    String? home;
    try {
      home = await ref
          .read(machineFeedControllerProvider(widget.origin))
          .remoteHome();
    } catch (_) {
      home = null;
    }
    if (!mounted || attempt != _attempt || home == null) return;
    setState(() => _home = home);
  }

  static String _message(Object e) => switch (e) {
    final BridgeLaneError err => appErrorFromLane(err).message,
    StateError(:final message) => message,
    _ => '$e',
  };

  /// The provider follows the options: a selection carried over from an
  /// earlier open survives only while still ready, else the default rule.
  ///
  /// **An IDLE draft only.** Re-picking is an edit, and an edit ends what the
  /// draft holds from its last submission: one in flight is left alone (its
  /// controls are disabled); one whose outcome is unknown keeps its provider
  /// and its id, so Try again resends that request even when the provider
  /// reads non-ready now ([replaysHeldRequest]) — a new id there could start
  /// a second session; and a refused one keeps the refusal it shows.
  void _reconcile() {
    final load = _load;
    if (load is! _Ready) return;
    final draft = ref.read(crazeDraftProvider(widget.origin));
    if (draft.phase != CrazePhase.idle) return;
    final want = reconcileProvider(draft.provider, load.options);
    if (want != draft.provider) _draft.edit(provider: want);
  }

  /// A tap on a provider row: a dimmed one refuses it — the rule, not just the
  /// look.
  void _pick(BridgeLaneProvider p, bool submitting) {
    if (!providerSelectable(p) || submitting) return;
    _draft.edit(provider: p.id);
  }

  void _useRecent(String dir) {
    _cwd.text = dir;
    _draft.edit(cwd: dir);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final draft = ref.watch(crazeDraftProvider(widget.origin));
    ref.listen(crazeDraftProvider(widget.origin), (prev, next) {
      // The form follows the draft when it changes under the fields — a spent
      // draft after a create, a recent directory — never by retyping what the
      // user just typed (the fields' own edits already match).
      if (_cwd.text != next.cwd) _cwd.text = next.cwd;
      if (_prompt.text != next.prompt) _prompt.text = next.prompt;
      if (_title.text != next.title) _title.text = next.title;
      final created = next.lastCreated;
      if (created != null &&
          !identical(created, prev?.lastCreated) &&
          _navigable) {
        widget.onCreated(created);
      }
      // A submission settled: the provider rule applies again (to a spent
      // draft — an unknown or refused one keeps what it sent).
      if (prev?.phase == CrazePhase.submitting &&
          next.phase != CrazePhase.submitting) {
        Future.microtask(() {
          if (mounted) _reconcile();
        });
      }
    });
    final craze = ref.watch(machineFeedProvider(widget.origin)).value?.craze;
    final resume = _opening(ref.watch(crazeResumeProvider(widget.origin)));
    ref.listen(crazeResumeProvider(widget.origin), (prev, next) {
      // A reopen landed while this sheet is on screen: the screen decides
      // what follows, once per landing.
      final landed = next.landed;
      if (landed != null && !identical(landed, prev?.landed) && _navigable) {
        widget.onResumed(landed);
      }
    });
    // A feed rebuilt under the open sheet (the machine removed and added
    // again, say) is a new incarnation, which the Resume state observes at
    // once ([CrazeResumeController.observeSoon]).
    ref.listen(
      machineFeedControllerProvider(widget.origin),
      (_, feed) => _resume.observeSoon(feed.incarnation),
    );

    final load = _load;
    final options = load is _Ready ? load.options : null;
    final submitting = draft.phase == CrazePhase.submitting;
    // Try again resends the held request as it was sent: its provider is not
    // re-checked against what craze lists now ([replaysHeldRequest]).
    final replaying = replaysHeldRequest(draft);
    // The Name field shows when the machine's craze takes a title (plan 029
    // D18) OR while a title is typed: a typed title is never hidden (E13).
    final titled =
        (craze?.caps?.createTitle ?? false) || draft.title.trim().isNotEmpty;
    final machineNote = crazeSheetNote(craze, widget.machine);
    final providers = options?.providers ?? const <BridgeLaneProvider>[];
    final noneReady = options != null && !providers.any(providerSelectable);
    final note =
        machineNote ?? (noneReady && !replaying ? noProviderReady : null);
    BridgeLaneProvider? selected;
    for (final p in providers) {
      if (p.id == draft.provider && (replaying || providerSelectable(p))) {
        selected = p;
      }
    }
    // A replay resends the directory it already expanded ([CrazeDraft.sentCwd]),
    // so the field's rule (and whether the home is known now) is not asked.
    final cwdProblem =
        replaying || (draft.cwd.isEmpty && draft.phase == CrazePhase.idle)
        ? null
        : directoryProblem(draft.cwd, home: _home);
    final refusal = draft.refusal == null ? null : refusalView(draft.refusal!);
    final recent = visibleRecentDirs(options?.recentDirs ?? const []);
    final canCreate =
        options != null &&
        (selected != null || replaying) &&
        (replaying || directoryProblem(draft.cwd, home: _home) == null) &&
        note == null &&
        !submitting;
    // `New | Resume` (plan 032 §3.4, PC11): shown where the options just read
    // say the hub can reopen, locked while either half's action runs. Every
    // rule is `craze_resume.dart`'s.
    final modesOffered = resumeOffered(options?.reopen, resume);
    final locked = modeLocked(submitting, resume);
    final resuming = resume.mode == CrazeSheetMode.resume;
    // The Resume half says only the machine's own note: the rest of the
    // create gate's (no provider ready) is the form's.
    final sheetNote = resuming ? machineNote : note;
    // A failed options read says so, with its Retry, in WHICHEVER half shows
    // ([optionsRetryHalf]) — never locked.
    final retryHalf = optionsRetryHalf(load is _Failed, resume);
    final saved = resume.load;
    logDriveState(
      'screen=craze-create machine=${widget.origin} '
      'state=${options == null ? (load is _Failed ? 'failed' : 'loading') : draft.phase.name} '
      'provider=${selected?.id ?? '-'} '
      'providers=${providers.map((p) => '${p.id}:${providerSelectable(p) ? 'ready' : 'dimmed'}').join(',')} '
      'recent=${options?.recentDirs.length ?? 0} '
      'request=${draft.requestId ?? '-'} create=$canCreate '
      'mode=${resume.mode.wire} '
      'modes=${!modesOffered ? 'off' : (locked ? 'locked' : 'on')} '
      'saved=${saved.phase} '
      'rows=${saved is SavedReady ? saved.sessions.map((r) => '${r.id}:${rowState(resume, r.id).phase}').join(',') : '-'} '
      'more=${saved is SavedReady && saved.more} '
      'gone=${resume.gone?.id ?? '-'}',
    );

    return Column(
      key: const ValueKey('craze-create-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (modesOffered) ...[
          _ModeControl(
            mode: resume.mode,
            locked: locked,
            onChoose: (mode) => _resume.choose(mode),
          ),
          const SizedBox(height: 14),
        ],
        if (sheetNote != null) ...[
          Container(
            key: const ValueKey('craze-create-note'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.warnBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sheetNote,
              style: sansStyle(fontSize: 13, color: c.warnFg),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (resuming) ...[
          if (retryHalf == CrazeSheetMode.resume && load is _Failed) ...[
            _ReadFailed(
              'craze could not read this machine\'s options: ${load.message}',
              keys: 'craze-create-options',
              onRetry: _read,
            ),
            const SizedBox(height: 10),
          ],
          _SavedList(
            machine: widget.machine,
            resume: resume,
            home: _home,
            locked: locked,
            onResume: (id) => unawaited(_resume.resume(id)),
            onRetryList: () => unawaited(_resume.readSaved()),
          ),
          if (resumingId(resume) != null) ...[
            const SizedBox(height: 8),
            Text(
              'Leaving keeps the resume running; its session appears as a '
              'row.',
              key: const ValueKey('craze-resume-leaving'),
              style: sansStyle(fontSize: 12, color: c.fg3),
            ),
          ],
        ] else ...[
          _Label('Provider', color: c.fg2),
          const SizedBox(height: 8),
          switch (load) {
            _Loading() => _Reading(
              'reading what ${widget.machine} can start…',
              key: const ValueKey('craze-create-loading'),
            ),
            _Failed(:final message) => _ReadFailed(
              'craze could not list providers: $message',
              keys: 'craze-create-options',
              onRetry: _read,
            ),
            _Ready() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in providers) ...[
                  _ProviderRow(
                    key: ValueKey('craze-provider-${p.id}'),
                    provider: p,
                    selected: identical(p, selected),
                    enabled: !submitting,
                    onTap: () => _pick(p, submitting),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          },
          const SizedBox(height: 14),
          _Label('Directory', color: c.fg2),
          const SizedBox(height: 8),
          if (recent.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, dir) in recent.indexed)
                  _RecentDir(
                    key: ValueKey('craze-recent-dir-$i'),
                    dir: dir,
                    label: abbreviateHome(dir, _home),
                    chosen: draft.cwd == dir,
                    onTap: submitting ? null : () => _useRecent(dir),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const ValueKey('craze-create-cwd'),
            controller: _cwd,
            enabled: !submitting,
            autocorrect: false,
            enableSuggestions: false,
            style: monoStyle(fontSize: 13, color: c.fg),
            decoration: const InputDecoration(
              labelText: 'Path on that machine (absolute, or ~/…)',
            ),
            onChanged: (v) => _draft.edit(cwd: v),
          ),
          if (cwdProblem != null || refusal?.where == RefusalWhere.cwd) ...[
            const SizedBox(height: 6),
            Text(
              refusal?.where == RefusalWhere.cwd ? refusal!.text : cwdProblem!,
              key: const ValueKey('craze-create-cwd-problem'),
              style: sansStyle(fontSize: 12, color: c.errFg),
            ),
          ],
          if (titled) ...[
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('craze-create-title'),
              controller: _title,
              enabled: !submitting,
              maxLines: 1,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
              onChanged: (v) => _draft.edit(title: v),
            ),
          ],
          if (refusal?.where == RefusalWhere.title) ...[
            const SizedBox(height: 6),
            Text(
              refusal!.text,
              key: const ValueKey('craze-create-title-problem'),
              style: sansStyle(fontSize: 12, color: c.errFg),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('craze-create-prompt'),
            controller: _prompt,
            enabled: !submitting,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'First prompt (optional)',
              hintText:
                  'what to start on — or leave it empty for an idle '
                  'session',
            ),
            onChanged: (v) => _draft.edit(prompt: v),
          ),
          if (draft.phase == CrazePhase.unknown) ...[
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('craze-create-unknown'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.warnBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                outcomeUnknownNote,
                style: sansStyle(fontSize: 13, color: c.warnFg),
              ),
            ),
          ],
          if (refusal?.where == RefusalWhere.cause) ...[
            const SizedBox(height: 14),
            Text(
              'The session failed to start:',
              style: sansStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.errFg,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.errBg,
                borderRadius: BorderRadius.circular(8),
              ),
              // craze's cause, VERBATIM — multi-line, monospace.
              child: SelectableText(
                refusal!.text,
                key: const ValueKey('craze-create-cause'),
                style: monoStyle(fontSize: 12, color: c.errFg),
              ),
            ),
          ],
          if (refusal?.where == RefusalWhere.general) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.errBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                refusal!.text,
                key: const ValueKey('craze-create-error'),
                style: monoStyle(fontSize: 12, color: c.errFg),
              ),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            key: const ValueKey('craze-create-submit'),
            label: primaryLabel(draft),
            onPressed: canCreate ? () => _draft.submit(home: _home) : null,
          ),
          if (submitting) ...[
            const SizedBox(height: 8),
            Text(
              'Leaving keeps the create running; its session appears as a row.',
              key: const ValueKey('craze-create-leaving'),
              style: sansStyle(fontSize: 12, color: c.fg3),
            ),
          ],
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: sansStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
  );
}

/// One provider, as craze listed it: its label, and — when it cannot start —
/// dimmed, with craze's state, reason and fix, and not selectable.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    super.key,
    required this.provider,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final BridgeLaneProvider provider;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final p = provider;
    final ok = providerSelectable(p);
    return Semantics(
      button: true,
      selected: selected,
      enabled: ok && enabled,
      child: Opacity(
        opacity: ok ? 1 : 0.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : c.surface,
              border: Border.all(color: selected ? c.accent : c.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.label,
                        style: sansStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                    ),
                    if (!ok)
                      Text(
                        providerStateWords(p.state),
                        key: ValueKey('craze-provider-state-${p.id}'),
                        style: monoStyle(fontSize: 11, color: c.fg3),
                      ),
                  ],
                ),
                if (!ok && p.reason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.reason!,
                    key: ValueKey('craze-provider-reason-${p.id}'),
                    style: sansStyle(fontSize: 12, color: c.fg2),
                  ),
                ],
                if (!ok && p.fix != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.fix!,
                    key: ValueKey('craze-provider-fix-${p.id}'),
                    style: monoStyle(fontSize: 12, color: c.fg3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of craze's recent directories, one tap to use.
class _RecentDir extends StatelessWidget {
  const _RecentDir({
    super.key,
    required this.dir,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String dir;

  /// What the chip reads — [dir] with its home abbreviated.
  final String label;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: chosen ? c.accent : c.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: monoStyle(fontSize: 12, color: chosen ? c.accent : c.fg2),
        ),
      ),
    );
  }
}

/// A read running: a spinner, and what is being read.
class _Reading extends StatelessWidget {
  const _Reading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: monoStyle(fontSize: 12.5, color: context.shed.fg3),
        ),
      ),
    ],
  );
}

/// A failed read, said with its Retry — `<keys>-error` and `<keys>-retry`.
/// The create options' is said in the half that shows ([optionsRetryHalf])
/// and its Retry is never disabled: a re-read touches neither half's action,
/// a reopen left running included. The saved list's Retry waits while either
/// half's action runs (a null [onRetry]).
class _ReadFailed extends StatelessWidget {
  const _ReadFailed(this.text, {required this.keys, required this.onRetry});

  final String text;
  final String keys;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          key: ValueKey('$keys-error'),
          style: sansStyle(fontSize: 13, color: context.shed.errFg),
        ),
      ),
      const SizedBox(width: 10),
      OutlinedButton.icon(
        key: ValueKey('$keys-retry'),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Retry'),
      ),
    ],
  );
}

/// The sheet's two halves (plan 032 §3.4): a new session, or a saved one
/// running again — `craze-mode-new` / `craze-mode-resume`, disabled while
/// either half's action runs.
class _ModeControl extends StatelessWidget {
  const _ModeControl({
    required this.mode,
    required this.locked,
    required this.onChoose,
  });

  final CrazeSheetMode mode;
  final bool locked;
  final void Function(CrazeSheetMode mode) onChoose;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('craze-mode'),
    children: [
      for (final m in CrazeSheetMode.values) ...[
        if (m != CrazeSheetMode.values.first) const SizedBox(width: 8),
        Expanded(
          child: _ModeChip(
            key: ValueKey('craze-mode-${m.wire}'),
            label: m.label,
            selected: m == mode,
            onTap: locked ? null : () => onChoose(m),
          ),
        ),
      ],
    ],
  );
}

/// One segment of [_ModeControl] — the create screen's kind chip, by look.
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null && !selected ? 0.5 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : Colors.transparent,
              border: Border.all(color: selected ? c.accent : c.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: sansStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? c.fg : c.fg2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet's Resume half (plan 032 §3.4): craze's saved sessions, newest
/// first — each its title (or "Untitled"), provider, workspace (the home
/// shortened to `~` where the feed knows it) and age, with a Resume button.
/// Rendered from the machine's Resume state by `craze_resume.dart`'s rules; it
/// holds no rule of its own.
class _SavedList extends StatelessWidget {
  const _SavedList({
    required this.machine,
    required this.resume,
    required this.home,
    required this.locked,
    required this.onResume,
    required this.onRetryList,
  });

  final String machine;
  final CrazeResume resume;

  /// The machine's home — what a workspace under it is shortened by.
  final String? home;

  /// A create submitting or a reopen running: the list's Retry waits.
  final bool locked;

  /// A row's button pressed ([CrazeResumeController.resume] holds the
  /// [canResume] gate).
  final void Function(String id) onResume;
  final VoidCallback onRetryList;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    switch (resume.load) {
      case SavedUnloaded() || SavedLoading():
        return _Reading(
          'reading the saved sessions on $machine…',
          key: const ValueKey('craze-saved-loading'),
        );
      case SavedFailed(:final refusal):
        return _ReadFailed(
          'craze could not list saved sessions: ${refusal.message}',
          keys: 'craze-saved-list',
          onRetry: locked ? null : onRetryList,
        );
      case SavedReady(:final sessions, :final more):
        final gone = resume.gone;
        final now = DateTime.now().millisecondsSinceEpoch;
        return Column(
          key: const ValueKey('craze-saved'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (gone != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.errBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '“${gone.title}” cannot run here any more, so it was '
                  'removed: ${gone.message}',
                  key: const ValueKey('craze-saved-gone'),
                  style: sansStyle(fontSize: 12, color: c.errFg),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (sessions.isEmpty)
              Text(
                'No saved sessions on $machine.',
                key: const ValueKey('craze-saved-empty'),
                style: sansStyle(fontSize: 13, color: c.fg3),
              ),
            for (final s in sessions) ...[
              _SavedRow(
                key: ValueKey('craze-saved-${s.id}'),
                session: s,
                state: rowState(resume, s.id),
                workspace: abbreviateHome(s.workspace, home),
                age: relativeAge(s.updatedUnixMs, now),
                enabled: canResume(resume, s.id),
                onResume: () => onResume(s.id),
              ),
              const SizedBox(height: 6),
            ],
            if (more)
              Text(
                moreNote,
                key: const ValueKey('craze-saved-more'),
                style: sansStyle(fontSize: 12, color: c.fg3),
              ),
          ],
        );
    }
  }
}

/// One saved session: its title, provider, workspace and age; its Resume
/// button (Resuming… while its reopen runs, Retry after `unavailable`); and
/// what its last reopen was refused with.
class _SavedRow extends StatelessWidget {
  const _SavedRow({
    super.key,
    required this.session,
    required this.state,
    required this.workspace,
    required this.age,
    required this.enabled,
    required this.onResume,
  });

  final BridgeLaneSavedSession session;
  final SavedRowState state;

  /// The workspace as shown (its home shortened).
  final String workspace;
  final String age;
  final bool enabled;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final id = session.id;
    final running = state is SavedResuming;
    final error = savedRowError(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: running ? c.accentSoft : c.surface,
        border: Border.all(color: running ? c.accent : c.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            savedTitle(session.title),
            key: ValueKey('craze-saved-title-$id'),
            overflow: TextOverflow.ellipsis,
            style: sansStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                session.provider,
                key: ValueKey('craze-saved-provider-$id'),
                style: sansStyle(fontSize: 12, color: c.fg3),
              ),
              Text(
                workspace,
                key: ValueKey('craze-saved-workspace-$id'),
                style: monoStyle(fontSize: 12, color: c.fg3),
              ),
              if (age.isNotEmpty)
                Text(
                  age,
                  key: ValueKey('craze-saved-updated-$id'),
                  style: sansStyle(fontSize: 12, color: c.fg3),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: ValueKey('craze-saved-resume-$id'),
              onPressed: enabled ? onResume : null,
              icon: running
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: Text(resumeLabel(state)),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            if (error.where == RefusalWhere.cause)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.errBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                // craze's cause, VERBATIM — multi-line, monospace.
                child: SelectableText(
                  error.text,
                  key: ValueKey('craze-saved-error-$id'),
                  style: monoStyle(fontSize: 12, color: c.errFg),
                ),
              )
            else
              Text(
                error.text,
                key: ValueKey('craze-saved-error-$id'),
                style: sansStyle(fontSize: 12, color: c.errFg),
              ),
          ],
        ],
      ),
    );
  }
}

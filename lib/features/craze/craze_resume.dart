/// **The craze create sheet's Resume half — its pure rules** (plan 032 §3.4,
/// M3): when the sheet offers `New | Resume`, the saved list's lifecycle, one
/// reopen at a time and where each one's outcome lands (drop the row, keep
/// it, offer Retry), which machine INCARNATION the state belongs to (a feed
/// rebuilt — a machine removed and added again under the same name, say — is
/// a new one: nothing the old one left running carries over, and no late
/// answer of its lands), where a failed create-options read offers its Retry,
/// and how a saved row reads (its title, its age).
///
/// The desktop's `crazeResume.ts`, ported rule for rule (shed plan 032 C5):
/// both clients show one sheet. Pure (no provider, no widget, no native call)
/// so `test/features/craze/craze_resume_test.dart` pins every one without the
/// bridge; the sheet's controller (`CrazeResumeController` in
/// `craze_create_sheet.dart`) holds a machine's state and runs its reopens,
/// and the sheet renders it — neither holds a rule of its own.
///
/// **One phone difference:** the incarnation is the machine's FEED
/// (`MachineFeed.incarnation`), where the desktop's is its craze source's
/// generation. A feed's stop/start (backgrounding) replaces its craze source
/// and is not a new incarnation: a reopen that runs through it is cut short
/// there, and says Retry (`craze_reopen`).
library;

import 'package:flutter/foundation.dart' show immutable, mapEquals;

import '../../src/rust/api/dto_lane.dart';
import 'craze_create.dart' show CrazeRefusal, RefusalWhere, crazeRefusalOf;

/// Which half of the sheet shows.
enum CrazeSheetMode {
  /// A new session (the create form).
  newSession('new', 'New'),

  /// A saved session, running again.
  resume('resume', 'Resume');

  const CrazeSheetMode(this.wire, this.label);

  /// The mode as the drive log and the desktop's dump name it.
  final String wire;

  /// The segment's label.
  final String label;
}

/// Where one saved row stands:
/// - [SavedResuming] — its reopen is running (minutes, at worst), as the
///   controller's `attempt`: only THAT reopen's outcome lands on the row;
/// - [SavedRefused] — a start failure (`start_failed`), a reopen whose answer
///   was `superseded`, or any other definite refusal: said inline, the row
///   kept, Resume again allowed;
/// - [SavedUnavailable] — transient, a lost answer included ("Retry is safe":
///   a reopen is idempotent): said inline, with Retry.
@immutable
sealed class SavedRowState {
  const SavedRowState();

  /// The phase as the drive log names it.
  String get phase;
}

final class SavedIdle extends SavedRowState {
  const SavedIdle();

  @override
  String get phase => 'idle';

  @override
  bool operator ==(Object other) => other is SavedIdle;

  @override
  int get hashCode => 0;
}

final class SavedResuming extends SavedRowState {
  const SavedResuming(this.attempt);

  final int attempt;

  @override
  String get phase => 'resuming';

  @override
  bool operator ==(Object other) =>
      other is SavedResuming && other.attempt == attempt;

  @override
  int get hashCode => Object.hash('resuming', attempt);
}

final class SavedRefused extends SavedRowState {
  const SavedRefused(this.refusal);

  final CrazeRefusal refusal;

  @override
  String get phase => 'refused';

  @override
  bool operator ==(Object other) =>
      other is SavedRefused && other.refusal == refusal;

  @override
  int get hashCode => Object.hash('refused', refusal);
}

final class SavedUnavailable extends SavedRowState {
  const SavedUnavailable(this.refusal);

  final CrazeRefusal refusal;

  @override
  String get phase => 'unavailable';

  @override
  bool operator ==(Object other) =>
      other is SavedUnavailable && other.refusal == refusal;

  @override
  int get hashCode => Object.hash('unavailable', refusal);
}

/// The saved list's read. [SavedLoading.token] fences an answer to the read
/// that asked: a sheet reopened while a read ran starts another, and only ITS
/// answer lands.
@immutable
sealed class SavedLoad {
  const SavedLoad();

  /// The phase as the drive log names it.
  String get phase;
}

final class SavedUnloaded extends SavedLoad {
  const SavedUnloaded();

  @override
  String get phase => 'unloaded';
}

final class SavedLoading extends SavedLoad {
  const SavedLoading(this.token);

  final int token;

  @override
  String get phase => 'loading';
}

final class SavedFailed extends SavedLoad {
  const SavedFailed(this.refusal);

  final CrazeRefusal refusal;

  @override
  String get phase => 'failed';
}

final class SavedReady extends SavedLoad {
  const SavedReady(this.sessions, {required this.more});

  /// craze's order: newest first.
  final List<BridgeLaneSavedSession> sessions;

  /// craze left some out: the sheet says it shows only the most recent.
  final bool more;

  @override
  String get phase => 'ready';
}

/// The last row dropped because it cannot run here any more (`gone`): what
/// it was called and craze's words — said where the row was.
typedef SavedGone = ({String id, String title, String message});

/// What a reopen's SUCCESS says that decides where it lands
/// ([reopenLanding]):
/// - `superseded` — the answer came through a craze source the machine's feed
///   no longer has (`MachineFeed.crazeReopenSession`), or a feed the machine
///   no longer has: nothing was listed, and nothing is opened on it here;
/// - `ended` — the session ended again before its row was listed: nothing to
///   open.
typedef ReopenAnswer = ({bool superseded, bool ended});

/// Where a reopen's SUCCESS lands — the controller's effects follow it:
/// - [dropped] — the attempt is not the reopen running on its row any more:
///   the state it began in was forgotten for a NEWER incarnation of the
///   machine ([observeSource]), so this answer is the old one's. No state
///   change, no navigation, nothing said;
/// - [superseded] — NOT openable: said on the row ([supersededNote]), the
///   sheet left where it is;
/// - [ended] — the session ended again before its row was listed: said, and
///   nothing opened;
/// - [open] — the sheet on screen (if any) gives way to the session's
///   transcript.
enum ReopenLanding { dropped, superseded, ended, open }

/// A reopen that LANDED (anything but [ReopenLanding.dropped]) — one object
/// per landing, so the sheet on screen tells a new one from one it has already
/// handled by identity (the create's `CrazeCreated`).
class CrazeResumed {
  CrazeResumed(this.reopened, this.landing);

  final BridgeLaneReopened reopened;
  final ReopenLanding landing;

  /// The running session's hostId (P11) — what its transcript opens on.
  String get hostId => reopened.session.id;
}

/// The marker for "leave it as it is" in [CrazeResume.copyWith], because null
/// is a value of the fields it guards.
const Object _keep = Object();

/// **A machine's Resume state** — held ABOVE the sheet, per machine, like a
/// create's draft: leaving the sheet keeps a reopen running (its session then
/// simply appears as a row), and a re-open finds it.
@immutable
class CrazeResume {
  const CrazeResume({
    this.gen,
    this.mode = CrazeSheetMode.newSession,
    this.load = const SavedUnloaded(),
    this.rows = const {},
    this.gone,
    this.landed,
  });

  /// Nothing chosen, nothing read, nothing running, bound to no incarnation.
  static const empty = CrazeResume();

  /// The machine INCARNATION it belongs to — the feed an answer about it came
  /// through (`MachineFeed.incarnation`: the feed the sheet opened on, the
  /// one its create options or its saved list came through, the one a reopen
  /// ran on), null until one says. The state is held by machine NAME, which a
  /// machine removed and added again keeps; this is what tells the two apart
  /// ([observeSource]).
  final int? gen;

  final CrazeSheetMode mode;
  final SavedLoad load;

  /// Each row's state by saved id; an absent id is idle.
  final Map<String, SavedRowState> rows;

  /// The last row dropped as `gone`, or null.
  final SavedGone? gone;

  /// The last reopen that landed — what the sheet on screen acts on when it
  /// changes (opens its transcript, says it ended). Not a rule's input: no
  /// rule reads it, and every reset forgets it.
  final CrazeResumed? landed;

  CrazeResume copyWith({
    int? gen,
    CrazeSheetMode? mode,
    SavedLoad? load,
    Map<String, SavedRowState>? rows,
    Object? gone = _keep,
    Object? landed = _keep,
  }) => CrazeResume(
    gen: gen ?? this.gen,
    mode: mode ?? this.mode,
    load: load ?? this.load,
    rows: rows ?? this.rows,
    gone: identical(gone, _keep) ? this.gone : gone as SavedGone?,
    landed: identical(landed, _keep) ? this.landed : landed as CrazeResumed?,
  );

  @override
  bool operator ==(Object other) =>
      other is CrazeResume &&
      other.gen == gen &&
      other.mode == mode &&
      identical(other.load, load) &&
      mapEquals(other.rows, rows) &&
      other.gone == gone &&
      identical(other.landed, landed);

  @override
  int get hashCode =>
      Object.hash(gen, mode, load, Object.hashAll(rows.entries), gone, landed);
}

/// What the sheet says under a list craze cut short.
const moreNote = 'Showing the 50 most recent.';

/// A running reopen's button. It can take minutes: a provider's load replays
/// the session, and craze is allowed 200 s per answer, sent again once.
const resumingLabel = 'Resuming… (this can take a few minutes)';

/// What a saved session with no title is called.
const untitled = 'Untitled';

/// What a row says when its reopen's answer was `superseded`: the session
/// runs, but the craze connection it was answered on has been replaced, so it
/// was not opened — and a Resume of it now joins it through the one there is.
const supersededNote =
    'craze resumed the session, but this machine\'s craze connection was '
    'replaced meanwhile, so it was not opened — Resume again to open it';

/// What the screen says when a reopen's session has already ended again.
const resumedEnded = 'craze reopened the session, and it has already ended.';

/// **Whether the sheet offers `New | Resume`** (PC11): when the create
/// options it just read say the hub can reopen — and while it already shows
/// Resume (a reopen running when the sheet was reopened, its options still
/// loading).
bool resumeOffered(bool? optionsReopen, CrazeResume r) =>
    optionsReopen == true || r.mode == CrazeSheetMode.resume;

/// The saved id whose reopen is running, or null. One at a time.
String? resumingId(CrazeResume r) {
  for (final MapEntry(:key, :value) in r.rows.entries) {
    if (value is SavedResuming) return key;
  }
  return null;
}

/// **Whether the `New | Resume` control is locked**: while a create is
/// submitting or a reopen is running — each finishes in the half it started
/// in.
bool modeLocked(bool createSubmitting, CrazeResume r) =>
    createSubmitting || resumingId(r) != null;

/// A sheet OPENING: nothing is cached (the create options' D8), so the list is
/// read again on the first choice of Resume and the sheet opens on New —
/// unless a reopen is still running, which the sheet then shows as it left it
/// (while it is still this incarnation's: the sheet observes the feed first,
/// [observeSource]). The incarnation the state is bound to is kept either way
/// — it is not the sheet's content but what fences an older incarnation's late
/// word out of the fresh one.
CrazeResume onSheetOpen(CrazeResume r) =>
    resumingId(r) != null ? r : CrazeResume(gen: r.gen);

/// Whether [gen] is a NEWER incarnation than the state's — [gen] said, the
/// state bound, and [gen] the larger: incarnations only grow (one counter for
/// the app's run), so a later one's is always the larger, and a smaller one is
/// an incarnation already replaced.
bool _newerSource(CrazeResume r, int? gen) =>
    gen != null && r.gen != null && gen > r.gen!;

/// **An answer about the machine came through its feed incarnation [gen]**:
/// the state is bound to that incarnation. The first one binds it; the same
/// one changes nothing; a NEWER one means the machine's feed was rebuilt (the
/// machine removed and added again under the same name, say) since this state
/// was made, so nothing in it is this incarnation's — a reopen left running
/// included — and it starts afresh, bound to [gen], on New. That reopen's
/// answer then finds no attempt to land on and is dropped whole
/// ([reopenLanding]). An OLDER one is a late word from an incarnation already
/// replaced: it changes nothing. No [gen] changes nothing.
CrazeResume observeSource(CrazeResume r, int? gen) {
  if (gen == null || r.gen == gen) return r;
  if (r.gen == null) return r.copyWith(gen: gen);
  return _newerSource(r, gen) ? CrazeResume(gen: gen) : r;
}

/// **Where a failed create-options read is said, with its Retry**: in the
/// half that shows — the New half's provider field, or, in Resume, above the
/// saved list. A sheet opened onto Resume (a reopen left running) must still
/// be able to read the options again: they say what offers `New | Resume`
/// once that reopen settles, and the providers New needs. The Retry is never
/// locked. Null while the read has not failed.
CrazeSheetMode? optionsRetryHalf(bool optionsFailed, CrazeResume r) =>
    optionsFailed ? r.mode : null;

/// Choose a half. The list is NOT read here: [listNeeded] says when the
/// controller reads it — the first time Resume is chosen.
CrazeResume chooseMode(CrazeResume r, CrazeSheetMode mode) =>
    r.mode == mode ? r : r.copyWith(mode: mode);

/// Whether the controller should read the saved list now: Resume shows, and
/// nothing has been read (or is being read) since the sheet opened.
bool listNeeded(CrazeResume r) =>
    r.mode == CrazeSheetMode.resume && r.load is SavedUnloaded;

/// A read of the list starts (the first choice, or Retry after a failed
/// read), fenced by [token]. A dropped row's note goes with the old list.
CrazeResume beginList(CrazeResume r, int token) =>
    r.copyWith(load: SavedLoading(token), gone: null);

/// How a saved-list read settled.
sealed class SavedListOutcome {
  const SavedListOutcome();
}

/// craze's list, read through the feed incarnation [gen].
final class SavedListed extends SavedListOutcome {
  const SavedListed(this.list, {required this.gen});

  final BridgeLaneSavedSessions list;
  final int? gen;
}

/// The read was refused.
final class SavedListRefused extends SavedListOutcome {
  const SavedListRefused(this.refusal);

  final CrazeRefusal refusal;
}

/// A read settles — applied only when it is still THE read ([token]), so an
/// answer for a sheet since closed and reopened never lands on the new one. A
/// fresh list forgets every row's settled state; a running reopen's stays —
/// unless the list came through a NEWER incarnation than the state's
/// ([observeSource]'s rule): then that reopen is the old one's, and goes too.
/// The list binds an unbound state to its incarnation, and moves a bound one
/// only forward (an older one's list still lands, as words about the machine;
/// it names nothing the state is bound to).
CrazeResume settleList(CrazeResume r, int token, SavedListOutcome outcome) {
  final load = r.load;
  if (load is! SavedLoading || load.token != token) return r;
  switch (outcome) {
    case SavedListRefused(:final refusal):
      return r.copyWith(load: SavedFailed(refusal));
    case SavedListed(:final list, :final gen):
      final moved = _newerSource(r, gen);
      final running = moved ? null : resumingId(r);
      return r.copyWith(
        gen: r.gen == null || moved ? gen : r.gen,
        load: SavedReady(List.unmodifiable(list.sessions), more: list.more),
        rows: running != null ? {running: r.rows[running]!} : const {},
      );
  }
}

/// The listed saved session [id], if the list holds it.
BridgeLaneSavedSession? savedSession(CrazeResume r, String id) {
  final load = r.load;
  if (load is! SavedReady) return null;
  for (final s in load.sessions) {
    if (s.id == id) return s;
  }
  return null;
}

/// A row's state (an absent one is idle).
SavedRowState rowState(CrazeResume r, String id) =>
    r.rows[id] ?? const SavedIdle();

/// **Whether [id]'s button works**: Resume shows, the list holds it, and no
/// reopen runs — one at a time, so every other button is disabled while one
/// does (its own reads Resuming…).
bool canResume(CrazeResume r, String id) =>
    r.mode == CrazeSheetMode.resume &&
    savedSession(r, id) != null &&
    resumingId(r) == null;

/// A reopen starts as the controller's [attempt] (a number no other reopen of
/// that machine carries) — refused (unchanged) by [canResume]'s rule.
CrazeResume beginResume(CrazeResume r, String id, int attempt) {
  if (!canResume(r, id)) return r;
  return r.copyWith(rows: {...r.rows, id: SavedResuming(attempt)}, gone: null);
}

/// Whether [attempt] is still the reopen running on [id] in [r].
bool _stillRunning(CrazeResume r, String id, int attempt) {
  final s = r.rows[id];
  return s is SavedResuming && s.attempt == attempt;
}

/// Where a reopen's SUCCESS lands — see [ReopenLanding].
ReopenLanding reopenLanding(
  CrazeResume r,
  String id,
  int attempt,
  ReopenAnswer answer,
) {
  if (!_stillRunning(r, id, attempt)) return ReopenLanding.dropped;
  if (answer.superseded) return ReopenLanding.superseded;
  return answer.ended ? ReopenLanding.ended : ReopenLanding.open;
}

/// How a reopen settled.
sealed class ResumeOutcome {
  const ResumeOutcome();
}

/// craze reopened it.
final class Resumed extends ResumeOutcome {
  const Resumed(this.answer);

  final ReopenAnswer answer;
}

/// The reopen was refused (see [reopenRefusalOf] for the codes).
final class ResumeRefused extends ResumeOutcome {
  const ResumeRefused(this.refusal);

  final CrazeRefusal refusal;
}

/// A reopen settles, by its code — never by its words — and only while
/// [attempt] is still the one running on [id] (else nothing changes:
/// [reopenLanding]'s `dropped`):
/// - **success** — the session runs now, so it is no longer saved: its row
///   leaves the list (the sheet gives way to its transcript, the controller's
///   part) — unless the answer was `superseded`, which keeps the row and says
///   so ([supersededNote]): Resume again joins the session through the
///   machine's craze as it is now;
/// - **`gone`** — it cannot run here any more (no such id, its directory
///   gone): the row is DROPPED and craze's words said where it was;
/// - **`unavailable`** — transient, a lost answer included: said inline, with
///   Retry;
/// - **anything else** (`start_failed`, a contract error): said inline, the
///   row KEPT.
CrazeResume settleResume(
  CrazeResume r,
  String id,
  int attempt,
  ResumeOutcome outcome,
) {
  if (!_stillRunning(r, id, attempt)) return r;
  final rows = {...r.rows}..remove(id);
  SavedLoad drop(SavedLoad load) => load is SavedReady
      ? SavedReady(
          List.unmodifiable(load.sessions.where((s) => s.id != id)),
          more: load.more,
        )
      : load;
  switch (outcome) {
    case Resumed(:final answer):
      if (answer.superseded) {
        return r.copyWith(
          rows: {
            ...rows,
            id: const SavedRefused(CrazeRefusal('superseded', supersededNote)),
          },
        );
      }
      return r.copyWith(load: drop(r.load), rows: rows);
    case ResumeRefused(:final refusal) when refusal.code == 'gone':
      final s = savedSession(r, id);
      return r.copyWith(
        load: drop(r.load),
        rows: rows,
        gone: (
          id: id,
          title: s == null ? id : savedTitle(s.title),
          message: refusal.message,
        ),
      );
    case ResumeRefused(:final refusal):
      return r.copyWith(
        rows: {
          ...rows,
          id: refusal.code == 'unavailable'
              ? SavedUnavailable(refusal)
              : SavedRefused(refusal),
        },
      );
  }
}

/// **A reopen's failure, as the sheet reads it** — by the bridge's variant,
/// never by its text (plan 032 PC10):
/// - [BridgeLaneReopenError_Gone] → `gone` (drop the row);
/// - [BridgeLaneReopenError_StartFailed] → `start_failed` (the cause, the row
///   kept);
/// - [BridgeLaneReopenError_Unavailable] → `unavailable` (Retry) — a lost
///   answer included;
/// - [BridgeLaneReopenError_Lane] → the lane contract's own code
///   ([crazeRefusalOf]), the row kept — except an unknown outcome, which for
///   a reopen is Retry: a reopen means "ensure it runs", so trying again
///   joins whatever the first one started (PC14d);
/// - a [StateError] is the feed refusing before it sent anything (no craze
///   source on that machine right now) — `unavailable`, Retry;
/// - anything else is an outcome nobody knows — `unavailable` for the same
///   reason: Retry is always safe.
CrazeRefusal reopenRefusalOf(Object e) => switch (e) {
  BridgeLaneReopenError_Gone(:final msg) => CrazeRefusal('gone', msg),
  BridgeLaneReopenError_StartFailed(:final msg) => CrazeRefusal(
    'start_failed',
    msg,
  ),
  BridgeLaneReopenError_Unavailable(:final msg) => CrazeRefusal(
    'unavailable',
    msg,
  ),
  BridgeLaneReopenError_Lane(:final error) => switch (crazeRefusalOf(error)) {
    CrazeRefusal(code: 'outcome_unknown', :final message) => CrazeRefusal(
      'unavailable',
      message,
    ),
    final refusal => refusal,
  },
  StateError(:final message) => CrazeRefusal('unavailable', message),
  _ => CrazeRefusal('unavailable', '$e'),
};

/// A row's button label: Resume; Resuming… while its reopen runs; Retry after
/// `unavailable`.
String resumeLabel(SavedRowState state) => switch (state) {
  SavedResuming() => resumingLabel,
  SavedUnavailable() => 'Retry',
  SavedIdle() || SavedRefused() => 'Resume',
};

/// Where a row's refusal is said: a start failure's cause verbatim (monospace,
/// as the create sheet says one), anything else as said — `unavailable`
/// adding that Retry is how to try again. Null for none.
({RefusalWhere where, String text})? savedRowError(SavedRowState state) =>
    switch (state) {
      SavedRefused(:final refusal) => (
        where: refusal.code == 'start_failed'
            ? RefusalWhere.cause
            : RefusalWhere.general,
        text: refusal.message,
      ),
      SavedUnavailable(:final refusal) => (
        where: RefusalWhere.general,
        text: '${refusal.message} — Retry',
      ),
      SavedIdle() || SavedResuming() => null,
    };

/// A saved session's title, or "Untitled".
String savedTitle(String? title) {
  final t = title?.trim() ?? '';
  return t.isEmpty ? untitled : t;
}

/// **When a saved session was last active, relative to [now]** (both Unix
/// ms): "just now", "N min ago", "N h ago", "yesterday", "N days ago", then the
/// date (UTC). A time in the future — a clock ahead of this one — is "just
/// now"; no time at all (0) is "".
String relativeAge(int ms, int now) {
  if (ms <= 0) return '';
  final secs = ((now - ms) / 1000).floor();
  if (secs < 60) return 'just now';
  final mins = secs ~/ 60;
  if (mins < 60) return '$mins min ago';
  final hours = mins ~/ 60;
  if (hours < 24) return '$hours h ago';
  final days = hours ~/ 24;
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  return DateTime.fromMillisecondsSinceEpoch(
    ms,
    isUtc: true,
  ).toIso8601String().substring(0, 10);
}

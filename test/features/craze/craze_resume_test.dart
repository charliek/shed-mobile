import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/craze/craze_create.dart';
import 'package:shed_mobile/features/craze/craze_resume.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';

/// **The craze create sheet's Resume half, as rules** (plan 032 §3.4, M3) —
/// `craze_resume.dart`, the desktop's `crazeResume.ts` ported rule for rule,
/// its node cases (`desktop/tauri/ui/test/crazeResume.test.mjs`) translated
/// case for case where the rule is shared. The cases marked CONTROL are the
/// plan's own: Resume shown exactly when the create options say `reopen`, the
/// list read on the FIRST choice of Resume, one reopen at a time with every
/// other button disabled, `gone` dropping the row, `start_failed` and contract
/// errors keeping it, `unavailable` offering Retry — branched on the code,
/// never the words — and the state bound to the machine's INCARNATION (a feed
/// rebuilt starts afresh, and the old one's late answer is dropped whole), a
/// `superseded` answer never opened. The desktop shell's own cases (every
/// status applied to every machine's state, a resume onto the panel already
/// on screen) have no phone counterpart: the phone observes through its
/// controller, and a transcript always opens as a new screen.
const _a = BridgeLaneSavedSession(
  id: '0192f0aa-a',
  provider: 'grok',
  workspace: '/home/me/proj',
  title: 'fix the parser',
  updatedUnixMs: 1000,
);
const _b = BridgeLaneSavedSession(
  id: 'grok:legacy',
  provider: 'grok',
  workspace: '/srv/other',
  updatedUnixMs: 500,
);

const _resumeMode = CrazeSheetMode.resume;
const _newMode = CrazeSheetMode.newSession;

/// craze's list of [sessions], read through incarnation [gen].
SavedListed _list(
  List<BridgeLaneSavedSession> sessions, {
  bool more = false,
  int? gen,
}) => SavedListed(
  BridgeLaneSavedSessions(sessions: sessions, more: more),
  gen: gen,
);

/// The sheet in Resume mode with [_a, _b] listed, through incarnation [gen].
CrazeResume _listed({bool more = false, int? gen}) => settleList(
  beginList(chooseMode(CrazeResume.empty, _resumeMode), 1),
  1,
  _list(const [_a, _b], more: more, gen: gen),
);

/// [_listed], with [_a]'s reopen running as attempt 1.
CrazeResume _running({int? gen}) => beginResume(_listed(gen: gen), _a.id, 1);

List<String> _ids(CrazeResume r) => [
  for (final s in (r.load as SavedReady).sessions) s.id,
];

CrazeResume _refuse(CrazeResume r, String id, int attempt, CrazeRefusal x) =>
    settleResume(r, id, attempt, ResumeRefused(x));

CrazeResume _resumed(
  CrazeResume r,
  String id,
  int attempt, {
  bool superseded = false,
  bool ended = false,
}) => settleResume(
  r,
  id,
  attempt,
  Resumed((superseded: superseded, ended: ended)),
);

const ReopenAnswer _open = (superseded: false, ended: false);

void main() {
  test('CONTROL: New | Resume shows exactly when the options say reopen', () {
    expect(resumeOffered(true, CrazeResume.empty), isTrue);
    expect(
      resumeOffered(false, CrazeResume.empty),
      isFalse,
      reason: 'a hub before 0.2.0',
    );
    expect(
      resumeOffered(null, CrazeResume.empty),
      isFalse,
      reason: 'options not read yet',
    );
    // A sheet reopened while its reopen runs shows Resume before its options
    // land.
    final running = _running();
    expect(resumeOffered(null, running), isTrue);
  });

  test('CONTROL: the list is read on the FIRST choice of Resume, and not '
      'again until the sheet reopens', () {
    expect(
      listNeeded(CrazeResume.empty),
      isFalse,
      reason: 'the sheet opens on New',
    );
    final chosen = chooseMode(CrazeResume.empty, _resumeMode);
    expect(chosen.mode, _resumeMode);
    expect(listNeeded(chosen), isTrue);
    final loading = beginList(chosen, 7);
    expect(listNeeded(loading), isFalse, reason: 'a read is running');
    final ready = settleList(loading, 7, _list([_a]));
    expect(
      listNeeded(chooseMode(chooseMode(ready, _newMode), _resumeMode)),
      isFalse,
      reason: 'kept across New and back',
    );
    expect(
      onSheetOpen(ready),
      CrazeResume.empty,
      reason: 'nothing cached across opens',
    );
    expect(listNeeded(chooseMode(onSheetOpen(ready), _resumeMode)), isTrue);
  });

  test('a read\'s answer lands only on the read that asked (the token)', () {
    final loading = beginList(chooseMode(CrazeResume.empty, _resumeMode), 2);
    final late = settleList(loading, 1, _list([_a]));
    expect(
      identical(late, loading),
      isTrue,
      reason: 'an older read\'s answer is dropped',
    );
    const busy = CrazeRefusal('unavailable', 'busy');
    final failed = settleList(loading, 2, const SavedListRefused(busy));
    expect((failed.load as SavedFailed).refusal, busy);
    expect(
      identical(settleList(failed, 2, _list([_a])), failed),
      isTrue,
      reason: 'a settled read takes no second answer',
    );
    // Retry after a failed read is a new read.
    expect(beginList(failed, 3).load, isA<SavedLoading>());
  });

  test('a fresh list keeps craze\'s order and more — and forgets settled '
      'rows', () {
    final r = _listed(more: true);
    expect(_ids(r), [_a.id, _b.id]);
    expect((r.load as SavedReady).more, isTrue);
    expect(moreNote, 'Showing the 50 most recent.');
    final refused = _refuse(
      beginResume(r, _a.id, 1),
      _a.id,
      1,
      const CrazeRefusal('start_failed', 'x'),
    );
    final again = settleList(beginList(refused, 9), 9, _list([_a]));
    expect(rowState(again, _a.id), const SavedIdle());
  });

  test('CONTROL: one reopen at a time — every other button is disabled '
      'while one runs', () {
    final r = _listed();
    expect(canResume(r, _a.id), isTrue);
    expect(canResume(r, _b.id), isTrue);
    expect(canResume(r, 'not-listed'), isFalse);
    final running = beginResume(r, _a.id, 1);
    expect(resumingId(running), _a.id);
    expect(rowState(running, _a.id), const SavedResuming(1));
    expect(canResume(running, _b.id), isFalse, reason: 'the other row waits');
    expect(
      canResume(running, _a.id),
      isFalse,
      reason: 'and its own is Resuming…',
    );
    expect(
      identical(beginResume(running, _b.id, 2), running),
      isTrue,
      reason: 'a second press is refused',
    );
    expect(resumeLabel(rowState(running, _a.id)), resumingLabel);
    expect(resumingLabel, 'Resuming… (this can take a few minutes)');
    expect(
      canResume(chooseMode(r, _newMode), _a.id),
      isFalse,
      reason: 'only in Resume',
    );
  });

  test('CONTROL: the mode is locked while a create submits or a reopen '
      'runs', () {
    expect(modeLocked(false, CrazeResume.empty), isFalse);
    expect(modeLocked(true, CrazeResume.empty), isTrue);
    expect(modeLocked(false, _running()), isTrue);
  });

  test('CONTROL: success takes the row off the list — it runs now', () {
    final done = _resumed(_running(), _a.id, 1);
    expect(_ids(done), [_b.id]);
    expect(resumingId(done), isNull);
    expect(done.gone, isNull);
    expect(canResume(done, _b.id), isTrue, reason: 'the others work again');
  });

  test('CONTROL: gone drops the row and says why where it was', () {
    const words =
        'the session\'s directory /home/me/proj is no longer a directory';
    final gone = _refuse(
      _running(),
      _a.id,
      1,
      const CrazeRefusal('gone', words),
    );
    expect(_ids(gone), [_b.id]);
    expect(gone.gone, (id: _a.id, title: 'fix the parser', message: words));
    expect(rowState(gone, _a.id), const SavedIdle());
    // The next reopen clears the note.
    expect(beginResume(gone, _b.id, 2).gone, isNull);
    // An untitled one is named "Untitled".
    final untitledGone = _refuse(
      beginResume(_listed(), _b.id, 1),
      _b.id,
      1,
      const CrazeRefusal('gone', 'm'),
    );
    expect(untitledGone.gone?.title, untitled);
  });

  test('CONTROL: start_failed and contract errors keep the row, said inline; '
      'Resume works again', () {
    for (final code in [
      'start_failed',
      'failed',
      'bad_request',
      'not_accepting',
    ]) {
      final refusal = CrazeRefusal(code, 'words for $code');
      final r = _refuse(_running(), _a.id, 1, refusal);
      expect(_ids(r), [_a.id, _b.id], reason: code);
      expect(rowState(r, _a.id), SavedRefused(refusal), reason: code);
      expect(resumeLabel(rowState(r, _a.id)), 'Resume', reason: code);
      expect(canResume(r, _a.id), isTrue, reason: code);
      expect(r.gone, isNull, reason: code);
    }
    final failed = _refuse(
      _running(),
      _a.id,
      1,
      const CrazeRefusal('start_failed', 'could not start: grok exited'),
    );
    expect(savedRowError(rowState(failed, _a.id)), (
      where: RefusalWhere.cause,
      text: 'could not start: grok exited',
    ));
    final other = _refuse(
      _running(),
      _a.id,
      1,
      const CrazeRefusal('failed', 'boom'),
    );
    expect(savedRowError(rowState(other, _a.id)), (
      where: RefusalWhere.general,
      text: 'boom',
    ));
  });

  test('CONTROL: unavailable — a lost answer\'s too — offers Retry, the row '
      'kept', () {
    const lost =
        'the reopen\'s answer was lost; the session may already be running — '
        'Retry is safe (twice: deadline)';
    final r = _refuse(
      _running(),
      _a.id,
      1,
      const CrazeRefusal('unavailable', lost),
    );
    expect(rowState(r, _a.id), isA<SavedUnavailable>());
    expect(resumeLabel(rowState(r, _a.id)), 'Retry');
    expect(savedRowError(rowState(r, _a.id)), (
      where: RefusalWhere.general,
      text: '$lost — Retry',
    ));
    expect(canResume(r, _a.id), isTrue);
    expect(_ids(r), [_a.id, _b.id]);
  });

  test('a settle with no reopen running changes nothing', () {
    final r = _listed();
    expect(identical(_resumed(r, _a.id, 1), r), isTrue);
  });

  test('CONTROL: a sheet opening keeps a running reopen, else starts '
      'fresh', () {
    final running = _running();
    expect(identical(onSheetOpen(running), running), isTrue);
    final settled = _refuse(
      running,
      _a.id,
      1,
      const CrazeRefusal('failed', 'x'),
    );
    expect(onSheetOpen(settled), CrazeResume.empty);
    // Afresh — but still bound to its incarnation, which fences an older
    // one's late word out of the fresh sheet.
    final settledAt = _refuse(
      _running(gen: 5),
      _a.id,
      1,
      const CrazeRefusal('failed', 'x'),
    );
    expect(onSheetOpen(settledAt), const CrazeResume(gen: 5));
    expect(
      observeSource(onSheetOpen(settledAt), 4).gen,
      5,
      reason: 'an older incarnation\'s word binds nothing',
    );
  });

  test('a fresh list keeps a running reopen\'s row', () {
    final running = _running();
    final relisted = settleList(beginList(running, 5), 5, _list([_a, _b]));
    expect(resumingId(relisted), _a.id);
  });

  test('CONTROL: an answer names the incarnation — the first binds, the '
      'same keeps, another starts afresh', () {
    expect(CrazeResume.empty.gen, isNull);
    final bound = observeSource(CrazeResume.empty, 5);
    expect(bound.gen, 5, reason: 'the first binds');
    expect(
      identical(observeSource(bound, 5), bound),
      isTrue,
      reason: 'the same incarnation changes nothing',
    );
    expect(
      identical(observeSource(bound, null), bound),
      isTrue,
      reason: 'none said changes nothing',
    );
    expect(_listed(gen: 5).gen, 5, reason: 'the list binds it too');
    final running = _running(gen: 5);
    // Left while it runs, and opened again on the SAME feed: as left.
    expect(identical(onSheetOpen(observeSource(running, 5)), running), isTrue);
    // The feed rebuilt meanwhile (the machine removed and added again under
    // the same name): incarnation 6 — a fresh sheet.
    final fresh = onSheetOpen(observeSource(running, 6));
    expect(
      fresh,
      const CrazeResume(gen: 6),
      reason: 'on New, nothing listed, nothing running',
    );
    expect(
      modeLocked(false, fresh),
      isFalse,
      reason: 'not locked by the old incarnation\'s reopen',
    );
    expect(
      resumeOffered(null, fresh),
      isFalse,
      reason: 'nor shows Resume before ITS options say reopen',
    );
    expect(
      listNeeded(chooseMode(fresh, _resumeMode)),
      isTrue,
      reason: 'and it reads its own list',
    );
  });

  test('CONTROL: an older incarnation\'s late answer is dropped — no state '
      'change, no landing', () {
    final fresh = observeSource(_running(gen: 5), 6);
    for (final answer in <ReopenAnswer>[
      _open,
      (superseded: false, ended: true),
      (superseded: true, ended: false),
    ]) {
      expect(
        reopenLanding(fresh, _a.id, 1, answer),
        ReopenLanding.dropped,
        reason: '$answer',
      );
      expect(
        identical(settleResume(fresh, _a.id, 1, Resumed(answer)), fresh),
        isTrue,
        reason: '$answer',
      );
    }
    expect(
      identical(
        _refuse(fresh, _a.id, 1, const CrazeRefusal('gone', 'm')),
        fresh,
      ),
      isTrue,
      reason: 'its refusal too',
    );
    // The same session resumed again on the new incarnation is ITS OWN
    // attempt: the old answer never lands on it.
    final relisted = settleList(
      beginList(chooseMode(fresh, _resumeMode), 2),
      2,
      _list([_a, _b], gen: 6),
    );
    final again = beginResume(relisted, _a.id, 2);
    expect(reopenLanding(again, _a.id, 1, _open), ReopenLanding.dropped);
    expect(identical(_resumed(again, _a.id, 1), again), isTrue);
    expect(
      reopenLanding(again, _a.id, 2, _open),
      ReopenLanding.open,
      reason: 'its own lands',
    );
  });

  test('the list binds the state to its incarnation — an older one\'s rows '
      'go', () {
    // The feed rebuilt between the options read and the list read.
    final reading = beginList(
      chooseMode(observeSource(CrazeResume.empty, 5), _resumeMode),
      3,
    );
    final moved = settleList(reading, 3, _list([_a], gen: 6));
    expect(moved.gen, 6);
    expect(_ids(moved), [_a.id]);
    // A running reopen never survives a list of another incarnation.
    final running = _running(gen: 5);
    final rereading = running.copyWith(load: const SavedLoading(9));
    final other = settleList(rereading, 9, _list([_a], gen: 6));
    expect(resumingId(other), isNull);
    expect(reopenLanding(other, _a.id, 1, _open), ReopenLanding.dropped);
    final same = settleList(rereading, 9, _list([_a], gen: 5));
    expect(
      rowState(same, _a.id),
      const SavedResuming(1),
      reason: 'its own incarnation\'s keeps it',
    );
  });

  test('CONTROL: an OLDER incarnation\'s word changes nothing — '
      'incarnations only grow', () {
    final bound = observeSource(CrazeResume.empty, 7);
    expect(identical(observeSource(bound, 5), bound), isTrue);
    final running = beginResume(_listed(gen: 7), _a.id, 1);
    expect(
      identical(observeSource(running, 5), running),
      isTrue,
      reason: 'a running reopen of the CURRENT one is kept',
    );
    final rereading = running.copyWith(load: const SavedLoading(4));
    final old = settleList(rereading, 4, _list([_a], gen: 5));
    expect(old.gen, 7);
    expect(rowState(old, _a.id), const SavedResuming(1));
  });

  test('CONTROL: a failed options read offers its Retry in the half that '
      'shows — Resume included', () {
    final running = _running(gen: 5);
    expect(running.mode, _resumeMode);
    expect(modeLocked(false, running), isTrue);
    expect(optionsRetryHalf(true, running), _resumeMode);
    expect(optionsRetryHalf(true, CrazeResume.empty), _newMode);
    expect(optionsRetryHalf(true, chooseMode(_listed(), _newMode)), _newMode);
    expect(optionsRetryHalf(false, running), isNull);
  });

  test('CONTROL: a superseded answer is not openable — said on the row, the '
      'row kept', () {
    final running = _running(gen: 5);
    expect(
      reopenLanding(running, _a.id, 1, (superseded: true, ended: false)),
      ReopenLanding.superseded,
    );
    final r = _resumed(running, _a.id, 1, superseded: true);
    expect(_ids(r), [_a.id, _b.id], reason: 'kept: Resume again joins it');
    expect(
      rowState(r, _a.id),
      const SavedRefused(CrazeRefusal('superseded', supersededNote)),
    );
    expect(savedRowError(rowState(r, _a.id)), (
      where: RefusalWhere.general,
      text: supersededNote,
    ));
    expect(resumeLabel(rowState(r, _a.id)), 'Resume');
    expect(canResume(r, _a.id), isTrue);
    expect(modeLocked(false, r), isFalse);
  });

  test('CONTROL: a current answer opens its transcript — or says it '
      'ended', () {
    final running = _running(gen: 5);
    expect(reopenLanding(running, _a.id, 1, _open), ReopenLanding.open);
    expect(
      reopenLanding(running, _a.id, 1, (superseded: false, ended: true)),
      ReopenLanding.ended,
    );
    final ended = _resumed(running, _a.id, 1, ended: true);
    expect(_ids(ended), [
      _b.id,
    ], reason: 'as any success: its row leaves the list');
  });

  test('CONTROL: a reopen\'s failure is read by its variant, never its '
      'words', () {
    expect(
      reopenRefusalOf(const BridgeLaneReopenError.gone(msg: 'no such')),
      const CrazeRefusal('gone', 'no such'),
    );
    expect(
      reopenRefusalOf(
        const BridgeLaneReopenError.startFailed(msg: 'could not start: x'),
      ),
      const CrazeRefusal('start_failed', 'could not start: x'),
    );
    expect(
      reopenRefusalOf(
        const BridgeLaneReopenError.unavailable(msg: 'Retry is safe'),
      ),
      const CrazeRefusal('unavailable', 'Retry is safe'),
    );
    expect(
      reopenRefusalOf(
        const BridgeLaneReopenError.lane(
          error: BridgeLaneError.badRequest(msg: 'bad id'),
        ),
      ),
      const CrazeRefusal('bad_request', 'bad id'),
      reason: 'a contract error keeps its own code: the row stays',
    );
    expect(
      reopenRefusalOf(
        const BridgeLaneReopenError.lane(
          error: BridgeLaneError.failed(msg: 'boom'),
        ),
      ),
      const CrazeRefusal('failed', 'boom'),
    );
    expect(
      reopenRefusalOf(
        const BridgeLaneReopenError.lane(
          error: BridgeLaneError.outcomeUnknown(msg: 'lost'),
        ),
      ),
      const CrazeRefusal('unavailable', 'lost'),
      reason: 'an unknown outcome is Retry: a reopen joins what it started',
    );
    expect(
      reopenRefusalOf(StateError('craze is not connected on mini3')),
      const CrazeRefusal('unavailable', 'craze is not connected on mini3'),
      reason: 'the feed refused before anything was sent: transient',
    );
    expect(
      reopenRefusalOf(Exception('a bridge panic')).code,
      'unavailable',
      reason: 'an outcome nobody knows is Retry too',
    );
    // Words that LOOK like another variant's never change the code.
    expect(
      reopenRefusalOf(
        const BridgeLaneReopenError.unavailable(msg: 'gone: start_failed'),
      ).code,
      'unavailable',
    );
  });

  test('the title, or Untitled', () {
    expect(savedTitle(_a.title), 'fix the parser');
    expect(savedTitle(_b.title), untitled);
    expect(savedTitle('   '), untitled);
    expect(untitled, 'Untitled');
  });

  test('the age reads relative, then as a date', () {
    final now = DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch;
    String ago(int ms) => relativeAge(now - ms, now);
    expect(ago(5000), 'just now');
    expect(
      relativeAge(now + 60000, now),
      'just now',
      reason: 'a clock ahead of ours',
    );
    expect(ago(5 * 60000), '5 min ago');
    expect(ago(3 * 3600000), '3 h ago');
    expect(ago(30 * 3600000), 'yesterday');
    expect(ago(4 * 86400000), '4 days ago');
    expect(
      relativeAge(DateTime.utc(2026, 8).millisecondsSinceEpoch, now),
      '2026-08-01',
    );
    expect(relativeAge(0, now), '', reason: 'no time');
  });
}

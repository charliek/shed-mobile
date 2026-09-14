import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/ssh/roost_reach.dart';

/// **Dart's leg of roost's classifier** (plan 020 amendment A2).
///
/// The table itself is pinned against the shared golden
/// `crates/fixtures/roost-vectors/stderr-classes.json` from
/// `integration_test/roost_goldens_test.dart`, beside the Rust and Go legs that
/// read the same file — that is what makes three implementations provably the
/// same rather than the same today.
///
/// What lives here is the fast half: the precedence order, which is the one
/// property that breaks silently (several blobs match two rules, and the answer
/// is whichever rule comes first), and the observer that carries an observation
/// from the transport to the two things that read it.
/// The class this file names most, spelled once.
const SshFailureClass notFound = SshFailureClass.notFound;

void main() {
  group('classifySshFailure', () {
    test('a changed host key outranks the verification failure it prints '
        'next', () {
      // ssh prints "Host key verification failed." right after the banner, so
      // a classifier that checked that rule first would report an unknown host
      // key for a machine-in-the-middle.
      final verdict = classifySshFailure(
        255,
        '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\n'
        'Host key verification failed.\n',
      );
      expect(verdict.failureClass, SshFailureClass.changedHostKey);
      expect(verdict.detail, isEmpty);
    });

    test('a refused login outranks a no-session line underneath it', () {
      final verdict = classifySshFailure(
        255,
        'shed@mini3: Permission denied (publickey).\n'
        'client-bridge: no session\n',
      );
      expect(verdict.failureClass, SshFailureClass.auth);
    });

    test('no-session outranks exit 127, which is the case that decides an '
        'OFFER', () {
      // The two actionable classes, and the only pair whose order changes what
      // a card offers: a start, not an install.
      final verdict = classifySshFailure(127, 'client-bridge: no session\n');
      expect(verdict.failureClass, SshFailureClass.noSession);
      expect(reachKindFor(verdict.failureClass), BridgeReachKind.noSession);
    });

    test('command not found and a bare 127 are both not-found', () {
      const missing = 'roost-session: command not found\n';
      expect(classifySshFailure(null, missing).failureClass, notFound);
      expect(classifySshFailure(127, '').failureClass, notFound);
      expect(reachKindFor(notFound), BridgeReachKind.notInstalled);
    });

    test('anything else is transport, carrying its last non-empty line', () {
      // 255 is NOT special-cased: roost does not, and neither does this.
      final verdict = classifySshFailure(
        255,
        'Welcome to Ubuntu\n\nkex_exchange_identification: read: Connection reset by peer\n\n',
      );
      expect(verdict.failureClass, SshFailureClass.transport);
      expect(
        verdict.detail,
        'kex_exchange_identification: read: Connection reset by peer',
      );
    });
  });

  test('lastNonEmptyLine takes the LAST line, trimmed, and nothing when there '
      'is none', () {
    expect(lastNonEmptyLine('first\n  last  \n\n'), 'last');
    expect(lastNonEmptyLine('   \n\n'), '');
    expect(lastNonEmptyLine(''), '');
  });

  test('NO class maps to `other`, which is what `other` means', () {
    // `Other` is what a failure that never ran an exec at all reports. A class
    // landing there would be a machine shrugging at an answer it had.
    for (final failureClass in SshFailureClass.values) {
      expect(
        reachKindFor(failureClass),
        isNot(BridgeReachKind.other),
        reason: '${failureClass.wire} must name an answer, not a shrug',
      );
    }
  });

  group('noteForExecStderr', () {
    test('records the two lines that name something the phone can DO', () {
      // The whole of amendment A2 in two strings: these are what a cold
      // machine and a stopped one actually write to that band.
      expect(
        noteForExecStderr('roost-session: command not found\n')?.kind,
        BridgeReachKind.notInstalled,
      );
      expect(
        noteForExecStderr('client-bridge: no session\n')?.kind,
        BridgeReachKind.noSession,
      );
      expect(
        noteForExecStderr('roost-session: command not found\n')?.message,
        'roost-session: command not found',
        reason: 'the far side\'s own words, trimmed and not rewritten',
      );
    });

    test('records NOTHING for a line roost did not name', () {
      // The fallback class means "nothing here is recognizable", and on a
      // remote process's own stderr that is a chatty program, not an
      // unreachable machine. Recording `Unreachable` here would put a guess
      // where the honest answer is "offer nothing" — and would do it on every
      // login banner.
      expect(noteForExecStderr('Welcome to Ubuntu 24.04.1 LTS\n'), isNull);
      expect(noteForExecStderr(''), isNull);
    });
  });

  group('RoostReachObserver', () {
    test('remembers the last thing the transport said, until a snapshot '
        'clears it', () {
      final observer = RoostReachObserver();
      expect(observer.last, isNull, reason: 'unclassified, so offer nothing');

      observer.record(
        const RoostReachNote(BridgeReachKind.notInstalled, 'not there'),
      );
      expect(observer.last?.kind, BridgeReachKind.notInstalled);

      observer.record(
        const RoostReachNote(BridgeReachKind.noSession, 'not running'),
      );
      expect(observer.last?.kind, BridgeReachKind.noSession, reason: 'later');

      observer.clear();
      expect(observer.last, isNull);
    });

    test('tells its listeners, and stops when one cancels', () {
      final observer = RoostReachObserver();
      final seen = <BridgeReachKind>[];
      final cancel = observer.listen((note) => seen.add(note.kind));

      observer.record(
        const RoostReachNote(BridgeReachKind.notInstalled, 'not there'),
      );
      cancel();
      observer.record(
        const RoostReachNote(BridgeReachKind.unreachable, 'asleep'),
      );

      expect(seen, <BridgeReachKind>[BridgeReachKind.notInstalled]);
    });

    test('a listener that cancels itself does not break the walk', () {
      // The drive loop's own shape: its listener is cancelled in a `finally`
      // that can run from inside a note it was just handed.
      final observer = RoostReachObserver();
      final seen = <String>[];
      late final void Function() cancel;
      cancel = observer.listen((note) {
        seen.add(note.message);
        cancel();
      });
      observer.listen((note) => seen.add('second:${note.message}'));

      observer.record(const RoostReachNote(BridgeReachKind.noSession, 'a'));
      observer.record(const RoostReachNote(BridgeReachKind.noSession, 'b'));

      expect(seen, <String>['a', 'second:a', 'second:b']);
    });
  });
}

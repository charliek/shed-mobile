import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/shed_session_group.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';

/// What an EMPTY shed group says, which is the only thing most users will read.
///
/// The ordering is the point. Every "no sessions" reason below assumes the
/// connection got somewhere and the server speaks 0.9.0; when it did not, or
/// does not, saying "no roost session on this shed" sends the user to fix the
/// wrong thing — the failure S6 already corrected once in the desktop Agents
/// pane.
MachineFeedState _state({
  bool reachable = false,
  bool connectedOnce = false,
  String? detail,
}) => MachineFeedState(
  machine: const MachineRecord(name: 'shed:h/web', host: 'h'),
  sessions: const [],
  overlay: const {},
  reachable: reachable,
  connectedOnce: connectedOnce,
  detail: detail,
);

void main() {
  test('a pre-0.9.0 server outranks every roost reason', () {
    // Only a pre-0.9.0 server enriches its overview rows with RC sessions, so
    // that is the signal. Its hub is retired on this side: no daemon on the
    // shed would help, and the message must not imply one would.
    final text = shedSessionsEmptyText(
      _state(connectedOnce: true, detail: 'no roost session on this shed'),
      serverPredatesRoost: true,
    );
    expect(text, contains('predates 0.9.0'));
    expect(text, contains('Upgrade the server'));
    expect(
      text,
      isNot(contains('no roost session')),
      reason: 'that is the 0.9.0 advice and it cannot help here',
    );
  });

  test('a start failure outranks the roost reasons too', () {
    expect(
      shedSessionsEmptyText(null, startError: 'no usable SSH identity'),
      contains('no usable SSH identity'),
    );
  });

  test('against a 0.9.0 server the roost reason is what shows', () {
    // The negative half: the new branches must not swallow the normal path.
    expect(
      shedSessionsEmptyText(
        _state(connectedOnce: true, detail: 'no roost session on this shed'),
      ),
      'no roost session on this shed',
    );
    expect(shedSessionsEmptyText(_state(reachable: true)), 'No sessions');
    expect(shedSessionsEmptyText(null), 'connecting…');
  });
}

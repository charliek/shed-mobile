import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/ssh/craze_reach.dart';

/// **The pre-`hello` classifier** (plan 025 §3.7.2, §3.3.2): the craze
/// tunnel's stderr is the only place the phone learns that a machine has no
/// craze, or a craze too old for shed — Rust, handed a loopback port, sees both
/// as a connection that ended before `hello`.
///
/// The two markers are pinned against the REAL binaries by the integration
/// harness (the jailed ladder with no craze on its PATH; craze v0.0.1). These
/// cells pin the rule's shape: what each marker means, that an unrecognized
/// band is unclassified rather than a guess, and that the message is the band's
/// last line rather than the whole tail.
void main() {
  test('the ladder\'s own marker is NOT INSTALLED, with its line', () {
    final note = crazeNoteForExec(
      stderr: 'Welcome to Ubuntu\ncraze: command not found\n',
    );
    expect(note?.cause, const BridgeSourceOffline.notInstalled());
    expect(note?.message, 'craze: command not found');
  });

  test('exit 127 is NOT INSTALLED even with nothing on the band', () {
    final note = crazeNoteForExec(exitCode: 127, stderr: '');
    expect(note?.cause, const BridgeSourceOffline.notInstalled());
    expect(note?.message, 'exit 127');
  });

  test('cobra\'s refusal of --hub is TOO OLD (craze v0.0.1)', () {
    final note = crazeNoteForExec(
      exitCode: 1,
      stderr: 'Error: unknown flag: --hub\nUsage:\n  craze bridge [flags]\n',
    );
    expect(note?.cause, const BridgeSourceOffline.tooOld());
    expect(
      note?.message,
      'Error: unknown flag: --hub',
      reason: 'the line that proved it, not cobra\'s usage text after it',
    );
  });

  test('a band that names neither is unclassified, not a guess', () {
    expect(crazeNoteForExec(stderr: ''), isNull);
    expect(crazeNoteForExec(stderr: 'Last login: Tue Oct  6\n'), isNull);
    expect(
      crazeNoteForExec(exitCode: 1, stderr: 'craze: no hub is running\n'),
      isNull,
      reason:
          'a bridge always Ensures a hub; anything else is not ours to name',
    );
  });

  test('a marker split across two frames still classifies once joined', () {
    // The pump hands the ACCUMULATED tail, so the second call sees the whole
    // line; the first sees half of it and must not guess.
    expect(crazeNoteForExec(stderr: 'craze: command not'), isNull);
    expect(
      crazeNoteForExec(stderr: 'craze: command not found\n')?.cause,
      const BridgeSourceOffline.notInstalled(),
    );
  });
}

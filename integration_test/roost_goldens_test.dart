import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/rc/rc_ui.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';
import 'package:shed_mobile/ssh/roost_reach.dart';

/// **Dart's leg of shed's three two-language goldens** (plan 020 §3.8, AC 6).
///
/// `crates/fixtures/roost-vectors/` holds three files that are **not** roost
/// vectors and not copies of anything: they are shed's own, and they exist
/// because one behaviour is implemented on both sides of a language boundary. A
/// golden asserted from every side is the only thing that makes the
/// implementations provably the same rather than the same today. Go and Rust
/// have read them since plan 019; this file makes Dart the third reader, and
/// the vendored README's table names it.
///
/// | golden | what Dart asserts it against |
/// |---|---|
/// | `bootstrap/exec-chain-command.txt` | `roostRemoteCommand()`, the string the tunnel hands `execute` verbatim |
/// | `agent-table.json` | `roostCapabilities().kinds`, the kinds a create form offers for a machine |
/// | `stderr-classes.json` | `classifySshFailure` + `reachKindFor`, Dart's port of roost's classifier and shed's reach mapping |
///
/// **These cells live here and not in `test/`** because `$SHED_CHECKOUT` is
/// guaranteed only here: `make test-integration-linux` refuses to run without a
/// shed checkout and CI checks out the pinned rev. A unit test that silently
/// skipped when the file was missing would be a golden that asserts nothing on
/// the machine that needed it most.
///
/// **The vendored vectors are never semantically edited.** Two of these three
/// are generated (`exec-chain-command.txt` from the live roost function), and
/// the way to move any of them is shed's own
/// `SHED_UPDATE_ROOST_GOLDEN=1 cargo test -p shed-core --test roost_provider_vectors`,
/// never a hand-edit to make a leg pass.

/// Where shed's checkout is — the same resolution the lane harness uses.
String get _shedCheckout => Platform.environment['SHED_CHECKOUT'] ?? '../shed';

String get _vectors => '$_shedCheckout/crates/fixtures/roost-vectors';

String _readVector(String name) {
  final file = File('$_vectors/$name');
  if (!file.existsSync()) {
    throw StateError(
      'no golden at ${file.path} — set SHED_CHECKOUT to a shed checkout '
      '(it defaults to ../shed)',
    );
  }
  return file.readAsStringSync();
}

Map<String, Object?> _readJson(String name) =>
    jsonDecode(_readVector(name)) as Map<String, Object?>;

List<Map<String, Object?>> _rows(Map<String, Object?> json, String key) =>
    (json[key]! as List<Object?>).cast<Map<String, Object?>>();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('the exec chain the tunnel runs is roost\'s own ladder', (
    _,
  ) async {
    // `roostRemoteCommand()` is `roost_ipc::ssh::remote_command()`, handed over
    // the bridge and passed to `execute` UNMODIFIED. Dart composes no part of
    // it; this is the assertion that says so from Dart's side, against the same
    // bytes Go's `ExecChainCommand` constant and Rust's live call are held to.
    final golden = _readVector('bootstrap/exec-chain-command.txt');
    // The file carries a trailing newline the command itself does not — a text
    // file without one is a nuisance in every tool that touches it — so
    // exactly one is trimmed. `trimRight` would also eat a trailing space the
    // ladder might one day legitimately end with.
    expect(
      golden.endsWith('\n'),
      isTrue,
      reason: 'the exec-chain golden ends in exactly one newline',
    );
    final expected = golden.substring(0, golden.length - 1);

    expect(roostRemoteCommand(), expected);

    // The one property everything downstream depends on beyond equality: the
    // whole command survives as ONE single-quoted word, so no `'\''` — which
    // is not an escape in csh/tcsh/fish — ever reaches a far side's login
    // shell.
    expect(expected.startsWith("sh -c '"), isTrue);
    expect(expected.endsWith("'"), isTrue);
    expect(
      expected.substring(7, expected.length - 1).contains("'"),
      isFalse,
      reason: 'the exec chain must carry no embedded single quote',
    );
  });

  testWidgets('the kinds a machine offers are the agent table\'s', (_) async {
    // Compared as SETS, never as sequences: the golden is in the PROVIDER's
    // display order while `roost_capabilities` orders cursor and opencode the
    // other way round. One is a menu a human reads and the other is a
    // capabilities advertisement whose order means nothing — so the thing worth
    // asserting is that neither list gained or lost a kind.
    final agents = _rows(_readJson('agent-table.json'), 'agents');
    final table = agents.map((row) => row['kind']! as String).toSet();
    final offered = roostCapabilities().kinds.map((k) => k.wire).toSet();

    expect(offered, table);

    // Every kind the table names is one this app KNOWS — an unrecognized wire
    // kind renders neutrally and offers nothing, so a machine whose agents all
    // fell through would look empty rather than broken.
    for (final kind in roostCapabilities().kinds) {
      expect(kind.known, isTrue, reason: '${kind.wire} is an unknown kind');
    }
  });

  testWidgets('a failed exec classifies the way roost classifies it', (
    _,
  ) async {
    // Two mappings, asserted separately because they are two different
    // collapses of one classifier: `classes` is roost's own
    // (`classify_ssh_failure`), and `reach_kinds` is the CLIENTS' reading of
    // it — what tells `NotInstalled` from `NoSession` in the plan matrix, and
    // what decides whether a machine card offers an install, a start, or
    // nothing.
    final golden = _readJson('stderr-classes.json');

    for (final row in _rows(golden, 'classes')) {
      final name = row['name']! as String;
      final verdict = classifySshFailure(
        row['exit_code'] as int?,
        row['stderr']! as String,
      );
      expect(
        verdict.failureClass.wire,
        row['class'],
        reason: 'case $name classified differently in Dart',
      );
      // `detail` is only ever set for `transport` — the other five classes ARE
      // the diagnosis — and the golden pins that by carrying null everywhere
      // else.
      expect(
        verdict.detail.isEmpty ? null : verdict.detail,
        row['detail'],
        reason: 'case $name: the detail line differs',
      );
    }

    final byWire = <String, SshFailureClass>{
      for (final c in SshFailureClass.values) c.wire: c,
    };
    for (final row in _rows(golden, 'reach_kinds')) {
      final name = row['name']! as String;
      final failureClass = byWire[row['class']];
      expect(failureClass, isNotNull, reason: 'case $name names no Dart class');
      expect(
        _kindWire(reachKindFor(failureClass!)),
        row['kind'],
        reason: 'case $name maps to a different kind in Dart',
      );
    }

    // Every class the golden pins is one Dart has, and every class Dart has is
    // pinned — a leg that quietly grew a seventh family, or quietly dropped
    // one, would otherwise still pass.
    final classes = _rows(golden, 'classes');
    final pinned = classes.map((row) => row['class']! as String).toSet();
    expect(pinned, byWire.keys.toSet());
  });
}

/// `shed_app::roost::ReachKind::as_str`'s kebab names, which are what
/// `reach_kinds` carries. The Dart enum crosses FRB by INDEX and has no wire
/// spelling of its own, so this is the one place the two vocabularies meet.
String _kindWire(BridgeReachKind kind) => switch (kind) {
  BridgeReachKind.notInstalled => 'not-installed',
  BridgeReachKind.noSession => 'no-session',
  BridgeReachKind.unreachable => 'unreachable',
  BridgeReachKind.other => 'other',
};

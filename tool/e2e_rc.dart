// M2 end-to-end (tier c): against a REAL shed. SSHes as `<shed>@host` (host-key
// pinned via TOFU for the spike) and drives shed-ext-rc: list → create a shell
// session → list (present) → kill → list (gone). Then creates a claude-rc session
// and prints its derived state + URL (informational — may be needs-auth/needs-trust
// if claude isn't logged in inside the shed). NOT run in CI.
//
//   dart run tool/e2e_rc.dart [shed@host:port]   (default shed-mobile-test@localhost:2222)
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/rc/rc_ui.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/rc/rc_service.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/ssh_runner.dart';

Future<void> main(List<String> args) async {
  final spec = args.isNotEmpty ? args[0] : 'shed-mobile-test@localhost:2222';
  final at = spec.split('@');
  final shed = at[0];
  final hp = at[1].split(':');
  final host = hp[0];
  final port = hp.length > 1 ? int.parse(hp[1]) : 22;

  final runner = SshRunner(
    host: host,
    port: port,
    user: shed,
    identities: KeyManager.defaultDesktopKey(),
    hostKeys: HostKeyStore(), // TOFU for the spike
  );
  final rc = RcService(runner: runner.run, shedName: shed, serverLabel: host);

  void show(String label, List<BridgeRcSession> list) {
    print(
      '$label: ${list.length} session(s)'
      '${list.isEmpty ? '' : ' — ${list.map((s) => '${s.slug}[${s.kind.wire}/${s.state.wire}]').join(', ')}'}',
    );
  }

  print('shed-ext-rc list (initial) over $shed@$host:$port ...');
  show('  initial', await rc.list());

  print('Creating a shell session (--wait) ...');
  final shell = await rc.create(kind: const BridgeRcKind.shell());
  print(
    '  created slug=${shell.slug} state=${shell.state.wire} tmux=${shell.tmuxSession}',
  );

  final afterCreate = await rc.list();
  show('  after create', afterCreate);
  if (!afterCreate.any((s) => s.slug == shell.slug)) {
    print('FAIL: created shell session not present in list');
    exit(1);
  }

  print('Killing ${shell.slug} ...');
  await rc.kill(shell.slug);
  final afterKill = await rc.list();
  show('  after kill', afterKill);
  if (afterKill.any((s) => s.slug == shell.slug)) {
    print('FAIL: shell session still present after kill');
    exit(1);
  }

  print('Killing ${shell.slug} again (idempotent) ...');
  await rc.kill(shell.slug); // must not throw

  print('Creating a claude-rc session (informational) ...');
  final rcs = await rc.create(kind: const BridgeRcKind.claudeRc());
  print(
    '  created slug=${rcs.slug} kind=${rcs.kind.wire} state=${rcs.state.wire} '
    'url=${rcs.url ?? '(none)'}',
  );
  print('Cleaning up ${rcs.slug} ...');
  await rc.kill(rcs.slug);

  print('\nE2E PASS');
  exit(0);
}

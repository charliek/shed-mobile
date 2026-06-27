// M3 end-to-end (tier c): against a REAL shed. Creates a shell RC session, attaches
// an interactive PTY via PtySession (`tmux attach -t rc-<slug>`), types a command,
// confirms the echoed output round-trips, resizes, detaches, then kills the session.
// Proves the bidirectional PTY (write/read/resize/teardown). NOT run in CI.
//
//   dart run tool/e2e_pty.dart [shed@host:port]   (default shed-mobile-test@localhost:2222)
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/rc/rc_service.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/pty_session.dart';
import 'package:shed_mobile/ssh/ssh_runner.dart';

Future<void> main(List<String> args) async {
  final spec = args.isNotEmpty ? args[0] : 'shed-mobile-test@localhost:2222';
  final at = spec.split('@');
  final shed = at[0];
  final hp = at[1].split(':');
  final host = hp[0];
  final port = hp.length > 1 ? int.parse(hp[1]) : 22;

  final identities = KeyManager.defaultDesktopKey();
  final hostKeys = HostKeyStore(); // TOFU for the spike
  final runner = SshRunner(
    host: host,
    port: port,
    user: shed,
    identities: identities,
    hostKeys: hostKeys,
  );
  final rc = RcService(runner: runner.run, shedName: shed, serverLabel: host);

  print('Creating a shell session to attach ...');
  final session = await rc.create(kind: RcKind.shell);
  print('  slug=${session.slug} state=${session.state.wire}');

  final pty = PtySession(
    host: host,
    port: port,
    user: shed,
    identities: identities,
    hostKeys: hostKeys,
    slug: session.slug,
  );

  final buf = StringBuffer();
  const Utf8Decoder(allowMalformed: true).bind(pty.output).listen(buf.write);

  print('Attaching PTY (tmux attach -t rc-${session.slug}) ...');
  await pty.start(cols: 100, rows: 30);

  // Let the shell prompt render, then type a uniquely-tagged command.
  await Future<void>.delayed(const Duration(milliseconds: 800));
  const marker = 'PTYOK_4242';
  pty.write(utf8.encode('echo $marker\n'));

  // Poll for the echoed output (the command echo and/or its result).
  var seen = false;
  for (var i = 0; i < 20; i += 1) {
    if (buf.toString().contains(marker)) {
      seen = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  print('Resizing PTY to 120x40 ...');
  pty.resize(120, 40);
  await Future<void>.delayed(const Duration(milliseconds: 300));

  print('Detaching ...');
  pty.close();

  print('Cleaning up rc-${session.slug} ...');
  await rc.kill(session.slug);

  if (!seen) {
    print('FAIL: did not observe "$marker" echoed back from the PTY');
    print('--- captured output (last 400 chars) ---');
    final s = buf.toString();
    print(s.substring(s.length > 400 ? s.length - 400 : 0));
    exit(1);
  }
  print('  observed "$marker" echoed back (${buf.length} bytes total)');
  print('\nE2E PASS');
  exit(0);
}

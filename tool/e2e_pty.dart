// M3 end-to-end (tier c): against a REAL shed. Attaches an interactive PTY via
// PtySession (`tmux attach -t rc-<slug>`), types a command, confirms the echoed
// output round-trips, resizes, then detaches. Proves the bidirectional PTY
// (write/read/resize/teardown). NOT run in CI.
//
//   dart run tool/e2e_pty.dart <slug> [shed@host:port]
//                                     (default shed-mobile-test@localhost:2222)
//
// **The session is yours to make and yours to clean up** (plan 022 S6,
// shed#328). This tool used to create and kill one through `RcService`, which
// drove `shed-ext-rc` over SSH — and `shed-ext-rc` is gone from the image along
// with the rest of the RC hub. Make a tmux session on the shed first, e.g.
//
//   shed exec <shed> -- tmux new-session -d -s rc-<slug>
//
// and remove it the same way afterwards. Nothing else in the tool changed: the
// PTY attaches to `rc-<slug>`, which is the naming `rcAttachCommand` composes.
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/pty_session.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/e2e_pty.dart <slug> [shed@host:port]');
    exit(2);
  }
  final slug = args[0];
  final spec = args.length > 1 ? args[1] : 'shed-mobile-test@localhost:2222';
  final at = spec.split('@');
  final shed = at[0];
  final hp = at[1].split(':');
  final host = hp[0];
  final port = hp.length > 1 ? int.parse(hp[1]) : 22;

  final identities = KeyManager.defaultDesktopKey();
  final hostKeys = HostKeyStore(); // TOFU for the spike

  final pty = PtySession(
    host: host,
    port: port,
    user: shed,
    identities: identities,
    hostKeys: hostKeys,
    slug: slug,
  );

  final buf = StringBuffer();
  const Utf8Decoder(allowMalformed: true).bind(pty.output).listen(buf.write);

  print('Attaching PTY (tmux attach -t rc-$slug) ...');
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

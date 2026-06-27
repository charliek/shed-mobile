// M0 task-1 API smoke (PLAN §13 A3). Exercises the exact dartssh2 2.18.0 +
// pinenacl API shapes the layered design depends on, against a REAL shed.
// Tier (c): needs a reachable secure shed and a trusted key. NOT run in CI.
//
// Usage:
//   dart run tool/api_smoke.dart [user@host:port]
//   (default: shed-mobile-test@localhost:2222, key ~/.ssh/id_ed25519)
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart';

/// SSH wire string for a public key: string("ssh-ed25519") || string(pub32).
String ed25519PublicOpenSsh(Uint8List pub32, String comment) {
  final b = BytesBuilder();
  void s(List<int> x) {
    final n = x.length;
    b.add([(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]);
    b.add(x);
  }

  s(ascii.encode('ssh-ed25519'));
  s(pub32);
  return 'ssh-ed25519 ${base64.encode(b.toBytes())} $comment';
}

Future<void> main(List<String> args) async {
  final target = args.isNotEmpty ? args[0] : 'shed-mobile-test@localhost:2222';
  final atSplit = target.split('@');
  final user = atSplit[0];
  final hostPort = atSplit[1].split(':');
  final host = hostPort[0];
  final port = hostPort.length > 1 ? int.parse(hostPort[1]) : 22;

  var failures = 0;
  void check(String name, bool ok, [String extra = '']) {
    print('${ok ? 'PASS' : 'FAIL'}  $name${extra.isEmpty ? '' : '  ($extra)'}');
    if (!ok) failures++;
  }

  // 1) Keygen round-trip (pinenacl -> OpenSSHEd25519KeyPair.toPem -> fromPem).
  try {
    final sk = SigningKey.generate();
    final seed32 = sk.seed.asTypedList;
    final pub32 = sk.verifyKey.asTypedList;
    final priv64 = sk.asTypedList;
    check(
      'keygen lengths',
      seed32.length == 32 && pub32.length == 32 && priv64.length == 64,
      'seed=${seed32.length} pub=${pub32.length} priv=${priv64.length}',
    );

    final pem = OpenSSHEd25519KeyPair(
      pub32,
      priv64,
      'shed-mobile-smoke',
    ).toPem();
    check(
      'toPem is OPENSSH PRIVATE KEY',
      pem.contains('BEGIN OPENSSH PRIVATE KEY'),
    );

    final parsed = SSHKeyPair.fromPem(pem);
    check(
      'fromPem round-trips',
      parsed.length == 1 && parsed.first is OpenSSHEd25519KeyPair,
    );

    final mine = ed25519PublicOpenSsh(pub32, 'shed-mobile-smoke');
    final lib =
        'ssh-ed25519 ${base64.encode(parsed.first.toPublicKey().encode())}';
    check(
      'public wire string matches lib',
      mine.startsWith(lib),
      '${mine.substring(0, 28)}...',
    );
  } catch (e) {
    check('keygen block', false, '$e');
  }

  // 2) SSH against the real shed with the trusted ~/.ssh key.
  SSHClient? client;
  try {
    final home = Platform.environment['HOME']!;
    final keyPem = File('$home/.ssh/id_ed25519').readAsStringSync();
    final identities = SSHKeyPair.fromPem(keyPem);
    check('imported ~/.ssh/id_ed25519', identities.isNotEmpty);

    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );
    String? hostFp;
    String? hostType;
    client = SSHClient(
      socket,
      username: user,
      identities: identities,
      onVerifyHostKey: (type, fingerprint) {
        hostType = type;
        // dartssh2 hands us utf8 bytes of "SHA256:<base64nopad>" (matches
        // ssh-keyscan / Go FingerprintSHA256 / shed /api/ssh-host-key).
        hostFp = utf8.decode(fingerprint);
        return true;
      },
    );
    await client.authenticated;
    check('authenticated', true, 'hostkey $hostType $hostFp');

    final res = await client.runWithResult('echo shed-mobile-smoke && id -un');
    final out = utf8.decode(res.stdout);
    check(
      'runWithResult exit+stdout',
      res.exitCode == 0 && out.contains('shed-mobile-smoke'),
      'exit=${res.exitCode} stdout=${out.trim()}',
    );

    // PTY round-trip.
    final session = await client.shell(
      pty: const SSHPtyConfig(width: 100, height: 30),
    );
    final buf = StringBuffer();
    final sub = session.stdout.listen(
      (d) => buf.write(utf8.decode(d, allowMalformed: true)),
    );
    session.write(Uint8List.fromList(utf8.encode('echo PTY_OK_MARKER\n')));
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!buf.toString().contains('PTY_OK_MARKER') &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check('PTY shell echo', buf.toString().contains('PTY_OK_MARKER'));
    session.resizeTerminal(120, 40);
    check('resizeTerminal ok', true);
    session.write(Uint8List.fromList(utf8.encode('exit\n')));
    await session.done.timeout(const Duration(seconds: 5), onTimeout: () {});
    await sub.cancel();
  } catch (e) {
    check('ssh block', false, '$e');
  } finally {
    client?.close();
  }

  print('\n${failures == 0 ? 'SMOKE PASS' : 'SMOKE FAIL ($failures)'}');
  exit(failures == 0 ? 0 : 1);
}

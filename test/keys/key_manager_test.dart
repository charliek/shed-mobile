import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/keys/key_manager.dart';

void main() {
  group('KeyManager.generateEd25519', () {
    test('produces a well-formed key that round-trips through fromPem', () {
      final g = KeyManager.generateEd25519(comment: 'unit@test');
      expect(g.authorizedKey, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      expect(g.authorizedKey, endsWith(' unit@test'));
      expect(g.fingerprint, startsWith('SHA256:'));
      expect(g.fingerprint, isNot(contains('='))); // unpadded, like ssh-keygen
      expect(g.privatePem, contains('OPENSSH PRIVATE KEY'));

      final reparsed = SSHKeyPair.fromPem(g.privatePem);
      expect(reparsed, hasLength(1));
      expect(reparsed.first.type, 'ssh-ed25519');
      // signing works (proves the private half is intact)
      final sig = reparsed.first.sign(Uint8List.fromList(utf8.encode('hi')));
      expect(sig.encode(), isNotEmpty);
    });

    test('each call yields a distinct key', () {
      final a = KeyManager.generateEd25519();
      final b = KeyManager.generateEd25519();
      expect(a.authorizedKey, isNot(b.authorizedKey));
    });

    test(
      'authorized_key + fingerprint match the real ssh-keygen',
      () async {
        final g = KeyManager.generateEd25519(comment: 'golden@test');
        final dir = Directory.systemTemp.createTempSync('km_test');
        try {
          final f = File('${dir.path}/id_ed25519');
          f.writeAsStringSync(g.privatePem);
          await Process.run('chmod', ['600', f.path]);

          final y = await Process.run('ssh-keygen', ['-y', '-f', f.path]);
          final l = await Process.run('ssh-keygen', ['-l', '-f', f.path]);
          expect(y.exitCode, 0, reason: 'ssh-keygen -y: ${y.stderr}');

          // ssh-keygen -y prints "<type> <base64>" (no comment from -y).
          final derived = (y.stdout as String).trim().split(' ');
          final ours = g.authorizedKey.split(' ');
          expect(derived[0], ours[0]); // ssh-ed25519
          expect(derived[1], ours[1]); // base64 public blob

          // ssh-keygen -l prints "<bits> SHA256:<hash> <comment> (ED25519)".
          final fp = (l.stdout as String).trim().split(' ')[1];
          expect(fp, g.fingerprint);
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
      skip: _which('ssh-keygen') == null ? 'ssh-keygen not on PATH' : false,
    );
  });
}

String? _which(String bin) {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    if (File('$dir/$bin').existsSync()) return '$dir/$bin';
  }
  return null;
}

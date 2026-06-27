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

  group('PublicIdentity', () {
    test('fromAuthorizedKeyLine round-trips a generated key', () {
      final g = KeyManager.generateEd25519(comment: 'rt@test');
      final id = PublicIdentity.fromAuthorizedKeyLine(g.authorizedKey);
      // Derived fingerprint matches the generator's (shared fingerprintOfBlob).
      expect(id.fingerprint, g.fingerprint);
      expect(id.authorizedKey, g.authorizedKey.trim());
    });

    test('tolerates a comment with spaces', () {
      final g = KeyManager.generateEd25519();
      final base = g.authorizedKey.split(' ').take(2).join(' ');
      final id = PublicIdentity.fromAuthorizedKeyLine('$base my laptop key');
      expect(id.fingerprint, g.fingerprint);
    });

    test('tolerates an options prefix before the key type', () {
      final g = KeyManager.generateEd25519();
      final base = g.authorizedKey.split(' ').take(2).join(' ');
      final id = PublicIdentity.fromAuthorizedKeyLine(
        'command="x",no-pty $base',
      );
      expect(id.fingerprint, g.fingerprint);
    });

    test('fromBlob recovers the key type and matches the generator', () {
      final g = KeyManager.generateEd25519();
      final blob = base64.decode(g.authorizedKey.split(' ')[1]);
      final id = PublicIdentity.fromBlob(blob);
      expect(id.authorizedKey, startsWith('ssh-ed25519 '));
      expect(id.fingerprint, g.fingerprint);
    });

    test('throws on malformed/empty lines', () {
      expect(
        () => PublicIdentity.fromAuthorizedKeyLine(''),
        throwsFormatException,
      );
      expect(
        () => PublicIdentity.fromAuthorizedKeyLine('not a key'),
        throwsFormatException,
      );
      expect(
        () => PublicIdentity.fromAuthorizedKeyLine(
          'ssh-ed25519 @@@not-base64@@@',
        ),
        throwsFormatException,
      );
      // Decodes as base64 but isn't a real key blob.
      expect(
        () => PublicIdentity.fromAuthorizedKeyLine('ssh-ed25519 AAAA'),
        throwsFormatException,
      );
    });

    test('rejects a blob whose embedded type mismatches the token', () {
      final g = KeyManager.generateEd25519();
      final b64 = g.authorizedKey.split(' ')[1]; // a real ssh-ed25519 blob
      expect(
        () => PublicIdentity.fromAuthorizedKeyLine('ssh-rsa $b64'),
        throwsFormatException,
      );
    });
  });
}

String? _which(String bin) {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    if (File('$dir/$bin').existsSync()) return '$dir/$bin';
  }
  return null;
}

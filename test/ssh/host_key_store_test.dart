import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';

Uint8List _fp(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('TOFU pins on first use and rejects a changed key', () async {
    final store = HostKeyStore();
    final verify = store.verifier('mini3:2222');
    expect(await verify('ssh-ed25519', _fp('SHA256:aaa')), isTrue);
    expect(await verify('ssh-ed25519', _fp('SHA256:aaa')), isTrue);
    expect(await verify('ssh-ed25519', _fp('SHA256:bbb')), isFalse);
    expect(store.pinFor('mini3:2222'), 'SHA256:aaa');
  });

  test(
    'non-TOFU accepts only the seeded pin and rejects an unknown host',
    () async {
      final store = HostKeyStore(
        pins: {'mini3:2222': 'SHA256:aaa'},
        tofu: false,
      );
      final verify = store.verifier('mini3:2222');
      expect(await verify('ssh-ed25519', _fp('SHA256:aaa')), isTrue);
      expect(await verify('ssh-ed25519', _fp('SHA256:zzz')), isFalse);
      final other = store.verifier('unknown:2222');
      expect(await other('ssh-ed25519', _fp('SHA256:aaa')), isFalse);
    },
  );
}

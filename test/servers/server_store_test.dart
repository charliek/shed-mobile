import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/servers/server_store.dart';
import 'package:shed_mobile/storage/secret_store.dart';

ServerRecord rec(String name) => ServerRecord(
  name: name,
  host: name,
  sshPort: 2222,
  apiUrl: 'https://$name:8443',
  tlsCertFingerprint: 'sha256:${'a' * 64}',
  hostKeyPin: 'SHA256:abc',
  controlToken: 'tok',
  controlTokenExpiresAt: DateTime.utc(2026, 6, 28),
);

void main() {
  test('add / list / get / remove round-trip through storage', () async {
    final store = ServerStore(InMemorySecretStore());
    expect(await store.list(), isEmpty);

    await store.add(rec('mini3'));
    await store.add(rec('mac-mini'));
    expect(
      (await store.list()).map((r) => r.name),
      containsAll(['mini3', 'mac-mini']),
    );

    final got = await store.get('mini3');
    expect(got, isNotNull);
    expect(got!.apiUrl, 'https://mini3:8443');
    expect(got.controlToken, 'tok');
    expect(got.controlTokenExpiresAt, DateTime.utc(2026, 6, 28));

    await store.remove('mini3');
    expect((await store.list()).map((r) => r.name), ['mac-mini']);
  });

  test('rejects a duplicate name', () async {
    final store = ServerStore(InMemorySecretStore());
    await store.add(rec('mini3'));
    expect(
      () => store.add(rec('mini3')),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'SERVER_EXISTS')),
    );
  });

  group('setAuthMode', () {
    test('flips to mtls and drops the now-useless seed', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      expect(await store.setAuthMode('mini3', 'mtls'), isTrue);

      final got = (await store.get('mini3'))!;
      expect(got.authMode, kAuthModeMtls);
      expect(got.controlToken, isNull);
      expect(got.controlTokenExpiresAt, isNull);
    });

    test('is a no-op when nothing changed', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      // Adopted fires on every mint — a same-shape rotation must not write.
      expect(await store.setAuthMode('mini3', 'token'), isFalse);
      expect(await store.setAuthMode('mini3', 'mtls'), isTrue);
      expect(await store.setAuthMode('mini3', 'mtls'), isFalse);
    });

    test('normalizes an unknown mode to token', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      await store.setAuthMode('mini3', 'mtls');
      expect(await store.setAuthMode('mini3', 'future-mode'), isTrue);
      expect((await store.get('mini3'))!.authMode, kAuthModeToken);
    });

    test('an unknown server is a no-op', () async {
      final store = ServerStore(InMemorySecretStore());
      expect(await store.setAuthMode('ghost', 'mtls'), isFalse);
    });
  });

  test('resolveTarget maps to a secure ServerTarget', () async {
    final store = ServerStore(InMemorySecretStore());
    await store.add(rec('mini3'));
    final t = await store.resolveTarget('mini3');
    expect(t, isNotNull);
    expect(t!.secure, isTrue);
    expect(t.baseUrl, 'https://mini3:8443');
    expect(t.tlsCertFingerprint, 'sha256:${'a' * 64}');
  });
}

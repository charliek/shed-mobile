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

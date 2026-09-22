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

  group('adoptCredential', () {
    test('flips to mtls and drops the now-useless seed', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      expect(await store.adoptCredential('mini3', 'mtls'), isTrue);

      final got = (await store.get('mini3'))!;
      expect(got.authMode, kAuthModeMtls);
      expect(got.controlToken, isNull);
      expect(got.controlTokenExpiresAt, isNull);
    });

    test('mtls clears the seed even when a token is passed', () async {
      // shed-core never sends one in mtls mode; the store does not depend on
      // that, because a bearer stored against a certificate server is dead
      // weight however it arrived.
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      expect(
        await store.adoptCredential(
          'mini3',
          'mtls',
          token: 'should-not-land',
          expiresAt: DateTime.utc(2030),
        ),
        isTrue,
      );
      final got = (await store.get('mini3'))!;
      expect(got.controlToken, isNull);
      expect(got.controlTokenExpiresAt, isNull);
    });

    test('a rotation replaces the token AND the expiry together', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      expect(
        await store.adoptCredential(
          'mini3',
          'token',
          token: 'tok-2',
          expiresAt: DateTime.utc(2027, 3, 4),
        ),
        isTrue,
      );
      final got = (await store.get('mini3'))!;
      expect(got.controlToken, 'tok-2');
      expect(got.controlTokenExpiresAt, DateTime.utc(2027, 3, 4));
    });

    test(
      'a token with no expiry stores none — the pair is never split',
      () async {
        final store = ServerStore(InMemorySecretStore());
        await store.add(rec('mini3'));
        expect(
          await store.adoptCredential('mini3', 'token', token: 'tok-2'),
          isTrue,
        );
        final got = (await store.get('mini3'))!;
        expect(got.controlToken, 'tok-2');
        // NOT rec()'s stale 2026-06-28 expiry left behind beside a new bearer.
        expect(got.controlTokenExpiresAt, isNull);
      },
    );

    test('mtls → token repopulates both halves', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      await store.adoptCredential('mini3', 'mtls');
      expect((await store.get('mini3'))!.controlToken, isNull);

      expect(
        await store.adoptCredential(
          'mini3',
          'token',
          token: 'reissued',
          expiresAt: DateTime.utc(2028),
        ),
        isTrue,
      );
      final got = (await store.get('mini3'))!;
      expect(got.authMode, kAuthModeToken);
      expect(got.controlToken, 'reissued');
      expect(got.controlTokenExpiresAt, DateTime.utc(2028));
    });

    test('no token passed keeps the stored pair (a bare ModeChanged)', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      // Nothing changes at all, so nothing is written — and crucially the seed
      // is NOT erased by the absent argument.
      expect(await store.adoptCredential('mini3', 'token'), isFalse);
      final got = (await store.get('mini3'))!;
      expect(got.controlToken, 'tok');
      expect(got.controlTokenExpiresAt, DateTime.utc(2026, 6, 28));
    });

    test('is a no-op when nothing changed', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      // Adopted fires on every mint — re-announcing the stored pair must not
      // write, mode and credential material alike.
      expect(await store.adoptCredential('mini3', 'token'), isFalse);
      expect(
        await store.adoptCredential(
          'mini3',
          'token',
          token: 'tok',
          expiresAt: DateTime.utc(2026, 6, 28),
        ),
        isFalse,
      );
      expect(await store.adoptCredential('mini3', 'mtls'), isTrue);
      expect(await store.adoptCredential('mini3', 'mtls'), isFalse);
    });

    test('normalizes an unknown mode to token', () async {
      final store = ServerStore(InMemorySecretStore());
      await store.add(rec('mini3'));
      await store.adoptCredential('mini3', 'mtls');
      expect(await store.adoptCredential('mini3', 'future-mode'), isTrue);
      expect((await store.get('mini3'))!.authMode, kAuthModeToken);
    });

    test('an unknown server is a no-op', () async {
      final store = ServerStore(InMemorySecretStore());
      expect(await store.adoptCredential('ghost', 'mtls'), isFalse);
      expect(
        await store.adoptCredential('ghost', 'token', token: 'tok-2'),
        isFalse,
      );
    });

    test('a storage-write failure SURFACES, it is not swallowed', () async {
      final store = ServerStore(_FailingWriteStore());
      await store.add(rec('mini3'));
      // The record is worth more than the hint: a caller that cannot write must
      // find out, and decide for itself (the credential sink contains it; a
      // silent drop inside the store would take that decision away).
      await expectLater(
        store.adoptCredential(
          'mini3',
          'token',
          token: 'tok-2',
          expiresAt: DateTime.utc(2027),
        ),
        throwsA(isA<StateError>()),
      );
      // ...and the queue is not wedged by the failure.
      expect(await store.adoptCredential('ghost', 'token'), isFalse);
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

  test('concurrent mutations are serialized — neither update is lost', () async {
    // Every mutation rewrites the WHOLE servers.v1 blob. With a real async gap
    // between the read and the write, two overlapping read-modify-writes both
    // observe the same starting list and the second write clobbers the first.
    // This store makes that gap explicit; without the mutation queue in
    // ServerStore the two adds below collapse to one surviving record.
    final store = ServerStore(_SlowSecretStore());

    await Future.wait([store.add(rec('alpha')), store.add(rec('beta'))]);

    final names = (await store.list()).map((r) => r.name).toList()..sort();
    expect(names, ['alpha', 'beta']);
  });

  test('a failed mutation does not wedge the queue', () async {
    final store = ServerStore(_SlowSecretStore());
    await store.add(rec('alpha'));

    // A duplicate add throws; the queue tail must still complete so later
    // mutations run rather than hanging forever behind the failure.
    await expectLater(store.add(rec('alpha')), throwsA(isA<AppError>()));

    await store.add(rec('beta'));
    final names = (await store.list()).map((r) => r.name).toList()..sort();
    expect(names, ['alpha', 'beta']);
  });
}

/// A [SecretStore] whose FIRST write succeeds (so a record can be seeded) and
/// every later one fails — the keychain-unavailable shape.
class _FailingWriteStore implements SecretStore {
  final _inner = InMemorySecretStore();
  int writes = 0;

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (writes++ > 0) throw StateError('secure storage unavailable');
    await _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

/// A [SecretStore] with a real async gap on both sides of a read-modify-write,
/// so overlapping mutations genuinely interleave instead of completing in one
/// synchronous microtask burst the way [InMemorySecretStore] does.
class _SlowSecretStore implements SecretStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(Duration.zero);
    return _m[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    _m[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    await Future<void>.delayed(Duration.zero);
    _m.remove(key);
  }
}

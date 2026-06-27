import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/keys/identity_store.dart';
import 'package:shed_mobile/storage/secret_store.dart';

/// A SecretStore that can be told to throw on the Nth write or on every read,
/// to exercise partial-write rollback and undecryptable-read recovery.
class _FlakyStore implements SecretStore {
  final _m = <String, String>{};
  int failWriteAfter = -1; // throw once this many writes have succeeded
  int _writes = 0;
  bool throwOnRead = false;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw Exception('undecryptable');
    return _m[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWriteAfter >= 0 && _writes >= failWriteAfter) {
      throw Exception('write failed');
    }
    _writes++;
    _m[key] = value;
  }

  @override
  Future<void> delete(String key) async => _m.remove(key);

  int get count => _m.length;
}

void main() {
  test('generate -> persist -> load -> delete lifecycle', () async {
    final store = IdentityStore(InMemorySecretStore());
    expect(await store.hasKey(), isFalse);
    expect(await store.authorizedKey(), isNull);

    final g = await store.generateAndStore(comment: 'dev@phone');
    expect(await store.hasKey(), isTrue);
    expect(await store.authorizedKey(), g.authorizedKey);

    final identities = await store.load();
    expect(identities, hasLength(1));
    expect(identities.first.type, 'ssh-ed25519');

    await store.delete();
    expect(await store.hasKey(), isFalse);
    expect(await store.authorizedKey(), isNull);
  });

  test('load before generate throws', () async {
    final store = IdentityStore(InMemorySecretStore());
    expect(store.load(), throwsStateError);
  });

  test('regenerating overwrites the stored key', () async {
    final store = IdentityStore(InMemorySecretStore());
    final a = await store.generateAndStore();
    final b = await store.generateAndStore();
    expect(a.authorizedKey, isNot(b.authorizedKey));
    expect(await store.authorizedKey(), b.authorizedKey);
  });

  test('a failed second write rolls back (no orphaned private key)', () async {
    final flaky = _FlakyStore()..failWriteAfter = 1; // pem succeeds, pub throws
    final store = IdentityStore(flaky);
    await expectLater(store.generateAndStore(), throwsException);
    expect(flaky.count, 0, reason: 'rollback should leave nothing behind');
    expect(await store.hasKey(), isFalse);
  });

  test('hasKey requires BOTH the private and public entries', () async {
    // A lone private PEM (e.g. left by some other partial-write path) must not
    // read as a complete identity.
    final raw = InMemorySecretStore();
    await raw.write('ssh_identity_pem', 'PEM-ONLY');
    expect(await IdentityStore(raw).hasKey(), isFalse);
  });

  test('an undecryptable read resets to a clean state (no crash)', () async {
    final flaky = _FlakyStore();
    final store = IdentityStore(flaky);
    await store.generateAndStore();
    flaky.throwOnRead = true; // simulate Keystore invalidation
    expect(await store.hasKey(), isFalse); // caught + reset, not thrown
    flaky.throwOnRead = false;
    expect(flaky.count, 0, reason: 'reset should have cleared the entries');
  });
}

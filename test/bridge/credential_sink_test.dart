import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/credential_sink.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/servers/server_store.dart';
import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/storage/secret_store.dart';

/// Counts writes so "a rotation must not cost a storage write" is assertable.
class _CountingStore implements SecretStore {
  final _inner = InMemorySecretStore();
  int writes = 0;

  @override
  Future<String?> read(String key) => _inner.read(key);
  @override
  Future<void> write(String key, String value) {
    writes++;
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

ServerRecord _rec({
  String name = 'mini3',
  String authMode = kAuthModeToken,
  String? token = 'seed-tok',
}) => ServerRecord(
  name: name,
  host: 'mini3.example',
  sshPort: 2222,
  apiUrl: 'https://mini3.example:8443',
  tlsCertFingerprint: 'sha256:${'a' * 64}',
  hostKeyPin: 'SHA256:abc',
  authMode: authMode,
  controlToken: token,
  controlTokenExpiresAt: token == null ? null : DateTime.utc(2030),
);

void main() {
  late _CountingStore secrets;
  late ProviderContainer container;
  late StreamController<BridgeCredentialEvent> events;
  late CredentialSink sink;
  var closed = 0;

  setUp(() {
    secrets = _CountingStore();
    container = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(secrets)],
    );
    events = StreamController<BridgeCredentialEvent>();
    closed = 0;
    sink = CredentialSink.register(
      container,
      open: () => events.stream,
      close: () => closed++,
    );
  });

  tearDown(() async {
    await sink.dispose();
    await events.close();
    container.dispose();
  });

  ServerStore store() => container.read(serverStoreProvider);

  /// Push an event and wait for the serialized write chain to drain.
  Future<void> emit(BridgeCredentialEvent e) async {
    events.add(e);
    await pumpEventQueue();
    await sink.settled;
  }

  test('a token→mtls flip is PERSISTED (AC5: survives a restart)', () async {
    await store().add(_rec());
    await emit(
      const BridgeCredentialEvent.adopted(server: 'mini3', authMode: 'mtls'),
    );

    // Re-read from storage, not from memory: this is the restart simulation.
    final back = await ServerStore(secrets).get('mini3');
    expect(back!.authMode, kAuthModeMtls);
    expect(back.isMtls, isTrue);
    // The stale bearer is dropped — it can authenticate nothing now.
    expect(back.controlToken, isNull);
    expect(back.controlTokenExpiresAt, isNull);
  });

  test('an mtls→token flip restores token mode', () async {
    await store().add(_rec(authMode: kAuthModeMtls, token: null));
    await emit(
      const BridgeCredentialEvent.modeChanged(
        server: 'mini3',
        authMode: 'token',
      ),
    );
    expect((await store().get('mini3'))!.authMode, kAuthModeToken);
  });

  test('a plain rotation costs no storage write', () async {
    await store().add(_rec());
    final baseline = secrets.writes;
    // Adopted fires on EVERY successful mint, including a same-shape rotation.
    for (var i = 0; i < 3; i++) {
      await emit(
        const BridgeCredentialEvent.adopted(
          server: 'mini3',
          authMode: 'token',
          expiresAtUnix: null,
        ),
      );
    }
    expect(secrets.writes, baseline);
  });

  test(
    'back-to-back Adopted + ModeChanged serialize to one final state',
    () async {
      await store().add(_rec());
      // The real emission order: the adoption, then the derived transition.
      events
        ..add(
          const BridgeCredentialEvent.adopted(
            server: 'mini3',
            authMode: 'mtls',
          ),
        )
        ..add(
          const BridgeCredentialEvent.modeChanged(
            server: 'mini3',
            authMode: 'mtls',
          ),
        );
      await pumpEventQueue();
      await sink.settled;
      expect((await store().get('mini3'))!.authMode, kAuthModeMtls);
      // One write for the change; the derived event finds nothing to do.
      expect(secrets.writes, 2); // the add + the flip
    },
  );

  test(
    'marks the server adopted for the session (drives the enrolling UI)',
    () async {
      await store().add(_rec(authMode: kAuthModeMtls, token: null));
      expect(container.read(adoptedServersProvider), isEmpty);
      await emit(
        const BridgeCredentialEvent.adopted(server: 'mini3', authMode: 'mtls'),
      );
      expect(container.read(adoptedServersProvider), contains('mini3'));
    },
  );

  test('an event for a removed server is a no-op, not a crash', () async {
    await emit(
      const BridgeCredentialEvent.adopted(server: 'ghost', authMode: 'mtls'),
    );
    expect(await store().list(), isEmpty);
    // The stream is still live afterwards.
    await store().add(_rec());
    await emit(
      const BridgeCredentialEvent.adopted(server: 'mini3', authMode: 'mtls'),
    );
    expect((await store().get('mini3'))!.authMode, kAuthModeMtls);
  });

  test('dispose ends the Rust stream once and is idempotent', () async {
    await sink.dispose();
    await sink.dispose();
    expect(closed, 1);
  });
}

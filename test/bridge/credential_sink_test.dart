import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/credential_sink.dart';
import 'package:shed_mobile/bridge/mint_sink.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/servers/server_store.dart';
import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/mint.dart';
import 'package:shed_mobile/src/rust/api/secret.dart';
import 'package:shed_mobile/storage/secret_store.dart';

/// Counts writes so "a rotation must not cost a storage write" is assertable.
class _CountingStore implements SecretStore {
  final _inner = InMemorySecretStore();
  int writes = 0;

  /// Arm one keychain-unavailable failure (consumed by the next write).
  bool failNextWrite = false;

  @override
  Future<String?> read(String key) => _inner.read(key);
  @override
  Future<void> write(String key, String value) {
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      return Future<void>.error(StateError('secure storage unavailable'));
    }
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

ServerRecord _rec({
  String name = 'mini3',
  String authMode = kAuthModeToken,
  String? token = 'seed-tok',
  DateTime? expiresAt,
}) => ServerRecord(
  name: name,
  host: 'mini3.example',
  sshPort: 2222,
  apiUrl: 'https://mini3.example:8443',
  tlsCertFingerprint: 'sha256:${'a' * 64}',
  hostKeyPin: 'SHA256:abc',
  authMode: authMode,
  controlToken: token,
  controlTokenExpiresAt: token == null
      ? null
      : (expiresAt ?? DateTime.utc(2030)),
);

/// A unix-seconds expiry, as the bridge reports it.
BigInt _unix(DateTime t) => BigInt.from(t.millisecondsSinceEpoch ~/ 1000);

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

  test(
    'a storage-write failure is contained, not fatal to the stream',
    () async {
      await store().add(_rec(token: null));
      secrets.failNextWrite = true;
      await emit(
        BridgeCredentialEvent.adopted(
          server: 'mini3',
          authMode: 'token',
          token: const BridgeSecret(value: 'lost-tok'),
          expiresAtUnix: _unix(DateTime.utc(2030)),
        ),
      );
      // The write threw out of ServerStore (it does not swallow), the sink
      // contained it, and NOTHING was half-written.
      var back = (await ServerStore(secrets).get('mini3'))!;
      expect(back.controlToken, isNull);

      // The stream survived: the next adoption still lands.
      await emit(
        BridgeCredentialEvent.adopted(
          server: 'mini3',
          authMode: 'token',
          token: const BridgeSecret(value: 'next-tok'),
          expiresAtUnix: _unix(DateTime.utc(2030)),
        ),
      );
      back = (await ServerStore(secrets).get('mini3'))!;
      expect(back.controlToken, 'next-tok');
    },
  );

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

  test('an mtls→token adoption REPOPULATES both halves', () async {
    // The excursion the old write-once seed never recovered from: once mtls had
    // dropped it, nothing ever wrote one again and every cold launch minted.
    await store().add(_rec(authMode: kAuthModeMtls, token: null));
    final exp = DateTime.utc(2033, 7, 8);
    await emit(
      BridgeCredentialEvent.adopted(
        server: 'mini3',
        authMode: 'token',
        token: const BridgeSecret(value: 'post-mtls-tok'),
        expiresAtUnix: _unix(exp),
      ),
    );

    final back = await ServerStore(secrets).get('mini3');
    expect(back!.authMode, kAuthModeToken);
    expect(back.controlToken, 'post-mtls-tok');
    expect(back.controlTokenExpiresAt, exp);
  });

  test(
    'a rotation replaces the token AND the expiry together (plan 023 §3.5)',
    () async {
      // The bug this commit fixes: the seed was written once, at add time, and
      // a rotation 22h later left the app holding a token the server had already
      // stopped honouring.
      await store().add(_rec(token: 'seed-tok', expiresAt: DateTime.utc(2030)));
      final rotatedExp = DateTime.utc(2031, 5, 6);
      await emit(
        BridgeCredentialEvent.adopted(
          server: 'mini3',
          authMode: 'token',
          token: const BridgeSecret(value: 'rotated-tok'),
          expiresAtUnix: _unix(rotatedExp),
        ),
      );

      final back = await ServerStore(secrets).get('mini3');
      expect(back!.controlToken, 'rotated-tok');
      expect(back.controlTokenExpiresAt, rotatedExp);
      expect(back.authMode, kAuthModeToken);
    },
  );

  test('the rotated pair survives a cold launch (a fresh store)', () async {
    await store().add(_rec());
    final exp = DateTime.utc(2032, 2, 3);
    await emit(
      BridgeCredentialEvent.adopted(
        server: 'mini3',
        authMode: 'token',
        token: const BridgeSecret(value: 'cold-tok'),
        expiresAtUnix: _unix(exp),
      ),
    );

    // A brand-new ServerStore over the SAME backing store — nothing in memory
    // carries over, which is exactly what a cold launch has.
    final cold = ServerStore(secrets);
    final target = await cold.resolveTarget('mini3');
    expect(target!.controlToken, 'cold-tok');
    expect(target.controlTokenExpiresAt, exp);
  });

  test('re-announcing the stored pair costs no storage write', () async {
    final exp = DateTime.utc(2030);
    await store().add(_rec(token: 'seed-tok', expiresAt: exp));
    final baseline = secrets.writes;
    // Adopted fires on EVERY successful mint; one that adopts what is already
    // stored (a cached credential re-announced) must stay free.
    for (var i = 0; i < 3; i++) {
      await emit(
        BridgeCredentialEvent.adopted(
          server: 'mini3',
          authMode: 'token',
          token: const BridgeSecret(value: 'seed-tok'),
          expiresAtUnix: _unix(exp),
        ),
      );
    }
    expect(secrets.writes, baseline);
  });

  test('a bare ModeChanged changes nothing but the mode — it neither invents '
      'nor erases credential material', () async {
    // Token direction: the event carries no token, and the stored pair must
    // survive it untouched.
    await store().add(_rec(token: 'seed-tok', expiresAt: DateTime.utc(2030)));
    await emit(
      const BridgeCredentialEvent.modeChanged(
        server: 'mini3',
        authMode: 'token',
      ),
    );
    var back = (await ServerStore(secrets).get('mini3'))!;
    expect(back.authMode, kAuthModeToken);
    expect(back.controlToken, 'seed-tok');
    expect(back.controlTokenExpiresAt, DateTime.utc(2030));

    // And nothing is invented for a record that has no seed at all.
    await store().add(_rec(name: 'bare', authMode: kAuthModeMtls, token: null));
    await emit(
      const BridgeCredentialEvent.modeChanged(
        server: 'bare',
        authMode: 'token',
      ),
    );
    back = (await ServerStore(secrets).get('bare'))!;
    expect(back.authMode, kAuthModeToken);
    expect(back.controlToken, isNull);
    expect(back.controlTokenExpiresAt, isNull);
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
    // Including one carrying a bearer — an orphan token must not be stored
    // under a name the app no longer has, nor create the record.
    await emit(
      BridgeCredentialEvent.adopted(
        server: 'ghost',
        authMode: 'token',
        token: const BridgeSecret(value: 'orphan-tok'),
        expiresAtUnix: _unix(DateTime.utc(2030)),
      ),
    );
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

  // shed-mobile#30. freezed generates a `toString()` for every sealed variant,
  // and it renders every field. Two variants carry a secret: a token-mode
  // `Adopted` (the bearer) and a mint `success` (the raw bundle stdout, which in
  // token mode IS the bearer plus its envelope). The assertions are on the
  // rendered STRING, not on a field's type, so a future codegen that starts
  // rendering the secret some other way fails here too.
  test('no generated type renders a secret', () async {
    const secret = 'bearer-7f3a9c-must-not-print';
    final exp = DateTime.utc(2034, 4, 5);

    // The credential sink still persists exactly that bearer...
    await store().add(_rec(token: null));
    final adopted = BridgeCredentialEvent.adopted(
      server: 'mini3',
      authMode: 'token',
      token: const BridgeSecret(value: secret),
      expiresAtUnix: _unix(exp),
    );
    await emit(adopted);
    final back = (await ServerStore(secrets).get('mini3'))!;
    expect(back.controlToken, secret);
    expect(back.controlTokenExpiresAt, exp);

    // ...and the mint path still hands Rust exactly the stdout the mint made.
    final submitted = <BridgeMintOutcome>[];
    await runMintRequest(
      const BridgeMintRequest(
        requestId: 'r1',
        purpose: BridgeMintPurpose.controlMint,
        host: 'mini3.example',
        sshPort: 2222,
        baseUrl: 'https://mini3.example:8443',
        extraArgs: [],
      ),
      mint: (_) async => secret,
      submit: ({required requestId, required outcome}) async {
        submitted.add(outcome);
        return 'accepted';
      },
    );
    final success = submitted.single as BridgeMintOutcome_Success;
    expect(success.rawStdout.value, secret);

    // Neither renders it: not `toString()`, not interpolation, not a copy.
    final rendered = <String, String>{
      'Adopted.toString()': adopted.toString(),
      'Adopted interpolated': '$adopted',
      'Adopted.copyWith(...).toString()':
          (adopted as BridgeCredentialEvent_Adopted)
              .copyWith(server: 'other')
              .toString(),
      'success.toString()': success.toString(),
      'success interpolated': '$success',
      'success.copyWith(...).toString()': success.copyWith().toString(),
    };
    final leaks = {
      for (final e in rendered.entries)
        if (e.value.contains(secret)) e.key: e.value,
    };
    expect(leaks, isEmpty, reason: 'a generated rendering printed the secret');

    // The next leak vector: neither type serializes. Nothing generates a
    // `toJson` today; a json_serializable adoption must not quietly add one.
    for (final Object v in [adopted, success]) {
      expect(() => (v as dynamic).toJson(), throwsNoSuchMethodError);
    }
  });

  test('a mint request submits exactly one outcome, even when the submit '
      'throws', () async {
    const req = BridgeMintRequest(
      requestId: 'r2',
      purpose: BridgeMintPurpose.controlMint,
      host: 'mini3.example',
      sshPort: 2222,
      baseUrl: 'https://mini3.example:8443',
      extraArgs: [],
    );

    // A failed mint is one failure outcome.
    final submitted = <BridgeMintOutcome>[];
    await runMintRequest(
      req,
      mint: (_) async => throw StateError('ssh refused'),
      submit: ({required requestId, required outcome}) async {
        submitted.add(outcome);
        return 'accepted';
      },
    );
    expect(submitted.single, isA<BridgeMintOutcome_Failure>());

    // A submit that throws is not retried as a failure for the same request.
    var calls = 0;
    await expectLater(
      runMintRequest(
        req,
        mint: (_) async => 'stdout',
        submit: ({required requestId, required outcome}) async {
          calls++;
          throw StateError('bridge gone');
        },
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('dispose ends the Rust stream once and is idempotent', () async {
    await sink.dispose();
    await sink.dispose();
    expect(closed, 1);
  });
}

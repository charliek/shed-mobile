import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/control/token_bundle.dart';
import 'package:shed_mobile/servers/server_target.dart';

ServerTarget secure({
  String name = 'mini3',
  String? token,
  DateTime? exp,
  String pin = 'sha256:aaaa',
}) => ServerTarget(
  name: name,
  host: name,
  sshPort: 2222,
  secure: true,
  baseUrl: 'https://$name:8443',
  tlsCertFingerprint: pin,
  controlToken: token,
  controlTokenExpiresAt: exp,
);

DateTime ms(int v) => DateTime.fromMillisecondsSinceEpoch(v);
final DateTime farFuture = ms(99999999);

void main() {
  group('ControlTokenProvider', () {
    test('returns null for a legacy (non-secure) host', () async {
      final p = ControlTokenProvider(
        'x',
        resolve: () async => const ServerTarget(
          name: 'x',
          host: 'x',
          sshPort: 2222,
          secure: false,
          baseUrl: 'http://x:8080',
        ),
        minter: (_) async => fail('must not mint'),
        now: () => 0,
        jitterMs: 0,
      );
      expect(await p.get(), isNull);
    });

    test('uses the config seed without minting when it is fresh', () async {
      var mints = 0;
      final p = ControlTokenProvider(
        'mini3',
        resolve: () async => secure(token: 'seed', exp: farFuture),
        minter: (_) async {
          mints++;
          return MintedToken('minted', farFuture);
        },
        now: () => 0,
        refreshWindowMs: 1000,
        jitterMs: 0,
      );
      expect(await p.get(), 'seed');
      expect(mints, 0);
    });

    test('proactively mints when within the refresh window', () async {
      var mints = 0;
      final p = ControlTokenProvider(
        'mini3',
        resolve: () async => secure(token: 'seed', exp: ms(10000)),
        minter: (_) async {
          mints++;
          return MintedToken('minted', farFuture);
        },
        now: () => 9000,
        refreshWindowMs: 5000,
        jitterMs: 0,
      );
      expect(await p.get(), 'minted');
      expect(mints, 1);
    });

    test('keeps a still-valid token when a proactive mint fails', () async {
      final p = ControlTokenProvider(
        'mini3',
        resolve: () async => secure(token: 'seed', exp: ms(10000)),
        minter: (_) async => throw AppError.authExpired(),
        now: () => 9000,
        refreshWindowMs: 5000,
        jitterMs: 0,
      );
      expect(await p.get(), 'seed');
    });

    test(
      'mints when the seed is expired, throwing if that mint fails',
      () async {
        var shouldFail = true;
        final p = ControlTokenProvider(
          'mini3',
          resolve: () async => secure(token: 'seed', exp: ms(1000)),
          minter: (_) async {
            if (shouldFail) throw AppError.tlsPinMismatch();
            return const MintedToken('fresh', null);
          },
          now: () => 5000,
          cooldownMs: 0,
          jitterMs: 0,
        );
        await expectLater(p.get(), throwsA(isA<AppError>()));
        shouldFail = false;
        expect(await p.get(), 'fresh');
      },
    );

    test('collapses concurrent mints into one (single-flight)', () async {
      var mints = 0;
      final gate = Completer<MintedToken>();
      final p = ControlTokenProvider(
        'mini3',
        resolve: () async => secure(), // no seed -> must mint
        minter: (_) {
          mints++;
          return gate.future;
        },
        now: () => 0,
        jitterMs: 0,
      );
      final f1 = p.get();
      final f2 = p.get();
      await Future<void>.delayed(Duration.zero);
      gate.complete(const MintedToken('m', null));
      expect(await f1, 'm');
      expect(await f2, 'm');
      expect(mints, 1);
    });

    test(
      'forces a fresh mint on invalidate (401), never the rejected token',
      () async {
        var mints = 0;
        final p = ControlTokenProvider(
          'mini3',
          resolve: () async => secure(token: 'seed', exp: farFuture),
          minter: (_) async {
            mints++;
            return MintedToken('mint$mints', farFuture);
          },
          now: () => 0,
          refreshWindowMs: 1,
          jitterMs: 0,
        );
        expect(await p.get(), 'seed');
        p.invalidate('seed');
        expect(await p.get(), 'mint1');
      },
    );

    test('does not re-mint within the cooldown after a failed mint', () async {
      var mints = 0;
      var nowMs = 5000;
      final p = ControlTokenProvider(
        'mini3',
        resolve: () async => secure(token: 'seed', exp: ms(1000)), // expired
        minter: (_) async {
          mints++;
          throw AppError.authExpired();
        },
        now: () => nowMs,
        cooldownMs: 1000,
        jitterMs: 0,
      );
      await expectLater(p.get(), throwsA(isA<AppError>()));
      expect(mints, 1);
      nowMs = 5500; // within cooldown
      await expectLater(p.get(), throwsA(isA<AppError>()));
      expect(mints, 1);
      nowMs = 6000; // cooldown elapsed
      await expectLater(p.get(), throwsA(isA<AppError>()));
      expect(mints, 2);
    });

    test(
      'ignores a stale 401 for a token it has already rotated past',
      () async {
        var mints = 0;
        final p = ControlTokenProvider(
          'mini3',
          resolve: () async => secure(token: 'seed', exp: farFuture),
          minter: (_) async {
            mints++;
            return MintedToken('mint$mints', farFuture);
          },
          now: () => 0,
          refreshWindowMs: 1,
          jitterMs: 0,
        );
        expect(await p.get(), 'seed');
        p.invalidate('seed'); // real 401 on the seed
        expect(await p.get(), 'mint1'); // rotated
        p.invalidate('seed'); // stale 401 for the old token -> ignored
        expect(await p.get(), 'mint1'); // still cached, no new mint
        expect(mints, 1);
      },
    );

    test(
      'drops the cached token when the host transport identity changes',
      () async {
        var pin = 'sha256:${'a' * 64}';
        var mints = 0;
        final p = ControlTokenProvider(
          'mini3',
          resolve: () async => secure(pin: pin), // no seed -> mints
          minter: (_) async {
            mints++;
            return MintedToken('mint$mints', farFuture);
          },
          now: () => 0,
          jitterMs: 0,
        );
        expect(await p.get(), 'mint1');
        expect(await p.get(), 'mint1'); // cached, same identity
        pin = 'sha256:${'b' * 64}'; // pin rotated -> identity change
        expect(await p.get(), 'mint2');
        expect(mints, 2);
      },
    );

    test('does not hand an in-flight mint to a changed identity', () async {
      var pin = 'sha256:${'a' * 64}';
      final gateA = Completer<MintedToken>();
      var calls = 0;
      final p = ControlTokenProvider(
        'mini3',
        resolve: () async => secure(pin: pin), // no seed -> must mint
        minter: (_) {
          calls++;
          if (calls == 1) return gateA.future; // identity A's mint, gated
          return Future.value(MintedToken('tokenB', farFuture));
        },
        now: () => 0,
        jitterMs: 0,
      );
      final fA = p.get(); // starts the gated mint for identity A
      await Future<void>.delayed(Duration.zero);
      pin = 'sha256:${'b' * 64}'; // transport identity changes to B
      final fB = p.get(); // must start a SEPARATE mint, not reuse A's
      gateA.complete(MintedToken('tokenA', farFuture));
      expect(await fA, 'tokenA');
      expect(await fB, 'tokenB');
      expect(calls, 2); // two distinct mints across identities
    });
  });
}

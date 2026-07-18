// B2 bridge-surface proofs — the production FRB shapes the shed-mobile migration
// (B3/B4) consumes, exercised end-to-end on a real device (macOS + Android
// emulator):
//   (a) TokenMinter inversion  — StreamSink out + oneshot registry + Dart submit
//                                (sealed BridgeMintOutcome) + shutdown-drains
//   (b) RcEventsWatcher stream  — a real BridgeClient (open-mode, local SSE) →
//                                two-call watcher → sealed BridgeWatcherUpdate
//   (c) Dart-backed RcRunner    — argv-out → fake-exec → decode-in (sealed DTOs)
//   (d) create-stream lifecycle — BridgeClient + CreateSink → sealed update;
//                                one-shot-on-401 (accepted behavior change)
//   (e) BridgeClient + BridgeError — a real method call surfaces a sealed error
// Plus the AC#2 leak counters (incl. the hermetic SSE servers) returning to zero.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/src/rust/api/bridge_rt.dart';
import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/create_stream.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/error.dart';
import 'package:shed_mobile/src/rust/api/local_sse.dart';
import 'package:shed_mobile/src/rust/api/mint.dart';
import 'package:shed_mobile/src/rust/api/rc_runner.dart';
import 'package:shed_mobile/src/rust/api/watcher.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';

const _pin =
    'sha256:'
    'abababababababababababababababababababababababababababababababab';

String _fixtureBundle(String pin) =>
    '{"scope":"control","token":"tok-12345","tls_cert_fingerprint":"$pin",'
    '"https_port":8443,"expires_at":"2030-01-01T00:00:00Z"}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  // -------- Slice (a): TokenMinter inversion --------
  group('slice a — mint inversion', () {
    late StreamSubscription<BridgeMintRequest> sub;

    setUp(() async {
      // Register the app-scoped mint sink and route submits. A request whose
      // host is "no-response" is deliberately left unanswered (timeout /
      // shutdown-drain tests).
      sub = setMintSink().listen((req) async {
        if (req.host == 'no-response') return;
        await submitMintResult(
          requestId: req.requestId,
          outcome: BridgeMintOutcome.success(
            rawStdout: _fixtureBundle(req.expectedTlsPin ?? _pin),
          ),
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      shutdownMintSink(); // sync now (Codex #9) — end the Rust sink fn cleanly
      await sub.cancel();
    });

    testWidgets('Rust emits → Dart submits → Rust parses the bundle', (
      _,
    ) async {
      final bundle = await demoMint(
        host: 'myhost',
        sshPort: 22,
        baseUrl: 'https://myhost:8443',
        expectedTlsPin: _pin,
        timeoutMs: BigInt.from(5000),
      );
      expect(bundle.httpsPort, 8443);
      expect(bundle.tokenPresent, true);
      expect(bundle.tokenLen, 9); // "tok-12345"
      expect(bundle.tlsCertFingerprint, _pin);
      final c = await liveCounters();
      expect(c.pendingMints, BigInt.zero); // RAII cleanup
    });

    testWidgets('unknown request_id submit is benign', (_) async {
      final r = await submitMintResult(
        requestId: 'does-not-exist',
        outcome: const BridgeMintOutcome.failure(code: 'x'),
      );
      expect(r, startsWith('rejected'));
    });

    testWidgets('timeout fires when Dart never submits', (_) async {
      Object? err;
      try {
        await demoMint(
          host: 'no-response',
          sshPort: 22,
          baseUrl: 'https://x',
          expectedTlsPin: _pin,
          timeoutMs: BigInt.from(300),
        );
      } catch (e) {
        err = e;
      }
      expect(err.toString(), contains('timed out'));
      final c = await liveCounters();
      expect(c.pendingMints, BigInt.zero);
    });

    testWidgets('shutdown drains an in-flight mint immediately (Codex #2)', (
      _,
    ) async {
      // A long-timeout mint that Dart never answers: shutdown must resolve it at
      // once (not after the full timeout) and zero the pending counter.
      final f = demoMint(
        host: 'no-response',
        sshPort: 22,
        baseUrl: 'https://x',
        expectedTlsPin: _pin,
        timeoutMs: BigInt.from(30000),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      shutdownMintSink();
      Object? err;
      try {
        await f;
      } catch (e) {
        err = e;
      }
      expect(err.toString(), contains('shut down'));
      final c = await liveCounters();
      expect(c.pendingMints, BigInt.zero);
    });
  });

  // -------- Slice (b): RcEventsWatcher → StreamSink (real BridgeClient) --------
  testWidgets(
    'slice b — watcher streams a folded event then tears down to zero',
    (_) async {
      final srv = await spawnWatcherTestSse();
      final client = await BridgeClient.connectOpen(
        baseUrl: srv.baseUrl(),
        serverName: 'demo',
      );
      final handle = await createRcWatcher(client: client, serverName: 'demo');
      final stream = rcWatcherEvents(handle: handle);

      final event =
          await stream
                  .firstWhere((u) => u is BridgeWatcherUpdate_Event)
                  .timeout(const Duration(seconds: 10))
              as BridgeWatcherUpdate_Event;

      // The decoded event is a sealed BridgeRcEvent; the overlay is the enumerable
      // folded snapshot; `resync` is present (folded onto the Event, Codex #4).
      final ev = event.event;
      expect(ev, isA<BridgeRcEvent_ActivityChanged>());
      expect((ev as BridgeRcEvent_ActivityChanged).slug, 'cdx777');
      expect(event.overlay.any((e) => e.slug == 'cdx777'), true);

      stopRcEvents(handle: handle); // sync now (Codex #9)
      srv.stop();
      final c = await liveCounters();
      expect(c.activeWatchers, BigInt.zero);
      expect(c.activeForwarders, BigInt.zero);
      expect(c.activeSseServers, BigInt.zero);
    },
  );

  // -------- Slice (c): Dart-backed RcRunner (pure shed_core::rc) --------
  testWidgets('slice c — argv-out → fake-exec → decode-in round-trips', (
    _,
  ) async {
    expect(await rcListArgv(), ['shed-ext-rc', 'list']);

    final prompt = await rcPromptArgv(slug: 'cdx777', sessionId: 'sess-1');
    expect(prompt, containsAll(['prompt', '--slug', 'cdx777', '--session-id']));

    // The validating create gate: argv + stdin (claude-rc accepts typed input).
    // `createdBy` is Dart-supplied so the wire provenance carries the version.
    final inv = await rcCreateInvocation(
      kind: 'claude-rc',
      name: 'My Session',
      slug: 'cdx777',
      target: 'proj',
      createdBy: 'shed-mobile/test',
      prompt: 'hello world',
    );
    expect(inv.argv, containsAll(['create', '--wait', '--kind', 'claude-rc']));
    expect(inv.argv, contains('shed-mobile/test'));
    expect(inv.stdin, 'hello world');

    // Dart "runs" the list argv (fake runner) → Rust decodes AND enriches the
    // stdout into the single BridgeRcSession type (host/shed injected).
    const canned =
        '{"rc_sessions":[{"slug":"cdx777","tmux_session":"tmux-cdx777",'
        '"kind":"claude-rc","state":"ready","managed":true,'
        '"display_name":"My Session"}]}';
    final sessions = await rcDecodeSessions(
      stdout: canned,
      host: 'mini3',
      shed: 'proj',
    );
    expect(sessions.length, 1);
    expect(sessions.first.slug, 'cdx777');
    expect(sessions.first.host, 'mini3');
    expect(sessions.first.shed, 'proj');
    expect(sessions.first.kind, const BridgeRcKind.claudeRc());
    expect(sessions.first.state, BridgeRcState.ready);
    expect(sessions.first.managed, true);

    // typed-error mapping → a sealed BridgeError.
    final err = await rcErrorFromExit(
      exitCode: 3,
      stderr: 'slug in use',
      stdout: '',
    );
    expect(err, isA<BridgeError_RcSlugTaken>());
  });

  // -------- Slice (d): create-stream sink lifecycle (real BridgeClient) --------
  testWidgets('slice d — create streams progress+complete, cancels to zero', (
    _,
  ) async {
    final srv = await spawnCreateTestSse();
    final client = await BridgeClient.connectOpen(
      baseUrl: srv.baseUrl(),
      serverName: 'demo',
    );
    final handle = await createShedStream(
      client: client,
      req: const BridgeCreateShedRequest(name: 'folio'),
    );
    final stream = createShedEvents(handle: handle);

    final got = <BridgeCreateUpdate>[];
    await for (final u in stream.timeout(const Duration(seconds: 10))) {
      got.add(u);
      if (u is BridgeCreateUpdate_Complete) break;
    }
    expect(got.any((u) => u is BridgeCreateUpdate_Progress), true);
    final complete =
        got.firstWhere((u) => u is BridgeCreateUpdate_Complete)
            as BridgeCreateUpdate_Complete;
    expect(complete.shed.name, 'folio');

    cancelCreate(handle: handle); // sync now (Codex #9)
    srv.stop();
    final c = await liveCounters();
    expect(c.activeCreateStreams, BigInt.zero);
    expect(c.activeSseServers, BigInt.zero);
  });

  testWidgets('slice d — cancel before streaming leaves zero live streams', (
    _,
  ) async {
    final srv = await spawnCreateTestSse();
    final client = await BridgeClient.connectOpen(
      baseUrl: srv.baseUrl(),
      serverName: 'demo',
    );
    final handle = await createShedStream(
      client: client,
      req: const BridgeCreateShedRequest(name: 'folio'),
    );
    cancelCreate(handle: handle);
    srv.stop();
    final c = await liveCounters();
    expect(c.activeCreateStreams, BigInt.zero);
    expect(c.activeSseServers, BigInt.zero);
  });

  testWidgets('slice d — create is ONE-SHOT on 401 (accepted change, Codex #8)', (
    _,
  ) async {
    // shed-core create_stream is one-shot on a stream-open 401 (invalidates the
    // sent token then surfaces BadStatus(401)); NO transparent retry. Assert a
    // single Error update, no progress/complete, no retry storm.
    final srv = await spawnStatusTestSse(status: 401);
    final client = await BridgeClient.connectOpen(
      baseUrl: srv.baseUrl(),
      serverName: 'demo',
    );
    final handle = await createShedStream(
      client: client,
      req: const BridgeCreateShedRequest(name: 'folio'),
    );
    final stream = createShedEvents(handle: handle);

    final got = <BridgeCreateUpdate>[];
    await for (final u in stream.timeout(const Duration(seconds: 10))) {
      got.add(u);
      if (u is BridgeCreateUpdate_Error) break;
    }
    expect(got.length, 1);
    expect(got.single, isA<BridgeCreateUpdate_Error>());
    expect((got.single as BridgeCreateUpdate_Error).message, contains('401'));

    cancelCreate(handle: handle);
    srv.stop();
    final c = await liveCounters();
    expect(c.activeCreateStreams, BigInt.zero);
    expect(c.activeSseServers, BigInt.zero);
  });

  // -------- Slice (e): BridgeClient method surfaces a sealed BridgeError --------
  testWidgets(
    'slice e — a real client call maps a fault to a sealed BridgeError',
    (_) async {
      // The local SSE server answers any path with 200 text/event-stream, so
      // /api/overview's body fails JSON decode → BridgeError_Decode. This proves
      // the BridgeClient method → bridge_rt → sealed-error path end to end.
      final srv = await spawnWatcherTestSse();
      final client = await BridgeClient.connectOpen(
        baseUrl: srv.baseUrl(),
        serverName: 'demo',
      );
      Object? err;
      try {
        await client.overview();
      } catch (e) {
        err = e;
      }
      expect(err, isA<BridgeError>());
      srv.stop();
    },
  );

  // -------- Final: all leak counters (incl. SSE servers) at zero --------
  testWidgets('all leak counters return to zero', (_) async {
    final c = await liveCounters();
    expect(c.activeWatchers, BigInt.zero);
    expect(c.activeForwarders, BigInt.zero);
    expect(c.activeCreateStreams, BigInt.zero);
    expect(c.pendingMints, BigInt.zero);
    expect(c.activeSseServers, BigInt.zero);
  });
}

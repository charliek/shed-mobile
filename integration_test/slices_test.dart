// B1 vertical-slice proofs — the four FRB patterns the shed-mobile migration
// depends on, exercised end-to-end on a real device (macOS + Android emulator):
//   (a) TokenMinter inversion  — StreamSink out + oneshot registry + Dart submit
//   (b) RcEventsWatcher stream  — long-lived StreamSink + opaque handle teardown
//   (c) Dart-backed RcRunner    — argv-out → Dart-exec → decode-in (pure rc path)
//   (d) create-stream lifecycle — CreateSink → StreamSink + cancellation
// Plus the AC#2 leak counters returning to zero after each teardown.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/src/rust/api/bridge_rt.dart';
import 'package:shed_mobile/src/rust/api/create_stream.dart';
import 'package:shed_mobile/src/rust/api/mint.dart';
import 'package:shed_mobile/src/rust/api/rc_runner.dart';
import 'package:shed_mobile/src/rust/api/watcher.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';

const _pin = 'sha256:'
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
      // host is "no-response" is deliberately left unanswered (timeout test).
      sub = setMintSink().listen((req) async {
        if (req.host == 'no-response') return;
        await submitMintResult(
          requestId: req.requestId,
          outcome: BridgeMintOutcome(
            success: true,
            rawStdout: _fixtureBundle(req.expectedTlsPin ?? _pin),
            failureCode: '',
          ),
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      await shutdownMintSink(); // end the Rust sink fn cleanly first
      await sub.cancel();
    });

    testWidgets('Rust emits → Dart submits → Rust parses the bundle', (_) async {
      final bundle = await demoMint(
        host: 'myhost',
        sshPort: 22,
        baseUrl: 'https://myhost:8443',
        expectedTlsPin: _pin,
        timeoutMs: BigInt.from(5000),
      );
      // ignore: avoid_print
      print('demoMint -> https_port=${bundle.httpsPort} '
          'token_present=${bundle.tokenPresent} len=${bundle.tokenLen}');
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
        outcome:
            const BridgeMintOutcome(success: false, rawStdout: '', failureCode: 'x'),
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
  });

  // -------- Slice (b): RcEventsWatcher → StreamSink --------
  testWidgets('slice b — watcher streams events then tears down to zero',
      (_) async {
    final handle = await createRcWatcher();
    final stream = rcWatcherEvents(handle: handle);

    final firstEvent = await stream
        .firstWhere((u) => u.kind == 'event')
        .timeout(const Duration(seconds: 10));
    // ignore: avoid_print
    print('watcher event -> shed=${firstEvent.shed} slug=${firstEvent.slug}');
    expect(firstEvent.slug, 'cdx777');

    await stopRcEvents(handle: handle);
    final c = await liveCounters();
    expect(c.activeWatchers, BigInt.zero);
    expect(c.activeForwarders, BigInt.zero);
  });

  // -------- Slice (c): Dart-backed RcRunner (pure shed_core::rc) --------
  testWidgets('slice c — argv-out → fake-exec → decode-in round-trips',
      (_) async {
    // list argv (pure builder)
    expect(await rcListArgv(), ['shed-ext-rc', 'list']);

    // prompt argv (the B0-gap builder, present in this rev)
    final prompt = await rcPromptArgv(slug: 'cdx777', sessionId: 'sess-1');
    expect(prompt, containsAll(['prompt', '--slug', 'cdx777', '--session-id']));

    // the validating create gate: argv + stdin (claude-rc accepts typed input)
    final inv = await rcCreateInvocation(
      kind: 'claude-rc',
      name: 'My Session',
      slug: 'cdx777',
      target: 'proj',
      prompt: 'hello world',
    );
    expect(inv.argv, containsAll(['create', '--wait', '--kind', 'claude-rc']));
    expect(inv.stdin, 'hello world');

    // Dart "runs" the list argv (fake runner) → Rust decodes the stdout.
    const canned =
        '{"rc_sessions":[{"slug":"cdx777","tmux_session":"tmux-cdx777",'
        '"kind":"claude-rc","state":"ready","managed":true,'
        '"display_name":"My Session"}]}';
    final sessions = await rcDecodeList(stdout: canned);
    // ignore: avoid_print
    print('decoded ${sessions.length} session(s): '
        '${sessions.map((s) => "${s.slug}/${s.kind}/${s.state}").join(",")}');
    expect(sessions.length, 1);
    expect(sessions.first.slug, 'cdx777');
    expect(sessions.first.kind, 'claude-rc');
    expect(sessions.first.state, 'ready');
    expect(sessions.first.managed, true);

    // typed-error mapping
    final err = await rcErrorFromExit(exitCode: 3, stderr: 'slug in use', stdout: '');
    expect(err, contains('SlugTaken'));
  });

  // -------- Slice (d): create-stream sink lifecycle --------
  testWidgets('slice d — create streams progress+complete, cancels to zero',
      (_) async {
    final handle = await createShedStream();
    final stream = createShedEvents(handle: handle);

    final got = <BridgeCreateUpdate>[];
    await for (final u in stream.timeout(const Duration(seconds: 10))) {
      got.add(u);
      if (u.kind == 'complete') break;
    }
    // ignore: avoid_print
    print('create updates -> ${got.map((u) => "${u.kind}:${u.message}${u.name}").join(" | ")}');
    expect(got.any((u) => u.kind == 'progress'), true);
    final complete = got.firstWhere((u) => u.kind == 'complete');
    expect(complete.name, 'folio');

    await cancelCreate(handle: handle);
    final c = await liveCounters();
    expect(c.activeCreateStreams, BigInt.zero);
  });

  testWidgets('slice d — cancel before streaming leaves zero live streams',
      (_) async {
    final handle = await createShedStream();
    await cancelCreate(handle: handle);
    final c = await liveCounters();
    expect(c.activeCreateStreams, BigInt.zero);
  });

  // -------- Final: all leak counters at zero --------
  testWidgets('all leak counters return to zero', (_) async {
    final c = await liveCounters();
    // ignore: avoid_print
    print('counters -> watchers=${c.activeWatchers} forwarders=${c.activeForwarders} '
        'create=${c.activeCreateStreams} mints=${c.pendingMints}');
    expect(c.activeWatchers, BigInt.zero);
    expect(c.activeForwarders, BigInt.zero);
    expect(c.activeCreateStreams, BigInt.zero);
    expect(c.pendingMints, BigInt.zero);
  });
}

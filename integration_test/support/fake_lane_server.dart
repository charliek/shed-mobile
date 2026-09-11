import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// **The shed fakes, driven from Dart over their control door** (plan 018
/// §3.13).
///
/// `desktop/tools/shedtest/fake_lane_server.py` hosts one of shed's own
/// `fake_gx.FakeGx` / `fake_opencode.FakeOpencode` and exposes its knobs on a
/// second loopback port. This is the Dart end of that door — so a lane cell
/// seeds a session, pushes a frame, or reads the request ledger without
/// re-deriving either fake in Dart.
///
/// **Nothing here re-implements a fake.** That is the entire point: the gx and
/// opencode wire vocabularies live in ONE place (shed's checkout, alongside the
/// adapters they were recorded from), and a mobile cell that re-derived an
/// envelope would agree with its own mistake. [envelope] reaches the Python
/// builders by name for the same reason.
///
/// ## Lifetime
///
/// The process is spawned holding its **stdin pipe**, which is the fake's own
/// watchdog: `fake_lane_server.py` exits on stdin EOF, so a `flutter test` run
/// that is killed mid-cell never leaves an orphan bound to a loopback port.
/// [stop] posts `/_/stop` first (the clean path, which lets the fake close its
/// sockets), then kills whatever is left.
class FakeLaneServer {
  FakeLaneServer._(this._process, this._info, this._client);

  /// Where shed's checkout is. The harness needs `desktop/tools/shedtest/`
  /// from it — CI checks the pinned rev out into `shed-sibling` and sets this;
  /// a dev with the usual sibling layout needs nothing.
  static String get shedCheckout =>
      Platform.environment['SHED_CHECKOUT'] ?? '../shed';

  static String get _script =>
      '$shedCheckout/desktop/tools/shedtest/fake_lane_server.py';

  /// Spawn one fake and wait for its startup line.
  ///
  /// `home` is gx's `$GROK_HOME`: the fake writes a discovery record and a
  /// `0600` token file there at startup, and that directory is what the
  /// harness's local probe reads. Ignored for opencode, which needs no
  /// credential.
  static Future<FakeLaneServer> start(
    String agent, {
    String? home,
    String? token,
    String? instanceId,
  }) async {
    final script = File(_script);
    if (!script.existsSync()) {
      throw StateError(
        'no fake_lane_server.py at ${script.path} — set SHED_CHECKOUT to a '
        'shed checkout (it defaults to ../shed)',
      );
    }
    final process = await Process.start('python3', [
      script.path,
      '--agent',
      agent,
      if (home != null) ...['--home', home],
      if (token != null) ...['--token', token],
      if (instanceId != null) ...['--instance-id', instanceId],
    ]);
    // Drained rather than ignored: a Python traceback is the only thing that
    // explains a startup line that never came, and an unread pipe would block
    // the child once it filled.
    final stderrLines = <String>[];
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderrLines.add);

    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    late final Map<String, Object?> info;
    try {
      final first = await lines.first.timeout(const Duration(seconds: 20));
      info = jsonDecode(first) as Map<String, Object?>;
    } on Object {
      process.kill(ProcessSignal.sigkill);
      throw StateError(
        'the fake never printed its startup line; stderr:\n'
        '${stderrLines.join('\n')}',
      );
    }
    return FakeLaneServer._(process, info, HttpClient());
  }

  final Process _process;
  final Map<String, Object?> _info;
  final HttpClient _client;
  bool _stopped = false;

  String get agent => _info['agent']! as String;
  int get port => _info['port']! as int;

  /// The url the agent announces on ITS host — what a gx discovery record is
  /// matched against, and (because this harness's reach is LOCAL) also the
  /// dial url. The two are never conflated in the code under test; here they
  /// are equal by construction, which is what makes the cells need no SSH.
  String get reportedUrl => _info['reported_url']! as String;

  /// gx's `$GROK_HOME`, or null (opencode, or a gx fake started without one).
  String? get home => _info['home'] as String?;

  String get controlUrl => _info['control']! as String;

  /// Call one allowlisted knob on the hosted fake.
  ///
  /// The allowlist is the Python side's (`GX_METHODS` / `OPENCODE_METHODS`), so
  /// a typo here is a 400 naming the method rather than a silent no-op.
  Future<Object?> call(
    String method, {
    List<Object?> args = const [],
    Map<String, Object?> kwargs = const {},
  }) => _post('$controlUrl/_/$method', {'args': args, 'kwargs': kwargs});

  /// Build one gx wire envelope by name — `chunk`, `turn_completed`,
  /// `permission_request`, … The body IS the kwargs object.
  Future<Map<String, Object?>> envelope(
    String name,
    Map<String, Object?> kwargs,
  ) async =>
      (await _post('$controlUrl/_/envelope/$name', kwargs))!
          as Map<String, Object?>;

  /// `POST /_/stop`, then kill whatever is still alive. Idempotent, and safe to
  /// call from a `tearDown` after a cell that already stopped it.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _post('$controlUrl/_/stop', const {});
    } on Object {
      // A fake that is already gone cannot be asked to go; the kill below is
      // the backstop either way.
    }
    _client.close(force: true);
    // The watchdog's signal, and the reason a killed test run leaks nothing.
    try {
      await _process.stdin.close();
    } on Object {
      // Already closed with the process.
    }
    final exited = await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (exited == -1) await _process.exitCode;
  }

  Future<Object?> _post(String url, Object body) async {
    final request = await _client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    // **`contentLength` explicitly.** Without it `HttpClient` sends the body
    // chunked, and `http.server` reads a request body ONLY off `Content-Length`
    // — so the fake would see an empty body and every `args` would arrive
    // missing. It fails as "missing 1 required positional argument", which
    // looks nothing like a transfer-encoding problem.
    final raw = utf8.encode(jsonEncode(body));
    request.contentLength = raw.length;
    request.add(raw);
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await response.transform(utf8.decoder).join();
    // Status BEFORE decode. The control door answers a refusal as
    // `400 {"error": …}`, which does parse — but a refusal shaped any other
    // way (a traceback, an empty body from a dead process) would fail here as
    // a JSON error and bury the status code this message exists to report.
    if (response.statusCode != 200) {
      throw StateError('$url answered ${response.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}

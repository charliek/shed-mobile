import 'dart:async';
import 'dart:convert';

import '../control/control_token_provider.dart';
import '../core/app_error.dart';
import '../net/pinned_http_client.dart';
import '../rc/rc_events.dart';
import '../rc/rc_feed.dart';
import 'shed_dtos.dart';

/// Typed client for the shed-server control API over pinned TLS. Mirrors the
/// orchestrator's shedClient.ts (401 -> invalidate -> retry once with a fresh,
/// different token; upstream `{error:{code,message}}` preserved).
class ShedClient {
  ShedClient(this.http, this.tokens);

  final PinnedHttpClient http;
  final TokenSource tokens;

  /// Release the underlying pinned HTTP client (call on provider dispose).
  void close() => http.close();

  Future<List<Shed>> listSheds() async =>
      _list((await _send('GET', '/api/sheds')), 'sheds', Shed.fromJson);

  Future<Shed> getShed(String name) async =>
      Shed.fromJson(_obj(await _send('GET', '/api/sheds/${_e(name)}')));

  Future<Shed> startShed(String name) async =>
      Shed.fromJson(_obj(await _send('POST', '/api/sheds/${_e(name)}/start')));

  Future<Shed> stopShed(String name) async =>
      Shed.fromJson(_obj(await _send('POST', '/api/sheds/${_e(name)}/stop')));

  /// Restart = stop then start (the server has no atomic restart endpoint). A
  /// start that fails after a successful stop leaves the shed stopped; callers
  /// refetch to reflect the real state.
  Future<Shed> restartShed(String name) async {
    await stopShed(name);
    return startShed(name);
  }

  Future<void> deleteShed(String name) async =>
      _ok(await _send('DELETE', '/api/sheds/${_e(name)}'));

  Future<List<Session>> listSessions(String name) async => _list(
    await _send('GET', '/api/sheds/${_e(name)}/sessions'),
    'sessions',
    Session.fromJson,
  );

  Future<void> killSession(String shed, String session) async => _ok(
    await _send('DELETE', '/api/sheds/${_e(shed)}/sessions/${_e(session)}'),
  );

  Future<List<ImageInfo>> listImages() async =>
      _list(await _send('GET', '/api/images'), 'images', ImageInfo.fromJson);

  /// One-call host snapshot (`GET /api/overview`): server identity + features,
  /// disk usage, and every shed with its rc-enriched sessions and capabilities.
  /// A server too old to expose the route responds 404, which `_obj` surfaces as
  /// an AppError the overview provider maps to an upgrade-required state.
  Future<Overview> fetchOverview() async =>
      Overview.fromJson(_obj(await _send('GET', '/api/overview')));

  /// This host's disk usage broken down by images/sheds/snapshots/orphans
  /// (`GET /api/system/df`). Throws (→ a per-host "unavailable" card) if the agent
  /// is too old to serve it.
  Future<SystemDiskUsage> getSystemDf() async =>
      SystemDiskUsage.fromJson(_obj(await _send('GET', '/api/system/df')));

  /// Create a shed, streaming progress. 401 on stream-open invalidates the token
  /// and retries once with a fresh, different token (the create stream's own
  /// errors arrive as `event: error`, not exceptions, so a retry only ever
  /// happens before any event is yielded).
  Stream<ShedCreateEvent> createShed(CreateShedRequest req) async* {
    final token = await tokens.get();
    try {
      yield* _createOnce(req, token);
    } on AppError catch (e) {
      if (e.statusCode == 401 && token != null) {
        tokens.invalidate(token);
        final next = await tokens.get();
        if (next != null && next != token) {
          yield* _createOnce(req, next);
          return;
        }
        throw AppError.authExpired();
      }
      rethrow;
    }
  }

  Stream<ShedCreateEvent> _createOnce(
    CreateShedRequest req,
    String? token,
  ) async* {
    await for (final e in http.postSse(
      '/api/sheds',
      body: req.toJson(),
      token: token,
    )) {
      switch (e.event) {
        case 'progress':
          final m = _tryJson(e.data);
          yield ShedProgress(
            (m?['phase'] as String?) ?? 'progress',
            (m?['message'] as String?) ?? e.data,
          );
        case 'complete':
          final m = _tryJson(e.data) ?? const {};
          yield ShedComplete(Shed.fromJson(m));
        case 'error':
          final err = (_tryJson(e.data)?['error']) as Map<String, Object?>?;
          yield ShedCreateError(
            (err?['code'] as String?) ?? 'BACKEND_ERROR',
            (err?['message'] as String?) ?? e.data,
          );
        default:
          break; // unknown event: ignore
      }
    }
  }

  /// Subscribe to the host's aggregate rc activity stream
  /// (`GET /api/rc/events`, SSE), decoding each frame into a typed [RcEvent].
  /// Unknown/malformed frames are dropped. A 401 on stream-open invalidates the
  /// token and retries once with a fresh, different token — but only before any
  /// event has been yielded (once frames flow, re-subscription is the caller's
  /// reconnect loop's job).
  ///
  /// A [StreamIterator] drives the read so an open error (the getSse non-200
  /// throw) surfaces at `moveNext` inside this try/catch — a plain `yield*`
  /// would forward the stream error PAST the catch (a Dart async* gotcha).
  Stream<RcEvent> rcEvents() async* {
    var token = await tokens.get();
    var retried = false;
    var yielded = false;
    while (true) {
      final it = StreamIterator(http.getSse('/api/rc/events', token: token));
      try {
        while (await it.moveNext()) {
          final ev = parseRcEvent(it.current);
          if (ev != null) {
            yielded = true;
            yield ev;
          }
        }
        return; // stream ended cleanly
      } on AppError catch (e) {
        if (!yielded && !retried && e.statusCode == 401 && token != null) {
          tokens.invalidate(token);
          final next = await tokens.get();
          if (next != null && next != token) {
            token = next;
            retried = true;
            continue;
          }
          throw AppError.authExpired();
        }
        rethrow;
      } finally {
        await it.cancel();
      }
    }
  }

  /// Fetch a page of a codex session's message feed through the hub proxy
  /// (`GET /api/sheds/{shed}/rc/v1/sessions/{slug}/messages`). `since` is
  /// exclusive; the page is bounded by `limit` (server caps at 200).
  Future<RcMessagesPage> fetchRcMessages(
    String shed,
    String slug, {
    int? since,
    int? limit,
  }) async {
    final q = <String>[
      if (since != null) 'since=$since',
      if (limit != null) 'limit=$limit',
    ];
    final qs = q.isEmpty ? '' : '?${q.join('&')}';
    final path =
        '/api/sheds/${_e(shed)}/rc/v1/sessions/${_e(slug)}/messages$qs';
    return RcMessagesPage.fromJson(_obj(await _send('GET', path)));
  }

  /// Post a typed line into a gated codex session
  /// (`POST /api/sheds/{shed}/rc/v1/sessions/{slug}/input`). Maps the hub /
  /// proxy status codes to a typed [AppError]: 409 → the session is no longer
  /// accepting input (a race — the caller refreshes state), 503 → the hub is
  /// unavailable, 404 → the session is gone. The hub's own error body is a flat
  /// `{error, message}`, so classification keys off the status, not the body.
  Future<void> postRcInput(String shed, String slug, String text) async {
    final path = '/api/sheds/${_e(shed)}/rc/v1/sessions/${_e(slug)}/input';
    final res = await _send('POST', path, body: {'text': text});
    if (res.status >= 200 && res.status < 300) return;
    throw _rcInputError(res);
  }

  AppError _rcInputError(HttpResult res) {
    // Tolerate both the server's nested {error:{code,message}} and the hub's
    // flat {error, message} shapes when pulling a human message.
    final j = _tryJson(res.body);
    final nested = j?['error'];
    final message = nested is Map<String, Object?>
        ? (nested['message'] as String?)
        : (j?['message'] as String?);
    return switch (res.status) {
      409 => AppError(
        'RC_NOT_ACCEPTING',
        message ?? 'the session is not accepting input right now',
        409,
      ),
      404 => AppError('RC_SESSION_GONE', message ?? 'rc session is gone', 404),
      503 => AppError(
        (nested is Map<String, Object?> ? nested['code'] as String? : null) ??
            'RC_HUB_UNAVAILABLE',
        message ?? 'rc hub is not available for this shed',
        503,
      ),
      _ => AppError(
        'RC_INPUT_FAILED',
        message ?? 'input delivery failed (HTTP ${res.status})',
        res.status,
      ),
    };
  }

  // ---- internals ----------------------------------------------------------

  Future<HttpResult> _send(String method, String path, {Object? body}) async {
    final token = await tokens.get();
    var res = await _do(method, path, token, body);
    if (res.status == 401 && token != null) {
      tokens.invalidate(token);
      final next = await tokens.get();
      if (next != null && next != token) {
        res = await _do(method, path, next, body);
      }
    }
    return res;
  }

  Future<HttpResult> _do(
    String method,
    String path,
    String? token,
    Object? body,
  ) {
    switch (method) {
      case 'GET':
        return http.getJson(path, token: token);
      case 'POST':
        return http.postJson(path, body: body, token: token);
      case 'DELETE':
        return http.deleteJson(path, token: token);
      default:
        throw ArgumentError('unsupported method $method');
    }
  }

  Never _fail(HttpResult res) {
    if (res.status == 401) throw AppError.authExpired();
    final err = (_tryJson(res.body)?['error']) as Map<String, Object?>?;
    throw AppError(
      (err?['code'] as String?) ?? 'SHED_SERVER_ERROR',
      (err?['message'] as String?) ?? 'HTTP ${res.status}',
      res.status,
    );
  }

  void _ok(HttpResult res) {
    if (res.status < 200 || res.status >= 300) _fail(res);
  }

  Map<String, Object?> _obj(HttpResult res) {
    if (res.status != 200) _fail(res);
    final d = jsonDecode(res.body);
    if (d is! Map<String, Object?>) {
      throw AppError('SHED_PARSE_ERROR', 'expected a JSON object');
    }
    return d;
  }

  List<T> _list<T>(
    HttpResult res,
    String key,
    T Function(Map<String, Object?>) of,
  ) {
    if (res.status != 200) _fail(res);
    final decoded = jsonDecode(res.body);
    final raw = decoded is List
        ? decoded
        : (decoded is Map<String, Object?> ? decoded[key] : null);
    // A nil Go slice marshals to `null` (e.g. `{"sheds":null}` from a host with
    // no sheds), so treat a null/absent list as empty — matching the
    // orchestrator's `resp?.sheds ?? []`.
    if (raw == null) return <T>[];
    if (raw is! List) {
      throw AppError('SHED_PARSE_ERROR', 'unexpected $key response shape');
    }
    return raw.whereType<Map<String, Object?>>().map(of).toList();
  }

  Map<String, Object?>? _tryJson(String s) {
    try {
      final d = jsonDecode(s);
      return d is Map<String, Object?> ? d : null;
    } on FormatException {
      return null;
    }
  }

  String _e(String s) => Uri.encodeComponent(s);
}

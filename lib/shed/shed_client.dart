import 'dart:convert';

import '../control/control_token_provider.dart';
import '../core/app_error.dart';
import '../net/pinned_http_client.dart';
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

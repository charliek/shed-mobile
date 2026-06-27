import 'dart:convert';

import '../control/control_token_provider.dart';
import '../core/app_error.dart';
import '../net/pinned_http_client.dart';
import 'shed_dtos.dart';

/// Typed client for the shed-server control API over pinned TLS. Mirrors the
/// orchestrator's shedClient.ts (401 -> invalidate -> retry once). M0 ships
/// listSheds; M1 adds the rest of the CRUD + SSE create.
class ShedClient {
  ShedClient(this.http, this.tokens);

  final PinnedHttpClient http;
  final TokenSource tokens;

  Future<List<Shed>> listSheds() async => _parseSheds(await _get('/api/sheds'));

  /// GET with a bearer token; on a 401 invalidate and retry once, but only with
  /// a *freshly minted, different* token (matches shedClient.ts).
  Future<HttpResult> _get(String path) async {
    final token = await tokens.get();
    var res = await http.getJson(path, token: token);
    if (res.status == 401 && token != null) {
      tokens.invalidate(token);
      final next = await tokens.get();
      if (next != null && next != token) {
        res = await http.getJson(path, token: next);
      }
    }
    return res;
  }

  List<Shed> _parseSheds(HttpResult res) {
    if (res.status == 401) throw AppError.authExpired();
    if (res.status != 200) {
      throw AppError(
        'SHED_SERVER_ERROR',
        'GET /api/sheds -> HTTP ${res.status}',
        res.status,
      );
    }
    final decoded = jsonDecode(res.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map<String, Object?> ? decoded['sheds'] : null);
    if (list is! List) {
      throw AppError(
        'SHED_PARSE_ERROR',
        'unexpected /api/sheds response shape',
      );
    }
    return list.whereType<Map<String, Object?>>().map(Shed.fromJson).toList();
  }
}

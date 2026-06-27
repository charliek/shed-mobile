import 'dart:convert';
import 'dart:io';

import '../core/app_error.dart';
import '../core/fingerprint.dart';
import '../core/sse_parser.dart';

/// A minimal HTTP response: status + decoded body string.
class HttpResult {
  const HttpResult(this.status, this.body);
  final int status;
  final String body;
}

/// HTTPS client that pins a self-signed leaf certificate by sha256(DER).
///
/// Built on `SecurityContext(withTrustedRoots: false)` so EVERY certificate
/// fails default validation and reaches [badCertificateCallback] — the pin is
/// therefore checked on every connection, even a CA-valid one (closes the
/// fail-open path; PLAN §13 S1). The callback bypasses hostname/expiry, so
/// identity rests on the fingerprint.
class PinnedHttpClient {
  PinnedHttpClient({
    required this.host,
    required this.port,
    required this.fingerprint,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration idleTimeout = const Duration(seconds: 120),
  }) : _client = HttpClient(context: SecurityContext(withTrustedRoots: false)) {
    _client.connectionTimeout = connectTimeout;
    _client.idleTimeout = idleTimeout;
    _client.badCertificateCallback = (cert, h, p) =>
        certFingerprint(cert.der) == fingerprint;
  }

  final String host;
  final int port;
  final String fingerprint;
  final HttpClient _client;

  Uri _uri(String path) => Uri.parse('https://$host:$port$path');

  void _headers(HttpClientRequest req, String? token, String accept) {
    req.headers.set(HttpHeaders.acceptHeader, accept);
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
  }

  Future<HttpResult> _readResult(HttpClientResponse resp) async =>
      HttpResult(resp.statusCode, await resp.transform(utf8.decoder).join());

  Future<HttpResult> getJson(String path, {String? token}) async {
    final req = await _client.getUrl(_uri(path));
    _headers(req, token, 'application/json');
    return _readResult(await req.close());
  }

  Future<HttpResult> postJson(
    String path, {
    Object? body,
    String? token,
  }) async {
    final req = await _client.postUrl(_uri(path));
    _headers(req, token, 'application/json');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    return _readResult(await req.close());
  }

  Future<HttpResult> deleteJson(String path, {String? token}) async {
    final req = await _client.deleteUrl(_uri(path));
    _headers(req, token, 'application/json');
    return _readResult(await req.close());
  }

  /// POST that streams an `text/event-stream` response (create-shed progress).
  Stream<SseRawEvent> postSse(
    String path, {
    Object? body,
    String? token,
  }) async* {
    final req = await _client.postUrl(_uri(path));
    _headers(req, token, 'text/event-stream');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final resp = await req.close();
    if (resp.statusCode != 200) {
      // Read the body so 401/auth and upstream {error:{code,message}} survive.
      final body = await resp.transform(utf8.decoder).join();
      Map<String, Object?>? err;
      try {
        final d = jsonDecode(body);
        if (d is Map<String, Object?> && d['error'] is Map<String, Object?>) {
          err = d['error'] as Map<String, Object?>;
        }
      } on FormatException {
        // non-JSON body
      }
      throw AppError(
        (err?['code'] as String?) ?? 'SHED_SERVER_ERROR',
        (err?['message'] as String?) ?? 'POST $path -> HTTP ${resp.statusCode}',
        resp.statusCode,
      );
    }
    yield* parseSseStream(resp);
  }

  void close() => _client.close(force: true);
}

import 'dart:convert';
import 'dart:io';

import '../core/fingerprint.dart';

/// A minimal HTTP response: status + decoded body string.
class HttpResult {
  const HttpResult(this.status, this.body);
  final int status;
  final String body;
}

/// HTTPS client that pins a self-signed leaf certificate by sha256(DER).
///
/// Built on a `SecurityContext(withTrustedRoots: false)` so EVERY certificate
/// fails default validation and reaches [badCertificateCallback] — the pin is
/// therefore checked on every connection, even a CA-valid one (closes the
/// fail-open path; PLAN §13 S1). The callback bypasses hostname/expiry, so we
/// rely on the fingerprint for identity.
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

  Future<HttpResult> getJson(String path, {String? token}) async {
    final req = await _client.getUrl(Uri.parse('https://$host:$port$path'));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return HttpResult(resp.statusCode, body);
  }

  void close() => _client.close(force: true);
}

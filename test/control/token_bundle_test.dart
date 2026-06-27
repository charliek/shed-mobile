import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/control/token_bundle.dart';
import 'package:shed_mobile/servers/server_target.dart';

ServerTarget target({String? pin}) => ServerTarget(
  name: 'mini3',
  host: 'mini3',
  sshPort: 2222,
  secure: true,
  baseUrl: 'https://mini3:8443',
  tlsCertFingerprint: pin,
);

String bundle({
  String scope = 'control',
  String token = 'shed_control_abc',
  String? fp,
  String? expiresAt = '2026-06-27T19:09:50.730171-05:00',
}) {
  final m = <String, Object?>{'scope': scope, 'token': token};
  if (fp != null) m['tls_cert_fingerprint'] = fp;
  if (expiresAt != null) m['expires_at'] = expiresAt;
  return jsonEncode(m);
}

void main() {
  group('parseTokenBundle', () {
    test('accepts a valid control bundle', () {
      final t = parseTokenBundle(bundle(), target());
      expect(t.token, 'shed_control_abc');
      expect(t.expiresAt, isNotNull);
    });

    test('accepts a matching minted fingerprint', () {
      final pin = 'sha256:${'a' * 64}';
      final t = parseTokenBundle(bundle(fp: pin), target(pin: pin));
      expect(t.token, 'shed_control_abc');
    });

    test('rejects a non-control scope', () {
      expect(
        () => parseTokenBundle(bundle(scope: 'session'), target()),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'SHED_AUTH_EXPIRED'),
        ),
      );
    });

    test(
      'rejects a minted fingerprint that differs from the pin (no silent re-pin)',
      () {
        expect(
          () => parseTokenBundle(
            bundle(fp: 'sha256:${'b' * 64}'),
            target(pin: 'sha256:${'a' * 64}'),
          ),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              'SHED_TLS_PIN_MISMATCH',
            ),
          ),
        );
      },
    );

    test('rejects unparseable JSON', () {
      expect(
        () => parseTokenBundle('not json', target()),
        throwsA(isA<AppError>()),
      );
    });

    test('rejects an empty or whitespace-only token', () {
      expect(
        () => parseTokenBundle(bundle(token: '   '), target()),
        throwsA(isA<AppError>()),
      );
    });

    test('rejects a missing or unparseable expiry (never non-expiring)', () {
      expect(
        () => parseTokenBundle(bundle(expiresAt: null), target()),
        throwsA(isA<AppError>()),
      );
      expect(
        () => parseTokenBundle(bundle(expiresAt: 'soon'), target()),
        throwsA(isA<AppError>()),
      );
    });
  });
}

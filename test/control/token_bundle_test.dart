import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/control/token_bundle.dart';

/// B4: the provider-mint path (`parseTokenBundle`/`MintedToken`) was retired —
/// the running-server control-token FSM lives in Rust and parses via
/// `parse_control_bundle`. What remains Dart is the add-server (TOFU)
/// `parseControlBundle`, covered below.

void main() {
  group('parseControlBundle', () {
    String cbundle({
      String scope = 'control',
      String token = 'tok',
      bool includeFp = true,
      String? fp,
      Object? port = 8443,
      String? exp = '2026-06-27T19:09:50Z',
    }) {
      final m = <String, Object?>{'scope': scope, 'token': token};
      if (includeFp) m['tls_cert_fingerprint'] = fp ?? 'sha256:${'a' * 64}';
      if (port != null) m['https_port'] = port;
      if (exp != null) m['expires_at'] = exp;
      return jsonEncode(m);
    }

    test('accepts a valid bundle', () {
      final b = parseControlBundle(cbundle());
      expect(b.httpsPort, 8443);
      expect(b.tlsCertFingerprint, 'sha256:${'a' * 64}');
      expect(b.token, 'tok');
    });

    test('requires the TLS fingerprint', () {
      expect(
        () => parseControlBundle(cbundle(includeFp: false)),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'SHED_TLS_PIN_MISSING'),
        ),
      );
    });

    test('rejects an out-of-range https_port', () {
      expect(
        () => parseControlBundle(cbundle(port: 70000)),
        throwsA(isA<AppError>()),
      );
      expect(
        () => parseControlBundle(cbundle(port: 0)),
        throwsA(isA<AppError>()),
      );
    });

    test('enforces an expected pin', () {
      expect(
        () => parseControlBundle(cbundle(), expectedPin: 'sha256:${'b' * 64}'),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            'SHED_TLS_PIN_MISMATCH',
          ),
        ),
      );
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/servers/server_record.dart';

ServerRecord _rec({String authMode = kAuthModeToken, String? token = 'tok'}) =>
    ServerRecord(
      name: 'mini3',
      host: 'mini3',
      sshPort: 2222,
      apiUrl: 'https://mini3:8443',
      tlsCertFingerprint: 'sha256:${'a' * 64}',
      hostKeyPin: 'SHA256:abc',
      authMode: authMode,
      controlToken: token,
      controlTokenExpiresAt: token == null ? null : DateTime.utc(2026, 6, 28),
    );

void main() {
  group('normalizeAuthMode (the STORED rule, matching AuthMode::from_wire)', () {
    test('only the exact "mtls" literal is mtls', () {
      expect(normalizeAuthMode('mtls'), kAuthModeMtls);
      expect(normalizeAuthMode(' mtls '), kAuthModeMtls);
    });

    test('missing, empty, legacy "secure" and unknown all read as token', () {
      // A record written before mtls existed has no auth_mode key at all — the
      // migration IS this tolerance (plan 002 §D6: no schema version field).
      for (final raw in <Object?>[
        null,
        '',
        '  ',
        'token',
        'secure', // the permanent legacy alias (plan 001 D1)
        'MTLS', // case-sensitive on the wire; not a match
        'future-mode',
        42,
        <String, Object?>{},
      ]) {
        expect(normalizeAuthMode(raw), kAuthModeToken, reason: 'raw=$raw');
      }
    });
  });

  group('ServerRecord json', () {
    test('round-trips the auth mode', () {
      final j = jsonDecode(jsonEncode(_rec(authMode: kAuthModeMtls).toJson()));
      final back = ServerRecord.fromJson(j as Map<String, Object?>);
      expect(back.authMode, kAuthModeMtls);
      expect(back.isMtls, isTrue);
    });

    test('a legacy record (no auth_mode key) decodes as token', () {
      final j = {
        'name': 'mini3',
        'host': 'mini3',
        'ssh_port': 2222,
        'api_url': 'https://mini3:8443',
        'tls_cert_fingerprint': 'sha256:${'a' * 64}',
        'host_key_pin': 'SHA256:abc',
        'control_token': 'tok',
      };
      final rec = ServerRecord.fromJson(j);
      expect(rec.authMode, kAuthModeToken);
      expect(rec.controlToken, 'tok'); // the seed survives — no re-mint needed
    });

    test('an unknown stored mode fails back to token, not mtls', () {
      final rec = ServerRecord.fromJson({
        ..._rec().toJson(),
        'auth_mode': 'quantum',
      });
      expect(rec.authMode, kAuthModeToken);
    });
  });

  group('copyWith (set-or-clear on the two credential fields)', () {
    test('OMITTING both keeps the stored seed — a bare mode update', () {
      final r = _rec().copyWith(authMode: kAuthModeToken);
      expect(r.controlToken, 'tok');
      expect(r.controlTokenExpiresAt, DateTime.utc(2026, 6, 28));
    });

    test('passing null to both CLEARS them — what a flip to mtls does', () {
      final r = _rec().copyWith(
        authMode: kAuthModeMtls,
        controlToken: null,
        controlTokenExpiresAt: null,
      );
      expect(r.authMode, kAuthModeMtls);
      expect(r.controlToken, isNull);
      expect(r.controlTokenExpiresAt, isNull);
    });

    test('passing values SETS them — a rotation replaces the whole pair', () {
      final r = _rec().copyWith(
        controlToken: 'rotated',
        controlTokenExpiresAt: DateTime.utc(2027, 1, 2),
      );
      expect(r.controlToken, 'rotated');
      expect(r.controlTokenExpiresAt, DateTime.utc(2027, 1, 2));
      expect(r.authMode, kAuthModeToken); // untouched
    });

    test('the two fields are independent of each other', () {
      // The sink always moves them together, but nothing about the sentinel
      // pattern couples them — assert that rather than assume it.
      final r = _rec().copyWith(controlTokenExpiresAt: null);
      expect(r.controlToken, 'tok');
      expect(r.controlTokenExpiresAt, isNull);
    });

    test('a cleared pair round-trips through JSON as absent keys', () {
      final cleared = _rec().copyWith(
        authMode: kAuthModeMtls,
        controlToken: null,
        controlTokenExpiresAt: null,
      );
      final j = cleared.toJson();
      expect(j.containsKey('control_token'), isFalse);
      expect(j.containsKey('control_token_expires_at'), isFalse);
      final back = ServerRecord.fromJson(
        jsonDecode(jsonEncode(j)) as Map<String, Object?>,
      );
      expect(back.controlToken, isNull);
      expect(back.controlTokenExpiresAt, isNull);
    });
  });
}

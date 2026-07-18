import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/rc/rc_service.dart';
import 'package:shed_mobile/ssh/ssh_connection.dart';
import 'package:shed_mobile/ssh/ssh_runner.dart';

/// B4: `RcService` is now a thin transport over the Rust `shed_core::rc` builders
/// (argv shape, the permission-mode gate, stdout decode, and exit-code mapping
/// all live in `rust/src/api/rc_runner.rs` + its unit tests, and are exercised
/// end-to-end by `integration_test/slices_test.dart`). Those paths call across
/// FFI, so they can't run under `flutter test` (no native lib) — this suite
/// covers only what stays PURE Dart: the `prompt` empty-text gate (which throws
/// BEFORE any SSH/bridge call) and the `classifySshException` transport mapping
/// `RcService._exec` delegates to.

class _FakeRunner {
  List<String>? argv;
  SshResult result = const SshResult(0, '', '');
  Object? error;

  SshRun get run =>
      (
        List<String> a, {
        String? stdin,
        Duration timeout = const Duration(seconds: 15),
      }) async {
        argv = a;
        if (error != null) throw error!;
        return result;
      };
}

RcService _service(_FakeRunner fake) =>
    RcService(runner: fake.run, shedName: 'myshed', serverLabel: 'mac-mini');

void main() {
  group('prompt gating (pure Dart, pre-bridge)', () {
    test('rejects empty text before any SSH/bridge call', () async {
      final fake = _FakeRunner();
      await expectLater(
        _service(fake).prompt('abc234', '   '),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'RC_BAD_REQUEST'),
        ),
      );
      // Never reached the runner (nor the argv bridge builder).
      expect(fake.argv, isNull);
    });
  });

  // The transport-error mapping RcService applies inside `_exec`. Tested against
  // the shared `classifySshException` directly (the argv-building step that
  // precedes `_exec` crosses FFI, so the full `list()`/`kill()` path can't run
  // here — this is the exact mapping those paths would surface).
  group('transport-error mapping (classifySshException)', () {
    test('auth failure → SSH_AUTH_DENIED 401', () {
      final e = classifySshException(SSHAuthFailError('denied'))!;
      expect(e.code, 'SSH_AUTH_DENIED');
      expect(e.statusCode, 401);
    });

    test('host-key mismatch → SSH_HOST_KEY_MISMATCH', () {
      final e = classifySshException(
        SSHHostkeyError('Hostkey verification failed'),
      )!;
      expect(e.code, 'SSH_HOST_KEY_MISMATCH');
    });

    test('socket / generic SSH / timeout → SSH_UNREACHABLE', () {
      expect(
        classifySshException(const SocketException('refused'))!.code,
        'SSH_UNREACHABLE',
      );
      expect(
        classifySshException(SSHStateError('boom'))!.code,
        'SSH_UNREACHABLE',
      );
      expect(
        classifySshException(TimeoutException('slow'))!.code,
        'SSH_UNREACHABLE',
      );
    });

    test('messages never echo transport detail (no leakage path)', () {
      final e = classifySshException(SSHAuthFailError('secret-detail-xyz'))!;
      expect(e.message, isNot(contains('secret-detail-xyz')));
    });

    test('a non-transport error is not classified (null → propagates)', () {
      expect(classifySshException(StateError('domain')), isNull);
    });
  });
}

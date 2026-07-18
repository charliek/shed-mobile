import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/bridge_adapters.dart';
import 'package:shed_mobile/rc/rc_service.dart';
import 'package:shed_mobile/src/rust/api/error.dart';

/// F1 — the RC-over-SSH AppError contract. `appErrorFromBridge`'s `Rc*` arms map
/// `shed_core::rc`'s exit-code domain (`error_from_exit` → typed `BridgeError`) to
/// the historical codes/statuses the old Dart `_rcError` mapper produced. These
/// `BridgeError` values are constructed directly — the mapping is pure Dart and
/// crosses no FFI. The HTTP plane (BadStatus → `_fromStatus`) is asserted here too
/// to lock the 404 → `RC_SESSION_GONE` distinction that must survive the change.
void main() {
  group('appErrorFromBridge — RC-over-SSH exit domain', () {
    test('slug taken (exit 3) → RC_SLUG_TAKEN/409', () {
      final e = appErrorFromBridge(
        const BridgeError.rcSlugTaken(detail: 'cdx in use'),
      );
      expect(e.code, 'RC_SLUG_TAKEN');
      expect(e.statusCode, 409);
      expect(e.message, 'cdx in use');
    });

    test('not found (exit 4) → RC_NOT_FOUND/404 (NOT RC_SESSION_GONE)', () {
      final e = appErrorFromBridge(
        const BridgeError.rcNotFound(detail: 'gone'),
      );
      expect(e.code, 'RC_NOT_FOUND');
      expect(e.statusCode, 404);
    });

    test('bad request (exit 2) → RC_BAD_REQUEST/400', () {
      final e = appErrorFromBridge(
        const BridgeError.rcBadRequest(detail: 'bad mode'),
      );
      expect(e.code, 'RC_BAD_REQUEST');
      expect(e.statusCode, 400);
    });

    test('missing binary (exit 127) → SHED_EXT_RC_MISSING/502', () {
      final e = appErrorFromBridge(const BridgeError.rcMissingBinary());
      expect(e.code, 'SHED_EXT_RC_MISSING');
      expect(e.statusCode, 502);
      expect(
        e.message,
        'shed-ext-rc is not installed on this shed — update the shed image',
      );
    });

    test('other non-zero → RC_FAILED/500 (detail carried from Rust)', () {
      final e = appErrorFromBridge(
        const BridgeError.rcFailed(detail: 'shed-ext-rc exited 5'),
      );
      expect(e.code, 'RC_FAILED');
      expect(e.statusCode, 500);
      expect(e.message, 'shed-ext-rc exited 5');
    });
  });

  group('appErrorFromBridge — HTTP plane (BadStatus)', () {
    test('404 keeps producing RC_SESSION_GONE/404', () {
      final e = appErrorFromBridge(const BridgeError.badStatus(code: 404));
      expect(e.code, 'RC_SESSION_GONE');
      expect(e.statusCode, 404);
    });

    test('401 → auth expired', () {
      final e = appErrorFromBridge(const BridgeError.badStatus(code: 401));
      expect(e.code, 'SHED_AUTH_EXPIRED');
    });

    test('409 → RC_NOT_ACCEPTING, 503 → RC_HUB_UNAVAILABLE', () {
      expect(
        appErrorFromBridge(const BridgeError.badStatus(code: 409)).code,
        'RC_NOT_ACCEPTING',
      );
      expect(
        appErrorFromBridge(const BridgeError.badStatus(code: 503)).code,
        'RC_HUB_UNAVAILABLE',
      );
    });
  });

  group('rcDecodeError — decode-path re-map', () {
    test('a decode RcFailed becomes RC_FAILED/502 (not the exit-path 500)', () {
      final e = rcDecodeError(
        const BridgeError.rcFailed(
          detail: 'shed-ext-rc returned an invalid session DTO',
        ),
      );
      expect(e.code, 'RC_FAILED');
      expect(e.statusCode, 502);
      expect(e.message, 'shed-ext-rc returned an invalid session DTO');
    });
  });

  group('appErrorFrom — non-bridge fallthrough', () {
    test('a non-BridgeError object wraps as SHED_ERROR', () {
      final e = appErrorFrom(StateError('boom'));
      expect(e.code, 'SHED_ERROR');
    });

    test('a BridgeError routes through appErrorFromBridge', () {
      final e = appErrorFrom(const BridgeError.rcNotFound(detail: 'x'));
      expect(e.code, 'RC_NOT_FOUND');
      expect(e.statusCode, 404);
    });
  });
}

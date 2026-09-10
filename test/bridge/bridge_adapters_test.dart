import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/bridge_adapters.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/rc/rc_service.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
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

  group('appErrorFromLane — the agent-lane domain (plan 018 §3.11)', () {
    // One arm per contract variant. The codes are what the controller and the
    // screen branch on: `LANE_NOT_ACCEPTING` and the two "already" arms are
    // rendered INLINE on the control that raised them, `LANE_UNAVAILABLE` is
    // the quiet one the re-open ladder exists for, and
    // `LANE_UNSUPPORTED_KIND` is deliberately not `LANE_NONE` — the row does
    // carry a lane, this build just cannot speak to it.
    const cases = <(BridgeLaneError, String, int?)>[
      (BridgeLaneError.unauthorized(), 'LANE_UNAUTHORIZED', 401),
      (BridgeLaneError.badRequest(msg: 'nope'), 'LANE_BAD_REQUEST', 400),
      (BridgeLaneError.unknownSession(), 'LANE_UNKNOWN_SESSION', 404),
      (BridgeLaneError.unknownApproval(), 'LANE_UNKNOWN_APPROVAL', 404),
      (BridgeLaneError.alreadySubmitted(), 'LANE_ALREADY_SUBMITTED', 409),
      (BridgeLaneError.alreadyResolved(), 'LANE_ALREADY_RESOLVED', 409),
      (BridgeLaneError.notAccepting(), 'LANE_NOT_ACCEPTING', 409),
      (BridgeLaneError.unavailable(msg: 'refused'), 'LANE_UNAVAILABLE', 503),
      (BridgeLaneError.failed(msg: 'boom'), 'LANE_FAILED', 500),
      (BridgeLaneError.noLane(msg: 'closed'), 'LANE_NONE', null),
      (
        BridgeLaneError.unsupportedLane(kind: 'codex'),
        'LANE_UNSUPPORTED_KIND',
        null,
      ),
    ];

    for (final (error, code, status) in cases) {
      test(code, () {
        final mapped = appErrorFromLane(error);
        expect(mapped.code, code);
        expect(mapped.statusCode, status);
      });
    }

    test('the msg arms carry the agent\'s own sentence whole', () {
      expect(
        appErrorFromLane(
          const BridgeLaneError.badRequest(msg: 'no option matches'),
        ).message,
        'no option matches',
      );
      expect(
        appErrorFromLane(
          const BridgeLaneError.unavailable(msg: 'nothing on :2421'),
        ).message,
        'nothing on :2421',
      );
      expect(
        appErrorFromLane(
          const BridgeLaneError.unsupportedLane(kind: 'codex'),
        ).message,
        contains('codex'),
      );
    });

    test(
      'appErrorFrom routes a lane error, and passes an AppError through',
      () {
        expect(
          appErrorFrom(const BridgeLaneError.notAccepting()).code,
          'LANE_NOT_ACCEPTING',
        );
        // A typed error re-wrapped as SHED_ERROR would bury the code every
        // branch above reads — `laneRemotePort` throws one of these.
        final own = AppError('LANE_BAD_SERVER_URL', 'no port', 400);
        expect(appErrorFrom(own), same(own));
      },
    );
  });
}

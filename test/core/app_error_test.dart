import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';

void main() {
  test('named constructors carry stable codes and status', () {
    expect(AppError.authExpired().code, 'SHED_AUTH_EXPIRED');
    expect(
      AppError.authExpired().statusCode,
      502,
    ); // matches orchestrator errors.ts
    expect(AppError.tlsPinMismatch().code, 'SHED_TLS_PIN_MISMATCH');
    expect(AppError.tlsPinMissing().code, 'SHED_TLS_PIN_MISSING');
    expect(AppError.hostKeyMismatch().code, 'SSH_HOST_KEY_MISMATCH');
  });

  test('toString does not leak beyond code + message', () {
    expect(
      AppError.authExpired().toString(),
      startsWith('AppError(SHED_AUTH_EXPIRED'),
    );
  });
}

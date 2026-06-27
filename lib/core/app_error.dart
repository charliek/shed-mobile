/// Typed application error with a stable code, mirroring the orchestrator's
/// AppError (apps/api/src/lib/errors.ts). Codes are surfaced to the UI; messages
/// are deliberately generic and never carry token or key material.
class AppError implements Exception {
  AppError(this.code, this.message, [this.statusCode]);

  final String code;
  final String message;
  final int? statusCode;

  factory AppError.authExpired() => AppError(
    'SHED_AUTH_EXPIRED',
    'Control token is missing or expired and could not be re-minted.',
    502,
  );

  factory AppError.tlsPinMismatch() => AppError(
    'SHED_TLS_PIN_MISMATCH',
    "The server's certificate did not match the configured pin.",
    502,
  );

  factory AppError.tlsPinMissing() => AppError(
    'SHED_TLS_PIN_MISSING',
    'A secure server has no TLS certificate pin configured.',
    502,
  );

  factory AppError.hostKeyMismatch() => AppError(
    'SSH_HOST_KEY_MISMATCH',
    "The server's SSH host key did not match the pinned key.",
    502,
  );

  @override
  String toString() => 'AppError($code: $message)';
}

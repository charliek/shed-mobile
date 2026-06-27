import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// Starts the Marionette driving binding and forwards `debugPrint` into it, so an
/// agent driving the app over the Dart VM Service can read app logs via
/// `get-logs`. Cloned from tapper's pattern.
///
/// Debug-only: the single call site in `main()` is gated behind `kDebugMode`, so
/// this function — and the `marionette_flutter` import — tree-shake out of release
/// builds. Stable widget keys (not custom hooks) make targeting reliable.
bool _initialized = false;

void initMarionetteDriver() {
  if (_initialized) return;
  _initialized = true;

  final logCollector = PrintLogCollector();
  MarionetteBinding.ensureInitialized(
    MarionetteConfiguration(logCollector: logCollector),
  );

  final flutterDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logCollector.addLog(message);
    flutterDebugPrint(message, wrapWidth: wrapWidth);
  };
}

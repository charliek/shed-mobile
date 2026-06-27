import 'package:flutter/foundation.dart';

/// Debug-only structured logs for agent driving, captured by Marionette's
/// `get-logs`. They expose state an agent can't read from the widget tree and
/// outcomes shown only in transient SnackBars. No-ops in release (`kDebugMode`
/// is const false, so the bodies + call sites tree-shake out). Cloned from tapper.

String? _lastState;

/// Emit `MSTATE <state>` only when [state] changes (dedup keeps the capped log
/// buffer readable), so an agent can wait on transitions without screenshotting.
void logDriveState(String state) {
  if (!kDebugMode) return;
  if (state == _lastState) return;
  _lastState = state;
  debugPrint('MSTATE $state');
}

/// Emit `MRESULT <action> ok` / `MRESULT <action> error=…` to confirm an action
/// whose only UI feedback is a transient SnackBar.
void logDriveResult(String action, {required bool ok, Object? error}) {
  if (!kDebugMode) return;
  debugPrint('MRESULT $action ${ok ? 'ok' : 'error=$error'}');
}

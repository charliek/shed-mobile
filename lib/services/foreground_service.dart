import 'dart:io' show Platform;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point the foreground-service isolate invokes. Must be a top-level
/// function with this annotation so it survives AOT tree-shaking.
@pragma('vm:entry-point')
void shedForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

/// The service exists only to keep the app process (and its SSH connections)
/// alive while a terminal/RC session is attached. It does no periodic work.
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Starts/stops a `specialUse` foreground service so Android doesn't kill the
/// app's live SSH session when it's backgrounded (an in-app terminal is the main
/// case). Android-only and entirely best-effort: any failure (permission denied,
/// OEM battery killer) is swallowed — foreground use is unaffected. Full
/// background-survival behaviour is a manual on-device check (tier d); it can't
/// be unit-tested.
class ShedForegroundService {
  ShedForegroundService._();

  static bool get _supported => Platform.isAndroid;
  static bool _inited = false;

  /// Desired-running intent. start()/stop() set it, and start() re-checks it after
  /// every await so a stop() that races an in-flight start (e.g. the user detaches
  /// while the notification-permission dialog is up) doesn't orphan the service.
  static bool _wantRunning = false;

  static Future<void> _ensureInit() async {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'shed_mobile_session',
        channelName: 'shed-mobile session',
        channelDescription: 'Keeps your shed terminal/SSH session connected.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true, // keep the radio up so SSH survives doze
      ),
    );
    // Best-effort: ask to be exempted from battery optimization so the OS is less
    // likely to kill the backgrounded session.
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    _inited = true;
  }

  /// Start the keep-alive service. Idempotent and best-effort; no-op off Android.
  /// NOTE: the single live [TerminalScreen] is the only caller — start on attach,
  /// stop on detach. If a second concurrent session is ever added, replace this
  /// boolean intent with an attach count so one detach can't stop a still-live one.
  static Future<void> start({required String text}) async {
    if (!_supported) return;
    _wantRunning = true;
    try {
      await _ensureInit();
      await FlutterForegroundTask.requestNotificationPermission();
      // Re-check intent after the awaits above: a detach may have called stop().
      if (!_wantRunning) return;
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.specialUse],
        notificationTitle: 'shed-mobile',
        notificationText: text,
        callback: shedForegroundCallback,
      );
      // A stop() that landed between the check and startService still wins.
      if (!_wantRunning) await stop();
    } catch (_) {
      // Best-effort: a missing permission or OEM restriction must not break the
      // foreground terminal.
    }
  }

  /// Stop the service if running. Idempotent and best-effort; no-op off Android.
  static Future<void> stop() async {
    _wantRunning = false;
    if (!_supported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}

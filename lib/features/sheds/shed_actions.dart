import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_client.dart';

/// Run a shed lifecycle action (start/stop/restart) against a server's client:
/// resolve the client, run [op], log the drive result, surface a failure as a
/// SnackBar, and always refetch `shedsProvider(serverName)` so the UI reflects
/// the real post-op state. The single source for this kernel — shared by the
/// per-host shed list and the cross-host shed cards (the card layers its own
/// busy state on top).
Future<void> runShedAction(
  WidgetRef ref,
  BuildContext context, {
  required String serverName,
  required String action,
  required Future<void> Function(ShedClient c) op,
}) async {
  try {
    final client = await ref.read(shedClientProvider(serverName).future);
    await op(client);
    logDriveResult(action, ok: true);
  } catch (e) {
    logDriveResult(action, ok: false, error: e);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$action failed: $e')));
    }
  } finally {
    ref.invalidate(shedsProvider(serverName));
  }
}

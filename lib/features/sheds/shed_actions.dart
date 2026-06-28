import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_client.dart';

/// The shared action kernel: run [op], log the drive result, surface a failure as
/// a SnackBar, and always run [invalidate] so the UI refetches the real post-op
/// state. [op] does its own work (resolve a client/service + call it) so this
/// serves both HTTP shed actions and SSH session actions.
Future<void> runAction(
  WidgetRef ref,
  BuildContext context, {
  required String action,
  required Future<void> Function() op,
  required void Function() invalidate,
}) async {
  try {
    await op();
    logDriveResult(action, ok: true);
  } catch (e) {
    logDriveResult(action, ok: false, error: e);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$action failed: $e')));
    }
  } finally {
    invalidate();
  }
}

/// A shed lifecycle action (start/stop/restart): resolves the server's client,
/// runs [op] against it, and refetches `shedsProvider(serverName)`. Shared by the
/// per-host shed list and the cross-host shed cards (the card layers busy state).
Future<void> runShedAction(
  WidgetRef ref,
  BuildContext context, {
  required String serverName,
  required String action,
  required Future<void> Function(ShedClient c) op,
}) => runAction(
  ref,
  context,
  action: action,
  op: () async {
    final client = await ref.read(shedClientProvider(serverName).future);
    await op(client);
  },
  invalidate: () => ref.invalidate(shedsProvider(serverName)),
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../src/rust/api/client.dart';

/// The shared action kernel: run [op], log the drive result, surface a failure as
/// a SnackBar, and (while the widget is still mounted) run [invalidate] so the UI
/// refetches the real post-op state. [op] does its own work (resolve a
/// client/service + call it) so this serves both HTTP shed actions and SSH session
/// actions.
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
    // Guard against a disposed ref: if the widget unmounted while [op] was in
    // flight, the caller's `ref.invalidate(...)` would throw "Cannot use Ref
    // after disposed". Skipping it is safe — the invalidated data is served by
    // autoDispose.family providers that refetch when next watched.
    if (context.mounted) invalidate();
  }
}

/// Confirm a shed delete. Shows the destructive-action dialog and resolves to
/// whether the user confirmed — `true` only when they tap Delete, `false` on
/// Cancel or a barrier dismiss. The single production call site (after the
/// cross-host/per-host card unification) is [ShedCard]'s delete action, which
/// guards against a rapid second tap stacking dialogs and re-checks
/// `context.mounted` across this await before mutating.
Future<bool> confirmShedDelete(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $name?'),
      content: const Text('This permanently deletes the shed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('shed-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A shed lifecycle action (start/stop/restart/delete): resolves the server's
/// client, runs [op] against it, and refetches the host's shed views (the shed
/// list AND the overview — the Hosts/Sessions views render from
/// [overviewProvider], so both must refresh). Shared by the per-host shed list
/// and the cross-host shed cards (the card layers busy state).
Future<void> runShedAction(
  WidgetRef ref,
  BuildContext context, {
  required String serverName,
  required String action,
  required Future<void> Function(BridgeClient c) op,
}) => runAction(
  ref,
  context,
  action: action,
  op: () async {
    final client = await ref.read(shedClientProvider(serverName).future);
    await op(client);
  },
  invalidate: () => invalidateShedViews(ref, serverName),
);

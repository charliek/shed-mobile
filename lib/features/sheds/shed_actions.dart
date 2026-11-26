import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../providers.dart';
import '../../src/rust/api/client.dart';
import '../../src/rust/api/dto.dart';

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
///
/// A cloud shed ([cloud]) says what goes with it: its machine and its disk.
Future<bool> confirmShedDelete(
  BuildContext context,
  String name, {
  bool cloud = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $name?'),
      content: Text(
        cloud
            ? 'Deletes the machine and its disk.'
            : 'This permanently deletes the shed.',
      ),
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

/// What a cloud shed's extend shows when it ends: fixed words for every
/// outcome, never the server's message.
String extendOutcomeWords(String name, BridgeExtendOutcome o) => switch (o) {
  BridgeExtendOutcome_Extended() => 'Extended $name',
  BridgeExtendOutcome_Refused(:final words) => 'Extend refused: $words',
  BridgeExtendOutcome_Unknown(:final hours, :final words) =>
    'An extend by $hours h: $words',
  BridgeExtendOutcome_Pending(:final words) => 'Extend not sent: $words',
};

/// Extend a cloud shed's lease by [hours] (plan 041): resolves the server's
/// client, sends the extend (the bridge never adds the hours twice), says how it
/// ended, and refetches the host's shed views (the list AND the overview) so
/// both show the new lease, or the extend whose outcome is unknown.
///
/// The refresh does not depend on the calling card: the provider container and
/// the messenger are taken before the first await, and the client is held for
/// the whole extend, so a card that unmounts meanwhile (the list refreshed, the
/// user navigated) still has both views refreshed. Only the snackbar needs a
/// messenger that is still mounted.
Future<void> runShedExtend(
  WidgetRef ref,
  BuildContext context, {
  required String serverName,
  required String name,
  required int hours,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Keep the client alive for the extend even if every widget watching it goes.
  final hold = container.listen(shedClientProvider(serverName), (_, _) {});
  String words;
  try {
    final client = await container.read(shedClientProvider(serverName).future);
    final out = await client.extend(name: name, hours: hours);
    logDriveResult(
      'shed-extend',
      ok: out is BridgeExtendOutcome_Extended,
      error: out is BridgeExtendOutcome_Extended ? null : out.runtimeType,
    );
    words = extendOutcomeWords(name, out);
  } catch (e) {
    logDriveResult('shed-extend', ok: false, error: e);
    words = 'Extend failed: ${appErrorFrom(e).message}';
  } finally {
    hold.close();
  }
  invalidateShedViewsIn(container, serverName);
  if (messenger != null && messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(words)));
  }
}

import 'package:flutter/material.dart';

/// Shown when a feed could not even be STARTED.
///
/// The distinction from an unreachable row matters. Once [MachineFeed.start]
/// runs, a connection that fails becomes a row with a reason on it — the
/// screen stays useful and says why. The failures this renders happen before
/// that: a missing or unreadable SSH identity, a server store that will not
/// open. The provider surfaces them as an `AsyncError`, and reading only
/// `.value` turns them into `null`, which is indistinguishable from "still
/// loading" — a spinner that never resolves.
///
/// So this says what failed, verbatim. A truncated or prettified message here
/// would hide the one string that names the actual cause.
class FeedStartFailure extends StatelessWidget {
  const FeedStartFailure({
    required this.origin,
    required this.error,
    super.key,
  });

  /// Human-facing name of what could not be reached, e.g. `my-server/web`.
  final String origin;

  /// The error as thrown. Rendered with `toString()` and not shortened.
  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('feed-start-failure'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Could not open $origin',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              '$error',
              key: const ValueKey('feed-start-failure-reason'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

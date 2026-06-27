import 'package:flutter/material.dart';

/// A centered error message with a Retry button — the shared failure state for
/// the list screens. Pass [messageKey] so the drive harness can read the error
/// (e.g. `sheds-error`, `rc-error`).
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.error,
    required this.onRetry,
    this.messageKey,
  });

  final Object error;
  final VoidCallback onRetry;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error', key: messageKey),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

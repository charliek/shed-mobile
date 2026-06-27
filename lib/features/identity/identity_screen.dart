import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../keys/key_manager.dart';
import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';

/// View the device's SSH public key + fingerprint, copy it, and (mobile only)
/// regenerate it. Shows only public material — never the private key.
class IdentityScreen extends ConsumerWidget {
  const IdentityScreen({super.key});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    logDriveResult('identity-copy', ok: true);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Public key copied')));
    }
  }

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate a new device key?'),
        content: const Text(
          'This replaces the current key. Connections will fail until you add '
          'the new public key to every shed (auth.ssh.authorized_keys) AND to '
          'GitHub. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('identity-regenerate-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // Capture lifecycle-independent handles before the async gap: the screen can
    // be popped while the key generates, which would invalidate `ref`. The
    // container outlives the widget, so invalidation always lands (important:
    // identitiesProvider isn't autoDispose, so a stale old key would otherwise
    // persist and new connections would keep using it).
    final store = ref.read(identityStoreProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await store.generateAndStore();
      // New connections must use the new key; existing PtySessions captured the
      // old identity by value and need a reconnect.
      container.invalidate(identitiesProvider);
      container.invalidate(publicIdentityProvider);
      logDriveResult('identity-regenerate', ok: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'New key generated — re-add it to your sheds + GitHub',
            ),
          ),
        );
      }
    } catch (e) {
      logDriveResult('identity-regenerate', ok: false, error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Regenerate failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(publicIdentityProvider);
    final canRegenerate = ref.watch(canRegenerateKeyProvider);
    logDriveState('screen=identity');
    return Scaffold(
      key: const ValueKey('identity-screen'),
      appBar: AppBar(title: const Text('SSH identity')),
      body: identity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('$e', key: const ValueKey('identity-error')),
          ),
        ),
        data: (id) => _body(context, ref, id, canRegenerate),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    PublicIdentity? id,
    bool canRegenerate,
  ) {
    if (id == null) {
      return const Center(
        key: ValueKey('identity-empty'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No SSH key found for this device.'),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Public key', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              id.authorizedKey,
              key: const ValueKey('identity-pubkey'),
              style: monoStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            id.fingerprint,
            key: const ValueKey('identity-fingerprint'),
            style: monoStyle(fontSize: 12, color: context.shed.fg2),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('identity-copy'),
            onPressed: () => _copy(context, id.authorizedKey),
            icon: const Icon(Icons.copy),
            label: const Text('Copy public key'),
          ),
          if (canRegenerate) ...[
            const SizedBox(height: 24),
            Text(
              'Trust this key on your sheds (auth.ssh.authorized_keys) or via '
              'GitHub before connecting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('identity-regenerate'),
              onPressed: () => _regenerate(context, ref),
              icon: Icon(
                Icons.refresh,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                'Regenerate device key',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

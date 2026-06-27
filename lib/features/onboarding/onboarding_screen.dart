import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../keys/key_manager.dart';
import '../../marionette/drive_state.dart';
import '../../providers.dart';

/// Mobile first-run: generate the device's ed25519 key in-app, show its public
/// half for the user to paste into GitHub (Settings → SSH and GPG keys), then
/// continue. Adding a server afterwards verifies the key is trusted (the SSH mint
/// succeeds, or surfaces SSH_AUTH_DENIED while GitHub propagation catches up).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  PublicIdentity? _key;
  bool _busy = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await ref.read(identityStoreProvider).generateAndStore();
      if (!mounted) return;
      setState(() => _key = g);
      logDriveResult('onboarding-generate', ok: true);
    } catch (e) {
      logDriveResult('onboarding-generate', ok: false, error: e);
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final k = _key;
    if (k == null) return;
    await Clipboard.setData(ClipboardData(text: k.authorizedKey));
    logDriveResult('onboarding-copy', ok: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Public key copied')));
    }
  }

  void _continue() {
    // Re-evaluate; the gate swaps to the server list now that a key exists.
    ref.invalidate(needsOnboardingProvider);
    logDriveResult('onboarding-continue', ok: true);
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    logDriveState(
      'screen=onboarding step=${key == null ? 'generate' : 'paste'}',
    );
    return Scaffold(
      key: const ValueKey('onboarding-screen'),
      appBar: AppBar(title: const Text('Set up this device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'shed-mobile connects to your sheds over SSH. Generate a key for '
              'this device, then add its public half to GitHub so your sheds '
              'trust it (Settings → SSH and GPG keys → New SSH key).',
            ),
            const SizedBox(height: 20),
            if (key == null)
              FilledButton(
                key: const ValueKey('onboarding-generate'),
                onPressed: _busy ? null : _generate,
                child: Text(_busy ? 'Generating…' : 'Generate device key'),
              ),
            if (key != null) ...[
              Text('Public key', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  key.authorizedKey,
                  key: const ValueKey('onboarding-pubkey'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                key.fingerprint,
                key: const ValueKey('onboarding-fingerprint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('onboarding-copy'),
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy public key'),
              ),
              const SizedBox(height: 24),
              const Text(
                'After adding it to GitHub (propagation can take up to ~1 hour), '
                'continue and add a server.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('onboarding-continue'),
                onPressed: _continue,
                child: const Text('Continue'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const ValueKey('onboarding-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

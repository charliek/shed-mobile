import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../servers/add_server_flow.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';

/// Add-server flow: enter host+port, SSH-mint to learn the fingerprints + token,
/// confirm both fingerprints, then persist. Trust root = the SSH host key.
class AddServerScreen extends ConsumerStatefulWidget {
  const AddServerScreen({super.key});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '2222');
  final _name = TextEditingController();
  ServerPreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final flow = await ref.read(addServerFlowProvider.future);
      final preview = await flow.preview(
        host: _host.text.trim(),
        sshPort: int.tryParse(_port.text.trim()) ?? 2222,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
      logDriveState('screen=add-server step=confirm host=${preview.host}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      logDriveResult('add-server-connect', ok: false, error: e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final flow = await ref.read(addServerFlowProvider.future);
      final name = _name.text.trim();
      await flow.commit(
        name: name.isEmpty ? _preview!.host : name,
        preview: _preview!,
      );
      logDriveResult('add-server', ok: true);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
      logDriveResult('add-server', ok: false, error: e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    logDriveState(
      'screen=add-server step=${preview == null ? 'input' : 'confirm'}',
    );
    return Scaffold(
      key: const ValueKey('add-server-screen'),
      appBar: AppBar(title: const Text('Add server')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('addserver-host'),
              controller: _host,
              enabled: preview == null && !_busy,
              decoration: const InputDecoration(
                labelText: 'Host (Tailscale name or 100.x IP)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('addserver-port'),
              controller: _port,
              enabled: preview == null && !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SSH port'),
            ),
            const SizedBox(height: 12),
            // Optional friendly name — handy when the host is a raw IP (no
            // MagicDNS). Editable at any step; defaults to the host if left blank.
            TextField(
              key: const ValueKey('addserver-name'),
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Name (optional — defaults to the host)',
              ),
            ),
            const SizedBox(height: 16),
            if (preview == null)
              PrimaryButton(
                key: const ValueKey('addserver-connect'),
                label: _busy ? 'Connecting…' : 'Connect & verify',
                onPressed: _busy ? null : _connect,
              ),
            if (preview != null) ...[
              const Text('Verify the fingerprints, then add:'),
              const SizedBox(height: 8),
              _Fingerprint(
                label: 'SSH host key',
                value: preview.hostKeyFingerprint,
              ),
              _Fingerprint(
                label: 'TLS cert',
                value: preview.tlsCertFingerprint,
              ),
              const SizedBox(height: 8),
              Text('API: ${preview.apiUrl}'),
              const SizedBox(height: 16),
              PrimaryButton(
                key: const ValueKey('addserver-confirm'),
                label: _busy ? 'Adding…' : 'Trust & add',
                onPressed: _busy ? null : _confirm,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const ValueKey('addserver-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fingerprint extends StatelessWidget {
  const _Fingerprint({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          SelectableText(value, style: monoStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

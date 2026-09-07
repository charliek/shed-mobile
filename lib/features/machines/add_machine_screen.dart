import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_record.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';

/// Add a machine — a native host reached over SSH, running a `roost-session`
/// (plan 012, roadmap R4; re-sourced onto roost by plan 013 S3m).
///
/// Deliberately separate from the add-SERVER flow, which is a multi-step
/// ceremony: a shed server needs its TLS pin fetched and confirmed, a control
/// token minted over an SSH bootstrap channel, and an auth mode resolved. A
/// machine needs none of that — it is an ordinary SSH host, so the form is the
/// four fields SSH itself needs and nothing more.
///
/// **The host field wants an ADDRESS, not just a name.** A phone has no
/// `~/.ssh/config` to resolve a bare name through, and on a Tailscale network
/// the name only resolves where MagicDNS is active — which an Android emulator
/// is not. Saying so in the field rather than letting it fail as an opaque DNS
/// error is the difference between a five-second fix and a debugging session.
class AddMachineScreen extends ConsumerStatefulWidget {
  const AddMachineScreen({super.key});

  @override
  ConsumerState<AddMachineScreen> createState() => _AddMachineScreenState();
}

class _AddMachineScreenState extends ConsumerState<AddMachineScreen> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _port = TextEditingController(text: '22');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _user.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final host = _host.text.trim();
    final user = _user.text.trim();
    final port = int.tryParse(_port.text.trim());

    if (name.isEmpty || host.isEmpty) {
      setState(() => _error = 'A name and an address are both required.');
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _error = 'The SSH port must be 1–65535.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(machineStoreProvider)
          .put(
            MachineRecord(
              name: name,
              host: host,
              user: user.isEmpty ? null : user,
              sshPort: port,
            ),
          );
      ref.invalidate(machinesProvider);
      logDriveResult('add-machine', ok: true);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      logDriveResult('add-machine', ok: false);
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Scaffold(
      appBar: AppBar(title: const Text('Add machine')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A machine is a computer you reach over SSH that runs a '
              'roost-session — not a shed VM. Its sessions appear beside your '
              'shed sessions.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: c.fg2),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('add-machine-name'),
              controller: _name,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'How it is labelled — e.g. mini3',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('add-machine-host'),
              controller: _host,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Address',
                helperText:
                    'Hostname or IP. Use the IP if this device has no DNS for '
                    'the name (a Tailscale IP works).',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('add-machine-user'),
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'SSH user',
                helperText: 'The account this device logs in as',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('add-machine-port'),
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SSH port'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'This device signs in with its own SSH key. Authorize it on '
                'the machine first — copy the key from Identity and add it to '
                r"that user's ~/.ssh/authorized_keys.",
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.fg2),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                key: const ValueKey('add-machine-error'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.errFg),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('add-machine-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Add machine'),
            ),
          ],
        ),
      ),
    );
  }
}

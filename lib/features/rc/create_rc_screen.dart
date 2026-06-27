import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../rc/rc_models.dart';
import '../../rc/rc_service.dart';

/// Create one RC session: pick the kind, optionally set a name / workdir /
/// kickoff prompt / permission mode, then create with `--wait` so the result
/// already carries the derived state (and URL, for claude kinds).
class CreateRcScreen extends ConsumerStatefulWidget {
  const CreateRcScreen({
    required this.serverName,
    required this.shedName,
    super.key,
  });

  final String serverName;
  final String shedName;

  @override
  ConsumerState<CreateRcScreen> createState() => _CreateRcScreenState();
}

class _CreateRcScreenState extends ConsumerState<CreateRcScreen> {
  RcKind _kind = defaultRcKind;
  final _name = TextEditingController();
  final _workdir = TextEditingController();
  final _prompt = TextEditingController();
  String? _permissionMode; // null = no flag (claude's own default)
  bool _busy = false;
  String? _error;

  ({String serverName, String shedName}) get _key =>
      (serverName: widget.serverName, shedName: widget.shedName);

  @override
  void dispose() {
    _name.dispose();
    _workdir.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = await ref.read(rcServiceProvider(_key).future);
      final name = _name.text.trim();
      final workdir = _workdir.text.trim();
      final prompt = _prompt.text.trim();
      final session = await svc.create(
        kind: _kind,
        // Blank name → null so the binary keeps the `<shed>/<slug>` default
        // (never an empty display name).
        displayName: name.isEmpty ? null : name,
        workdir: workdir.isEmpty ? null : workdir,
        prompt: prompt.isEmpty ? null : prompt,
        // The service drops the mode for non-claude kinds, so a mode picked
        // before switching to a shell is safely ignored.
        permissionMode: _permissionMode,
      );
      logDriveState(
        'screen=create-rc created slug=${session.slug} '
        'state=${session.state.wire} url=${session.url ?? '-'}',
      );
      logDriveResult('rc-create', ok: true);
      if (mounted) Navigator.of(context).pop(session);
    } catch (e) {
      logDriveResult('rc-create', ok: false, error: e);
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    logDriveState('screen=create-rc kind=${_kind.wire}');
    return Scaffold(
      key: const ValueKey('create-rc-screen'),
      appBar: AppBar(title: Text('New session · ${widget.shedName}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Kind', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final k in RcKind.values)
                  ChoiceChip(
                    key: ValueKey('createrc-kind-${k.wire}'),
                    label: Text(k.wire),
                    selected: _kind == k,
                    onSelected: _busy ? null : (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('createrc-name'),
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Session name (optional — defaults to shed/slug)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('createrc-workdir'),
              controller: _workdir,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Workdir (optional — defaults to \$SHED_WORKSPACE)',
              ),
            ),
            const SizedBox(height: 12),
            if (_kind.acceptsPrompt)
              TextField(
                key: const ValueKey('createrc-prompt'),
                controller: _prompt,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: _kind == RcKind.shell
                      ? 'Command (optional)'
                      : 'Kickoff prompt (optional)',
                ),
              ),
            if (_kind.runsClaude) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const ValueKey('createrc-permission-mode'),
                initialValue: _permissionMode,
                decoration: const InputDecoration(
                  labelText: 'Permission mode',
                  helperText: 'claude --permission-mode',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('(claude default)'),
                  ),
                  for (final m in rcPermissionModes)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _permissionMode = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('createrc-submit'),
              onPressed: _busy ? null : _create,
              child: Text(_busy ? 'Creating…' : 'Create'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const ValueKey('createrc-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

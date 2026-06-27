import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_dtos.dart';

/// Create a shed and stream live progress (the create-SSE path). Repo is entered
/// as `owner/repo` text (the MVP RepoSource); leave blank for a base shed.
class CreateShedScreen extends ConsumerStatefulWidget {
  const CreateShedScreen({required this.serverName, super.key});

  final String serverName;

  @override
  ConsumerState<CreateShedScreen> createState() => _CreateShedScreenState();
}

class _CreateShedScreenState extends ConsumerState<CreateShedScreen> {
  final _name = TextEditingController();
  final _repo = TextEditingController();
  final _lines = <String>[];
  bool _running = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _lines.clear();
    });
    try {
      final client = await ref.read(
        shedClientProvider(widget.serverName).future,
      );
      final repo = _repo.text.trim();
      final req = CreateShedRequest(
        name: _name.text.trim(),
        repo: repo.isEmpty ? null : repo,
      );
      await for (final e in client.createShed(req)) {
        if (!mounted) return;
        setState(() {
          switch (e) {
            case ShedProgress(:final phase, :final message):
              _lines.add('[$phase] $message');
            case ShedComplete(:final shed):
              _lines.add('complete: ${shed.name} (${shed.status})');
              _done = true;
            case ShedCreateError(:final code, :final message):
              _error = '$code: $message';
          }
        });
        logDriveState('screen=create lines=${_lines.length} done=$_done');
      }
      logDriveResult('shed-create', ok: _error == null && _done, error: _error);
      if (_done && _error == null && mounted) {
        ref.invalidate(shedsProvider(widget.serverName));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      logDriveResult('shed-create', ok: false, error: e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('create-shed-screen'),
      appBar: AppBar(title: Text('Create shed on ${widget.serverName}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('create-name'),
              controller: _name,
              enabled: !_running,
              decoration: const InputDecoration(labelText: 'Shed name'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('create-repo'),
              controller: _repo,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: 'Repo (owner/repo, optional)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('create-submit'),
              onPressed: (_running || _name.text.trim().isEmpty)
                  ? null
                  : _create,
              child: Text(_running ? 'Creating…' : 'Create'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('create-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                key: const ValueKey('create-log'),
                children: [
                  for (final l in _lines)
                    Text(l, style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

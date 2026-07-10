import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_dtos.dart';
import '../../shed/shed_name.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';

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
  final _cpus = TextEditingController();
  final _memory = TextEditingController();
  final _lines = <String>[];
  bool _running = false;
  bool _done = false;
  bool _noProvision = false;
  String? _image; // null = server default
  String? _error;
  // Last auto-suggested name — lets us refresh the suggestion as the repo
  // changes without ever overwriting a name the user typed themselves.
  String _lastSuggestion = '';

  @override
  void initState() {
    super.initState();
    // Rebuild on input so the Create button + field validation re-evaluate
    // (without the name listener, the button never enables — the original bug).
    _name.addListener(_rebuild);
    _repo.addListener(_onRepoChanged);
    _cpus.addListener(_rebuild);
    _memory.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onRepoChanged() {
    // Suggest a name from the repo, but only while the field is empty or still
    // shows our last suggestion (never clobber a user-typed name).
    if (_name.text.isEmpty || _name.text == _lastSuggestion) {
      final suggestion = suggestShedName(_repo.text);
      _lastSuggestion = suggestion;
      if (_name.text != suggestion) {
        _name.value = TextEditingValue(
          text: suggestion,
          selection: TextSelection.collapsed(offset: suggestion.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _repo.dispose();
    _cpus.dispose();
    _memory.dispose();
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
      final req = CreateShedRequest.fromForm(
        name: _name.text,
        repo: _repo.text,
        image: _image ?? '',
        cpus: _cpus.text,
        memoryMb: _memory.text,
        noProvision: _noProvision,
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
        invalidateShedViews(ref, widget.serverName);
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
    final nameError = validateShedName(_name.text);
    final cpusError = validatePositiveIntField(_cpus.text);
    final memError = validatePositiveIntField(_memory.text);
    // Images are best-effort: an empty list just leaves "(server default)".
    // (Type is inferred as List<ImageInfo> from asData; naming it here would
    // collide with Flutter's painting-layer ImageInfo.)
    final images =
        ref.watch(imagesProvider(widget.serverName)).asData?.value ?? const [];
    // Hoisted: the SSE log rebuilds on every progress event, and every line
    // shares one style — build it once, not per line per rebuild.
    final logStyle = monoStyle(fontSize: 12, color: context.shed.fg2);
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
              decoration: InputDecoration(
                labelText: 'Shed name',
                helperText: 'lowercase letters, digits, hyphens',
                // Only nag once something invalid is typed; an empty field just
                // leaves Create disabled.
                errorText: _name.text.trim().isEmpty ? null : nameError,
              ),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const ValueKey('create-image'),
              initialValue: _image,
              decoration: const InputDecoration(labelText: 'Image'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('(server default)'),
                ),
                for (final img in images)
                  DropdownMenuItem(value: img.name, child: Text(img.name)),
              ],
              onChanged: _running ? null : (v) => setState(() => _image = v),
            ),
            ExpansionTile(
              key: const ValueKey('create-advanced'),
              title: const Text('Advanced'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextField(
                  key: const ValueKey('create-cpus'),
                  controller: _cpus,
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'vCPUs (optional)',
                    errorText: cpusError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('create-memory'),
                  controller: _memory,
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Memory MB (optional)',
                    errorText: memError,
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('create-noprovision'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Skip provisioning'),
                  value: _noProvision,
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _noProvision = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              key: const ValueKey('create-submit'),
              label: _running ? 'Creating…' : 'Create',
              onPressed:
                  (_running ||
                      nameError != null ||
                      cpusError != null ||
                      memError != null)
                  ? null
                  : _create,
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
                children: [for (final l in _lines) Text(l, style: logStyle)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

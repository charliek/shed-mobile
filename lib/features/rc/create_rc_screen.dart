import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../rc/rc_models.dart';
import '../../rc/rc_service.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';

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
  // Pre-select `auto` so sessions run autonomously by default; the user can
  // switch to "(claude default)" (null = no flag) or another mode.
  String? _permissionMode = defaultRcPermissionMode;
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
            Text(
              'Kind',
              style: sansStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.shed.fg2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in RcKind.values)
                  _KindChip(
                    key: ValueKey('createrc-kind-${k.wire}'),
                    label: k.wire,
                    selected: _kind == k,
                    onTap: _busy ? null : () => setState(() => _kind = k),
                  ),
                // codex-rc is a future kind — shown as a disabled placeholder.
                const _SoonChip(label: 'codex-rc · soon'),
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
            const SizedBox(height: 28),
            PrimaryButton(
              key: const ValueKey('createrc-submit'),
              label: _busy ? 'Creating…' : 'Create',
              onPressed: _busy ? null : _create,
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

/// A selectable segmented kind option (the design's `segStyle`): accent-tinted
/// when selected, hairline-bordered otherwise.
class _KindChip extends StatelessWidget {
  const _KindChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    // Restore the button/selected semantics that ChoiceChip gave for free.
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? shed.accentSoft : Colors.transparent,
            border: Border.all(color: selected ? shed.accent : shed.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: monoStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? shed.fg : shed.fg2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A non-interactive "coming soon" kind placeholder.
class _SoonChip extends StatelessWidget {
  const _SoonChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: shed.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(label, style: monoStyle(fontSize: 12.5, color: shed.fg3)),
    );
  }
}

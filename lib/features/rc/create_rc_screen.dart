import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../rc/rc_capabilities.dart';
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

  /// The permission mode to send for [kind]: the (already capability-gated)
  /// claude dropdown value for a claude kind (nullable → claude's own default);
  /// a fixed autonomous `auto` for the other agent kinds (codex/cursor/
  /// opencode), which have no dropdown and are only offered when capabilities
  /// are present; null for shell (no posture). The service re-drops it for a
  /// posture-less kind.
  String? _modeFor(RcKind kind, String? claudeMode) {
    if (kind.runsClaude) return claudeMode;
    if (kind.hasPermissionMode) return defaultRcPermissionMode;
    return null;
  }

  Future<void> _create(RcKind kind, String? claudeMode) async {
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
        kind: kind,
        // Blank name → null so the binary keeps the `<shed>/<slug>` default
        // (never an empty display name).
        displayName: name.isEmpty ? null : name,
        workdir: workdir.isEmpty ? null : workdir,
        prompt: prompt.isEmpty ? null : prompt,
        permissionMode: _modeFor(kind, claudeMode),
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

  /// The kinds this shed offers, gated on its capabilities:
  ///   - caps == data(non-null) → the shed's own `creatableKinds()` (empty when
  ///     the shed advertises nothing installed — "present but empty");
  ///   - caps == data(null) (absent — stopped/old binary) → the safe base
  ///     (claude + shell), so an un-probed shed can still start those;
  ///   - loading/error → the same safe base, so the form is usable immediately
  ///     and degrades rather than blanking.
  List<RcKind> _offeredKinds(AsyncValue<RcCapabilities?> caps) => caps.when(
    data: (c) => c == null ? _baseKinds : c.creatableKinds(),
    loading: () => _baseKinds,
    error: (_, _) => _baseKinds,
  );

  /// The always-safe base when a shed's capabilities are absent: claude + shell.
  static const List<RcKind> _baseKinds = [RcKind.claudeRc, RcKind.shell];

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(shedCapabilitiesProvider(_key));
    final offered = _offeredKinds(caps);
    // Permission-mode gate: the generic `skip` is new — an OLD binary (a shed
    // whose capabilities are absent) rejects it, so only the historical claude
    // set is offered there; present capabilities unlock the full set. Sending
    // still goes through the clamped [claudeMode] so a stale selection can
    // never reach an old binary.
    final capsPresent = caps.asData?.value != null;
    final modes = capsPresent ? rcPermissionModes : rcClaudeHistoricalModes;
    final String? claudeMode =
        (_permissionMode != null && modes.contains(_permissionMode))
        ? _permissionMode
        : null;
    // The effective selection: keep the user's pick when still offered, else fall
    // to the first offered kind (or null when the shed offers none).
    final RcKind? selected = offered.contains(_kind)
        ? _kind
        : (offered.isEmpty ? null : offered.first);
    logDriveState(
      'screen=create-rc kind=${selected?.wire ?? '-'} '
      'offered=${offered.map((k) => k.wire).join(',')}',
    );
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
            if (offered.isEmpty)
              Text(
                'This shed offers no session kinds — update the shed image.',
                key: const ValueKey('createrc-no-kinds'),
                style: monoStyle(fontSize: 12.5, color: context.shed.fg3),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in offered)
                    _KindChip(
                      key: ValueKey('createrc-kind-${k.wire}'),
                      label: k.wire,
                      selected: selected == k,
                      onTap: _busy ? null : () => setState(() => _kind = k),
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
            if (selected != null && selected.acceptsPrompt)
              TextField(
                key: const ValueKey('createrc-prompt'),
                controller: _prompt,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: selected == RcKind.shell
                      ? 'Command (optional)'
                      : 'Kickoff prompt (optional)',
                ),
              ),
            // The full permission-mode picker is claude-only; the other agent
            // kinds run under an autonomous `auto` default (no dropdown).
            if (selected != null && selected.runsClaude) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const ValueKey('createrc-permission-mode'),
                initialValue: claudeMode,
                decoration: const InputDecoration(
                  labelText: 'Permission mode',
                  helperText: 'claude --permission-mode',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('(claude default)'),
                  ),
                  for (final m in modes)
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
              onPressed: (_busy || selected == null)
                  ? null
                  : () => _create(selected, claudeMode),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../providers.dart';
import '../../rc/rc_ui.dart';
import '../../src/rust/api/dto.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';

/// The reduced create-form view of one host's overview for a target shed:
/// which kinds to offer, whether full caps are present (unlocks the generic
/// `skip` perm mode), whether to show the loading spinner, the retry button,
/// an optional status note, the "present but empty" no-kinds message, and a
/// drive-state token (`loading|error|unsupported|missing|stopped|absent|
/// present`) the drive layer can assert the branch on.
typedef _CapsView = ({
  List<BridgeRcKind> offered,
  bool capsPresent,
  bool loading,
  bool retry,
  String? note,
  bool showNoKinds,
  String logToken,
});

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
  BridgeRcKind _kind = defaultRcKind;
  final _name = TextEditingController();
  final _workdir = TextEditingController();
  final _prompt = TextEditingController();
  // Pre-select `auto` so sessions run autonomously by default; the user can
  // switch to "(claude default)" (null = no flag) or another mode.
  String? _permissionMode = defaultRcPermissionMode;
  bool _busy = false;
  String? _error;
  // Set the instant a Retry tap fires so a rapid second tap can't stack a
  // second in-flight probe before the provider transitions to loading; cleared
  // (via `ref.listen` in build) once the overview reload settles.
  bool _retrying = false;

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
  String? _modeFor(BridgeRcKind kind, String? claudeMode) {
    if (kind.runsClaude) return claudeMode;
    if (kind.hasPermissionMode) return defaultRcPermissionMode;
    return null;
  }

  Future<void> _create(BridgeRcKind kind, String? claudeMode) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = await rcServiceOneShot(ref, _key);
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

  /// The always-safe base when a shed's capabilities are absent: claude + shell.
  static const List<BridgeRcKind> _baseKinds = [
    BridgeRcKind.claudeRc(),
    BridgeRcKind.shell(),
  ];

  /// Re-probe this host's overview. Guarded so a rapid second tap can't stack a
  /// second in-flight probe before the provider even transitions to loading.
  void _retryCaps() {
    if (_retrying) return;
    setState(() => _retrying = true);
    ref.invalidate(overviewProvider(widget.serverName));
  }

  /// Reduce the host overview into everything the offering + status area needs.
  /// We key off [overviewProvider] (not the lossy `shedCapabilitiesProvider`,
  /// which collapses server-too-old / shed-missing / shed-stopped / probe-failed
  /// all into one `null`) so each of those becomes a distinct, honest UI branch:
  /// a bare loading spinner, an error+retry, a quiet non-retry base (old server),
  /// a neutral base note (stopped/missing shed), a base+unavailable+retry
  /// (running but no caps), or the real `creatableKinds()` (caps present).
  _CapsView _resolveCaps(AsyncValue<OverviewResult> caps) {
    // A retained previous value (a reload after data) still renders from data;
    // only a value-less loading/error surfaces the loading/error branches.
    if (!caps.hasValue) {
      return caps.hasError
          ? _base(
              offered: const [],
              retry: true,
              note: "Couldn't read this shed's capabilities.",
              logToken: 'error',
            )
          : _base(offered: const [], loading: true, logToken: 'loading');
    }
    final result = caps.requireValue;
    // Server predates GET /api/overview: base is CORRECT here and a retry would
    // just re-404 forever — quiet base + a non-retry note, today's good path.
    if (result is OverviewUnsupported) {
      return _base(
        note: 'Server too old for codex/cursor/opencode.',
        logToken: 'unsupported',
      );
    }
    final overview = (result as OverviewData).overview;
    BridgeOverviewShed? row;
    for (final s in overview.sheds) {
      if (s.shed.name == widget.shedName) {
        row = s;
        break;
      }
    }
    // Shed not in the overview at all: neutral — do NOT claim "unreadable".
    if (row == null) {
      return _base(
        note: 'This shed isn\'t on this server — refresh its host.',
        logToken: 'missing',
      );
    }
    // Found but not running: caps only exist for a running shed, so this is not
    // a failure — a neutral "start it" note, no retry.
    if (!bridgeShedIsRunning(row.shed)) {
      final note = switch (row.shed.status) {
        BridgeShedStatus.stopped => 'Start the shed to see its session kinds.',
        BridgeShedStatus.starting =>
          'This shed is starting — its session kinds will appear once it\'s '
              'running.',
        _ => 'This shed isn\'t running — start it to see its session kinds.',
      };
      return _base(note: note, logToken: 'stopped');
    }
    final shedCaps = row.capabilities;
    // Running but no caps: a probe miss (retry re-probes) or an old binary that
    // can't advertise (retry is a harmless no-op) — the note is honest either
    // way, and unlike an old SERVER a retry here can genuinely self-heal.
    if (shedCaps == null) {
      return _base(
        retry: true,
        note: 'codex/cursor/opencode unavailable for this shed.',
        logToken: 'absent',
      );
    }
    // Caps present: the shed's own creatable set (empty → "present but empty").
    final offered = shedCaps.creatableKinds();
    return (
      offered: offered,
      capsPresent: true,
      loading: false,
      retry: false,
      note: null,
      showNoKinds: offered.isEmpty,
      logToken: 'present',
    );
  }

  /// The shared shape of every "capabilities not usable yet" branch except
  /// loading: caps absent (so [_baseKinds] is offered by default), not loading,
  /// and never "present but empty" (base kinds are never empty). Folds the
  /// boilerplate that would otherwise repeat across five [_resolveCaps] arms.
  _CapsView _base({
    List<BridgeRcKind> offered = _baseKinds,
    bool loading = false,
    bool retry = false,
    String? note,
    required String logToken,
  }) => (
    offered: offered,
    capsPresent: false,
    loading: loading,
    retry: retry,
    note: note,
    showNoKinds: false,
    logToken: logToken,
  );

  @override
  Widget build(BuildContext context) {
    final capsAsync = ref.watch(overviewProvider(widget.serverName));
    // Clear the retry guard once a reload settles (data or error), re-enabling
    // the Retry button. Firing outside build makes the setState safe.
    ref.listen(overviewProvider(widget.serverName), (_, next) {
      if (_retrying && !next.isLoading) setState(() => _retrying = false);
    });
    final view = _resolveCaps(capsAsync);
    final offered = view.offered;
    // Permission-mode gate: the generic `skip` is new — an OLD binary (a shed
    // whose capabilities are absent) rejects it, so only the historical claude
    // set is offered there; present capabilities unlock the full set. Sending
    // still goes through the clamped [claudeMode] so a stale selection can
    // never reach an old binary.
    final capsPresent = view.capsPresent;
    final modes = capsPresent ? rcPermissionModes : rcClaudeHistoricalModes;
    final String? claudeMode =
        (_permissionMode != null && modes.contains(_permissionMode))
        ? _permissionMode
        : null;
    // The effective selection: keep the user's pick when still offered, else fall
    // to the first offered kind (or null when the shed offers none).
    final BridgeRcKind? selected = offered.contains(_kind)
        ? _kind
        : (offered.isEmpty ? null : offered.first);
    logDriveState(
      'screen=create-rc caps=${view.logToken} '
      'kind=${selected?.wire ?? '-'} '
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
            // The offering area is a single-state branch keyed off the overview
            // reduction: a bare spinner while probing, the chips once we have an
            // offering, the "present but empty" message when caps advertise
            // nothing, or nothing at all (the error branch renders only the note
            // + Retry below — no premature base chips).
            if (view.loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  key: const ValueKey('createrc-caps-loading'),
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Reading capabilities…',
                      style: monoStyle(fontSize: 12.5, color: context.shed.fg3),
                    ),
                  ],
                ),
              )
            else if (offered.isNotEmpty)
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
              )
            else if (view.showNoKinds)
              Text(
                'This shed offers no session kinds — update the shed image.',
                key: const ValueKey('createrc-no-kinds'),
                style: monoStyle(fontSize: 12.5, color: context.shed.fg3),
              ),
            // Status note (loading has none): the honest reason base kinds are
            // (or aren't) all that's offered — old server / stopped / missing /
            // running-but-no-caps / couldn't-read.
            if (view.note != null) ...[
              const SizedBox(height: 10),
              Text(
                view.note!,
                key: const ValueKey('createrc-caps-note'),
                style: monoStyle(fontSize: 12.5, color: context.shed.fg3),
              ),
            ],
            // Retry ONLY where a re-probe can actually change the answer (a real
            // error, or a running shed whose caps didn't come through) — never
            // on an old SERVER (it would re-404 forever). Disabled while a reload
            // is already in flight so taps can't stack probes.
            if (view.retry) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('createrc-caps-retry'),
                  onPressed: (_retrying || capsAsync.isLoading)
                      ? null
                      : _retryCaps,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ),
            ],
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
                  labelText: selected == const BridgeRcKind.shell()
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

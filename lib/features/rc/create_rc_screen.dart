import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../craze/craze_create.dart';
import '../craze/craze_create_sheet.dart';
import '../create/create_rc_target.dart';
import '../lanes/lane_screen.dart';
import '../../lanes/lane_controller.dart';
import '../../rc/rc_ui.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';

/// Create one session: pick the kind, then fill in what that kind takes.
///
/// **Exactly three kinds** (plan 025 O3): Claude and opencode, launched as
/// roost tabs (a workdir and nothing else — see [CreateRcTarget.acceptsKickoff]),
/// and **craze** — offered where the target's craze source is live and can
/// create — whose own sheet ([CrazeCreateSheet]) takes the provider, the
/// directory and an optional first prompt. A craze session created here opens
/// its transcript at once, in place of this screen.
class CreateRcScreen extends ConsumerStatefulWidget {
  const CreateRcScreen({required this.target, super.key});

  /// Where the session will run — a shed or a machine. Everything that differs
  /// between the two lives behind this; the form below never branches on it.
  final CreateRcTarget target;

  @override
  ConsumerState<CreateRcScreen> createState() => _CreateRcScreenState();
}

class _CreateRcScreenState extends ConsumerState<CreateRcScreen> {
  BridgeRcKind _kind = defaultRcKind;

  /// The craze sheet has been on screen — chosen, the only kind offered, or a
  /// craze create still in flight to come back to. While true, the craze
  /// choice stays on screen even when the machine's craze stops offering a
  /// create under it — the sheet then says why and keeps the typed form (plan
  /// 025 §3.8), rather than the choice silently vanishing and taking the form
  /// off screen with it. Picking another kind clears it.
  bool _crazeChosen = false;
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

  @override
  void initState() {
    super.initState();
    // A craze create still running — or one whose outcome is unknown, which
    // only "Try again" here can resolve — reopens on the craze choice, so the
    // same form and the same request id are what the person sees.
    final origin = widget.target.crazeOrigin;
    if (origin != null) {
      final phase = ref.read(crazeDraftProvider(origin)).phase;
      if (phase == CrazePhase.submitting || phase == CrazePhase.unknown) {
        _kind = const BridgeRcKind.craze();
        _crazeChosen = true;
      }
    }
  }

  /// A craze create landed while its sheet was on screen (plan 025 §3.8):
  /// this screen gives way to the new session's transcript — at once, the row
  /// is already listed — and says what became of a first prompt craze did not
  /// take. A session that has already ended has no transcript to open.
  void _crazeCreated(String origin, CrazeCreated c) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    logDriveState(
      'screen=craze-create created=${c.hostId} ended=${c.ended} '
      'prompt=${c.created.prompt}',
    );
    if (c.ended) {
      messenger?.showSnackBar(const SnackBar(content: Text(crazeCreatedEnded)));
      navigator.pop();
      return;
    }
    final notice = promptNotice(c.created);
    if (notice != null) {
      messenger?.showSnackBar(
        SnackBar(
          key: const ValueKey('craze-create-prompt-notice'),
          content: Text(notice.join('\n')),
        ),
      );
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LaneScreen(
          machine: origin,
          kind: crazeLaneKind,
          slug: c.hostId,
          title: c.created.session.title,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _workdir.dispose();
    _prompt.dispose();
    super.dispose();
  }

  /// The permission mode to send for [kind]: null outright for a target that
  /// does not accept kickoff at all ([CreateRcTarget.acceptsKickoff] — a
  /// machine's `tab.open` has no posture to carry, and the form hides the
  /// dropdown accordingly, but this is the seam that actually keeps a stale
  /// [_permissionMode] from riding along to it); otherwise the
  /// (already capability-gated) claude dropdown value for a claude kind
  /// (nullable → claude's own default); a fixed autonomous `auto` for the
  /// other agent kinds (opencode), which have no dropdown and are only offered
  /// when capabilities are present; null for shell (no posture). The service
  /// re-drops it for a posture-less kind.
  String? _modeFor(BridgeRcKind kind, String? claudeMode) {
    if (!widget.target.acceptsKickoff) return null;
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
      final name = _name.text.trim();
      final workdir = _workdir.text.trim();
      final prompt = _prompt.text.trim();
      final created = await widget.target.create(
        ref,
        kind: kind,
        // Blank name → null so the target keeps its own default (never an
        // empty display name).
        displayName: name.isEmpty ? null : name,
        workdir: workdir.isEmpty ? null : workdir,
        prompt: prompt.isEmpty ? null : prompt,
        permissionMode: _modeFor(kind, claudeMode),
      );
      logDriveState(
        'screen=create-rc created slug=${created.slug} '
        'state=${created.state} url=${created.url ?? '-'}',
      );
      logDriveResult('rc-create', ok: true);
      if (mounted) Navigator.of(context).pop(created.result);
    } catch (e) {
      logDriveResult('rc-create', ok: false, error: e);
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-probe this host's overview. Guarded so a rapid second tap can't stack a
  /// second in-flight probe before the provider even transitions to loading.
  void _retryCaps() {
    if (_retrying) return;
    setState(() => _retrying = true);
    widget.target.refresh(ref);
  }

  @override
  Widget build(BuildContext context) {
    // Clear the retry guard once a reload settles (data or error), re-enabling
    // the Retry button. Firing outside build makes the setState safe.
    widget.target.listenSettled(ref, () {
      if (_retrying) setState(() => _retrying = false);
    });
    final view = widget.target.caps(ref);
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
    // craze, once chosen, stays a choice while its source cannot create — the
    // sheet says why, and the typed form stays on screen (plan 025 §3.8).
    final crazeOrigin = widget.target.crazeOrigin;
    const craze = BridgeRcKind.craze();
    final kinds = [
      ...offered,
      if (crazeOrigin != null &&
          _crazeChosen &&
          _kind == craze &&
          !offered.contains(craze))
        craze,
    ];
    // The effective selection: keep the user's pick when still offered, else fall
    // to the first offered kind (or null when the shed offers none).
    final BridgeRcKind? selected = kinds.contains(_kind)
        ? _kind
        : (kinds.isEmpty ? null : kinds.first);
    final crazeSelected = crazeOrigin != null && selected == craze;
    // The craze sheet is on screen — chosen, or the only kind there is (a
    // machine with craze and no roost): from here on it stays, exactly as a
    // chosen one does, until another kind is picked. A field, not state: this
    // build already renders it, so nothing needs to rebuild for it.
    if (crazeSelected) {
      _kind = craze;
      _crazeChosen = true;
    }
    logDriveState(
      'screen=create-rc caps=${view.logToken} '
      'kind=${selected?.wire ?? '-'} '
      'offered=${kinds.map((k) => k.wire).join(',')}',
    );
    return Scaffold(
      key: const ValueKey('create-rc-screen'),
      appBar: AppBar(title: Text('New session · ${widget.target.label}')),
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
            else if (kinds.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in kinds)
                    _KindChip(
                      key: ValueKey('createrc-kind-${k.wire}'),
                      label: k.wire,
                      selected: selected == k,
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              _kind = k;
                              _crazeChosen = k == craze;
                            }),
                    ),
                ],
              )
            else if (view.showNoKinds)
              Text(
                widget.target.noKindsHint,
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
                  onPressed: (_retrying || view.reloading) ? null : _retryCaps,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // craze's own sheet in place of the roost launch form: what to
            // start is craze's question (its providers, its recent
            // directories), and it creates through the machine's craze source.
            if (crazeSelected)
              CrazeCreateSheet(
                key: ValueKey('craze-create-$crazeOrigin'),
                origin: crazeOrigin,
                machine: widget.target.label,
                onCreated: (c) => _crazeCreated(crazeOrigin, c),
              ),
            // The optional detail fields, offered only where the target can
            // actually carry them: a roost-backed machine titles its own tab
            // and takes no kickoff prompt or posture, and a field whose
            // contents would be dropped is worse than no field at all.
            if (!crazeSelected && widget.target.acceptsKickoff) ...[
              TextField(
                key: const ValueKey('createrc-name'),
                controller: _name,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: widget.target.nameFieldLabel,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!crazeSelected) ...[
              TextField(
                key: const ValueKey('createrc-workdir'),
                controller: _workdir,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: widget.target.workdirFieldLabel,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!crazeSelected &&
                widget.target.acceptsKickoff &&
                selected != null &&
                selected.acceptsPrompt)
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
            if (!crazeSelected &&
                widget.target.acceptsKickoff &&
                selected != null &&
                selected.runsClaude) ...[
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
            if (!crazeSelected) ...[
              const SizedBox(height: 28),
              PrimaryButton(
                key: const ValueKey('createrc-submit'),
                label: _busy ? 'Creating…' : 'Create',
                onPressed: (_busy || selected == null)
                    ? null
                    : () => _create(selected, claudeMode),
              ),
            ],
            if (!crazeSelected && _error != null) ...[
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

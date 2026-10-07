/// **The craze create sheet** (plan 025 §3.8, CM4) — provider + directory + an
/// optional first prompt, nothing else (D6: no model, no effort, no permission
/// mode; craze's own defaults).
///
/// The create screen's craze choice renders it in place of the roost launch
/// form. What it holds and what it does not — the desktop's
/// `CrazeCreateDialog`, as rules rather than as React:
///
/// - **The options are read on every open** (D8: nothing cached) — providers
///   in craze's order, the default, the recent directories — through
///   `MachineFeed.crazeOptions`, on a connection of their own.
/// - **The draft is NOT the sheet's**: the typed form, the request id and the
///   submission's phase live in [crazeDraftProvider], per machine, so leaving
///   the screen keeps a submission running — its session simply appears as a
///   row — and a re-open finds the same form and the same id.
/// - **No state clears the typed form**: loading, a failed options read, the
///   machine's craze going offline or turning out too old, a refusal, an
///   unknown outcome — each says its piece and leaves what was typed alone.
///   Only a created session spends the draft.
///
/// Every rule it applies is `craze_create.dart`'s (pure, unit-tested); this
/// file is the draft's owner and the rendering.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../machines/machine_feed.dart';
import '../../providers.dart';
import '../../src/rust/api/craze.dart';
import '../../src/rust/api/dto_lane.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';
import 'craze_create.dart';

/// How a submission's request id is minted — `crazeNewRequestId`
/// (`shed_craze::new_request_id`: `shed-` and a UUID v4 in its simple form).
/// A provider so a widget test, which has no native library, can count them.
final crazeRequestIdMintProvider = Provider<String Function()>(
  (ref) => crazeNewRequestId,
);

/// **One machine's craze create draft** — keyed by the feed origin.
///
/// Deliberately NOT `autoDispose`: the draft outlives the sheet (and the
/// screen). Leaving while a submission runs keeps it running, and coming back
/// — even after the outcome turned out unknown — finds the same form and the
/// same request id, which is what makes "Try again" resume the request rather
/// than start a second session. One small value per machine visited, for the
/// app's run.
final crazeDraftProvider =
    NotifierProvider.family<CrazeDraftController, CrazeDraft, String>(
      CrazeDraftController.new,
    );

/// The draft's owner: edits, and the one submission at a time.
class CrazeDraftController extends Notifier<CrazeDraft> {
  CrazeDraftController(this.origin);

  /// The machine's feed key — a machine's name, or `shed:<server>/<shed>`.
  final String origin;

  @override
  CrazeDraft build() => CrazeDraft.empty;

  /// An edit of the form ([CrazeDraft.edit]'s rule: any change mints a new id
  /// next time; nothing while a submission is in flight).
  void edit({Object? provider = _keepProvider, String? cwd, String? prompt}) {
    state = identical(provider, _keepProvider)
        ? state.edit(cwd: cwd, prompt: prompt)
        : state.edit(provider: provider, cwd: cwd, prompt: prompt);
  }

  /// **Run one submission of this machine's draft.** The request id is the
  /// draft's: reused while an outcome is unknown, minted anew after any
  /// definite one ([CrazeDraft.beginSubmit] / [CrazeDraft.settle]). Created:
  /// the draft is spent, carrying what was created for the sheet on screen
  /// ([CrazeDraft.lastCreated]) — whether a transcript opens is that sheet's
  /// call, not this one's.
  ///
  /// **The feed is held for as long as the create runs**, because the feed
  /// owns the create's connection and closes it when it is torn down. Without
  /// this hold, leaving the screen would let the machine's feed go (it lives
  /// only while something listens) and cut the create short — and a create cut
  /// short is an outcome nobody knows. With it, leaving the screen leaves the
  /// create running and its session appears as a row.
  Future<void> submit() async {
    final current = state;
    if (current.phase == CrazePhase.submitting) return;
    final started = current.beginSubmit(ref.read(crazeRequestIdMintProvider));
    state = started;
    final feedHold = ref.listen(
      machineFeedControllerProvider(origin),
      (_, _) {},
    );
    final stateHold = ref.listen(machineFeedProvider(origin), (_, _) {});
    try {
      final feed = feedHold.read();
      final created = await feed.crazeCreateSession(started.request());
      // The feed folds the created row in before the create returns
      // (`MachineFeed.crazeCreateSession`), so a row it does NOT list now is a
      // session craze answered for that has already ended (a replayed answer).
      final listed = feed.state.rows.any(
        (r) => r is CrazeMachineRow && r.session.id == created.session.id,
      );
      logDriveResult('craze-create', ok: true);
      if (ref.mounted) {
        state = state.spent(CrazeCreated(created, ended: !listed));
      }
    } catch (e) {
      logDriveResult('craze-create', ok: false, error: e);
      if (ref.mounted) state = state.settle(crazeRefusalOf(e));
    } finally {
      feedHold.close();
      stateHold.close();
    }
  }
}

const Object _keepProvider = Object();

/// Where the options read stands.
sealed class _OptionsLoad {
  const _OptionsLoad();
}

final class _Loading extends _OptionsLoad {
  const _Loading();
}

final class _Failed extends _OptionsLoad {
  const _Failed(this.message);
  final String message;
}

final class _Ready extends _OptionsLoad {
  const _Ready(this.options);
  final BridgeLaneCreateOptions options;
}

/// The craze create sheet for one machine — the create screen's craze choice.
class CrazeCreateSheet extends ConsumerStatefulWidget {
  const CrazeCreateSheet({
    required this.origin,
    required this.machine,
    required this.onCreated,
    super.key,
  });

  /// The machine's feed key (what the draft and the feed are addressed by).
  final String origin;

  /// What to call the machine in a sentence.
  final String machine;

  /// A submission created a session WHILE this sheet was on screen: the
  /// screen decides what follows (open its transcript, say why not). Called
  /// once per created session.
  final void Function(CrazeCreated created) onCreated;

  @override
  ConsumerState<CrazeCreateSheet> createState() => _CrazeCreateSheetState();
}

class _CrazeCreateSheetState extends ConsumerState<CrazeCreateSheet> {
  late final TextEditingController _cwd;
  late final TextEditingController _prompt;
  _OptionsLoad _load = const _Loading();

  /// Bumped by every read, so an answer that lost to a Retry is dropped.
  int _attempt = 0;

  CrazeDraftController get _draft =>
      ref.read(crazeDraftProvider(widget.origin).notifier);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(crazeDraftProvider(widget.origin));
    _cwd = TextEditingController(text: draft.cwd);
    _prompt = TextEditingController(text: draft.prompt);
    _read();
  }

  @override
  void dispose() {
    _cwd.dispose();
    _prompt.dispose();
    super.dispose();
  }

  /// Read what a create can start here NOW — on every open and every Retry.
  Future<void> _read() async {
    final attempt = ++_attempt;
    setState(() => _load = const _Loading());
    try {
      final options = await ref
          .read(machineFeedControllerProvider(widget.origin))
          .crazeOptions();
      if (!mounted || attempt != _attempt) return;
      setState(() => _load = _Ready(options));
      _reconcile();
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() => _load = _Failed(_message(e)));
    }
  }

  static String _message(Object e) => switch (e) {
    final BridgeLaneError err => appErrorFromLane(err).message,
    StateError(:final message) => message,
    _ => '$e',
  };

  /// The provider follows the options: a selection carried over from an
  /// earlier open survives only while still ready, else the default rule. A
  /// submission in flight is left alone (its controls are disabled).
  void _reconcile() {
    final load = _load;
    if (load is! _Ready) return;
    final draft = ref.read(crazeDraftProvider(widget.origin));
    if (draft.phase == CrazePhase.submitting) return;
    final want = reconcileProvider(draft.provider, load.options);
    if (want != draft.provider) _draft.edit(provider: want);
  }

  /// A tap on a provider row: a dimmed one refuses it — the rule, not just the
  /// look.
  void _pick(BridgeLaneProvider p, bool submitting) {
    if (!providerSelectable(p) || submitting) return;
    _draft.edit(provider: p.id);
  }

  void _useRecent(String dir) {
    _cwd.text = dir;
    _draft.edit(cwd: dir);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final draft = ref.watch(crazeDraftProvider(widget.origin));
    ref.listen(crazeDraftProvider(widget.origin), (prev, next) {
      // The form follows the draft when it changes under the fields — a spent
      // draft after a create, a recent directory — never by retyping what the
      // user just typed (the fields' own edits already match).
      if (_cwd.text != next.cwd) _cwd.text = next.cwd;
      if (_prompt.text != next.prompt) _prompt.text = next.prompt;
      final created = next.lastCreated;
      if (created != null && !identical(created, prev?.lastCreated)) {
        widget.onCreated(created);
      }
      // A submission settled: the provider rule applies again.
      if (prev?.phase == CrazePhase.submitting &&
          next.phase != CrazePhase.submitting) {
        Future.microtask(() {
          if (mounted) _reconcile();
        });
      }
    });
    final craze = ref.watch(machineFeedProvider(widget.origin)).value?.craze;

    final load = _load;
    final options = load is _Ready ? load.options : null;
    final submitting = draft.phase == CrazePhase.submitting;
    final machineNote = crazeSheetNote(craze, widget.machine);
    final providers = options?.providers ?? const <BridgeLaneProvider>[];
    final noneReady = options != null && !providers.any(providerSelectable);
    final note = machineNote ?? (noneReady ? noProviderReady : null);
    BridgeLaneProvider? selected;
    for (final p in providers) {
      if (p.id == draft.provider && providerSelectable(p)) selected = p;
    }
    final cwdProblem = draft.cwd.isEmpty && draft.phase == CrazePhase.idle
        ? null
        : directoryProblem(draft.cwd);
    final refusal = draft.refusal == null ? null : refusalView(draft.refusal!);
    final canCreate =
        options != null &&
        selected != null &&
        directoryProblem(draft.cwd) == null &&
        note == null &&
        !submitting;
    logDriveState(
      'screen=craze-create machine=${widget.origin} '
      'state=${options == null ? (load is _Failed ? 'failed' : 'loading') : draft.phase.name} '
      'provider=${selected?.id ?? '-'} '
      'providers=${providers.map((p) => '${p.id}:${providerSelectable(p) ? 'ready' : 'dimmed'}').join(',')} '
      'recent=${options?.recentDirs.length ?? 0} '
      'request=${draft.requestId ?? '-'} create=$canCreate',
    );

    return Column(
      key: const ValueKey('craze-create-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null) ...[
          Container(
            key: const ValueKey('craze-create-note'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.warnBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(note, style: sansStyle(fontSize: 13, color: c.warnFg)),
          ),
          const SizedBox(height: 14),
        ],
        _Label('Provider', color: c.fg2),
        const SizedBox(height: 8),
        switch (load) {
          _Loading() => Row(
            key: const ValueKey('craze-create-loading'),
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'reading what ${widget.machine} can start…',
                  style: monoStyle(fontSize: 12.5, color: c.fg3),
                ),
              ),
            ],
          ),
          _Failed(:final message) => Row(
            children: [
              Expanded(
                child: Text(
                  'craze could not list providers: $message',
                  key: const ValueKey('craze-create-options-error'),
                  style: sansStyle(fontSize: 13, color: c.errFg),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const ValueKey('craze-create-options-retry'),
                onPressed: _read,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
          _Ready() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in providers) ...[
                _ProviderRow(
                  key: ValueKey('craze-provider-${p.id}'),
                  provider: p,
                  selected: providerSelectable(p) && p.id == draft.provider,
                  enabled: !submitting,
                  onTap: () => _pick(p, submitting),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        },
        const SizedBox(height: 14),
        _Label('Directory', color: c.fg2),
        const SizedBox(height: 8),
        if (options != null && options.recentDirs.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, dir) in options.recentDirs.indexed)
                _RecentDir(
                  key: ValueKey('craze-recent-dir-$i'),
                  dir: dir,
                  chosen: draft.cwd == dir,
                  onTap: submitting ? null : () => _useRecent(dir),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: const ValueKey('craze-create-cwd'),
          controller: _cwd,
          enabled: !submitting,
          autocorrect: false,
          enableSuggestions: false,
          style: monoStyle(fontSize: 13, color: c.fg),
          decoration: const InputDecoration(
            labelText: 'Absolute path on that machine',
          ),
          onChanged: (v) => _draft.edit(cwd: v),
        ),
        if (cwdProblem != null || refusal?.where == RefusalWhere.cwd) ...[
          const SizedBox(height: 6),
          Text(
            refusal?.where == RefusalWhere.cwd ? refusal!.text : cwdProblem!,
            key: const ValueKey('craze-create-cwd-problem'),
            style: sansStyle(fontSize: 12, color: c.errFg),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('craze-create-prompt'),
          controller: _prompt,
          enabled: !submitting,
          minLines: 3,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'First prompt (optional)',
            hintText:
                'what to start on — or leave it empty for an idle '
                'session',
          ),
          onChanged: (v) => _draft.edit(prompt: v),
        ),
        if (draft.phase == CrazePhase.unknown) ...[
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('craze-create-unknown'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.warnBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              outcomeUnknownNote,
              style: sansStyle(fontSize: 13, color: c.warnFg),
            ),
          ),
        ],
        if (refusal?.where == RefusalWhere.cause) ...[
          const SizedBox(height: 14),
          Text(
            'The session failed to start:',
            style: sansStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.errFg,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.errBg,
              borderRadius: BorderRadius.circular(8),
            ),
            // craze's cause, VERBATIM — multi-line, monospace.
            child: SelectableText(
              refusal!.text,
              key: const ValueKey('craze-create-cause'),
              style: monoStyle(fontSize: 12, color: c.errFg),
            ),
          ),
        ],
        if (refusal?.where == RefusalWhere.general) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.errBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              refusal!.text,
              key: const ValueKey('craze-create-error'),
              style: monoStyle(fontSize: 12, color: c.errFg),
            ),
          ),
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          key: const ValueKey('craze-create-submit'),
          label: primaryLabel(draft),
          onPressed: canCreate ? _draft.submit : null,
        ),
        if (submitting) ...[
          const SizedBox(height: 8),
          Text(
            'Leaving keeps the create running; its session appears as a row.',
            key: const ValueKey('craze-create-leaving'),
            style: sansStyle(fontSize: 12, color: c.fg3),
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: sansStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
  );
}

/// One provider, as craze listed it: its label, and — when it cannot start —
/// dimmed, with craze's state, reason and fix, and not selectable.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    super.key,
    required this.provider,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final BridgeLaneProvider provider;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final p = provider;
    final ok = providerSelectable(p);
    return Semantics(
      button: true,
      selected: selected,
      enabled: ok && enabled,
      child: Opacity(
        opacity: ok ? 1 : 0.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : c.surface,
              border: Border.all(color: selected ? c.accent : c.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.label,
                        style: sansStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                    ),
                    if (!ok)
                      Text(
                        providerStateWords(p.state),
                        key: ValueKey('craze-provider-state-${p.id}'),
                        style: monoStyle(fontSize: 11, color: c.fg3),
                      ),
                  ],
                ),
                if (!ok && p.reason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.reason!,
                    key: ValueKey('craze-provider-reason-${p.id}'),
                    style: sansStyle(fontSize: 12, color: c.fg2),
                  ),
                ],
                if (!ok && p.fix != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.fix!,
                    key: ValueKey('craze-provider-fix-${p.id}'),
                    style: monoStyle(fontSize: 12, color: c.fg3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of craze's recent directories, one tap to use.
class _RecentDir extends StatelessWidget {
  const _RecentDir({
    super.key,
    required this.dir,
    required this.chosen,
    required this.onTap,
  });

  final String dir;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: chosen ? c.accent : c.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          dir,
          overflow: TextOverflow.ellipsis,
          style: monoStyle(fontSize: 12, color: chosen ? c.accent : c.fg2),
        ),
      ),
    );
  }
}

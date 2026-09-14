import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_feed.dart';
import '../../machines/roost_bootstrap_flow.dart';
import '../../providers.dart';
import '../../src/rust/api/roost_bootstrap.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/primary_button.dart';

/// **The install / start affordance on a machine card** (plan 020 §3.8, commit
/// C-M4).
///
/// Shown only where [roostOfferFor] names one — an install for a machine with
/// nothing on roost's candidate ladder, a start for one where a `roost-session`
/// is installed and not serving, and nothing at all for the other two reach
/// kinds. The branch is the TYPED kind and never a substring of the reason
/// sentence; the whole decision lives in [roostOfferFor], beside the fold it
/// depends on, and is tested there.
///
/// ## Probe, consent, act
///
/// The button runs a read-only probe first. That is not a nicety: the reach
/// kind says a `roost-session` is not answering, and only the probe says what
/// is actually on the host, where an install would land, and where the bytes
/// would come from — which is everything the consent sheet has to show.
/// Nothing is changed on the far side until the sheet comes back `true`.
///
/// ## Where the drive goes
///
/// Both verbs go through `roostBootstrapFlowProvider`, whose `drive` is
/// `MachineFeed.runBootstrap`. This widget never assembles a
/// `RoostBootstrapRunner`: a completed install is what entitles this app run to
/// keep the machine's agent hooks wired, and the feed is where that claim is
/// recorded and the watcher re-spawned. See the provider's own doc.
///
/// The card needs no success handling. A completed install starts a
/// `roost-session`, the re-spawned watcher publishes a `Snapshot`, the snapshot
/// clears `downKind` — and this widget stops being rendered at all, because
/// [roostOfferFor] now answers null.
class RoostBootstrapOffer extends ConsumerStatefulWidget {
  const RoostBootstrapOffer({
    required this.machine,
    required this.offer,
    super.key,
  });

  final String machine;
  final RoostOffer offer;

  @override
  ConsumerState<RoostBootstrapOffer> createState() =>
      _RoostBootstrapOfferState();
}

/// Where a drive has got to. The button's label and the line under it both
/// render off this, so there is one answer to "what is happening".
enum _Step {
  /// Nothing in flight — the offer, as first shown.
  idle('idle'),

  /// The read-only look at the host.
  probe('probe'),

  /// The sheet is up and the user has not answered it.
  confirm('confirm'),

  /// Consented, and acting.
  install('install');

  const _Step(this.wire);

  /// The token the drive transcript carries. `probe` and `confirm` are the two
  /// §3.8 names; the other two are this widget's own and cost nothing.
  final String wire;
}

class _RoostBootstrapOfferState extends ConsumerState<RoostBootstrapOffer> {
  _Step _step = _Step.idle;

  /// The sentence under the button: a status line for a probe with no button, a
  /// failure's message, or null when there is nothing to say.
  String? _note;

  /// Whether [_note] is a failure, so it is coloured as one.
  bool _noteIsError = false;

  bool get _busy => _step != _Step.idle;

  /// The action word, for both the button and the keys the drive harness reads.
  String get _action => switch (widget.offer) {
    RoostOffer.install => 'install',
    RoostOffer.start => 'start',
  };

  void _settle(String? note, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _step = _Step.idle;
      _note = note;
      _noteIsError = isError;
    });
  }

  void _advance(_Step step) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _note = null;
      _noteIsError = false;
    });
  }

  /// Probe, then — if there is something to consent to — ask.
  Future<void> _run() async {
    if (_busy) return;
    final flow = ref.read(roostBootstrapFlowProvider(widget.machine));
    _advance(_Step.probe);
    final BridgeBootstrapStep step;
    try {
      step = await flow.probe();
    } catch (e) {
      _settle('$e', isError: true);
      logDriveResult('roost-bootstrap-probe', ok: false, error: e);
      return;
    }
    if (!mounted) return;
    switch (step) {
      case BridgeBootstrapStep_Probed(:final probe):
        logDriveResult('roost-bootstrap-probe', ok: true);
        await _consent(flow, probe);
      case BridgeBootstrapStep_Failed(:final failure):
        _settle(failure.message, isError: true);
        logDriveResult(
          'roost-bootstrap-probe',
          ok: false,
          error: failure.stageCode,
        );
      // Neither can come back from a drive: `run()` loops until the machine
      // reaches a terminal step, and a probe machine's terminal steps are
      // `Probed` and `Failed`. Reported rather than ignored — a silent
      // fallthrough here would look like a button that did nothing.
      case BridgeBootstrapStep_Exec() || BridgeBootstrapStep_Installed():
        _settle('the probe did not finish', isError: true);
        logDriveResult('roost-bootstrap-probe', ok: false, error: 'unfinished');
    }
  }

  /// Show what the probe found, and act on it only if the sheet says so.
  Future<void> _consent(
    RoostBootstrapFlow flow,
    BridgeBootstrapProbe probe,
  ) async {
    // Pin P6's row and the already-up-to-date row: reported, never acted on.
    // The client should not offer a button for either.
    if (!probe.actionable) {
      _settle(roostProbeStatusLine(probe));
      return;
    }
    final source = flow.source(probe.arch);
    // Nothing to send. The button is replaced by shed-core's own sentence
    // rather than by one this card invents.
    if (probe.needsSource && !source.available) {
      _settle(source.describe, isError: true);
      return;
    }
    final consent = roostConsentFor(
      target: widget.machine,
      probe: probe,
      source: source,
    );
    if (consent == null) {
      _settle(roostProbeStatusLine(probe));
      return;
    }

    _advance(_Step.confirm);
    if (!mounted) return;
    final ok = await showRoostConsentSheet(
      context,
      machine: widget.machine,
      consent: consent,
    );
    if (!mounted) return;
    // **Dismissing performs nothing** (AC 5). A barrier tap and a swipe-down
    // both answer null; Cancel answers false. All three land here, and the only
    // thing past this line is the install.
    if (ok != true) {
      _settle(null);
      logDriveResult('roost-bootstrap', ok: false, error: 'dismissed');
      return;
    }

    _advance(_Step.install);
    final BridgeBootstrapStep step;
    try {
      step = await flow.install(probe);
    } catch (e) {
      _settle('$e', isError: true);
      logDriveResult('roost-bootstrap', ok: false, error: e);
      return;
    }
    switch (step) {
      case BridgeBootstrapStep_Installed(:final installed):
        // The card does not announce this. The install started a session, the
        // re-spawned watcher will publish a `Snapshot`, and the snapshot is
        // what makes this whole widget go away.
        _settle(_installedNote(installed));
        logDriveResult('roost-bootstrap', ok: true);
      case BridgeBootstrapStep_Failed(:final failure):
        _settle(_failureNote(failure), isError: true);
        logDriveResult('roost-bootstrap', ok: false, error: failure.stageCode);
      case BridgeBootstrapStep_Exec() || BridgeBootstrapStep_Probed():
        _settle('the install did not finish', isError: true);
        logDriveResult('roost-bootstrap', ok: false, error: 'unfinished');
    }
  }

  /// What an install is worth saying on the card afterwards: the warnings, if
  /// any, and otherwise the readiness line.
  static String _installedNote(BridgeBootstrapInstalled installed) {
    final warnings = [
      if (installed.pathWarning != null) installed.pathWarning!,
      if (installed.backupWarning != null) installed.backupWarning!,
    ];
    if (warnings.isNotEmpty) return warnings.join(' · ');
    return installed.verdict ?? 'roost-session installed';
  }

  /// A failure's sentence, plus the one thing a person has to know after a
  /// post-commit stop: which binary is on the host now.
  static String _failureNote(BridgeBootstrapFailure failure) {
    final restored = failure.restored;
    if (restored == null) return failure.message;
    return restored
        ? '${failure.message} Your previous roost-session was put back.'
        : '${failure.message} The new one is still on the host.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    logDriveState(
      'screen=machine-card machine=${widget.machine} '
      'offer=$_action step=${_step.wire}',
    );
    final note = _note;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // Keyed by ACTION as well as machine: which of the two a card is
              // offering is the thing AC 2 is about, and a key that read the
              // same for both would let an install offer pass a test written
              // for a start.
              key: ValueKey('machine-roost-$_action-${widget.machine}'),
              onPressed: _busy ? null : _run,
              icon: Icon(switch (widget.offer) {
                RoostOffer.install => Icons.download_outlined,
                RoostOffer.start => Icons.play_arrow_outlined,
              }, size: 18),
              label: Text(switch (_step) {
                _Step.probe => 'Checking…',
                _Step.confirm => 'Waiting for you…',
                _Step.install => switch (widget.offer) {
                  RoostOffer.install => 'Installing…',
                  RoostOffer.start => 'Starting…',
                },
                _Step.idle => switch (widget.offer) {
                  RoostOffer.install => 'Install roost-session',
                  RoostOffer.start => 'Start roost-session',
                },
              }),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                key: ValueKey('machine-roost-note-${widget.machine}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _noteIsError ? c.errFg : c.fg3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// **The consent sheet** — the `AddServerScreen` preview → confirm shape, as a
/// modal sheet (plan 020 §3.8).
///
/// A `bool` result and nothing else: `true` is "do it", and **every other
/// answer is do nothing**. A barrier tap and a swipe both return null, Cancel
/// returns false, and the caller acts on `true` alone.
Future<bool?> showRoostConsentSheet(
  BuildContext context, {
  required String machine,
  required RoostConsent consent,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => RoostConsentSheet(machine: machine, consent: consent),
);

/// What the sheet renders: the target, the plan, and what will be written.
class RoostConsentSheet extends StatelessWidget {
  const RoostConsentSheet({
    required this.machine,
    required this.consent,
    super.key,
  });

  final String machine;
  final RoostConsent consent;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    logDriveState(
      'screen=roost-consent machine=$machine step=confirm '
      'action=${consent.action}',
    );
    final backup = consent.backup;
    return SafeArea(
      child: Padding(
        key: const ValueKey('roost-consent-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // **The lines scroll; the answer does not.** An Update carries a
            // sixth line and a short phone carries less room than this sheet
            // wants, and a consent sheet whose Cancel is the thing off the
            // bottom is a consent sheet with one exit.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${consent.action} roost-session',
                      key: const ValueKey('roost-consent-title'),
                      style: sansStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // THE TARGET, on its own line and in mono: it is the one
                    // thing that must not be misread, and every other line is
                    // about it.
                    _Line(
                      label: 'Machine',
                      value: machine,
                      mono: true,
                      valueKey: const ValueKey('roost-consent-target'),
                    ),
                    // THE PLAN.
                    _Line(
                      label: 'Plan',
                      value: consent.what,
                      valueKey: const ValueKey('roost-consent-plan'),
                    ),
                    // WHAT WILL BE WRITTEN: where it lands, where the bytes
                    // come from, what else the host will wire — and, for an
                    // update, what happens to the file already there.
                    _Line(
                      label: 'Writes to',
                      value: consent.where,
                      mono: true,
                      valueKey: const ValueKey('roost-consent-where'),
                    ),
                    _Line(
                      label: 'From',
                      value: consent.from,
                      valueKey: const ValueKey('roost-consent-from'),
                    ),
                    _Line(
                      label: 'Also',
                      value: consent.hooks,
                      valueKey: const ValueKey('roost-consent-hooks'),
                    ),
                    if (backup != null)
                      _Line(
                        label: 'Backup',
                        value: backup,
                        valueKey: const ValueKey('roost-consent-backup'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              key: const ValueKey('roost-consent-confirm'),
              label: consent.action,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('roost-consent-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    required this.valueKey,
    this.mono = false,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            key: valueKey,
            style: mono
                ? monoStyle(fontSize: 12.5, color: c.fg)
                : Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: c.fg2),
          ),
        ],
      ),
    );
  }
}

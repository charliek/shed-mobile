/// **Where a new session will run** — a shed, or a machine.
///
/// The create FORM is the same either way: pick a kind, name it, point it at a
/// directory, optionally give it a kickoff prompt and a permission mode. What
/// differs is only where the offered kinds are read from and what runs the
/// create. That difference lives here so the form itself never branches on it —
/// a machine is not a second-class place to start an agent, and a form that
/// asked "shed or machine?" in its own body would make it look like one.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_adapters.dart';
import '../../providers.dart';
import '../../rc/rc_ui.dart';
import '../../src/rust/api/dto.dart';
import '../../machines/machine_feed.dart';
import '../../src/rust/api/dto_rc.dart';

/// The reduced create-form view of a target's capabilities: which kinds to
/// offer, whether full caps are present (unlocks the generic `skip` perm mode),
/// whether to show the loading spinner, the retry button, an optional status
/// note, the "present but empty" no-kinds message, and a drive-state token the
/// drive layer can assert the branch on.
typedef RcCapsView = ({
  List<BridgeRcKind> offered,
  bool capsPresent,
  bool loading,
  bool reloading,
  bool retry,
  String? note,
  bool showNoKinds,
  String logToken,
});

/// What a create produced: enough to log honestly, plus the value to pop.
typedef RcCreated = ({String slug, String state, String? url, Object result});

/// The always-safe base when capabilities are absent: claude + shell. Every
/// build of shed-ext-rc and every build of sx has had both.
const List<BridgeRcKind> baseRcKinds = [
  BridgeRcKind.claudeRc(),
  BridgeRcKind.shell(),
];

/// The shared shape of every "capabilities not usable yet" branch except
/// loading: caps absent (so [baseRcKinds] is offered), not loading, and never
/// "present but empty" (base kinds are never empty).
RcCapsView baseCapsView({
  List<BridgeRcKind> offered = baseRcKinds,
  bool loading = false,
  bool retry = false,
  String? note,
  required String logToken,
}) => (
  offered: offered,
  capsPresent: false,
  loading: loading,
  reloading: false,
  retry: retry,
  note: note,
  showNoKinds: false,
  logToken: logToken,
);

/// Caps present: the target's own creatable set (empty → "present but empty").
RcCapsView presentCapsView(BridgeRcCapabilities caps) {
  final offered = caps.creatableKinds();
  return (
    offered: offered,
    capsPresent: true,
    loading: false,
    reloading: false,
    retry: false,
    note: null,
    showNoKinds: offered.isEmpty,
    logToken: 'present',
  );
}

/// Stamp "a reload is in flight" onto a reduced view. Kept separate from the
/// reduction so the branch arms don't each have to thread it: a retained
/// previous value still renders its data branch, but the Retry button must stay
/// disabled while the reload it triggered is still running.
RcCapsView withReloading(RcCapsView v, bool reloading) => (
  offered: v.offered,
  capsPresent: v.capsPresent,
  loading: v.loading,
  reloading: reloading,
  retry: v.retry,
  note: v.note,
  showNoKinds: v.showNoKinds,
  logToken: v.logToken,
);

sealed class CreateRcTarget {
  const CreateRcTarget();

  /// What the app bar says after "New session · ".
  String get label;

  /// What to do about a target that advertises capabilities but offers no
  /// kinds. The two have different fixes and must not share a sentence.
  String get noKindsHint;

  /// What a blank Session name / Workdir will actually do HERE. A shed and a
  /// machine default them differently, and a form that names the shed default
  /// on a machine is telling the user something untrue.
  String get nameFieldLabel;
  String get workdirFieldLabel;

  /// Reduce this target's capability source into everything the offering +
  /// status area needs.
  RcCapsView caps(WidgetRef ref);

  /// Re-probe. Wired to the Retry button.
  void refresh(WidgetRef ref);

  /// Call [onSettled] when a reload finishes, so the Retry guard can clear.
  /// Must be called from `build` — it registers a `ref.listen`.
  void listenSettled(WidgetRef ref, VoidCallback onSettled);

  Future<RcCreated> create(
    WidgetRef ref, {
    required BridgeRcKind kind,
    String? displayName,
    String? workdir,
    String? prompt,
    String? permissionMode,
  });
}

/// A session in a shed, read through the host's overview.
class ShedRcTarget extends CreateRcTarget {
  const ShedRcTarget({required this.serverName, required this.shedName});

  final String serverName;
  final String shedName;

  ({String serverName, String shedName}) get _key =>
      (serverName: serverName, shedName: shedName);

  @override
  String get label => shedName;

  @override
  String get noKindsHint =>
      'This shed offers no session kinds — update the shed image.';

  @override
  String get nameFieldLabel =>
      'Session name (optional — defaults to shed/slug)';

  @override
  String get workdirFieldLabel =>
      'Workdir (optional — defaults to \$SHED_WORKSPACE)';

  @override
  void refresh(WidgetRef ref) => ref.invalidate(overviewProvider(serverName));

  @override
  void listenSettled(WidgetRef ref, VoidCallback onSettled) {
    ref.listen(overviewProvider(serverName), (_, next) {
      if (!next.isLoading) onSettled();
    });
  }

  /// We key off [overviewProvider] (not the lossy `shedCapabilitiesProvider`,
  /// which collapses server-too-old / shed-missing / shed-stopped / probe-failed
  /// all into one `null`) so each becomes a distinct, honest UI branch.
  @override
  RcCapsView caps(WidgetRef ref) {
    final async = ref.watch(overviewProvider(serverName));
    return withReloading(_reduce(async), async.isLoading);
  }

  RcCapsView _reduce(AsyncValue<OverviewResult> async) {
    // A retained previous value (a reload after data) still renders from data;
    // only a value-less loading/error surfaces the loading/error branches.
    if (!async.hasValue) {
      return async.hasError
          ? baseCapsView(
              offered: const [],
              retry: true,
              note: "Couldn't read this shed's capabilities.",
              logToken: 'error',
            )
          : baseCapsView(offered: const [], loading: true, logToken: 'loading');
    }
    final result = async.requireValue;
    // Server predates GET /api/overview: base is CORRECT here and a retry would
    // just re-404 forever — quiet base + a non-retry note, today's good path.
    if (result is OverviewUnsupported) {
      return baseCapsView(
        note: 'Server too old for codex/cursor/opencode.',
        logToken: 'unsupported',
      );
    }
    final overview = (result as OverviewData).overview;
    BridgeOverviewShed? row;
    for (final s in overview.sheds) {
      if (s.shed.name == shedName) {
        row = s;
        break;
      }
    }
    // Shed not in the overview at all: neutral — do NOT claim "unreadable".
    if (row == null) {
      return baseCapsView(
        note: "This shed isn't on this server — refresh its host.",
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
        _ => "This shed isn't running — start it to see its session kinds.",
      };
      return baseCapsView(note: note, logToken: 'stopped');
    }
    final shedCaps = row.capabilities;
    // Running but no caps: a probe miss (retry re-probes) or an old binary that
    // can't advertise (retry is a harmless no-op) — the note is honest either
    // way, and unlike an old SERVER a retry here can genuinely self-heal.
    if (shedCaps == null) {
      return baseCapsView(
        retry: true,
        note: 'codex/cursor/opencode unavailable for this shed.',
        logToken: 'absent',
      );
    }
    return presentCapsView(shedCaps);
  }

  @override
  Future<RcCreated> create(
    WidgetRef ref, {
    required BridgeRcKind kind,
    String? displayName,
    String? workdir,
    String? prompt,
    String? permissionMode,
  }) async {
    final svc = await rcServiceOneShot(ref, _key);
    final session = await svc.create(
      kind: kind,
      displayName: displayName,
      workdir: workdir,
      prompt: prompt,
      permissionMode: permissionMode,
    );
    return (
      slug: session.slug,
      state: session.state.wire,
      url: session.url,
      result: session,
    );
  }
}

/// A session on a machine, read through the machine's own capability probe.
///
/// A machine has no overview and no lifecycle to explain — it is reachable or
/// it is not — so the branch set is smaller than a shed's, but the two failure
/// modes it does have are the same two, and say the same things.
class MachineRcTarget extends CreateRcTarget {
  const MachineRcTarget({required this.machineName});

  final String machineName;

  @override
  String get label => machineName;

  @override
  String get noKindsHint =>
      '$machineName has no agents installed that sx can run.';

  @override
  String get nameFieldLabel =>
      'Session name (optional — defaults to $machineName/slug)';

  // No $SHED_WORKSPACE on a machine: the engine runs where ssh lands it, which
  // is the account's home directory.
  @override
  String get workdirFieldLabel => 'Workdir (optional — defaults to \$HOME)';

  @override
  void refresh(WidgetRef ref) =>
      ref.invalidate(machineFeedProvider(machineName));

  @override
  void listenSettled(WidgetRef ref, VoidCallback onSettled) {
    ref.listen(machineFeedProvider(machineName), (_, next) {
      if (!next.isLoading) onSettled();
    });
  }

  @override
  RcCapsView caps(WidgetRef ref) {
    final async = ref.watch(machineFeedProvider(machineName));
    return withReloading(_reduce(async), async.isLoading);
  }

  RcCapsView _reduce(AsyncValue<MachineFeedState> async) {
    if (!async.hasValue) {
      return async.hasError
          ? baseCapsView(
              offered: const [],
              retry: true,
              note: "Couldn't reach $machineName.",
              logToken: 'error',
            )
          : baseCapsView(offered: const [], loading: true, logToken: 'loading');
    }
    final state = async.requireValue;
    // Unreachable: creating would only fail, so offer nothing and say why —
    // the shed side has no equivalent (a stopped shed can still be started
    // from its own card; a machine the phone cannot reach cannot).
    if (!state.reachable) {
      return baseCapsView(
        offered: const [],
        retry: true,
        note: '$machineName is unreachable right now.',
        logToken: 'unreachable',
      );
    }
    final caps = state.capabilities;
    // Reachable but the probe found nothing: an old `sx`, or a probe that
    // failed on its own. Base is honest and a retry can self-heal.
    if (caps == null) {
      return baseCapsView(
        retry: true,
        note: 'codex/cursor/opencode unavailable on $machineName.',
        logToken: 'absent',
      );
    }
    return presentCapsView(caps);
  }

  @override
  Future<RcCreated> create(
    WidgetRef ref, {
    required BridgeRcKind kind,
    String? displayName,
    String? workdir,
    String? prompt,
    String? permissionMode,
  }) async {
    final feed = ref.read(machineFeedControllerProvider(machineName));
    final slug = await feed.create(
      kind: kind,
      // Blank → null, so the feed applies its `<machine>/<slug>` default
      // where the slug actually exists.
      displayName: displayName,
      workdir: workdir,
      prompt: prompt,
      permissionMode: permissionMode,
    );
    // The one-shot create does not report state back the way a shed's
    // `--wait` does; the hub's next reconcile carries it.
    return (slug: slug, state: 'created', url: null, result: slug);
  }
}

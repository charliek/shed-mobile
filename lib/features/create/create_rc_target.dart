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

import '../../providers.dart';
import '../../rc/rc_ui.dart';
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

  /// Whether a create HERE can carry the optional detail fields — a session
  /// name, a kickoff prompt, a permission mode.
  ///
  /// The form hides all three when it cannot, AND — separately — never sends a
  /// permission mode to [create] when it cannot: hiding the dropdown stops a
  /// new selection, but `_permissionMode` still starts non-null (`auto`), so
  /// the screen's `_modeFor` gates on this flag too before it ever reaches
  /// [create]. A machine's sessions are roost tabs now (plan 013 S3m), and
  /// roost's `tab.open` takes an argv and a directory: it titles the tab
  /// itself, and a prompt or a posture needs a provider script on the far
  /// side, which is a later slice. Offering fields whose contents would be
  /// dropped on the floor is the failure mode this flag exists to prevent —
  /// the kind and the directory are the whole of what a
  /// machine create can honestly ask for.
  bool get acceptsKickoff => true;

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

/// **Anything reached through a roost feed** — a shed, or a machine.
///
/// Since S6 (plan 022, shed#328) those are the same thing to this form: both
/// run their agents as roost tabs, both are read over the phone's own SSH
/// tunnel, and both launch with `tab.open`. What is left to differ is the
/// label, the empty-capabilities sentence, and the origin key the feed is
/// addressed by — so that is all the two subclasses below carry.
abstract class RoostRcTarget extends CreateRcTarget {
  const RoostRcTarget();

  /// Which feed to read and launch through. See [shedFeedKey].
  String get origin;

  /// What to call this place in a sentence ("… is unreachable right now").
  String get subject;

  /// Never rendered — roost names the tab itself (see [acceptsKickoff]).
  @override
  String get nameFieldLabel => 'Session name';

  /// No `$SHED_WORKSPACE` here and no landing-dir default: roost opens the tab
  /// in the project's directory, and with neither that nor a workdir, the
  /// account's home.
  @override
  String get workdirFieldLabel => 'Workdir (optional — defaults to \$HOME)';

  /// roost's `tab.open` starts the agent and nothing more: it titles the tab
  /// itself, and a prompt or a permission posture needs a provider script on
  /// the far side, which is a later slice. Offering fields whose contents would
  /// be dropped on the floor is the failure mode this flag exists to prevent.
  @override
  bool get acceptsKickoff => false;

  @override
  void refresh(WidgetRef ref) => ref.invalidate(machineFeedProvider(origin));

  @override
  void listenSettled(WidgetRef ref, VoidCallback onSettled) {
    ref.listen(machineFeedProvider(origin), (_, next) {
      if (!next.isLoading) onSettled();
    });
  }

  @override
  RcCapsView caps(WidgetRef ref) {
    final async = ref.watch(machineFeedProvider(origin));
    return withReloading(_reduce(async), async.isLoading);
  }

  RcCapsView _reduce(AsyncValue<MachineFeedState> async) {
    if (!async.hasValue) {
      return async.hasError
          ? baseCapsView(
              offered: const [],
              retry: true,
              note: "Couldn't reach $subject.",
              logToken: 'error',
            )
          : baseCapsView(offered: const [], loading: true, logToken: 'loading');
    }
    final state = async.requireValue;
    // Unreachable: creating would only fail, so offer nothing and say why. The
    // feed's own `detail` is the honest half — "no roost session on this shed"
    // and "this device's key is not authorized" have different fixes, and
    // flattening them to "unreachable" throws the actionable part away.
    if (!state.reachable) {
      final detail = state.detail;
      return baseCapsView(
        offered: const [],
        retry: true,
        note: detail == null
            ? '$subject is unreachable right now.'
            : '$subject is unreachable right now — $detail.',
        logToken: 'unreachable',
      );
    }
    final caps = state.capabilities;
    // Reachable but no capabilities. Unreachable in practice: a roost feed's
    // capabilities are SYNTHESIZED (`roostCapabilities`), not probed, so there
    // is no round trip left to miss. Kept as the honest degradation for a state
    // built without them.
    if (caps == null) {
      return baseCapsView(
        retry: true,
        note: 'codex/cursor/opencode unavailable on $subject.',
        logToken: 'absent',
      );
    }
    return presentCapsView(caps);
  }

  /// [displayName], [prompt] and [permissionMode] are not plumbed: roost's
  /// `tab.open` starts the agent in a directory and titles the tab itself. They
  /// are not silently dropped either — [acceptsKickoff] is false, so the form
  /// never offers them and they arrive null.
  @override
  Future<RcCreated> create(
    WidgetRef ref, {
    required BridgeRcKind kind,
    String? displayName,
    String? workdir,
    String? prompt,
    String? permissionMode,
  }) async {
    final feed = ref.read(machineFeedControllerProvider(origin));
    final slug = await feed.create(kind: kind, workdir: workdir);
    // `tab.open` answers with the tab, not with a settled agent; the watcher's
    // next push carries the real lifecycle a second or two later.
    return (slug: slug, state: 'created', url: null, result: slug);
  }
}

/// A session in a shed — a roost tab on the shed's own `roost-session`.
///
/// **Not the host's overview any more** (plan 022 S6). The overview's
/// `rc_capabilities` block went with the RC hub, and its session rows are plain
/// tmux rows now; what a shed can run is what roost can launch there, which is
/// the same synthesized block a machine reads.
class ShedRcTarget extends RoostRcTarget {
  const ShedRcTarget({required this.serverName, required this.shedName});

  final String serverName;
  final String shedName;

  @override
  String get origin => shedFeedKey(serverName, shedName);

  @override
  String get subject => shedName;

  @override
  String get label => shedName;

  @override
  String get noKindsHint =>
      '$shedName has no agents installed that roost can run.';
}

/// A session on a machine — a roost tab on the machine's own `roost-session`.
///
/// A machine has no shed lifecycle to explain — it is reachable or it is not —
/// but everything that decides what the form offers is shared with a shed now,
/// so this class is a name and a label.
class MachineRcTarget extends RoostRcTarget {
  const MachineRcTarget({required this.machineName});

  final String machineName;

  @override
  String get origin => machineName;

  @override
  String get subject => machineName;

  @override
  String get label => machineName;

  @override
  String get noKindsHint =>
      '$machineName has no agents installed that roost can run.';
}

/// **One machine's bootstrap, from the card to the answer** (plan 020 §3.8,
/// commit C-M4).
///
/// Two verbs and a sentence: [RoostBootstrapFlow.probe] looks at the host and
/// changes nothing, [RoostBootstrapFlow.install] acts on a probe the user
/// consented to, and [roostConsentFor] is what the sheet between them says.
///
/// ## The drive is the feed's, and that is the whole design
///
/// Neither verb runs a bootstrap itself. Each opens a machine on the bridge and
/// hands the handle to [RoostBootstrapFlow.drive] — `MachineFeed.runBootstrap`
/// in production, wired once in `roostBootstrapFlowProvider`.
///
/// A completed install is the ONLY thing that entitles this app run to keep a
/// machine's agent hooks wired, and `MachineFeed.runBootstrap` is where that
/// claim is recorded and the machine's watcher re-spawned to honour it. A UI
/// free to assemble its own [RoostBootstrapRunner] is a UI free to drive an
/// install that records nothing — which is plan 019's defect exactly, a seam
/// built and then constructed by no production caller. So the runner is not
/// reachable from here at all: this file knows how to OPEN a bootstrap and what
/// to SAY about it, and the driving belongs to the object that owns the
/// connection.
library;

import 'dart:io';

import '../src/rust/api/roost_bootstrap.dart';
import '../ssh/roost_bootstrap_runner.dart';

// ---------------------------------------------------------------------------
// the bridge, behind a seam
// ---------------------------------------------------------------------------

/// One open bootstrap machine on the bridge, and the way to end it.
///
/// The seam exists for the reason [BootstrapHandle]'s does: a
/// [BridgeRoostBootstrap] is an FRB opaque only the native library can produce,
/// so without an interface here not one rule in this file could be exercised
/// without a machine, a host and a `roost-session` on it.
abstract class BootstrapSession {
  /// The handle a drive is given.
  BootstrapHandle get handle;

  /// End it — the synchronous co-primary teardown. Idempotent; `Drop` is the
  /// backstop.
  void close();
}

/// [BootstrapSession] over the real bridge.
class LiveBootstrapSession implements BootstrapSession {
  LiveBootstrapSession(this.bridge);

  final BridgeRoostBootstrap bridge;

  @override
  late final BootstrapHandle handle = LiveBootstrapHandle(bridge);

  @override
  void close() => roostBootstrapClose(handle: bridge);
}

/// Opening a read-only probe of [host].
typedef OpenProbe = Future<BootstrapSession> Function(RoostHostTarget host);

/// Opening an install of [host], against a consented probe's own answers.
typedef OpenInstall =
    Future<BootstrapSession> Function(
      RoostHostTarget host, {
      required String fingerprint,
      required String arch,
      required bool needsSource,
      required String scratchDir,
    });

/// Which rung the bytes would come from — decided without running or fetching
/// anything.
typedef SourcePreviewFn =
    BridgeBootstrapSourcePreview Function(String target, String arch);

/// **Driving one bootstrap to its answer** — `MachineFeed.runBootstrap` in
/// production, and nothing else in it.
typedef BootstrapDrive =
    Future<BridgeBootstrapStep> Function(BootstrapHandle handle);

Future<BootstrapSession> _liveProbe(RoostHostTarget host) async =>
    LiveBootstrapSession(await roostBootstrapProbe(host: host));

Future<BootstrapSession> _liveInstall(
  RoostHostTarget host, {
  required String fingerprint,
  required String arch,
  required bool needsSource,
  required String scratchDir,
}) async => LiveBootstrapSession(
  await roostBootstrapInstall(
    host: host,
    fingerprint: fingerprint,
    arch: arch,
    needsSource: needsSource,
    scratchDir: scratchDir,
  ),
);

BridgeBootstrapSourcePreview _liveSourcePreview(String target, String arch) =>
    roostBootstrapSourcePreview(target: target, arch: arch);

// ---------------------------------------------------------------------------
// the flow
// ---------------------------------------------------------------------------

/// **The two verbs a machine card drives, and the sentence between them.**
class RoostBootstrapFlow {
  RoostBootstrapFlow({
    required this.target,
    required this.localPort,
    required this.drive,
    OpenProbe? openProbe,
    OpenInstall? openInstall,
    SourcePreviewFn? sourcePreview,
    String? scratchDir,
  }) : _openProbe = openProbe ?? _liveProbe,
       _openInstall = openInstall ?? _liveInstall,
       _sourcePreview = sourcePreview ?? _liveSourcePreview,
       _scratchDir = scratchDir ?? Directory.systemTemp.path;

  /// The grammar token this host is addressed by — the machine's own name,
  /// which is also what the watcher labels its rows with and what the
  /// entitlement registry is keyed on. One vocabulary, so a claim cannot be
  /// recorded under one spelling and asked for under another.
  final String target;

  /// The loopback port fronting this machine's `roost-session`, read AT CALL
  /// TIME rather than captured: the tunnel comes and goes with the feed, and a
  /// port snapshotted when this object was built is a port that may since have
  /// been closed and rebound.
  final int? Function() localPort;

  /// **Where a bootstrap is actually run** — see this file's header.
  final BootstrapDrive drive;

  final OpenProbe _openProbe;
  final OpenInstall _openInstall;
  final SourcePreviewFn _sourcePreview;

  /// The release-asset rung's scratch directory.
  ///
  /// An argument rather than an environment read because Android has no `/tmp`
  /// — and unread on a phone either way: the release pin is `None`, so the
  /// override rung is the only live one and no asset is ever downloaded.
  final String _scratchDir;

  /// **Look at the host. Nothing is changed**, which is what makes it safe to
  /// run before the consent sheet — and why the sheet can carry the returned
  /// probe's fingerprint as the thing an install re-checks.
  Future<BridgeBootstrapStep> probe() => _drive(_openProbe);

  /// **Act on a probe the user consented to.**
  ///
  /// Every argument comes off [probe] — the machine re-probes first and refuses
  /// if the host moved, which is what the fingerprint is for.
  Future<BridgeBootstrapStep> install(BridgeBootstrapProbe probe) => _drive(
    (host) => _openInstall(
      host,
      fingerprint: probe.fingerprint,
      arch: probe.arch,
      needsSource: probe.needsSource,
      scratchDir: _scratchDir,
    ),
  );

  /// The consent sheet's "from where" line, for a probe's architecture.
  BridgeBootstrapSourcePreview source(String arch) =>
      _sourcePreview(target, arch);

  /// Open, drive, and close — in a `finally`, so a drive that threw still ends
  /// the machine rather than leaving a half-run install holding a descriptor.
  Future<BridgeBootstrapStep> _drive(
    Future<BootstrapSession> Function(RoostHostTarget) open,
  ) async {
    final session = await open(_host());
    try {
      return await drive(session.handle);
    } finally {
      session.close();
    }
  }

  RoostHostTarget _host() {
    final port = localPort();
    // The same refusal `MachineFeed.acquireForward` gives, and for the same
    // reason: every `Step::Call` and `Step::Hooks` dials this port, so a
    // bootstrap against a machine with no tunnel could only fail later and
    // less clearly.
    if (port == null) throw StateError('the machine is not connected');
    return RoostHostTarget(
      target: target,
      localPort: port,
      // roost's `BootstrapOptions::jail_fs_root`, false in production: it is a
      // hermetic lane's knob, and a variable meant for a test must never steer
      // which binary a shipped app execs.
      jailFsRoot: false,
    );
  }
}

// ---------------------------------------------------------------------------
// what the sheet says
// ---------------------------------------------------------------------------

/// Where an install lands when neither the plan nor the probe named a
/// destination — roost's own rung 1.
const String kRoostDefaultDest = '~/.local/bin/roost-session';

/// **The hook-wiring sentence, verbatim** (plan 020 §3.9, owner decision D2).
///
/// The same string the desktop's consent card shows
/// (`desktop/tauri/ui/src/lib/roost.ts`). It describes what gets wired, and it
/// is true under last-writer-wins: at session protocol 5 there is no lease, hook
/// wiring is open to every one of your clients, they all send the same thing,
/// and roost records which one wrote them last. No warning sentence is added.
const String kRoostHooksSentence =
    'roost-session will also wire its hooks into the agents already configured '
    'there — claude, codex, cursor, opencode, grok — and nothing else.';

/// **What the user is being asked to consent to** — the four required lines
/// (what, where, from where, and the hooks sentence), plus the Update-only
/// backup note.
///
/// Client-owned copy, because consent is client-owned. A port of the desktop's
/// `roostConsentCopy`, field for field, so two clients asking the same
/// permission do not word it two ways.
class RoostConsent {
  const RoostConsent({
    required this.action,
    required this.what,
    required this.where,
    required this.from,
    required this.hooks,
    this.backup,
  });

  /// The confirm button's word — the plan matrix's own row name, never
  /// invented copy.
  final String action;

  /// One sentence: what this does, and to which host.
  final String what;

  /// The host and the path a binary lands at, or is started from.
  final String where;

  /// Which rung the bytes come from — shed-core's own sentence, rendered there
  /// so a card cannot promise one origin in wording the log then reports
  /// differently.
  final String from;

  /// [kRoostHooksSentence], always.
  final String hooks;

  /// The Update-only note about the incumbent. Null for every other plan.
  final String? backup;
}

/// The consent copy for an ACTIONABLE probe, or null for the two rows that
/// offer no button at all (`up-to-date`, and pin P6's `report`).
///
/// Null rather than a fabricated sentence: those two rows are not a consent
/// question, they are a status line — see [roostProbeStatusLine].
RoostConsent? roostConsentFor({
  required String target,
  required BridgeBootstrapProbe probe,
  required BridgeBootstrapSourcePreview source,
}) {
  final plan = probe.plan;
  final fallbackDest = probe.installDest ?? kRoostDefaultDest;
  return switch (plan) {
    BridgeBootstrapPlan_Install(:final dest) => RoostConsent(
      action: 'Install',
      what: 'Install roost-session on $target.',
      where: '$target, at ${dest ?? fallbackDest}',
      from: source.describe,
      hooks: kRoostHooksSentence,
    ),
    BridgeBootstrapPlan_Update(:final dest) => RoostConsent(
      action: 'Update',
      what:
          'Replace the roost-session on $target that this app can\'t talk to.',
      where: '$target, at ${dest ?? fallbackDest}',
      from: source.describe,
      hooks: kRoostHooksSentence,
      backup:
          'The file currently at ${dest ?? fallbackDest} will be backed up '
          'before it\'s replaced.',
    ),
    BridgeBootstrapPlan_Start(:final path) => RoostConsent(
      action: 'Start',
      what: 'Start the roost-session already on $target.',
      where: '$target, at $path',
      // A start sends no bytes, and saying where bytes would have come from
      // would describe something that is not about to happen.
      from: 'Nothing is sent — the binary is already there.',
      hooks: kRoostHooksSentence,
    ),
    BridgeBootstrapPlan_UpToDate() || BridgeBootstrapPlan_Report() => null,
  };
}

/// **The one-line status a card shows instead of, or beside, a button.**
///
/// A port of the desktop's `roostStatusLine`, and it rewrites nothing roost
/// pinned: `report` renders `plan.message` VERBATIM (pin P6's copy — somebody
/// is using that session, and the sentence names the command *they* would run).
/// Every other line is this client's own short summary, because roost pins no
/// sentence for it.
String roostProbeStatusLine(BridgeBootstrapProbe probe) => switch (probe.plan) {
  BridgeBootstrapPlan_Report(:final message) => message,
  BridgeBootstrapPlan_UpToDate(:final identity) =>
    'roost-session ${identity.appVersion} running '
        '(protocol ${identity.sessionProtocol})',
  BridgeBootstrapPlan_Install() => 'roost-session not found',
  BridgeBootstrapPlan_Update(:final replacesNewer) =>
    replacesNewer
        ? 'roost-session on this host speaks a newer protocol — replacing is a '
              'downgrade'
        : 'roost-session is a build this app can\'t read',
  BridgeBootstrapPlan_Start() => 'roost-session installed, not running',
};

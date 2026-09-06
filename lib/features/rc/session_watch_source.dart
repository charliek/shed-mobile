import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../rc/rc_ui.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../src/rust/api/machine.dart';
import '../terminal/terminal_target.dart';

/// The live facts the watch screen renders from, however they were obtained.
///
/// `features` is the session's `kind_features` entry and is what gates every
/// control — never the kind. `lastSeq` is the feed's high-water mark; a bump
/// means "there is something new to fetch", not the content itself.
typedef WatchedSession = ({
  BridgeRcState state,
  BridgeRcActivity? activity,
  BigInt? lastSeq,
  BridgeRcKindFeatures? features,
});

/// Where a watched session's feed, input, and terminal come from.
///
/// The screen above this is transport-agnostic: a shed session is reached
/// through its server's HTTP API, a machine session through an SSH-forwarded
/// port to the machine's own hub — but both serve the SAME `/v1` message
/// cursor and the same control verbs, so everything above "how do I reach it"
/// is one implementation.
///
/// Each method takes the `ref` rather than capturing one: these run inside an
/// `autoDispose` scope, and a stored ref outlives the scope that owns it.
abstract class SessionWatchSource {
  const SessionWatchSource();

  /// The session this source is bound to.
  String get slug;

  /// App-bar title.
  String get title;

  /// Where the TUI handoff attaches. Always available — the terminal is the
  /// floor every kind can fall back to, including ones with no feed at all.
  TerminalTarget get terminalTarget;

  /// The live view, read inside `build`. Implementations watch their own
  /// providers here, which is why it takes a [WidgetRef] and not a snapshot.
  WatchedSession watch(WidgetRef ref);

  /// One page of the message cursor at or after [since].
  Future<BridgeRcMessagesPage> messages(
    WidgetRef ref, {
    required BigInt since,
    required int limit,
  });

  /// Deliver a line of input to a session that is WAITING for one — the
  /// keystroke path for a `gated` kind.
  Future<void> sendInput(WidgetRef ref, String text);

  /// Start a structured turn. Only for a kind whose `input` is `turn`.
  Future<void> steer(WidgetRef ref, String text);

  /// Interrupt a running turn. `false` = nothing was running, which is an
  /// answer rather than a failure.
  Future<bool> interrupt(WidgetRef ref);
}

/// A session inside a shed, reached through its server.
class ShedWatchSource extends SessionWatchSource {
  const ShedWatchSource({
    required this.serverName,
    required this.shedName,
    required this.session,
  });

  final String serverName;
  final String shedName;
  final BridgeRcSession session;

  @override
  String get slug => session.slug;

  /// `<shed>/<slug>` — the same form the terminal's title takes, so moving
  /// between the two views never leaves you wondering which box you are on.
  @override
  String get title => '$shedName/$slug';

  @override
  TerminalTarget get terminalTarget => ShedTerminalTarget(
    serverName: serverName,
    shedName: shedName,
    slug: slug,
    title: '$shedName/$slug',
  );

  @override
  WatchedSession watch(WidgetRef ref) {
    final patch = ref.watch(
      liveActivityProvider(
        serverName,
      ).select((a) => a.value?.lookup(shedName, slug)),
    );
    final caps = ref
        .watch(
          shedCapabilitiesProvider((
            serverName: serverName,
            shedName: shedName,
          )),
        )
        .value;
    return (
      state: patch?.state ?? session.state,
      activity: patch?.activity ?? session.activity,
      lastSeq: patch?.lastSeq,
      features: caps?.kindFeatures[session.kind.wire],
    );
  }

  @override
  Future<BridgeRcMessagesPage> messages(
    WidgetRef ref, {
    required BigInt since,
    required int limit,
  }) async {
    final client = await ref.read(shedClientProvider(serverName).future);
    return client.rcMessages(
      shed: shedName,
      slug: slug,
      since: since,
      limit: limit,
    );
  }

  @override
  Future<void> sendInput(WidgetRef ref, String text) async {
    final client = await ref.read(shedClientProvider(serverName).future);
    await client.rcInput(shed: shedName, slug: slug, text: text);
  }

  @override
  Future<void> steer(WidgetRef ref, String text) async {
    final client = await ref.read(shedClientProvider(serverName).future);
    await client.rcTurn(shed: shedName, slug: slug, text: text);
  }

  @override
  Future<bool> interrupt(WidgetRef ref) async {
    final client = await ref.read(shedClientProvider(serverName).future);
    return client.rcInterrupt(shed: shedName, slug: slug);
  }
}

/// A session on a machine, reached over the feed's SSH-forwarded hub port.
///
/// Everything here rides the tunnel the feed already holds, so watching a
/// machine session costs no second connection. That is also the constraint: a
/// machine whose feed is down has no port, and every method below fails
/// honestly rather than silently doing nothing.
class MachineWatchSource extends SessionWatchSource {
  const MachineWatchSource({required this.machineName, required this.session});

  final String machineName;
  final BridgeRcSession session;

  @override
  String get slug => session.slug;

  @override
  String get title => '$machineName/$slug';

  @override
  TerminalTarget get terminalTarget => MachineTerminalTarget(
    machineName: machineName,
    slug: slug,
    title: '$machineName/$slug',
  );

  @override
  WatchedSession watch(WidgetRef ref) {
    final feed = ref.watch(machineFeedProvider(machineName)).value;
    // The row as the feed currently holds it, so a session that ended or
    // changed kind mid-watch is reflected rather than frozen at open time.
    final live =
        feed?.sessions.where((s) => s.slug == slug).firstOrNull ?? session;
    return (
      state: feed?.stateOf(live) ?? live.state,
      activity: feed?.activityOf(live) ?? live.activity,
      lastSeq: feed?.overlay[slug]?.lastSeq,
      features: feed?.featuresFor(live),
    );
  }

  /// The feed's forwarded port, or a thrown error naming the real problem.
  int _port(WidgetRef ref) {
    final port = ref
        .read(machineFeedControllerProvider(machineName))
        .tunnelPort;
    if (port == null) {
      throw StateError('$machineName is not connected');
    }
    return port;
  }

  @override
  Future<BridgeRcMessagesPage> messages(
    WidgetRef ref, {
    required BigInt since,
    required int limit,
  }) async {
    // The hub's cursor takes no limit — it answers with what it has since the
    // cursor, and the caller pages by advancing `since`. The screen's `limit`
    // is its own pagination budget, honoured by the shed's API; here it is
    // simply not part of the wire.
    return machineMessages(localPort: _port(ref), slug: slug, since: since);
  }

  @override
  Future<void> sendInput(WidgetRef ref, String text) =>
      machineInput(localPort: _port(ref), slug: slug, text: text);

  @override
  Future<void> steer(WidgetRef ref, String text) async {
    await machineTurn(localPort: _port(ref), slug: slug, text: text);
  }

  @override
  Future<bool> interrupt(WidgetRef ref) =>
      machineInterrupt(localPort: _port(ref), slug: slug);
}

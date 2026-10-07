import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/ssh/roost_tunnel.dart';

/// **craze's hermetic client recipe, from Dart** (plan 025 §3.7.4) — the
/// phone's twin of `shed_craze::testing::Recipe` and the desktop's
/// `CrazeEnv`, so the phone's cells drive the REAL hub over the REAL feed.
///
/// - **The binaries** come from `SHED_CRAZE_BIN_DIR` (shed's `make
///   craze-binaries` prints it; CI's `craze-binaries` action, run from the
///   pinned shed sibling, exports it): `craze`, `craze-fake-host`,
///   `craze-fake-agent` at shed's `CRAZE_TEST_SHA`, and `craze-0.0.1`, the real
///   v0.0.1, for the too-old cell. They are COPIED into a private PATH
///   directory, so the command line of every craze process of this rig's — each
///   bridge, the hub the first one births, each host the hub creates, the fake
///   hosts — starts with that directory, which is how [CrazeRig.teardown]
///   tells them from anything else on the machine.
/// - **The environment** of every craze process is exactly the recipe's six
///   variables and nothing inherited: `HOME`, `CRAZE_HOME`, `CRAZE_RUNTIME_DIR`
///   (short, under `/tmp`, 0700 — craze refuses a runtime dir under a
///   group-writable ancestor, plan 025 Amendment A3), `PATH` (the private
///   directory and nothing else), `CRAZE_FAKE_SCRIPT=grok-echo`,
///   `CRAZE_FAKE_SESSION_ID={dir}`. The first bridge's environment becomes the
///   hub's, which hands it to every host and agent.
/// - **The transport** is [tunnelOpen]: the feed's own `RoostTunnel`, its
///   SSH exec replaced by a local `/bin/sh` running the JAILED ladder
///   (`crazeJailedBridgeArgv`: rungs 1–2 only, no exec PATH), so no craze
///   installed on this host — `/usr/local/bin/craze` is a real v0.0.1 here —
///   can ever answer a hermetic cell.
/// - **The skip rule**: without the binaries every cell SKIPS with a message;
///   `SHED_CRAZE_REQUIRE=1` (CI) turns that skip into a FAILURE, so the job can
///   never go green on skipped craze cells.
///
/// Never touches `~/.craze`, `~/.cache/craze` or `/usr/local/bin/craze`: no
/// rig's `HOME`, `CRAZE_HOME` or `PATH` reaches them.
class CrazeBins {
  CrazeBins(this.dir);

  final String dir;

  String get craze => '$dir/craze';
  String get fakeHost => '$dir/craze-fake-host';
  String get fakeAgent => '$dir/craze-fake-agent';
  String get craze001 => '$dir/craze-0.0.1';

  /// The binaries, or null with [why] set when a cell must skip — a
  /// [StateError] instead when `SHED_CRAZE_REQUIRE=1`.
  static CrazeBins? resolve() {
    final raw = Platform.environment['SHED_CRAZE_BIN_DIR'] ?? '';
    String? missing;
    if (raw.isEmpty) {
      missing = 'SHED_CRAZE_BIN_DIR is not set';
    } else {
      final bins = CrazeBins(raw);
      final absent = [
        bins.craze,
        bins.fakeHost,
        bins.fakeAgent,
        bins.craze001,
      ].where((p) => !File(p).existsSync()).toList();
      if (absent.isNotEmpty) missing = '$raw lacks ${absent.join(', ')}';
    }
    if (missing == null) return CrazeBins(raw);
    if (Platform.environment['SHED_CRAZE_REQUIRE'] == '1') {
      throw StateError(
        'SHED_CRAZE_REQUIRE=1 but the craze binaries are missing: $missing — '
        'a craze cell may not skip here',
      );
    }
    why =
        '$missing (run shed\'s `make craze-binaries` and export the '
        'SHED_CRAZE_BIN_DIR= line it prints)';
    return null;
  }

  /// Why [resolve] answered null.
  static String why = '';
}

/// What a rig's private `PATH` offers.
enum CrazePath {
  /// craze and its fakes at the pin — craze's recipe.
  recipe,

  /// Nothing: craze is not installed.
  empty,

  /// The real v0.0.1 as `craze`: craze too old for shed.
  tooOld,
}

/// One hermetic craze namespace (the module doc).
class CrazeRig {
  CrazeRig._(this.root, this.bins);

  final String root;
  final CrazeBins bins;

  String get home => '$root/home';
  String get crazeHome => '$root/ch';
  String get runtime => '$root/run';
  String get pathDir => '$root/path';
  String get work => '$root/work';

  final List<Process> _fakeHosts = [];

  /// Every bridge this rig's tunnels exec'd, in order — the craze processes a
  /// cell may need to find again (CM5's resume cell kills a lane's own).
  final List<Process> bridges = [];

  /// What each bridge's client asked the hub for, in order: the roster's
  /// `sessions.subscribe`, or a lane's `session.connect{sessionId: <hostId>}`
  /// (the hub's splice). How a cell finds ONE connection's process —
  /// [laneBridge], [rosterBridge] — rather than guessing from the order the
  /// bridges happened to start in.
  final List<({Process process, String method, String? hostId})> connections =
      [];

  /// The bridges this rig has SIGSTOPped and not yet continued — continued
  /// first thing in [teardown], so its SIGTERM is not left pending.
  final Set<Process> _stopped = {};

  /// The bridges that have exited (their exit code is in) — so a pid read in
  /// `/proc` is known to be the bridge's own, never a reused one.
  final Set<Process> _exited = {};

  /// How many times the feed's ROOST tunnel was dialled — each one refused (no
  /// `roost-session` here), and each one a roost `Down` on the watcher's
  /// doubling backoff, which is what lets a cell know how long roost will now
  /// stay quiet.
  int roostDials = 0;

  /// While set, every craze dial waits on it before its bridge runs — a
  /// source installed and not yet SEEDED, or a lane whose connection was
  /// killed kept from redialling, for as long as a cell needs one.
  Completer<void>? holdCrazeDials;

  /// Every `session.create` a craze bridge of this rig carried, in order:
  /// its request id, and whether it was [dropCreates]-dropped. What the
  /// create cells count sessions and ids by (the desktop rig's `creates.log`).
  final List<({String? requestId, bool dropped})> creates = [];

  /// **A lost answer, exactly** (the desktop rig's `drop-creates`): while set,
  /// a bridge that carries a `session.create` relays it to the hub and then
  /// relays nothing back, and a second later the bridge is killed. The hub has
  /// the create — a client that disconnects does not cancel one — and the
  /// client never sees its answer: an unknown outcome.
  bool dropCreates = false;

  static int _next = 0;

  /// Start a namespace: the directories (0700, under `/tmp`, short — a socket
  /// path must stay under 100 bytes), the binaries copied, `config.toml`.
  static Future<CrazeRig> start(
    CrazeBins bins, {
    CrazePath path = CrazePath.recipe,
  }) async {
    late String root;
    while (true) {
      root = '/tmp/shczm-$pid-${_next++}';
      if (!Directory(root).existsSync()) break;
    }
    final rig = CrazeRig._(root, bins);
    for (final dir in [
      root,
      rig.home,
      rig.crazeHome,
      rig.runtime,
      rig.pathDir,
    ]) {
      Directory(dir).createSync();
      _chmod('0700', dir);
    }
    Directory(rig.work).createSync();
    void copy(String from, String name) {
      final to = '${rig.pathDir}/$name';
      File(from).copySync(to);
      _chmod('0755', to);
    }

    switch (path) {
      case CrazePath.recipe:
        copy(bins.craze, 'craze');
        copy(bins.fakeHost, 'craze-fake-host');
        copy(bins.fakeAgent, 'craze-fake-agent');
      case CrazePath.empty:
        break;
      case CrazePath.tooOld:
        copy(bins.craze001, 'craze');
    }
    File('${rig.crazeHome}/config.toml').writeAsStringSync(
      'provider = "grok"\nhost_idle_exit = "30s"\n\n[agents]\n'
      'grok = "${rig.pathDir}/craze-fake-agent"\n',
    );
    return rig;
  }

  /// Exactly what a craze process of this namespace sees.
  Map<String, String> get env => {
    'HOME': home,
    'CRAZE_HOME': crazeHome,
    'CRAZE_RUNTIME_DIR': runtime,
    'PATH': pathDir,
    'CRAZE_FAKE_SCRIPT': 'grok-echo',
    'CRAZE_FAKE_SESSION_ID': '{dir}',
  };

  /// **The feed's tunnel seam, hermetic** — what `machineTunnelOpenProvider`
  /// (or `MachineFeed.openTunnel`) is overridden with.
  ///
  /// The feed's own `RoostTunnel`, port, accept loop and byte pump, with ONE
  /// thing replaced: the SSH exec. The craze command (`crazeRemoteCommand()`)
  /// runs as a local `/bin/sh` over the JAILED ladder under this rig's six
  /// variables; the roost command is refused at the dial (no `roost-session`
  /// here — the feed's roost watcher sees a closed connection and reports the
  /// machine down, which is all a craze cell needs of it).
  Future<RoostTunnel> tunnelOpen({
    required Future<SSHClient> Function() connect,
    required String remoteCommand,
    required String machine,
    void Function(String)? onStderr,
  }) {
    final craze = remoteCommand == crazeRemoteCommand();
    return RoostTunnel.openWithExec(
      exec: (command) async {
        if (!craze) {
          roostDials++;
          throw StateError('no roost-session in the craze harness');
        }
        final hold = holdCrazeDials;
        if (hold != null) await hold.future;
        final argv = crazeJailedBridgeArgv();
        // `/bin/sh` by absolute path: the jailed PATH holds only craze's
        // binaries, so a bare `sh` would not resolve.
        final process = await Process.start(
          '/bin/sh',
          argv.sublist(1),
          environment: env,
          includeParentEnvironment: false,
          workingDirectory: root,
        );
        bridges.add(process);
        unawaited(process.exitCode.then((_) => _exited.add(process)));
        return ProcessExecSession(
          process,
          inspect: (line) => _clientLine(line, process),
        );
      },
      remoteCommand: remoteCommand,
      machine: machine,
      onStderr: onStderr,
    );
  }

  /// One client→hub line on a craze bridge: a roster subscription or a lane's
  /// splice is logged to [connections]; a `session.create` is logged to
  /// [creates], and cut ([dropCreates]) when asked.
  bool _clientLine(String line, Process process) {
    Object? msg;
    try {
      msg = jsonDecode(line);
    } on FormatException {
      return false;
    }
    if (msg is! Map) return false;
    final method = msg['method'];
    final params = msg['params'];
    if (method == 'sessions.subscribe' || method == 'session.connect') {
      connections.add((
        process: process,
        method: method as String,
        hostId: params is Map ? params['sessionId'] as String? : null,
      ));
      return false;
    }
    if (method != 'session.create') return false;
    final drop = dropCreates;
    creates.add((
      requestId: params is Map ? params['requestId'] as String? : null,
      dropped: drop,
    ));
    return drop;
  }

  /// The bridge carrying [hostId]'s lane NOW — the latest connection whose
  /// client asked the hub to splice it to that host. The lane's own process:
  /// never the feed tunnel's listener, never the roster's.
  Process laneBridge(String hostId) => connections
      .lastWhere(
        (c) => c.method == 'session.connect' && c.hostId == hostId,
        orElse: () => throw StateError('no lane connection to $hostId yet'),
      )
      .process;

  /// How many roster subscriptions this rig's bridges have carried — a
  /// replacement roster connection (the source redialling) moves it.
  int get rosterConnections =>
      connections.where((c) => c.method == 'sessions.subscribe').length;

  /// The bridge carrying the source's roster subscription now.
  Process rosterBridge() => connections
      .lastWhere(
        (c) => c.method == 'sessions.subscribe',
        orElse: () => throw StateError('no roster connection yet'),
      )
      .process;

  /// **Kill** one of this rig's bridges (SIGTERM): its connection ends as a
  /// dropped transport does — the far side gone, nothing said.
  void killBridge(Process bridge) {
    _guard(bridge);
    bridge.kill();
  }

  /// **Freeze** one of this rig's bridges (SIGSTOP): its connection stays
  /// open and carries nothing either way until [resume] — a roster that has
  /// not flushed, for as long as a cell needs one.
  ///
  /// **Proven, not assumed**: it throws unless the signal was delivered (a
  /// bridge that already exited takes none) and the kernel then reports the
  /// process STOPPED (`/proc/<pid>/stat` state `T`) — so a cell that goes on
  /// after it knows the connection is frozen. [isPaused] re-reads the same.
  Future<void> pause(Process bridge) async {
    _guard(bridge);
    if (_exited.contains(bridge) || !bridge.kill(ProcessSignal.sigstop)) {
      throw StateError(
        'SIGSTOP not delivered: bridge ${bridge.pid} has exited',
      );
    }
    _stopped.add(bridge);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!isPaused(bridge)) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'bridge ${bridge.pid} never stopped: /proc state '
          '${procState(bridge.pid)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Whether [bridge] is, right now, one this rig froze that is still alive
  /// and STOPPED: [pause]d and not resumed, its exit code not in, and the
  /// kernel's own state letter `T`.
  bool isPaused(Process bridge) =>
      _stopped.contains(bridge) &&
      !_exited.contains(bridge) &&
      procState(bridge.pid) == 'T';

  /// Let a [pause]d bridge run again (SIGCONT). False when it had already
  /// exited — the teardown's case, which is not an error there.
  bool resume(Process bridge) {
    _guard(bridge);
    _stopped.remove(bridge);
    return bridge.kill(ProcessSignal.sigcont);
  }

  /// A process's state letter from `/proc/<pid>/stat` — `T` stopped by a
  /// signal, `S` sleeping, `R` running, `Z` exited and not yet reaped — or
  /// null when there is no such process. Read after the LAST `)`: the command
  /// name between the parentheses may hold anything, spaces and parentheses
  /// included.
  static String? procState(int pid) {
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      final close = stat.lastIndexOf(')');
      if (close < 0 || stat.length < close + 3) return null;
      return stat.substring(close + 2, close + 3);
    } on FileSystemException {
      return null;
    }
  }

  /// A bridge this rig started, and nothing else — never pid 0 or 1, never
  /// this process.
  void _guard(Process bridge) {
    if (bridge.pid <= 1 || bridge.pid == pid || !bridges.contains(bridge)) {
      throw StateError('not one of this rig\'s bridges: ${bridge.pid}');
    }
  }

  /// Point `[agents].grok` at [agent] (craze reads its config at every
  /// create; grok stays the default provider).
  void setGrokAgent(String agent) {
    File('$crazeHome/config.toml').writeAsStringSync(
      'provider = "grok"\nhost_idle_exit = "30s"\n\n[agents]\n'
      'grok = "$agent"\n',
    );
  }

  /// The fake agent this rig's grok runs by default.
  String get grokEcho => '$pathDir/craze-fake-agent';

  /// The fake agent running [script] (`exit-two-lines`, `hang`, …) behind a
  /// two-line wrapper — `[agents]` names one binary and no arguments, and the
  /// flag wins over the recipe's `CRAZE_FAKE_SCRIPT` (shed-craze's
  /// `Recipe::script_agent`). It execs THIS rig's copy, so the agent it
  /// becomes is one [teardown] finds.
  String scriptAgent(String script) {
    final path = '$root/$script-agent';
    File(path).writeAsStringSync(
      '#!/bin/sh\nexec \'$pathDir/craze-fake-agent\' -script $script "\$@"\n',
    );
    _chmod('0755', path);
    return path;
  }

  /// Start a `craze-fake-host` listed in this namespace's registry as
  /// [hostId] running [sessionId], and wait for its ready line. Its stdin
  /// stays open: [op] writes to it, and its end is how it is told to go.
  Future<Map<String, Object?>> fakeHost(String hostId, String sessionId) async {
    final process = await Process.start(
      '$pathDir/craze-fake-host',
      ['--registry', home, '--host-id', hostId, '--session-id', sessionId],
      environment: env,
      includeParentEnvironment: false,
      workingDirectory: root,
    );
    _fakeHosts.add(process);
    process.stderr.drain<void>();
    // Read to the end, not just the ready line: an unread pipe would block
    // the fake host the moment it filled.
    final ready = Completer<String>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!ready.isCompleted) ready.complete(line);
          },
          onDone: () {
            if (!ready.isCompleted) {
              ready.completeError(
                StateError(
                  'craze-fake-host $hostId exited before its ready line',
                ),
              );
            }
          },
        );
    final line = await ready.future.timeout(const Duration(seconds: 30));
    return (jsonDecode(line) as Map).cast<String, Object?>();
  }

  /// One op (craze's fixture `op` object) to the [index]th fake host.
  void op(Map<String, Object?> op, {int index = 0}) {
    _fakeHosts[index].stdin.writeln(jsonEncode(op));
  }

  /// The pids this namespace's hub records name, each checked to run this
  /// rig's own copy of craze.
  Future<List<int>> hubPids() async {
    final dir = Directory('$home/.cache/craze/hubs');
    if (!dir.existsSync()) return const [];
    final pids = <int>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final rec = jsonDecode(f.readAsStringSync()) as Map;
        final p = rec['pid'];
        if (p is int && await _runsOurs(p)) pids.add(p);
      } on FormatException {
        continue;
      }
    }
    return pids;
  }

  /// SIGTERM this namespace's hub, by the pid its record names, its command
  /// line checked just before.
  Future<void> sigtermHub() async {
    final pids = await hubPids();
    if (pids.isEmpty) throw StateError('no live hub of this rig\'s to signal');
    for (final p in pids) {
      await _signal(p, ProcessSignal.sigterm);
    }
  }

  /// Take craze away from this namespace's PATH (the ladder then finds none).
  void uninstall() {
    final craze = File('$pathDir/craze');
    if (craze.existsSync()) craze.renameSync('$pathDir/craze.off');
  }

  /// craze's own `cleanup`: every fake host's stdin closed; SIGTERM to every
  /// process whose program is one of this rig's copies (re-read just before
  /// each signal; never pid 0 or 1, never this process); a bounded wait; the
  /// same again with the fake hosts; SIGKILL as the backstop. Answers what was
  /// still running at the end — nothing, normally.
  Future<List<String>> teardown() async {
    for (final b in [..._stopped]) {
      resume(b);
    }
    for (final h in _fakeHosts) {
      await h.stdin.close().catchError((Object _) {});
    }
    for (final (p, _) in await processes()) {
      await _signal(p, ProcessSignal.sigterm);
    }
    var deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) &&
        (await processes()).isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final left = [
      for (final (p, args) in await processes()) 'process $p: $args',
    ];
    for (final (p, _) in await processes()) {
      await _signal(p, ProcessSignal.sigkill);
    }
    for (final h in _fakeHosts) {
      h.kill(ProcessSignal.sigkill);
    }
    deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline) &&
        (await processes()).isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      Directory(root).deleteSync(recursive: true);
    } on FileSystemException {
      // A process killed a moment ago may still be closing a file under it.
    }
    return left;
  }

  /// Every live process of this rig's: `(pid, command line)`.
  Future<List<(int, String)>> processes() async {
    final out = await Process.run('ps', [
      '-A',
      '-ww',
      '-o',
      'pid=',
      '-o',
      'args=',
    ]);
    final found = <(int, String)>[];
    for (final raw in (out.stdout as String).split('\n')) {
      final line = raw.trimLeft();
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      final p = int.tryParse(line.substring(0, space));
      final args = line.substring(space).trimLeft();
      if (p != null && _ours(args)) found.add((p, args));
    }
    return found;
  }

  bool _ours(String args) => args.startsWith('$pathDir/');

  Future<bool> _runsOurs(int p) async {
    final out = await Process.run('ps', ['-ww', '-o', 'args=', '-p', '$p']);
    return _ours((out.stdout as String).trim());
  }

  /// Signal [p] only if, read again just now, it runs one of this rig's
  /// copies — never pid 0 or 1, never this process.
  Future<void> _signal(int p, ProcessSignal signal) async {
    if (p <= 1 || p == pid) return;
    if (!await _runsOurs(p)) return;
    Process.killPid(p, signal);
  }

  static void _chmod(String mode, String path) {
    final r = Process.runSync('chmod', [mode, path]);
    if (r.exitCode != 0) throw StateError('chmod $mode $path: ${r.stderr}');
  }
}

/// A local [Process] as the tunnel's exec — the four things a byte pump needs,
/// with the process's own names (`RoostExecSession`'s).
///
/// **Two things are added.** The first is an SSH channel's ORDER. An ssh exec's stdout, its
/// stderr and its end all ride one channel, so the far side's last stderr line
/// always arrives before the EOF that ends the channel. A local process has two
/// independent pipes, and its stdout can close — which ends the pump and
/// cancels its stderr listener — before the stderr line written just ahead of
/// the exit is delivered: the ladder's `craze: command not found` then never
/// reaches the classifier, and a not-installed machine reads as unclassified
/// for as long as the race keeps losing. So stdout's END waits (bounded) for
/// stderr's, exactly the order a real channel gives.
///
/// The second is [inspect]: every line the client writes is shown to it after
/// it is relayed, and an answer of true CUTS the exchange there — nothing more
/// is relayed back, and a second later the process is killed (the rig's
/// [CrazeRig.dropCreates]).
class ProcessExecSession implements RoostExecSession {
  ProcessExecSession(this.process, {this.inspect}) {
    // A write after the process has gone is a closed pipe, which is the far
    // side ending — the pump learns it from `done`, not from an error here.
    process.stdin.done.catchError((Object _) {});
    _stdin.stream.listen(
      (chunk) {
        try {
          process.stdin.add(chunk);
        } on Object {
          // As above.
        }
        _look(chunk);
      },
      onDone: () => process.stdin.close().catchError((Object _) {}),
      cancelOnError: false,
    );
    process.stderr.listen(
      (chunk) => _stderr.add(_bytes(chunk)),
      onDone: () {
        if (!_stderrDone.isCompleted) _stderrDone.complete();
        _stderr.close();
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    process.stdout.listen(
      (chunk) {
        if (!_cut) _stdout.add(_bytes(chunk));
      },
      onDone: () async {
        await _stderrDone.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
        await _stdout.close();
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  final Process process;

  /// Shown every client line; true cuts the exchange (the class doc).
  final bool Function(String line)? inspect;

  /// The client's bytes since its last newline.
  final List<int> _line = [];

  /// Cut: nothing more reaches the client, and the process is on its way out.
  bool _cut = false;

  void _look(List<int> chunk) {
    final look = inspect;
    if (look == null || _cut) return;
    for (final b in chunk) {
      if (b != 0x0a) {
        _line.add(b);
        continue;
      }
      final line = utf8.decode(_line, allowMalformed: true);
      _line.clear();
      if (look(line)) {
        _cut = true;
        // A second for the hub to take what was relayed, then the far side
        // goes — the connection ends with no answer on it.
        Future<void>.delayed(const Duration(seconds: 1), process.kill);
        return;
      }
    }
  }

  final StreamController<Uint8List> _stdin = StreamController<Uint8List>();
  final StreamController<Uint8List> _stdout = StreamController<Uint8List>();
  final StreamController<Uint8List> _stderr = StreamController<Uint8List>();
  final Completer<void> _stderrDone = Completer<void>();

  @override
  StreamSink<Uint8List> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => process.exitCode.then((_) {});

  /// Ending the exec ends the bridge, as an SSH channel's close does.
  @override
  void close() => process.kill();

  static Uint8List _bytes(List<int> chunk) =>
      chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
}

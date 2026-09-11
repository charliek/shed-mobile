import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/shell_quote.dart';
import 'host_key_store.dart';
import 'ssh_connection.dart';

/// The result of one remote command: the process exit code plus decoded output.
class SshResult {
  const SshResult(this.code, this.stdout, this.stderr);

  final int code;
  final String stdout;
  final String stderr;
}

/// The signature shared by [SshRunner.run] and the fakes that stand in for it.
/// Lets services depend on a function instead of a live connection, so their
/// command-shape and error-mapping logic is unit-testable without a real shed.
typedef SshRun =
    Future<SshResult> Function(
      List<String> argv, {
      String? stdin,
      Duration timeout,
    });

/// The signature shared by [SshRunner.runWire] and the fakes that stand in for
/// it: one ALREADY-COMPOSED wire command, not an argv list.
///
/// Distinct from [SshRun] on purpose. Every normal path sends a command a remote
/// `bash -lc` re-parses, so [SshRun]'s argv is POSIX-quoted by `wireCmd`. The
/// reserved `_bootstrap` channel has NO shell on the far side — shed-server reads
/// `sess.RawCommand()` and splits it on whitespace — so its request line is
/// COMPOSED, and quoting it would corrupt it (plan 002 §7 P2; see
/// [BootstrapService.requestLine]). This seam is what lets that composition be
/// asserted byte-for-byte in a unit test.
typedef SshRunWire =
    Future<SshResult> Function(
      String command, {
      String? stdin,
      Duration timeout,
    });

/// One command's outcome on an already-open connection, output UNDECODED.
///
/// Bytes, not strings, because the one caller that reaches for [execOn]
/// directly is the gx credential probe, whose stdout carries a bearer token
/// that is parsed in Rust and must never be decoded, logged or interpolated on
/// this side of the bridge (plan 018 §3.11).
class SshExecResult {
  const SshExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The remote process's exit status, or null when the server never sent one.
  /// dartssh2 occasionally drops the `exit-status` request even on success, so
  /// null is "unknown", not "failed" — see [SshRunner.run] for how the buffered
  /// runner resolves it.
  final int? exitCode;

  final Uint8List stdout;
  final Uint8List stderr;
}

/// Run [command] on an ALREADY-OPEN [client] and collect its output.
///
/// The connection is neither opened nor closed here: this is the half of
/// [SshRunner] that a long-lived consumer needs, where one client is shared by
/// a roost tunnel, a lane's forwards and a one-shot probe, and closing it after
/// a command would take the others down with it.
///
/// Both output streams are drained to completion **before** `done` is awaited:
/// dartssh2 can complete `done` while stdout still holds buffered data, and
/// reading them the other way round truncates the last frame.
Future<SshExecResult> execOn(
  SSHClient client,
  String command, {
  String? stdin,
}) async {
  final session = await client.execute(command);
  if (stdin != null) {
    session.stdin.add(utf8.encode(stdin));
    // Closing stdin sends EOF (not a channel close), so a binary that reads
    // stdin (shed-ext-rc --prompt-stdin) sees end-of-input and proceeds;
    // without it that read would block until the timeout fires.
    await session.stdin.close();
  }

  final out = BytesBuilder(copy: false);
  final err = BytesBuilder(copy: false);
  final outDone = Completer<void>();
  final errDone = Completer<void>();
  final outSub = session.stdout.listen(
    out.add,
    onDone: outDone.complete,
    onError: outDone.completeError,
  );
  final errSub = session.stderr.listen(
    err.add,
    onDone: errDone.complete,
    onError: errDone.completeError,
  );
  // Either band can complete with an ERROR, and the first `await` below would
  // then throw straight past the other band's subscription and past the
  // session, leaving a live channel behind on the shared client. That matters
  // more now than it did when this was private to `SshRunner`: the gx probe
  // runs through here, on the one `SSHClient` a machine feed owns for
  // everything, so a leaked channel is a leak for the whole app rather than
  // for one call. Normal completion still falls through untouched.
  // **Registered BEFORE the first await, and that ordering is the whole point.**
  // An error handed to a `Completer` whose future has no listener YET is
  // reported to the zone as UNHANDLED at that instant — which fails the
  // enclosing `flutter_test` case and raises a spurious crash report in the
  // app. While the code below sits on `outDone.future`, the OTHER two futures
  // have no listener, so an error on either is already reported by the time any
  // `finally` could run; a handler attached afterwards cannot retract it.
  //
  // `ignore()` suppresses only the unhandled-error REPORT, never the value: an
  // `await` on the same future afterwards still throws, so the primary failure
  // below still propagates. Verified against the pinned SDK (Dart 3.12):
  // ignore-then-await throws, and ignore-after-the-fact is still reported.
  //
  // dartssh2 2.18.0 as pinned never errors these controllers and completes
  // `done` only successfully, so this is a latent ordering rather than one seen
  // today — but it is an ordering its API and its own `onError` branches admit.
  final done = session.done;
  outDone.future.ignore();
  errDone.future.ignore();
  done.ignore();

  var ok = false;
  try {
    await outDone.future;
    await errDone.future;
    await done;
    ok = true;
  } finally {
    if (!ok) {
      await outSub.cancel();
      await errSub.cancel();
      session.close();
    }
  }

  return SshExecResult(
    exitCode: session.exitCode,
    stdout: out.takeBytes(),
    stderr: err.takeBytes(),
  );
}

/// Runs one-shot commands over SSH as `<user>@host`, pinned to the stored host
/// key. Port of apps/api/src/lib/ssh.ts `run` for the ssh target — the
/// orchestrator shells out to the `ssh` binary; here dartssh2 speaks the protocol
/// directly. Each call opens and tears down its own connection: RC operations are
/// infrequent and a page load already batches into a single `list`, mirroring the
/// orchestrator's per-request SSH model.
class SshRunner {
  SshRunner({
    required this.host,
    required this.port,
    required this.user,
    required this.identities,
    required this.hostKeys,
  });

  final String host;
  final int port;
  final String user;
  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;

  /// Connect, run [argv] (each token POSIX-quoted into one wire command the
  /// remote `bash -lc` re-parses), optionally feed [stdin], and return the
  /// result. Transport failures surface as dartssh2 [SSHError]s / [SocketException]s
  /// for the caller to classify; a command that runs but exits non-zero returns an
  /// [SshResult] carrying that code. Never logs stdout/stderr (callers decide what,
  /// if anything, is safe to surface).
  Future<SshResult> run(
    List<String> argv, {
    String? stdin,
    Duration timeout = const Duration(seconds: 15),
  }) => runWire(wireCmd(argv), stdin: stdin, timeout: timeout);

  /// Connect and run one ALREADY-COMPOSED [command] verbatim — no quoting layer
  /// at all. Only the `_bootstrap` mint uses this (that channel has no remote
  /// shell); everything else goes through [run], which quotes its argv. Callers
  /// of this method own the wire shape and must not interpolate untrusted data
  /// into it.
  Future<SshResult> runWire(
    String command, {
    String? stdin,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return withSshClient(
      host: host,
      port: port,
      user: user,
      identities: identities,
      hostKeys: hostKeys,
      timeout: timeout,
      body: (client) => _exec(client, command, stdin).timeout(timeout),
    );
  }

  /// [execOn] plus this runner's decoding and exit-code resolution.
  static Future<SshResult> _exec(
    SSHClient client,
    String command,
    String? stdin,
  ) async {
    final raw = await execOn(client, command, stdin: stdin);
    final stdoutStr = utf8.decode(raw.stdout, allowMalformed: true);
    final stderrStr = utf8.decode(raw.stderr, allowMalformed: true);
    return SshResult(
      _resolveCode(raw.exitCode, stdoutStr),
      stdoutStr,
      stderrStr,
    );
  }

  /// dartssh2 occasionally reports a null/late exit code even on success (a
  /// dropped `exit-status`), so a non-empty stdout from a command that prints its
  /// DTO is a positive success signal (the same trust model as the bootstrap
  /// mint). Commands that print nothing on success (kill) rely on a delivered
  /// exit code and fall back to a generic failure here.
  static int _resolveCode(int? exitCode, String stdout) {
    if (exitCode != null) return exitCode;
    return stdout.trim().isEmpty ? 1 : 0;
  }
}

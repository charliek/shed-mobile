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
  }) {
    return withSshClient(
      host: host,
      port: port,
      user: user,
      identities: identities,
      hostKeys: hostKeys,
      timeout: timeout,
      body: (client) => _exec(client, wireCmd(argv), stdin).timeout(timeout),
    );
  }

  Future<SshResult> _exec(
    SSHClient client,
    String command,
    String? stdin,
  ) async {
    final session = await client.execute(command);
    if (stdin != null) {
      session.stdin.add(Uint8List.fromList(utf8.encode(stdin)));
      // Closing stdin sends EOF (not a channel close), so a binary that reads
      // stdin (shed-ext-rc --prompt-stdin) sees end-of-input and proceeds;
      // without it that read would block until the timeout fires.
      await session.stdin.close();
    }

    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    session.stdout.listen(
      out.add,
      onDone: outDone.complete,
      onError: outDone.completeError,
    );
    session.stderr.listen(
      err.add,
      onDone: errDone.complete,
      onError: errDone.completeError,
    );
    await outDone.future;
    await errDone.future;
    await session.done;

    final stdoutStr = utf8.decode(out.takeBytes(), allowMalformed: true);
    final stderrStr = utf8.decode(err.takeBytes(), allowMalformed: true);
    return SshResult(
      _resolveCode(session.exitCode, stdoutStr),
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

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/shell_quote.dart';
import 'host_key_store.dart';
import 'ssh_connection.dart';

/// Largest terminal dimension we forward to the remote PTY. Mirrors the
/// orchestrator's rcAttach `MAX_TERM_DIM`; dims outside [1, _maxDim] are clamped
/// (never sent raw) so a bogus viewport can't ask tmux for a degenerate size.
const int _maxDim = 1000;

int clampPtyDim(int v) => v < 1 ? 1 : (v > _maxDim ? _maxDim : v);

/// The remote command that attaches to an RC session's tmux pane, POSIX-quoted
/// into the single wire string the remote `bash -lc` re-parses. Pure so the wire
/// form is unit-testable. Mirrors rcAttach.ts (`tmux attach -t rc-<slug>`).
String rcAttachCommand(String slug) =>
    wireCmd(['tmux', 'attach', '-t', 'rc-$slug']);

/// Inverse of the `rc-<slug>` tmux naming [rcAttachCommand] relies on: recover the
/// slug from a tmux session name. `GET /api/sessions` returns the tmux `name`
/// (e.g. `rc-baxjjh`), not the slug, so the cross-host Sessions view derives the
/// slug here to build a [PtySession]. Tolerant — a name without the `rc-` prefix is
/// returned unchanged so a foreign/legacy session yields a non-empty value the
/// caller can reject. Pure; round-trip tested against [rcAttachCommand].
String rcSlugFromTmux(String tmuxName) =>
    tmuxName.startsWith('rc-') ? tmuxName.substring(3) : tmuxName;

/// A long-lived interactive PTY attached to an RC session's tmux pane over a
/// host-key-pinned SSH connection. Built on [withSshClient] (the same connection
/// primitive the one-shot [SshRunner] and the bootstrap mint use), but keeps the
/// channel open and bidirectional for the terminal's lifetime.
///
/// Closing the session detaches tmux (the rc session keeps running) — it does not
/// kill the pane.
class PtySession {
  PtySession({
    required this.host,
    required this.port,
    required this.user,
    required this.identities,
    required this.hostKeys,
    required this.slug,
  });

  final String host;
  final int port;
  final String user;
  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;
  final String slug;

  final _output = StreamController<Uint8List>.broadcast();
  final _ready = Completer<void>();
  final _done = Completer<int?>();
  final _close = Completer<void>();
  SSHSession? _session;
  bool _started = false;

  /// Merged stdout+stderr bytes from the remote PTY.
  Stream<Uint8List> get output => _output.stream;

  /// Completes (with the remote exit code, if delivered) when the session ends —
  /// the remote process exits or [close] is called.
  Future<int?> get done => _done.future;

  /// Connect, allocate a PTY at [cols]x[rows], and run `tmux attach`. The returned
  /// future completes once the PTY is open, or throws an [AppError] if the
  /// connection / host-key check fails. After it resolves, the session streams
  /// until the remote exits or [close] is called (then [done] completes).
  Future<void> start({required int cols, required int rows}) {
    assert(!_started, 'PtySession.start may only be called once');
    _started = true;
    unawaited(_run(cols, rows));
    return _ready.future;
  }

  Future<void> _run(int cols, int rows) async {
    int? exitCode;
    try {
      await withSshClient(
        host: host,
        port: port,
        user: user,
        identities: identities,
        hostKeys: hostKeys,
        timeout: const Duration(seconds: 15),
        body: (client) async {
          final session = await client.execute(
            rcAttachCommand(slug),
            pty: SSHPtyConfig(
              width: clampPtyDim(cols),
              height: clampPtyDim(rows),
            ),
          );
          _session = session;
          // stdin stays open for the session's lifetime (interactive input).
          session.stdout.listen(_emit, onError: (_) {});
          session.stderr.listen(_emit, onError: (_) {});
          if (!_ready.isCompleted) _ready.complete();
          // End on either the remote process exiting or a local close().
          await Future.any([session.done, _close.future]);
          exitCode = session.exitCode;
        },
      );
    } catch (e) {
      final mapped = classifySshException(e) ?? e;
      // A failure before the PTY opened is a connect error the caller awaits;
      // afterwards it just ends the session (surfaced via [done]).
      if (!_ready.isCompleted) _ready.completeError(mapped);
    } finally {
      _session = null;
      if (!_output.isClosed) await _output.close();
      if (!_done.isCompleted) _done.complete(exitCode);
    }
  }

  void _emit(Uint8List data) {
    if (!_output.isClosed) _output.add(data);
  }

  /// Forward keystrokes to the remote PTY. No-op once the session has ended; a
  /// keystroke racing the channel teardown (done fired, _session not yet nulled)
  /// is dropped rather than thrown.
  void write(List<int> data) {
    final s = _session;
    if (s == null) return;
    try {
      s.stdin.add(data is Uint8List ? data : Uint8List.fromList(data));
    } catch (_) {
      // Channel is closing/closed; safe to drop the keystroke.
    }
  }

  /// Resize the remote PTY (dims clamped to [1, _maxDim]). Same teardown-race
  /// tolerance as [write].
  void resize(int cols, int rows) {
    final s = _session;
    if (s == null) return;
    try {
      s.resizeTerminal(clampPtyDim(cols), clampPtyDim(rows));
    } catch (_) {
      // Channel is closing/closed; the resize is moot.
    }
  }

  /// Detach and tear the connection down (the rc session keeps running).
  void close() {
    if (!_close.isCompleted) _close.complete();
    _session?.close();
  }
}

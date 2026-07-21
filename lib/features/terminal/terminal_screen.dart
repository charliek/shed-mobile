import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../core/url_launch.dart';
import '../../core/url_scan.dart';
import '../../providers.dart';
import '../../services/foreground_service.dart';
import '../../ssh/pty_session.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import 'terminal_keys.dart';

/// Signature of [buildPtySession] — the production factory that assembles a
/// (still-unstarted) [PtySession]. A test injects a fake here to exercise the
/// terminal without a real SSH PTY; null in production (see [buildPtySession]).
typedef PtyBuilder =
    Future<PtySession> Function(
      WidgetRef ref, {
      required String serverName,
      required String shedName,
      required String slug,
    });

/// In-app terminal: an xterm view wired to a [PtySession] that attaches to a
/// shed RC session's tmux pane (`tmux attach -t rc-<slug>`) over pinned SSH.
/// Detaching (leaving the screen) keeps the rc session running.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    required this.serverName,
    required this.shedName,
    required this.slug,
    required this.title,
    this.ptyBuilder,
    this.urlLauncher,
    super.key,
  });

  final String serverName;
  final String shedName;
  final String slug;
  final String title;

  /// Test-only seam: overrides the [buildPtySession] factory so the screen's
  /// lifecycle (connect/reconnect/dispose) can be driven with a fake PTY. Always
  /// null in production.
  @visibleForTesting
  final PtyBuilder? ptyBuilder;

  /// Test seam for the URL banner's "Open" action: an injected launcher passed
  /// straight through to [launchExternalUrl]. Production leaves this null (the
  /// real url_launcher is used); tests inject a fake to assert the launched
  /// [Uri] and to simulate success / false / throw. Mirrors `SessionCard`.
  @visibleForTesting
  final UrlLauncher? urlLauncher;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _terminal = Terminal(maxLines: 10000);
  final _terminalController = TerminalController();
  final _terminalFocus = FocusNode();
  PtySession? _pty;

  /// Owned subscription for the decoded remote output. Cancelled on reconnect
  /// and dispose so a superseded connection's bytes can't reach the terminal.
  StreamSubscription<String>? _outputSub;

  /// Bumped every [_connect]. Stream/`done` callbacks capture their generation
  /// and no-op unless they're still the current one — a reconnect (or dispose)
  /// can't be `setState`-clobbered by the connection it replaced.
  int _generation = 0;
  bool _connecting = true;
  String? _error;
  int? _exitCode;
  bool _ctrlArmed = false;
  double _fontSize = 13;

  /// Bounded rolling tail of decoded output, scanned for a login/any http(s) URL
  /// (see [appendBoundedTail] — a small fixed window, never a second copy of the
  /// terminal's scrollback).
  String _urlScanTail = '';

  /// The URL currently surfaced in the banner (null when none is showing), and
  /// the one the user last dismissed. Re-detecting either is a no-op: a TUI
  /// redraw re-emits the same URL, and a dismissed URL must not pop back.
  String? _detectedUrl;
  String? _dismissedUrl;

  @visibleForTesting
  Terminal get terminal => _terminal;

  @visibleForTesting
  TerminalController get terminalController => _terminalController;

  @override
  void initState() {
    super.initState();
    // Keystrokes -> remote stdin (through the sticky-Ctrl filter); viewport
    // changes -> remote PTY resize.
    _terminal.onOutput = (data) {
      // Correct xterm's mouse-wheel SGR codes (68–71 → 64–67) so tmux + TUIs
      // recognize the scroll, then apply sticky-Ctrl and forward to the PTY.
      _pty?.write(
        applyStickyCtrl(armed: _ctrlArmed, data: fixWheelReport(data)),
      );
      if (_ctrlArmed) setState(() => _ctrlArmed = false); // any input disarms
    };
    _terminal.onResize = (w, h, _, _) => _pty?.resize(w, h);
    // Report focus in/out to the remote (DECSET 1004) so tmux's focus-events and
    // TUIs like claude can track when the terminal is focused. Gated on the app
    // having enabled focus reporting, so nothing is injected otherwise.
    _terminalFocus.addListener(_onFocusChange);
    _connect();
  }

  void _onFocusChange() {
    final report = focusReport(
      enabled: _terminal.reportFocusMode,
      focused: _terminalFocus.hasFocus,
    );
    if (report != null) _pty?.write(report);
  }

  void _adjustFont(double delta) =>
      setState(() => _fontSize = (_fontSize + delta).clamp(8.0, 28.0));

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    // Disarm first so a single-letter clipboard isn't turned into a control code
    // when it routes through onOutput.
    if (_ctrlArmed) setState(() => _ctrlArmed = false);
    _terminal.paste(text); // honors bracketed-paste mode
  }

  Future<void> _copy() async {
    final range = _terminalController.selection;
    if (range == null) return;
    // Never log the copied text: a cursor login URL carries an auth token.
    await _copyToClipboard(_terminal.buffer.getText(range), 'terminal-copy');
  }

  /// Copy [text] to the clipboard, log [logName] as ok, and — once mounted —
  /// show the "Copied" snackbar. Shared by [_copy] (the xterm selection) and the
  /// URL banner's Copy link action: both copy-then-confirm identically and only
  /// differ in the source text and the drive-log name. [text] itself is never
  /// logged (a selection or a detected URL may carry an auth token).
  Future<void> _copyToClipboard(String text, String logName) async {
    await Clipboard.setData(ClipboardData(text: text));
    logDriveResult(logName, ok: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  /// Feed one decoded output [data] chunk through the bounded scan tail and, if a
  /// NEW http(s) URL surfaces, raise the banner. De-duped: a re-emitted (TUI
  /// redraw) or already-dismissed URL is ignored. Called only from inside the
  /// output listener's `mounted && gen == _generation` guard, so the setState is
  /// safe. The URL is NEVER logged — a cursor login link carries an auth token.
  void _scanForUrl(String data) {
    _urlScanTail = appendBoundedTail(_urlScanTail, data);
    final u = latestUrlIn(_urlScanTail);
    if (u == null || u == _detectedUrl || u == _dismissedUrl) return;
    setState(() => _detectedUrl = u);
    logDriveState('terminal-url detected=t');
  }

  /// Open the detected URL via the shared safe-launch helper (http/https only; a
  /// rejected/failed launch snackbars instead of throwing).
  Future<void> _openUrl(String url) async {
    final outcome = await launchExternalUrl(url, launcher: widget.urlLauncher);
    logDriveResult(
      'terminal-url-open',
      ok: outcome == UrlLaunchOutcome.success,
    );
    if (!mounted || outcome == UrlLaunchOutcome.success) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
  }

  /// Dismiss the banner and remember the URL so a redraw can't re-surface it (a
  /// reconnect clears the memory — see [_connect]).
  void _dismissUrl() => setState(() {
    _dismissedUrl = _detectedUrl;
    _detectedUrl = null;
  });

  Future<void> _connect() async {
    // Claim this generation; anything the previous connection fires from here on
    // is stale and must no-op (see the mounted && gen == _generation guards).
    final gen = ++_generation;
    // Reconnect tears the old connection down first: cancel its output stream and
    // close its pty so it stops emitting before the new one opens. Null-safe on
    // the first connect. Not awaited — cancel() removes the listener immediately
    // (so no more chunks reach the terminal), but its returned future can hang on
    // a converter-bound broadcast stream; the generation guard is the backstop.
    unawaited(_outputSub?.cancel());
    _outputSub = null;
    _pty?.close();
    _pty = null;
    setState(() {
      _connecting = true;
      _error = null;
      _exitCode = null;
      // Fresh session -> re-detect from scratch: a URL from the previous
      // connection is stale, and a previously-dismissed one should be offered
      // again if it reappears.
      _urlScanTail = '';
      _detectedUrl = null;
      _dismissedUrl = null;
    });
    PtySession? pty;
    try {
      pty = await (widget.ptyBuilder ?? buildPtySession)(
        ref,
        serverName: widget.serverName,
        shedName: widget.shedName,
        slug: widget.slug,
      );
      // Disposed — or superseded by a newer connect — while resolving connect
      // params? The session is unstarted (no connection opened yet), so just drop
      // it. `_pty` is still null here, so teardown couldn't have closed it.
      if (!mounted || gen != _generation) {
        pty.close();
        return;
      }
      // Own it before awaiting start() so dispose()/the next connect is the single
      // teardown authority (closing mid-connect tears the session down promptly).
      _pty = pty;
      // Stream remote output into the terminal. A chunked UTF-8 decoder buffers
      // multibyte sequences split across SSH packets. Guarded so a chunk delivered
      // after dispose/reconnect can't write into a torn-down terminal.
      _outputSub = const Utf8Decoder(allowMalformed: true)
          .bind(pty.output)
          .listen((data) {
            if (mounted && gen == _generation) {
              _terminal.write(data);
              _scanForUrl(data);
            }
          });
      pty.done.then((code) {
        if (!mounted || gen != _generation) return;
        setState(() => _exitCode = code);
        logDriveState('screen=terminal slug=${widget.slug} state=exited');
        // The SSH session ended — stop the keep-alive foreground service
        // (Android; no-op elsewhere) so its notification doesn't linger past the
        // session. A reconnect restarts it in _connect; dispose also stops it.
        unawaited(ShedForegroundService.stop());
      });
      // Start at the terminal's current size if laid out, else a sane default;
      // the TerminalView fires onResize after layout to correct it.
      await pty.start(cols: _terminal.viewWidth, rows: _terminal.viewHeight);
      if (!mounted || gen != _generation) return; // torn down mid-start
      setState(() => _connecting = false);
      // Keep the SSH session alive if the app is backgrounded (Android only;
      // best-effort, no-op elsewhere). Generic text — the shed name/slug stays
      // in-app rather than on the lock screen.
      unawaited(ShedForegroundService.start(text: 'Terminal session active'));
      logDriveResult('terminal-connect', ok: true);
    } catch (e) {
      logDriveResult('terminal-connect', ok: false, error: e);
      // start() may have thrown after `_pty` was assigned — close that pty so its
      // half-open connection isn't leaked. Only if we're still the current
      // generation; a newer connect already owns (and will tear down) `_pty`.
      if (gen == _generation) {
        pty?.close();
        if (mounted) {
          setState(() {
            _connecting = false;
            _error = '$e';
          });
        }
      }
    }
  }

  @override
  void dispose() {
    unawaited(_outputSub?.cancel());
    _pty?.close();
    _terminalController.dispose();
    _terminalFocus.dispose(); // also drops _onFocusChange
    unawaited(ShedForegroundService.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = !_connecting && _error == null && _exitCode == null;
    if (kDebugMode && active) {
      // Debug-only: reading viewInsets registers a keyboard dependency (rebuilds
      // on the show/hide animation), so keep it behind kDebugMode. Re-logged when
      // the keyboard inset or font changes (logDriveState dedups) — lets the
      // drive assert the soft keyboard stays up on key taps.
      final inset = MediaQuery.of(context).viewInsets.bottom;
      logDriveState(
        'screen=terminal slug=${widget.slug} state=ready '
        'keyboardVisible=${inset > 0} inset=${inset.round()} '
        'font=${_fontSize.round()}',
      );
    }
    // The terminal view is always dark, so force the dark theme on the
    // surrounding chrome (app bar, key toolbar, banners) regardless of the app's
    // light/dark setting — light chrome around a dark terminal looks broken.
    return Theme(
      data: shedDarkTheme,
      child: Scaffold(
        key: const ValueKey('terminal-screen'),
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('terminal-back'),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Detach',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(widget.title),
          actions: [
            if (active) ...[
              IconButton(
                key: const ValueKey('terminal-font-dec'),
                icon: const Icon(Icons.text_decrease),
                tooltip: 'Smaller text',
                onPressed: () => _adjustFont(-1),
              ),
              IconButton(
                key: const ValueKey('terminal-font-inc'),
                icon: const Icon(Icons.text_increase),
                tooltip: 'Larger text',
                onPressed: () => _adjustFont(1),
              ),
              IconButton(
                key: const ValueKey('terminal-paste'),
                icon: const Icon(Icons.content_paste),
                tooltip: 'Paste',
                onPressed: _paste,
              ),
              // Enabled only while there's a selection; rebuilds as the controller
              // reports selection changes.
              AnimatedBuilder(
                animation: _terminalController,
                builder: (context, _) => IconButton(
                  key: const ValueKey('terminal-copy'),
                  icon: const Icon(Icons.content_copy),
                  tooltip: 'Copy',
                  onPressed: _terminalController.selection == null
                      ? null
                      : _copy,
                ),
              ),
            ],
            if (_exitCode != null || _error != null)
              IconButton(
                key: const ValueKey('terminal-reconnect'),
                icon: const Icon(Icons.refresh),
                tooltip: 'Reconnect',
                onPressed: _connect,
              ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_connecting) {
      return const Center(
        key: ValueKey('terminal-connecting'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$_error', key: const ValueKey('terminal-error')),
        ),
      );
    }
    return Column(
      children: [
        if (_exitCode != null)
          Container(
            width: double.infinity,
            // The terminal chrome is always dark, but this reads the State's
            // (ambient) context above the Theme wrap, so pin the dark token.
            color: ShedColors.dark.surface2,
            padding: const EdgeInsets.all(8),
            child: Text(
              'Session ended (exit $_exitCode). Tap reconnect to reattach.',
              key: const ValueKey('terminal-ended'),
              style: TextStyle(color: ShedColors.dark.fg),
            ),
          ),
        // A detected login/any http(s) URL: a one-tap Copy/Open banner (grabbing
        // a cursor login URL by drag-selecting on a phone terminal is painful).
        // Shown only while the session is live.
        if (_detectedUrl != null && _exitCode == null)
          _urlBanner(_detectedUrl!),
        Expanded(
          child: TerminalView(
            _terminal,
            key: const ValueKey('terminal-view'),
            controller: _terminalController,
            focusNode: _terminalFocus,
            autofocus: true,
            textStyle: TerminalStyle(fontSize: _fontSize),
          ),
        ),
        // The virtual-key toolbar sits at the bottom, just above the soft
        // keyboard (the Scaffold uses adjustResize). Hidden once the session ends.
        if (_exitCode == null)
          TerminalKeys(
            ctrlArmed: _ctrlArmed,
            onToggleCtrl: () => setState(() => _ctrlArmed = !_ctrlArmed),
            onKey: (bytes) {
              _pty?.write(bytes);
              // Toolbar keys are literal; a pending Ctrl shouldn't carry over to
              // the next soft-keyboard letter, so consume it like any input.
              if (_ctrlArmed) setState(() => _ctrlArmed = false);
            },
          ),
      ],
    );
  }

  /// The dismissible "Link detected" banner. Styled for the always-dark terminal
  /// chrome (this builds under the State's ambient context, above the Theme wrap,
  /// so the dark tokens are pinned). Shows a truncated preview of the URL but the
  /// value is never logged.
  Widget _urlBanner(String url) {
    const c = ShedColors.dark;
    return Container(
      key: const ValueKey('terminal-url-banner'),
      width: double.infinity,
      color: c.surface2,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Icon(Icons.link, size: 18, color: c.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Link detected',
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.fg3, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const ValueKey('terminal-url-copy'),
            style: TextButton.styleFrom(
              foregroundColor: c.fg,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            onPressed: () => _copyToClipboard(url, 'terminal-url-copy'),
            child: const Text('Copy link'),
          ),
          TextButton(
            key: const ValueKey('terminal-url-open'),
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            onPressed: () => _openUrl(url),
            child: const Text('Open'),
          ),
          IconButton(
            key: const ValueKey('terminal-url-dismiss'),
            icon: const Icon(Icons.close, size: 18),
            color: c.fg3,
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: _dismissUrl,
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../services/foreground_service.dart';
import '../../ssh/pty_session.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import 'terminal_keys.dart';

/// In-app terminal: an xterm view wired to a [PtySession] that attaches to a
/// shed RC session's tmux pane (`tmux attach -t rc-<slug>`) over pinned SSH.
/// Detaching (leaving the screen) keeps the rc session running.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    required this.serverName,
    required this.shedName,
    required this.slug,
    required this.title,
    super.key,
  });

  final String serverName;
  final String shedName;
  final String slug;
  final String title;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _terminal = Terminal(maxLines: 10000);
  final _terminalFocus = FocusNode();
  PtySession? _pty;
  bool _connecting = true;
  String? _error;
  int? _exitCode;
  bool _ctrlArmed = false;
  double _fontSize = 13;

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

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
      _exitCode = null;
    });
    try {
      final pty = await buildPtySession(
        ref,
        serverName: widget.serverName,
        shedName: widget.shedName,
        slug: widget.slug,
      );
      // Disposed while resolving connect params? The session is unstarted (no
      // connection opened yet), so just drop it — dispose() couldn't have closed
      // it (_pty was still null).
      if (!mounted) return;
      // Own it before awaiting start() so dispose() is the single teardown
      // authority (closing mid-connect tears the session down promptly).
      _pty = pty;
      // Stream remote output into the terminal. A chunked UTF-8 decoder buffers
      // multibyte sequences split across SSH packets.
      const Utf8Decoder(
        allowMalformed: true,
      ).bind(pty.output).listen(_terminal.write);
      pty.done.then((code) {
        if (!mounted) return;
        setState(() => _exitCode = code);
        logDriveState('screen=terminal slug=${widget.slug} state=exited');
      });
      // Start at the terminal's current size if laid out, else a sane default;
      // the TerminalView fires onResize after layout to correct it.
      await pty.start(cols: _terminal.viewWidth, rows: _terminal.viewHeight);
      if (!mounted) return; // dispose() already closed the pty
      setState(() => _connecting = false);
      // Keep the SSH session alive if the app is backgrounded (Android only;
      // best-effort, no-op elsewhere). Generic text — the shed name/slug stays
      // in-app rather than on the lock screen.
      unawaited(ShedForegroundService.start(text: 'Terminal session active'));
      logDriveResult('terminal-connect', ok: true);
    } catch (e) {
      logDriveResult('terminal-connect', ok: false, error: e);
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _pty?.close();
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
        Expanded(
          child: TerminalView(
            _terminal,
            key: const ValueKey('terminal-view'),
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
}

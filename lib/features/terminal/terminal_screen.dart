import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../ssh/pty_session.dart';

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
  PtySession? _pty;
  bool _connecting = true;
  String? _error;
  int? _exitCode;

  @override
  void initState() {
    super.initState();
    // Keystrokes -> remote stdin; viewport changes -> remote PTY resize.
    _terminal.onOutput = (data) => _pty?.write(utf8.encode(data));
    _terminal.onResize = (w, h, _, _) => _pty?.resize(w, h);
    _connect();
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
      logDriveState('screen=terminal slug=${widget.slug} state=ready');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Text(
              'Session ended (exit $_exitCode). Tap reconnect to reattach.',
              key: const ValueKey('terminal-ended'),
            ),
          ),
        Expanded(
          child: TerminalView(
            _terminal,
            key: const ValueKey('terminal-view'),
            autofocus: true,
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../src/rust/api/roost.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';

/// The refresh cadence — plan 013 §3.5 pins it at 2 s (`SHED_ROOST_POLL_MS`
/// governs the Rust watcher's own poll; this is a separate, screen-owned
/// timer over one already-open [BridgeRoostPeek] connection).
const Duration _refreshInterval = Duration(seconds: 2);

/// The peek's three roost calls, behind a seam a widget test can stub.
///
/// Owns the [BridgeRoostPeek] handle itself, so the screen only ever calls
/// [open]/[dump]/[close] and never touches the handle directly — that is what
/// lets a test swap in a fake with no bridge underneath it at all.
abstract class PeekSource {
  /// Dial and hold the one connection this peek's whole life rides on.
  Future<void> open();

  /// One frame over the held connection. Throws on a transient read failure —
  /// the screen keeps its last-good frame and polling continues at the same
  /// cadence (plan 013 §3.5: "a dump error shows an inline error line and
  /// keeps polling").
  Future<BridgeTabDump> dump();

  /// Release the held connection. Idempotent.
  Future<void> close();
}

/// Production [PeekSource]: the FRB `roost_peek_*` calls bound to one
/// `(localPort, tabId)`.
class RoostPeekSource implements PeekSource {
  RoostPeekSource({required this.localPort, required this.tabId});

  final int localPort;
  final PlatformInt64 tabId;

  BridgeRoostPeek? _handle;

  @override
  Future<void> open() async {
    _handle = await roostPeekOpen(localPort: localPort, tabId: tabId);
  }

  @override
  Future<BridgeTabDump> dump() {
    final handle = _handle;
    if (handle == null) throw StateError('peek is not open');
    return roostPeekDump(handle: handle);
  }

  @override
  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    if (handle != null) await roostPeekClose(handle: handle);
  }
}

/// **A read-only view of one roost tab** — `tab.dump`'s rendered rows, polled
/// every 2 s over one held connection (plan 013 §3.5).
///
/// This is the whole of the machine attach story for a `native-remote` kind:
/// roost owns the terminal, so there is no keystroke path here, only what is
/// currently on screen. [attachKind] is what routes here in the first place —
/// a `tmux` row still gets the real xterm attach ([TerminalScreen]).
class RoostPeekScreen extends ConsumerStatefulWidget {
  const RoostPeekScreen({
    required this.machineName,
    required this.tabId,
    required this.title,
    this.peekSource,
    this.peekSourceBuilder,
    super.key,
  });

  /// The machine the tab lives on — read to find the feed's tunnel port.
  final String machineName;

  /// The tab to peek, roost's own id.
  final PlatformInt64 tabId;

  /// App-bar title — the session's display name.
  final String title;

  /// Test seam: overrides the [PeekSource] entirely, bypassing the tunnel-port
  /// lookup. Always null in production.
  @visibleForTesting
  final PeekSource? peekSource;

  /// Test seam: overrides how the PRODUCTION source is BUILT (in place of
  /// [_RoostPeekScreenState._buildProductionSource]), still routed through
  /// the same try/catch `_open()` uses for a real `open()` failure — so a
  /// test can exercise "the build step itself throws" (e.g. no tunnel port
  /// yet) without a real machine feed or the Rust bridge behind it. Ignored
  /// when [peekSource] is set. Always null in production.
  @visibleForTesting
  final PeekSource Function()? peekSourceBuilder;

  @override
  ConsumerState<RoostPeekScreen> createState() => _RoostPeekScreenState();
}

class _RoostPeekScreenState extends ConsumerState<RoostPeekScreen> {
  PeekSource? _source;
  Timer? _timer;

  bool _opening = true;
  String? _openError;

  BridgeTabDump? _dump;
  String? _dumpError;

  // What was last logged, so the drive log only fires on a real state change
  // (rows or error-state) rather than once per 2 s tick.
  int? _loggedRows;
  bool? _loggedHadError;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  /// Build the production source: the machine's feed tunnel port, looked up
  /// through the SAME controller the sessions list already holds open — a peek
  /// rides the feed's existing SSH connection rather than opening a second one.
  PeekSource _buildProductionSource() {
    final port = ref
        .read(machineFeedControllerProvider(widget.machineName))
        .tunnelPort;
    if (port == null) {
      throw StateError('${widget.machineName} is not connected');
    }
    return RoostPeekSource(localPort: port, tabId: widget.tabId);
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _openError = null;
    });
    // `_buildProductionSource()` lives INSIDE this try, not just
    // `source.open()`: it can throw too (no tunnel port yet), and that
    // failure needs the same error-line-plus-retry rendering as an `open()`
    // failure — not an unhandled rejection that never reaches the UI.
    PeekSource? source;
    try {
      source =
          widget.peekSource ??
          (widget.peekSourceBuilder ?? _buildProductionSource)();
      _source = source;
      await source.open();
      if (!mounted) {
        // Disposed while `open()` was in flight: `dispose()` saw `_opening`
        // still true and deliberately left this source alone (see
        // `dispose()`), so THIS is the only place that will ever close the
        // handle that just came up. Without this, it leaks.
        await source.close();
        return;
      }
      setState(() => _opening = false);
      await _refresh(); // first frame immediately, not after a 2s wait
      // Disposed while that first `dump()` was in flight: `dispose()` has
      // already cancelled `_timer` and (seeing `_opening` false) closed the
      // source. Starting a periodic timer NOW would create one nothing will
      // ever cancel, polling a closed source every 2 s for the life of the
      // isolate — so the mounted check has to sit AFTER the await, not only
      // inside `_refresh()`.
      if (!mounted) return;
      _timer?.cancel();
      _timer = Timer.periodic(_refreshInterval, (_) => unawaited(_refresh()));
    } catch (e) {
      if (!mounted) {
        // Same reasoning as above, for a source that failed to open (it may
        // still hold a partially-acquired resource) — `close()` is
        // documented idempotent, so this and `dispose()` never both firing
        // is not a correctness requirement, only a redundant safety net.
        if (source != null) await source.close();
        return;
      }
      setState(() {
        _opening = false;
        _openError = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    final source = _source;
    if (source == null) return;
    try {
      final dump = await source.dump();
      if (!mounted) return;
      setState(() {
        _dump = dump;
        _dumpError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _dumpError = '$e');
    }
    _logState();
  }

  void _logState() {
    final rows = _dump?.rowsText.length;
    final hadError = _dumpError != null;
    if (rows == _loggedRows && hadError == _loggedHadError) return;
    _loggedRows = rows;
    _loggedHadError = hadError;
    logDriveState(
      'screen=peek machine=${widget.machineName} tab=${widget.tabId} '
      'rows=${rows ?? 0}',
    );
  }

  /// Retry after an OPEN failure: close whatever partial state exists (a
  /// [PeekSource] that failed `open()` may still hold a live socket) and start
  /// over from scratch.
  ///
  /// SERIALIZED on `_opening`. The retry button only renders while `_openError`
  /// is set, but `close()` is awaited before `_open()` sets `_opening` itself —
  /// so without this guard a second tap inside that gap starts a second
  /// `_open()`, and the two race to assign `_source`. The loser's handle is then
  /// open with nothing holding it. Flipping `_opening` here closes the gap AND
  /// swaps the error line for the spinner on the first tap.
  Future<void> _retry() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _openError = null;
    });
    _timer?.cancel();
    _timer = null;
    await _source?.close();
    // Disposed mid-close: `_open()` would `setState` on a dead State. The
    // source is already closed by the await above, and `dispose()` deliberately
    // skipped it (`_opening` is true), so there is nothing left to release.
    if (!mounted) return;
    _source = null;
    await _open();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // While `_open()` is still in flight (`_opening` still true — building
    // the source, or awaiting `open()`), that pending call owns closing it:
    // it will notice `!mounted` itself once it wakes up (see `_open()`).
    // Closing here too would double-close before `open()` has even
    // returned, and — for a real handle — before there is anything to
    // close: `_source` gets assigned synchronously, but the underlying
    // resource isn't live until `open()` resolves.
    if (!_opening) unawaited(_source?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('roost-peek-screen'),
      appBar: AppBar(title: Text(widget.title)),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_opening) {
      return const Center(
        key: ValueKey('roost-peek-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final openError = _openError;
    if (openError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                openError,
                key: const ValueKey('roost-peek-open-error'),
                textAlign: TextAlign.center,
                // The fixed dark palette, not `context.shed` — same choice
                // `_dumpView`'s error line makes, so the whole screen's colors
                // come from one place regardless of the app's own theme.
                style: sansStyle(fontSize: 13, color: ShedColors.dark.errFg),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey('roost-peek-retry'),
                onPressed: () => unawaited(_retry()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return _dumpView(context);
  }

  Widget _dumpView(BuildContext context) {
    final dump = _dump;
    return Container(
      color: ShedColors.dark.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_dumpError != null)
            Container(
              key: const ValueKey('roost-peek-error'),
              width: double.infinity,
              color: ShedColors.dark.surface2,
              padding: const EdgeInsets.all(8),
              child: Text(
                _dumpError!,
                style: monoStyle(fontSize: 11, color: ShedColors.dark.errFg),
              ),
            ),
          if (dump == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var row = 0; row < dump.rowsText.length; row += 1)
                        _row(dump, row),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BridgeTabDump dump, int row) {
    final highlighted = dump.cursorVisible && dump.cursorRow == row;
    final text = Text(
      dump.rowsText[row].isEmpty ? ' ' : dump.rowsText[row],
      style: monoStyle(fontSize: 12, color: ShedColors.dark.fg),
    );
    if (!highlighted) return text;
    return ColoredBox(
      key: const ValueKey('roost-peek-cursor'),
      color: ShedColors.dark.accentSoft,
      child: text,
    );
  }
}

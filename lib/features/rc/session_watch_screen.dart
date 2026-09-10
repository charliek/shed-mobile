import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../core/app_error.dart';
import '../../rc/rc_ui.dart';
import '../../shed/shed_status.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/status_badge.dart';
import '../terminal/terminal_screen.dart';
import 'feed_rows.dart';
import 'session_watch_source.dart';

/// **Watching one session**: its message feed, its live status, and the one
/// way to act on it that makes sense for its kind.
///
/// This is the screen the whole remote-control story is FOR. Nobody steers an
/// agent they cannot see — you open a session to read what it has done and what
/// it is asking, and only then answer it. So the controls live here, beside the
/// output, rather than on a list row where acting would be guesswork.
///
/// Transport-agnostic by construction: a [SessionWatchSource] supplies the feed,
/// the input path, and the terminal target, so a session in a SHED (reached
/// through its server) and one on a MACHINE (reached over an SSH-forwarded port
/// to the machine's own hub) render and behave identically. They serve the same
/// `/v1` cursor; only the route differs, and that is not a thing a person
/// should have to think about.
///
/// Messages are hub-sanitized, so they render as plain [Text] — no markdown.
/// Live append rides the source's seq bumps (`message.appended` carries a
/// high-water mark, not content, so a bump triggers a targeted fetch). Anything
/// the feed cannot serve — a needs-auth or dead lifecycle, no feed for this
/// kind at all — hands off to the in-app TUI, which is the floor every kind
/// can stand on.
class SessionWatchScreen extends ConsumerStatefulWidget {
  const SessionWatchScreen({required this.source, super.key});

  final SessionWatchSource source;

  @override
  ConsumerState<SessionWatchScreen> createState() => _SessionWatchScreenState();
}

class _SessionWatchScreenState extends ConsumerState<SessionWatchScreen> {
  static const int _pageLimit = 200;

  final _messages = <BridgeRcFeedMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  Object? _loadError;
  bool _historyTruncated = false;
  BigInt _lastSeq = BigInt.zero;

  /// The last seq this build reacted to, so one bump schedules one drain.
  BigInt? _seenSeq;
  bool _sending = false;
  bool _appending = false;

  /// A seq bump arrived while a drain was in flight. Set instead of dropping
  /// it, and consumed when that drain finishes — see [_appendNew].
  bool _appendAgain = false;

  /// Bumped at the start of every [_reload]; in-flight [_appendNew] drains (and
  /// stale [_reload]s) capture it and abort when it moves, so a reload can never
  /// race an append into duplicate rows (duplicate seq ValueKeys would crash the
  /// ListView).
  int _generation = 0;

  String get _slug => widget.source.slug;

  @override
  void initState() {
    super.initState();
    // Defer the first load until after the initial build has established the
    // liveActivityProvider watch (which keeps shedClientProvider alive), so the
    // client isn't disposed out from under the fetch.
    // `mounted` because a screen can be pushed and popped before its first
    // post-frame callback runs (an immediate programmatic replace), and
    // `_reload` calls setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Append [msgs] to [into], enforcing strictly increasing POSITIVE seqs:
  /// non-positive, duplicate, and regressing seqs are skipped. seq is
  /// guest-controlled data — a duplicate would produce duplicate ValueKeys
  /// (ListView crash) and a non-advancing seq would spin the pagination loop.
  /// Returns how many messages were appended.
  static int _addMonotonic(
    List<BridgeRcFeedMessage> into,
    List<BridgeRcFeedMessage> msgs,
  ) {
    var last = into.isEmpty ? BigInt.zero : into.last.seq;
    var added = 0;
    for (final m in msgs) {
      if (m.seq <= last) continue;
      into.add(m);
      last = m.seq;
      added++;
    }
    return added;
  }

  Future<void> _reload() async {
    final gen = ++_generation; // invalidates any in-flight append/older reload
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final acc = <BridgeRcFeedMessage>[];
      var cursor = BigInt.zero;
      var truncated = false;
      var first = true;
      var restarted = false;
      while (true) {
        final page = await widget.source.messages(
          ref,
          since: cursor,
          limit: _pageLimit,
        );
        if (!mounted || gen != _generation) return; // superseded
        if (page.truncated) {
          if (first || restarted) {
            // Head-of-ring drop (normal drop-oldest) — or we already restarted
            // once: record the gap and keep going rather than looping forever.
            truncated = true;
          } else {
            // The ring dropped/restarted MID-pagination (a later page reported
            // a stale cursor): restart the whole backfill once from scratch.
            restarted = true;
            acc.clear();
            cursor = BigInt.zero;
            first = true;
            continue;
          }
        }
        first = false;
        final added = _addMonotonic(acc, page.messages);
        if (page.messages.length < _pageLimit) break; // reached the tail
        final maxSeq = acc.isEmpty ? BigInt.zero : acc.last.seq;
        // Strictly-increasing cursor guard: a full page that doesn't advance
        // the cursor (all-duplicate / non-positive seqs) must stop, not spin.
        if (added == 0 || maxSeq <= cursor) break;
        cursor = maxSeq;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(acc);
        _historyTruncated = truncated;
        _lastSeq = acc.isEmpty ? BigInt.zero : acc.last.seq;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      // Broad catch: transport failures (SocketException/Handshake…) from the
      // pinned client are unwrapped, not AppError — either way the screen must
      // land in the error state, never stuck on _loading forever.
      if (!mounted || gen != _generation) return;
      setState(() {
        _loadError = appErrorFrom(e);
        _loading = false;
      });
    }
  }

  /// Drain everything past [_lastSeq] into the feed (triggered by a
  /// `message.appended` seq bump). A `truncated` page means the cursor is stale
  /// (the ring dropped messages or restarted, resetting seq) → full refetch.
  Future<void> _appendNew() async {
    // A bump that lands while a drain is in flight is NOT dropped — it is
    // remembered and drained when this one finishes. Returning early used to
    // lose it outright: the seq was already marked seen, so nothing would fetch
    // that message until some *later* message happened to arrive. On a session
    // that then went quiet, the last thing it said stayed invisible.
    if (_appending || _loading) {
      _appendAgain = true;
      return;
    }
    _appending = true;
    final gen = _generation; // abort if a reload supersedes this drain
    try {
      while (mounted && gen == _generation) {
        final page = await widget.source.messages(
          ref,
          since: _lastSeq,
          limit: _pageLimit,
        );
        if (!mounted || gen != _generation) return;
        if (page.truncated) {
          await _reload();
          return;
        }
        if (page.messages.isEmpty) break;
        var added = 0;
        setState(() {
          added = _addMonotonic(_messages, page.messages);
          if (added > 0) _lastSeq = _messages.last.seq;
        });
        if (added == 0) break; // nothing advanced — don't spin
        _scrollToBottom();
        if (page.messages.length < _pageLimit) break;
      }
    } catch (_) {
      // A transient append failure (AppError or raw transport) is non-fatal —
      // the next seq bump (or a manual refresh) retries. Don't clobber the
      // rendered feed with an error state.
    } finally {
      _appending = false;
    }
    // Drain again for anything that arrived while we were busy.
    if (_appendAgain && mounted) {
      _appendAgain = false;
      await _appendNew();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// Send what is typed, by whichever verb this KIND accepts.
  ///
  /// `turn` and `gated` are not two features to choose between — they are how
  /// two different kinds of agent take direction, and offering the wrong one
  /// earns a 409 the user cannot act on. One text field, one Send, and the verb
  /// resolved from `kind_features`.
  Future<void> _send({required bool asTurn}) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (asTurn) {
        await widget.source.steer(ref, text);
      } else {
        await widget.source.sendInput(ref, text);
      }
      if (!mounted) return; // the controller is disposed with the screen
      _input.clear();
      logDriveResult('session-watch-input', ok: true);
    } catch (e) {
      // Broad catch: raw transport failures must land in the snackbar path
      // like an AppError would, not escape as an unhandled async exception.
      logDriveResult('session-watch-input', ok: false, error: e);
      if (!mounted) return;
      final err = appErrorFrom(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err.statusCode == 409
                ? 'The session is not accepting that right now'
                : 'Send failed: ${err.message}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openTui() {
    logDriveResult('session-watch-handoff', ok: true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(target: widget.source.terminalTarget),
      ),
    );
  }

  /// Stop the running turn. Offered only for a kind that advertises it, and the
  /// answer `false` ("nothing was running") is reported as information rather
  /// than an error — it is a legitimate outcome of asking.
  Future<void> _interrupt() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final stopped = await widget.source.interrupt(ref);
      logDriveResult('session-watch-interrupt', ok: true);
      if (!mounted) return;
      if (!stopped) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nothing was running')));
      }
    } catch (e) {
      logDriveResult('session-watch-interrupt', ok: false, error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Interrupt failed: ${appErrorFrom(e).message}')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The live view, however this source obtains it — the screen never learns
    // whether it is looking at a shed or a machine.
    final live = widget.source.watch(ref);
    _reactToSeq(live.lastSeq);

    final state = live.state;
    final activity = live.activity;
    final kf = live.features;

    // **Every affordance below is gated on kind_features, never on the kind.**
    // A kind takes direction as a structured TURN or as a gated keystroke, and
    // offering the wrong one produces a 409 the user cannot act on.
    final permits = rcStatePermitsActivity(state);
    final asTurn = kf?.input == 'turn';
    // A turn kind accepts direction whenever it is alive. A `gated` kind takes
    // a line whenever it is not blocked on a DECISION — including while it is
    // working: codex and cursor are TUIs that queue typing mid-turn (codex even
    // says "tab to queue message"), and the hub delivers accordingly. Gating
    // the box on needs_input hid it during exactly the turn a person most wants
    // to correct.
    //
    // needs_approval is the one activity that still closes it: there a line
    // does not queue, it ANSWERS the dialog on screen.
    final inputAvailable =
        permits &&
        (asTurn ||
            ((kf?.inputGated ?? false) &&
                activity != BridgeRcActivity.needsApproval));
    final canInterrupt = (kf?.interrupt ?? false) && permits;
    // needs-auth / dead → the feed can't drive the session; hand off to the TUI.
    final blocked =
        state == BridgeRcState.needsAuth || state == BridgeRcState.dead;

    logDriveState(
      'screen=session-watch title=${widget.source.title} '
      'slug=$_slug state=${state.wire} activity=${activity?.wire ?? 'none'} '
      'msgs=${_messages.length} truncated=$_historyTruncated '
      'verb=${asTurn ? 'turn' : 'input'} '
      'input=${inputAvailable ? 'enabled' : (blocked ? 'blocked' : 'disabled')} '
      'interrupt=${canInterrupt ? 'offered' : 'hidden'}',
    );

    return Scaffold(
      key: const ValueKey('session-watch-screen'),
      appBar: AppBar(
        // Two lines, because one could not hold both. The SLUG is what you
        // came looking for and gets the emphasis; the origin answers "which
        // box am I on", which matters more now that a shed and a machine
        // render identically. The status badge moved OUT of the actions row —
        // with three icons beside it the title was truncating to `8c8…`,
        // which is the one thing here that cannot be inferred from context.
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_slug, style: const TextStyle(fontSize: 17)),
            Text(
              widget.source.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.shed.fg3),
            ),
          ],
        ),
        actions: [
          if (canInterrupt)
            IconButton(
              key: const ValueKey('session-watch-interrupt'),
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Interrupt',
              onPressed: _sending ? null : _interrupt,
            ),
          // The terminal is always one tap away, not only when the feed fails.
          // Some kinds have no feed at all, and for the rest the TUI is where
          // you go when the rendered view is not telling you enough.
          IconButton(
            key: const ValueKey('session-watch-open-tui-action'),
            icon: const Icon(Icons.terminal),
            tooltip: 'Terminal',
            onPressed: _openTui,
          ),
          IconButton(
            key: const ValueKey('session-watch-refresh'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // The status strip: what the session is doing right now, on its own
          // line where it has room to say so.
          _statusStrip(context, activity, state),
          if (blocked) _handoffBanner(context, state),
          Expanded(child: _feedBody(context)),
          if (!_loading && _loadError == null)
            _inputBar(context, enabled: inputAvailable, asTurn: asTurn),
        ],
      ),
    );
  }

  /// Drain or refetch when the feed's high-water mark moves.
  ///
  /// A LOWER seq means the hub restarted (seq is monotonic per hub run and
  /// resets to 1), so the cursor belongs to a previous incarnation and a
  /// targeted drain would stall on empty pages forever — refetch instead.
  void _reactToSeq(BigInt? seq) {
    // The feed went away (a reconnect cleared the overlay). What is on screen
    // belongs to a connection that no longer exists, so the next non-null seq
    // must be acted on even if it repeats a number we have already seen — a new
    // hub run restarts its counter, and `seq == _seenSeq` across that boundary
    // is a coincidence, not a duplicate.
    if (seq == null) {
      _seenSeq = null;
      return;
    }
    if (seq == _seenSeq) return;
    _seenSeq = seq;
    // Deferred: this runs during build, and both paths call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (seq < _lastSeq) {
        _reload();
      } else if (seq > _lastSeq) {
        _appendNew();
      }
    });
  }

  /// A thin full-width strip under the app bar carrying the lifecycle and the
  /// live activity. Full width because "needs approval" and "reconnecting" are
  /// sentences a person reads, and squeezing them beside three icons is how
  /// they get truncated into uselessness.
  Widget _statusStrip(
    BuildContext context,
    BridgeRcActivity? activity,
    BridgeRcState state,
  ) {
    final c = context.shed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          StatusBadge(
            key: const ValueKey('session-watch-state'),
            tone: shedStatusTone(state.wire).tone,
            label: state.wire.replaceAll('-', ' '),
          ),
          const SizedBox(width: 8),
          _activityBadge(activity, state),
        ],
      ),
    );
  }

  Widget _activityBadge(BridgeRcActivity? activity, BridgeRcState state) {
    final d = rcActivityBadge(state, activity);
    if (d == null) return const SizedBox.shrink();
    return StatusBadge(
      key: const ValueKey('session-watch-activity'),
      tone: d.tone,
      label: d.label,
      pulse: d.pulse,
    );
  }

  Widget _feedBody(BuildContext context) {
    final c = context.shed;
    if (_loading) {
      return const Center(
        key: ValueKey('session-watch-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final err = _loadError;
    if (err != null) {
      final app = err is AppError ? err : null;
      final unavailable =
          app != null &&
          (app.statusCode == 503 || app.code == 'RC_HUB_UNAVAILABLE');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unavailable
                    ? 'Live view unavailable on this shed'
                    : 'Could not load the feed: ${app?.message ?? err}',
                key: ValueKey(
                  unavailable
                      ? 'session-watch-unavailable'
                      : 'session-watch-error',
                ),
                textAlign: TextAlign.center,
                style: sansStyle(fontSize: 14, color: c.fg2),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('session-watch-retry'),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('session-watch-open-tui'),
                    onPressed: _openTui,
                    icon: const Icon(Icons.terminal, size: 18),
                    label: const Text('Open terminal'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet',
          key: const ValueKey('session-watch-empty'),
          style: sansStyle(fontSize: 14, color: c.fg3),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('session-watch-list'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 10),
      // Leading extra slot for the truncation divider when applicable.
      itemCount: _messages.length + (_historyTruncated ? 1 : 0),
      itemBuilder: (context, i) {
        if (_historyTruncated && i == 0) {
          return const RcTruncatedDivider(
            key: ValueKey('session-watch-truncated'),
          );
        }
        final msg = _messages[i - (_historyTruncated ? 1 : 0)];
        return RcMessageTile(
          key: ValueKey('session-watch-msg-${msg.seq}'),
          msg: msg,
        );
      },
    );
  }

  Widget _handoffBanner(BuildContext context, BridgeRcState state) {
    final c = context.shed;
    final label = state == BridgeRcState.dead
        ? 'Session ended'
        : 'Session needs sign-in';
    return Container(
      key: const ValueKey('session-watch-banner'),
      width: double.infinity,
      color: c.toneBg(ShedStatusTone.warn),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label — open the terminal to continue.',
              style: monoStyle(
                fontSize: 12.5,
                color: c.toneFg(ShedStatusTone.warn),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            // Suffixed -banner: the error/unavailable body carries the plain
            // session-watch-open-tui key, and both can never share one key (the
            // banner + error body can be on screen together).
            key: const ValueKey('session-watch-open-tui-banner'),
            onPressed: _openTui,
            icon: const Icon(Icons.terminal, size: 18),
            label: const Text('Terminal'),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(
    BuildContext context, {
    required bool enabled,
    required bool asTurn,
  }) {
    final c = context.shed;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('session-watch-input'),
                controller: _input,
                enabled: enabled && !_sending,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => enabled ? _send(asTurn: asTurn) : null,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: enabled
                      ? (asTurn ? 'What should it do next?' : 'Reply…')
                      : 'Waiting for the session to ask',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton.filled(
                    key: const ValueKey('session-watch-send'),
                    onPressed: enabled ? () => _send(asTurn: asTurn) : null,
                    icon: const Icon(Icons.send, size: 20),
                    tooltip: 'Send',
                  ),
          ],
        ),
      ),
    );
  }
}

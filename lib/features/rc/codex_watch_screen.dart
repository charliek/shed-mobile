import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../core/app_error.dart';
import '../../providers.dart';
import '../../rc/rc_feed.dart';
import '../../rc/rc_models.dart';
import '../../shed/shed_status.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/status_badge.dart';
import '../terminal/terminal_screen.dart';

/// The codex non-TUI "watch" view: a read-only rendering of a session's message
/// feed (`GET /api/sheds/{shed}/rc/v1/sessions/{slug}/messages`) with a gated
/// input bar. Messages are hub-sanitized, so they render as plain [Text] — no
/// markdown. Live append rides the host's `GET /api/rc/events` stream via
/// [liveActivityProvider] (the `message.appended` seq bump triggers a targeted
/// /messages fetch). Anything the feed can't serve (needs-auth/dead lifecycle,
/// hub unavailable) hands off to the in-app TUI terminal.
class CodexWatchScreen extends ConsumerStatefulWidget {
  const CodexWatchScreen({
    required this.serverName,
    required this.shedName,
    required this.session,
    super.key,
  });

  final String serverName;
  final String shedName;
  final RcSession session;

  @override
  ConsumerState<CodexWatchScreen> createState() => _CodexWatchScreenState();
}

class _CodexWatchScreenState extends ConsumerState<CodexWatchScreen> {
  static const int _pageLimit = 200;

  final _messages = <RcFeedMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  Object? _loadError;
  bool _historyTruncated = false;
  int _lastSeq = 0;
  bool _sending = false;
  bool _appending = false;

  /// Bumped at the start of every [_reload]; in-flight [_appendNew] drains (and
  /// stale [_reload]s) capture it and abort when it moves, so a reload can never
  /// race an append into duplicate rows (duplicate seq ValueKeys would crash the
  /// ListView).
  int _generation = 0;

  String get _slug => widget.session.slug;

  @override
  void initState() {
    super.initState();
    // Defer the first load until after the initial build has established the
    // liveActivityProvider watch (which keeps shedClientProvider alive), so the
    // client isn't disposed out from under the fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
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
  static int _addMonotonic(List<RcFeedMessage> into, List<RcFeedMessage> msgs) {
    var last = into.isEmpty ? 0 : into.last.seq;
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
      final client = await ref.read(
        shedClientProvider(widget.serverName).future,
      );
      final acc = <RcFeedMessage>[];
      var cursor = 0;
      var truncated = false;
      var first = true;
      var restarted = false;
      while (true) {
        final page = rcMessagesPageFromBridge(
          await client.rcMessages(
            shed: widget.shedName,
            slug: _slug,
            since: BigInt.from(cursor),
            limit: _pageLimit,
          ),
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
            cursor = 0;
            first = true;
            continue;
          }
        }
        first = false;
        final added = _addMonotonic(acc, page.messages);
        if (page.messages.length < _pageLimit) break; // reached the tail
        final maxSeq = acc.isEmpty ? 0 : acc.last.seq;
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
        _lastSeq = acc.isEmpty ? 0 : acc.last.seq;
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
    if (_appending || _loading) return;
    _appending = true;
    final gen = _generation; // abort if a reload supersedes this drain
    try {
      final client = await ref.read(
        shedClientProvider(widget.serverName).future,
      );
      while (mounted && gen == _generation) {
        final page = rcMessagesPageFromBridge(
          await client.rcMessages(
            shed: widget.shedName,
            slug: _slug,
            since: BigInt.from(_lastSeq),
            limit: _pageLimit,
          ),
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final client = await ref.read(
        shedClientProvider(widget.serverName).future,
      );
      await client.rcInput(shed: widget.shedName, slug: _slug, text: text);
      if (!mounted) return; // the controller is disposed with the screen
      _input.clear();
      logDriveResult('codex-watch-input', ok: true);
    } catch (e) {
      // Broad catch: raw transport failures must land in the snackbar path
      // like an AppError would, not escape as an unhandled async exception.
      logDriveResult('codex-watch-input', ok: false, error: e);
      if (!mounted) return;
      final err = appErrorFrom(e);
      // 409 = the session stopped waiting between the gate check and the post
      // (a race). Refresh the base state so the input bar re-gates correctly.
      if (err.statusCode == 409) {
        ref.invalidate(overviewProvider(widget.serverName));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err.statusCode == 409
                ? 'Session is no longer waiting for input'
                : 'Send failed: ${err.message}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openTui() {
    logDriveResult('codex-watch-handoff', ok: true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          serverName: widget.serverName,
          shedName: widget.shedName,
          slug: _slug,
          title: '${widget.shedName}/$_slug',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;

    // Overlay the live SSE patch onto the base session for state/activity, and
    // react to the feed's latest-seq bumps by draining new messages.
    final patch = ref.watch(
      liveActivityProvider(
        widget.serverName,
      ).select((a) => a.value?.lookup(widget.shedName, _slug)),
    );
    ref.listen(
      liveActivityProvider(
        widget.serverName,
      ).select((a) => a.value?.lookup(widget.shedName, _slug)?.lastSeq),
      (prev, next) {
        if (next == null) return;
        if (next < _lastSeq) {
          // The hub restarted (seq is monotonic per hub run and resets to 1):
          // our cursor is from a previous incarnation, so a targeted drain
          // would stall on empty/truncated pages forever — full refetch.
          _reload();
        } else if (next > _lastSeq) {
          _appendNew();
        }
      },
    );

    final state = patch?.state ?? s.state;
    final activity = patch?.activity ?? s.activity;
    final caps = ref
        .watch(
          shedCapabilitiesProvider((
            serverName: widget.serverName,
            shedName: widget.shedName,
          )),
        )
        .value;
    final kf = caps?.kindFeatures[s.kind.wire];

    // Input is only ever enabled for a gated kind that is actively waiting AND
    // whose lifecycle permits it (needs-*/dead never accept input).
    final inputAvailable =
        (kf?.inputGated ?? false) &&
        rcStatePermitsActivity(state) &&
        activity == RcActivity.needsInput;
    // needs-auth / dead → the feed can't drive the session; hand off to the TUI.
    final blocked = state == RcState.needsAuth || state == RcState.dead;

    logDriveState(
      'screen=codex-watch server=${widget.serverName} shed=${widget.shedName} '
      'slug=$_slug state=${state.wire} activity=${activity?.wire ?? 'none'} '
      'msgs=${_messages.length} truncated=$_historyTruncated '
      'input=${inputAvailable ? 'enabled' : (blocked ? 'blocked' : 'disabled')}',
    );

    return Scaffold(
      key: const ValueKey('codex-watch-screen'),
      appBar: AppBar(
        title: Text(_slug),
        actions: [
          _activityBadge(activity, state),
          IconButton(
            key: const ValueKey('codex-watch-refresh'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          if (blocked) _handoffBanner(context, state),
          Expanded(child: _feedBody(context)),
          if (!_loading && _loadError == null)
            _inputBar(context, enabled: inputAvailable),
        ],
      ),
    );
  }

  Widget _activityBadge(RcActivity? activity, RcState state) {
    final d = rcActivityBadge(state, activity);
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Center(
        child: StatusBadge(
          key: const ValueKey('codex-watch-activity'),
          tone: d.tone,
          label: d.label,
          pulse: d.pulse,
        ),
      ),
    );
  }

  Widget _feedBody(BuildContext context) {
    final c = context.shed;
    if (_loading) {
      return const Center(
        key: ValueKey('codex-watch-loading'),
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
                  unavailable ? 'codex-watch-unavailable' : 'codex-watch-error',
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
                    key: const ValueKey('codex-watch-retry'),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('codex-watch-open-tui'),
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
          key: const ValueKey('codex-watch-empty'),
          style: sansStyle(fontSize: 14, color: c.fg3),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('codex-watch-list'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 10),
      // Leading extra slot for the truncation divider when applicable.
      itemCount: _messages.length + (_historyTruncated ? 1 : 0),
      itemBuilder: (context, i) {
        if (_historyTruncated && i == 0) return const _TruncatedDivider();
        final msg = _messages[i - (_historyTruncated ? 1 : 0)];
        return _MessageTile(
          key: ValueKey('codex-watch-msg-${msg.seq}'),
          msg: msg,
        );
      },
    );
  }

  Widget _handoffBanner(BuildContext context, RcState state) {
    final c = context.shed;
    final label = state == RcState.dead
        ? 'Session ended'
        : 'Session needs sign-in';
    return Container(
      key: const ValueKey('codex-watch-banner'),
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
            // codex-watch-open-tui key, and both can never share one key (the
            // banner + error body can be on screen together).
            key: const ValueKey('codex-watch-open-tui-banner'),
            onPressed: _openTui,
            icon: const Icon(Icons.terminal, size: 18),
            label: const Text('Terminal'),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context, {required bool enabled}) {
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
                key: const ValueKey('codex-watch-input'),
                controller: _input,
                enabled: enabled && !_sending,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => enabled ? _send() : null,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: enabled
                      ? 'Reply to codex…'
                      : 'Input available when codex is waiting',
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
                    key: const ValueKey('codex-watch-send'),
                    onPressed: enabled ? _send : null,
                    icon: const Icon(Icons.send, size: 20),
                    tooltip: 'Send',
                  ),
          ],
        ),
      ),
    );
  }
}

/// The "history truncated" marker shown at the top of the feed when the hub ring
/// dropped messages older than the earliest retained one.
class _TruncatedDivider extends StatelessWidget {
  const _TruncatedDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Padding(
      key: const ValueKey('codex-watch-truncated'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.line)),
          const SizedBox(width: 10),
          Text(
            'earlier history truncated',
            style: monoStyle(fontSize: 10.5, color: c.fg3),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: c.line)),
        ],
      ),
    );
  }
}

/// One feed message, rendered as plain text with role/type styling: user
/// right-aligned, assistant plain, tool blocks collapsed to a single mono line,
/// reasoning/status dimmed. No markdown — the hub already stripped ANSI/control.
class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.msg, super.key});

  final RcFeedMessage msg;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final pad = const EdgeInsets.fromLTRB(16, 5, 16, 5);

    if (msg.type == 'tool_use' || msg.type == 'tool_result') {
      final tool = msg.tool;
      final name = tool?.name ?? msg.type;
      final detail = tool?.detail;
      return Padding(
        padding: pad,
        child: Text(
          detail == null ? '⚙ $name' : '⚙ $name — $detail',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: monoStyle(fontSize: 11.5, color: c.fg3),
        ),
      );
    }

    if (msg.type == 'reasoning' ||
        msg.type == 'status' ||
        msg.role == 'system') {
      return Padding(
        padding: pad,
        child: Text(
          msg.text ?? '',
          style: sansStyle(fontSize: 12.5, color: c.fg3),
        ),
      );
    }

    final isUser = msg.role == 'user';
    return Padding(
      padding: pad,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser ? c.toneBg(ShedStatusTone.ok) : c.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            msg.text ?? '',
            style: sansStyle(
              fontSize: 13.5,
              color: isUser ? c.toneFg(ShedStatusTone.ok) : c.fg,
            ),
          ),
        ),
      ),
    );
  }
}

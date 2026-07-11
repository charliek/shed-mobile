// The codex message feed served by the rc hub through the server proxy
// (`GET /api/sheds/{name}/rc/v1/sessions/{slug}/messages`). Mirrors the guest's
// `feedMessage` / `hubMessagesResponse` (`internal/ext/rc/hub_messages.go`):
// each message is already sanitized (ANSI/control-stripped, per-field capped)
// by the hub, so the client renders it as plain text — no markdown. The one
// client-side addition: Unicode format characters (category Cf — bidi
// overrides like U+202E) are stripped from display text at decode, because the
// hub's sanitizer covers ANSI + C0/C1 controls but not Cf, and a bidi override
// can visually reverse what a rendered message appears to say.

import '../core/text_sanitize.dart';

/// One tool call/result block on a feed message: a name plus a compact detail
/// (invocation args for a `tool_use`, output for a `tool_result`). Both are
/// hub-sanitized; either may be absent.
class RcFeedTool {
  const RcFeedTool({this.name, this.detail});
  final String? name;
  final String? detail;

  factory RcFeedTool.fromJson(Map<String, Object?> j) =>
      RcFeedTool(name: _text(j['name']), detail: _text(j['detail']));
}

/// One normalized conversation message in the feed. `role` ∈ {user, assistant,
/// tool, system}; `type` ∈ {text, tool_use, tool_result, reasoning, status}.
/// `seq` is monotonic per hub run (restarts from 1 on hub restart — a client
/// that sees a seq lower than one it holds does a full refetch).
class RcFeedMessage {
  const RcFeedMessage({
    required this.seq,
    this.ts,
    required this.role,
    required this.type,
    this.text,
    this.tool,
  });

  final int seq;
  final String? ts;
  final String role;
  final String type;
  final String? text;
  final RcFeedTool? tool;

  factory RcFeedMessage.fromJson(Map<String, Object?> j) {
    final rawTool = j['tool'];
    return RcFeedMessage(
      seq: _int(j['seq']),
      ts: _str(j['ts']),
      role: _str(j['role']) ?? '',
      type: _str(j['type']) ?? '',
      text: _text(j['text']),
      tool: rawTool is Map<String, Object?>
          ? RcFeedTool.fromJson(rawTool)
          : null,
    );
  }
}

/// A page of the feed: `GET …/messages?since=<seq>&limit=<n>`. [truncated] means
/// the requested `since` cursor predates the ring (drop-oldest discarded unseen
/// messages) OR points beyond the ring's current tail (the ring restarted) — in
/// either case the client must refetch from the earliest retained message.
class RcMessagesPage {
  const RcMessagesPage({required this.messages, required this.truncated});
  final List<RcFeedMessage> messages;
  final bool truncated;

  factory RcMessagesPage.fromJson(Map<String, Object?> j) {
    final raw = j['messages'];
    return RcMessagesPage(
      messages: <RcFeedMessage>[
        if (raw is List)
          for (final m in raw)
            if (m is Map<String, Object?>) RcFeedMessage.fromJson(m),
      ],
      truncated: j['truncated'] == true,
    );
  }
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// [_str] plus the Cf strip — for guest-controlled display text (message text,
/// tool name/detail).
String? _text(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  final t = stripFormatChars(s).trim();
  return t.isEmpty ? null : t;
}

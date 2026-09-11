/// **The row widgets a `BridgeRcFeedMessage` transcript is made of** — shared by
/// the RC watch screen and the agent-lane screen (plan 018 §3.12).
///
/// They live here rather than inside either screen because the two screens
/// render the SAME type: a lane's transcript rows are `RcFeedMessage`s (the
/// contract chose that deliberately, so a lane row sorts into the same views an
/// RC row does). Two copies of this styling would drift, and the drift would be
/// invisible — the same message rendered two ways on two screens of one app.
///
/// Nothing here knows where its message came from: no transport, no provider,
/// no keys of its own. The caller supplies the key, which is what lets the two
/// screens keep their own drive-key namespaces (`session-watch-msg-<seq>` vs
/// `lane-msg-<seq>`) over one widget.
library;

import 'package:flutter/material.dart';

import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';

/// One feed message, rendered as plain text with role/type styling: user
/// right-aligned, assistant plain, tool blocks collapsed to a single mono line,
/// reasoning/status dimmed. No markdown — the hub already stripped ANSI/control.
class RcMessageTile extends StatelessWidget {
  const RcMessageTile({required this.msg, super.key});

  final BridgeRcFeedMessage msg;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final pad = const EdgeInsets.fromLTRB(16, 5, 16, 5);

    if (msg.msgType == 'tool_use' || msg.msgType == 'tool_result') {
      final tool = msg.tool;
      final name = tool?.name ?? msg.msgType;
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

    if (msg.msgType == 'reasoning' ||
        msg.msgType == 'status' ||
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

/// The "history truncated" marker shown at the top of a feed whose ring dropped
/// messages older than the earliest retained one.
///
/// Not a message row — it carries no [BridgeRcFeedMessage] — but it belongs to
/// the same transcript, and the caller keys it (`session-watch-truncated`).
class RcTruncatedDivider extends StatelessWidget {
  const RcTruncatedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Padding(
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

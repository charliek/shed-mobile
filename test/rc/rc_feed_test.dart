import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/rc/rc_feed.dart';

RcMessagesPage _page(String json) =>
    RcMessagesPage.fromJson(jsonDecode(json) as Map<String, Object?>);

void main() {
  group('RcMessagesPage.fromJson', () {
    test('decodes a mixed feed page with text + tool blocks', () {
      final p = _page('''
      {
        "messages": [
          {"seq": 1, "ts": "2026-06-19T18:53:00Z", "role": "user", "type": "text", "text": "hi"},
          {"seq": 2, "role": "assistant", "type": "reasoning", "text": "thinking"},
          {"seq": 3, "role": "tool", "type": "tool_use",
           "tool": {"name": "shell", "detail": "ls -la"}}
        ],
        "truncated": false
      }
      ''');
      expect(p.messages, hasLength(3));
      expect(p.truncated, isFalse);
      expect(p.messages[0].role, 'user');
      expect(p.messages[0].text, 'hi');
      expect(p.messages[1].type, 'reasoning');
      expect(p.messages[2].tool!.name, 'shell');
      expect(p.messages[2].tool!.detail, 'ls -la');
      expect(p.messages[2].text, isNull);
    });

    test('truncated flag + empty page decode ([] not null)', () {
      final p = _page('{"messages": [], "truncated": true}');
      expect(p.messages, isEmpty);
      expect(p.truncated, isTrue);
    });

    test('tolerates a missing messages key / absent fields', () {
      final p = _page('{"truncated": false}');
      expect(p.messages, isEmpty);
      final one = _page(
        '{"messages":[{"seq":5,"role":"system","type":"status"}]}',
      );
      expect(one.messages.single.seq, 5);
      expect(one.messages.single.ts, isNull);
      expect(one.messages.single.text, isNull);
      expect(one.messages.single.tool, isNull);
    });

    test('strips Unicode format chars (bidi override / zero-width) from '
        'text and tool fields', () {
      // The hub strips ANSI + C0/C1 controls but not category Cf: a U+202E
      // (RLO) can visually reverse rendered text; U+200B hides content. Raw
      // strings keep the \u escapes for the JSON decoder to expand.
      final p = _page(
        r'{"messages":[{"seq":1,"role":"assistant","type":"text",'
        r'"text":"safe\u202e EVIL"},'
        r'{"seq":2,"role":"tool","type":"tool_use",'
        r'"tool":{"name":"sh\u200bell","detail":"rm\u202e x"}}]}',
      );
      expect(p.messages[0].text, 'safe EVIL');
      expect(p.messages[1].tool!.name, 'shell');
      expect(p.messages[1].tool!.detail, 'rm x');
    });
  });
}

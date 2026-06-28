import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/shed/shed_status.dart';
import 'package:shed_mobile/theme/shed_colors.dart';

void main() {
  group('shedStatusTone', () {
    test('ok family: running/ready/online → ok ● (no pulse)', () {
      for (final s in ['running', 'ready', 'online']) {
        final d = shedStatusTone(s);
        expect(d.tone, ShedStatusTone.ok, reason: s);
        expect(d.dot, '●');
        expect(d.pulse, isFalse);
      }
    });

    test('starting pulses; working/reconnecting are steady warn', () {
      expect(shedStatusTone('starting').pulse, isTrue);
      expect(shedStatusTone('starting').tone, ShedStatusTone.warn);
      expect(shedStatusTone('working').pulse, isFalse);
      expect(shedStatusTone('working').tone, ShedStatusTone.warn);
      expect(shedStatusTone('reconnecting').tone, ShedStatusTone.warn);
      expect(shedStatusTone('needs-auth').tone, ShedStatusTone.warn);
    });

    test('idle family: stopped/idle/offline → idle ○', () {
      for (final s in ['stopped', 'idle', 'offline']) {
        expect(shedStatusTone(s).tone, ShedStatusTone.idle, reason: s);
        expect(shedStatusTone(s).dot, '○');
      }
    });

    test('error/dead → err ▲ (the case the old toneFor was missing)', () {
      expect(shedStatusTone('error').tone, ShedStatusTone.err);
      expect(shedStatusTone('error').dot, '▲');
      expect(shedStatusTone('dead').tone, ShedStatusTone.err);
    });

    test('an unknown status falls back to idle (never crashes)', () {
      expect(shedStatusTone('wat').tone, ShedStatusTone.idle);
    });
  });

  group('kindColor', () {
    const c = ShedColors.light;
    test('claude kinds → claude accent', () {
      expect(kindColor(c, 'claude-rc'), c.kindClaude);
      expect(kindColor(c, 'claude-broker'), c.kindClaude);
    });
    test('codex kinds → codex accent', () {
      expect(kindColor(c, 'codex-rc'), c.kindCodex);
    });
    test('cursor / opencode → their own accents', () {
      expect(kindColor(c, 'cursor'), c.kindCursor);
      expect(kindColor(c, 'opencode'), c.kindOpencode);
    });
    test('shell and any unknown kind → shell grey, NEVER claude', () {
      expect(kindColor(c, 'shell'), c.kindShell);
      final unknown = kindColor(c, 'some-foreign-agent');
      expect(unknown, c.kindShell);
      expect(unknown, isNot(c.kindClaude));
    });
    test('is case-insensitive', () {
      expect(kindColor(c, 'Claude-RC'), c.kindClaude);
    });
  });
}

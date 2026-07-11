import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/rc/rc_models.dart';

void main() {
  group('RcKind.fromWire', () {
    test('decodes every known kind', () {
      expect(RcKind.fromWire('claude-rc'), RcKind.claudeRc);
      expect(RcKind.fromWire('claude-broker'), RcKind.claudeBroker);
      expect(RcKind.fromWire('codex'), RcKind.codex);
      expect(RcKind.fromWire('opencode'), RcKind.opencode);
      expect(RcKind.fromWire('cursor'), RcKind.cursor);
      expect(RcKind.fromWire('shell'), RcKind.shell);
    });

    test('an unknown/foreign kind is PRESERVED verbatim, not collapsed', () {
      // Unknown-kind policy: the raw wire string is kept and marked not-known so
      // it renders neutrally — it must NOT become claude-broker (that would grant
      // it claude affordances it should never get).
      final foreign = RcKind.fromWire('some-future-agent');
      expect(foreign.wire, 'some-future-agent');
      expect(foreign.known, isFalse);
      expect(foreign, isNot(RcKind.claudeBroker));
      // Neutral: not promptable, no claude posture.
      expect(foreign.acceptsPrompt, isFalse);
      expect(foreign.runsClaude, isFalse);
      expect(foreign.hasPermissionMode, isFalse);
      expect(foreign.tool, isNull);
    });

    test('null/empty preserve as an (empty) unknown kind', () {
      expect(RcKind.fromWire('').known, isFalse);
      expect(RcKind.fromWire(null).known, isFalse);
      expect(RcKind.fromWire(null).wire, '');
    });

    test('create-time default is claude-rc', () {
      expect(defaultRcKind, RcKind.claudeRc);
    });

    test('creatable excludes claude-broker and unknown kinds', () {
      expect(RcKind.creatable, [
        RcKind.claudeRc,
        RcKind.codex,
        RcKind.opencode,
        RcKind.cursor,
        RcKind.shell,
      ]);
      expect(RcKind.creatable, isNot(contains(RcKind.claudeBroker)));
    });

    test('acceptsPrompt: agents + shell yes; broker + unknown no', () {
      expect(RcKind.claudeRc.acceptsPrompt, isTrue);
      expect(RcKind.codex.acceptsPrompt, isTrue);
      expect(RcKind.cursor.acceptsPrompt, isTrue);
      expect(RcKind.opencode.acceptsPrompt, isTrue);
      expect(RcKind.shell.acceptsPrompt, isTrue);
      expect(RcKind.claudeBroker.acceptsPrompt, isFalse);
    });

    test('runsClaude: only the two claude kinds', () {
      expect(RcKind.claudeRc.runsClaude, isTrue);
      expect(RcKind.claudeBroker.runsClaude, isTrue);
      expect(RcKind.codex.runsClaude, isFalse);
      expect(RcKind.cursor.runsClaude, isFalse);
      expect(RcKind.opencode.runsClaude, isFalse);
      expect(RcKind.shell.runsClaude, isFalse);
    });

    test('hasPermissionMode: every known agent kind except shell', () {
      expect(RcKind.claudeRc.hasPermissionMode, isTrue);
      expect(RcKind.claudeBroker.hasPermissionMode, isTrue);
      expect(RcKind.codex.hasPermissionMode, isTrue);
      expect(RcKind.cursor.hasPermissionMode, isTrue);
      expect(RcKind.opencode.hasPermissionMode, isTrue);
      expect(RcKind.shell.hasPermissionMode, isFalse);
    });

    test('tool maps agent kinds to their token; shell/unknown null', () {
      expect(RcKind.claudeRc.tool, 'claude');
      expect(RcKind.claudeBroker.tool, 'claude');
      expect(RcKind.codex.tool, 'codex');
      expect(RcKind.opencode.tool, 'opencode');
      expect(RcKind.cursor.tool, 'cursor');
      expect(RcKind.shell.tool, isNull);
    });

    test('authHint carries per-agent login remediation', () {
      expect(RcKind.claudeRc.authHint, contains('/login'));
      expect(RcKind.codex.authHint, contains('codex login'));
      expect(RcKind.opencode.authHint, contains('opencode auth login'));
      expect(RcKind.cursor.authHint, contains('cursor-agent login'));
      expect(RcKind.shell.authHint, isNotEmpty);
      expect(RcKind.fromWire('x').authHint, isNotEmpty); // neutral fallback
    });
  });

  group('RcState.fromWire', () {
    test('decodes known states', () {
      for (final st in RcState.values) {
        expect(RcState.fromWire(st.wire), st);
      }
    });

    test('unknown/null reads as starting (transient, not dead)', () {
      expect(RcState.fromWire('paused'), RcState.starting);
      expect(RcState.fromWire(null), RcState.starting);
    });
  });

  group('RcSession.fromJson', () {
    test('fully-populated managed session', () {
      final s = RcSession.fromJson({
        'slug': 'abc234',
        'tmux_session': 'rc-abc234',
        'kind': 'claude-rc',
        'state': 'ready',
        'managed': true,
        'display_name': 'charliek/abc234',
        'workdir': '/home/shed',
        'url': 'https://claude.ai/code/session_01RCkTDrdZ2Rr12sD5dfMjgr',
        'id': '9f1c0e7a-1111-4222-8333-444455556666',
        'created_by': 'shed-remote-agent/0.1.0',
        'created_at': '2026-06-19T18:53:00Z',
        'target_label': 'shed:t1@localmac-dev',
      });
      expect(s.slug, 'abc234');
      expect(s.tmuxSession, 'rc-abc234');
      expect(s.kind, RcKind.claudeRc);
      expect(s.state, RcState.ready);
      expect(s.isReady, isTrue);
      expect(s.managed, isTrue);
      expect(s.displayName, 'charliek/abc234');
      expect(s.workdir, '/home/shed');
      expect(s.hasUrl, isTrue);
      expect(s.url, contains('session_'));
      expect(s.id, '9f1c0e7a-1111-4222-8333-444455556666');
      expect(s.createdBy, 'shed-remote-agent/0.1.0');
      expect(s.targetLabel, 'shed:t1@localmac-dev');
    });

    test('minimal session: optionals omitted, display name falls back', () {
      final s = RcSession.fromJson({
        'slug': 'brk900',
        'tmux_session': 'rc-brk900',
        'kind': 'claude-broker',
        'state': 'starting',
        'managed': false,
      }, displayNameFallback: (slug) => 'myshed/$slug');
      expect(s.kind, RcKind.claudeBroker);
      expect(s.state, RcState.starting);
      expect(s.managed, isFalse);
      expect(s.displayName, 'myshed/brk900'); // fallback applied
      expect(s.workdir, isNull);
      expect(s.url, isNull);
      expect(s.hasUrl, isFalse);
      expect(s.id, isNull);
      expect(s.createdBy, isNull);
      expect(s.createdAt, isNull);
      expect(s.targetLabel, isNull);
    });

    test('without a fallback, display name defaults to the slug', () {
      final s = RcSession.fromJson({
        'slug': 'brk900',
        'tmux_session': 'rc-brk900',
        'kind': 'claude-broker',
        'state': 'starting',
        'managed': false,
      });
      expect(s.displayName, 'brk900');
    });

    test('empty-string optionals are treated as absent', () {
      final s = RcSession.fromJson({
        'slug': 'x',
        'tmux_session': 'rc-x',
        'kind': 'shell',
        'state': 'ready',
        'managed': true,
        'workdir': '   ',
        'url': '',
      });
      expect(s.workdir, isNull);
      expect(s.url, isNull);
    });
  });

  // The cross-tool contract: this fixture is byte-identical to shed-extensions'
  // internal/rc/testdata/rcSessionDto.golden.json. If shed-ext-rc's stdout shape
  // drifts, this decode (and the Go/Swift consumers) break in lockstep.
  test('golden DTO fixture decodes (cross-tool contract)', () {
    final raw = File(
      'test/rc/testdata/rcSessionDto.golden.json',
    ).readAsStringSync();
    final obj = jsonDecode(raw) as Map<String, Object?>;
    final sessions = (obj['rc_sessions'] as List)
        .cast<Map<String, Object?>>()
        .map(
          (m) =>
              RcSession.fromJson(m, displayNameFallback: (s) => 'fallback/$s'),
        )
        .toList();
    expect(sessions, hasLength(2));

    final full = sessions[0];
    expect(full.kind, RcKind.claudeRc);
    expect(full.state, RcState.ready);
    expect(full.managed, isTrue);
    expect(full.id, isNotNull);
    expect(full.url, contains('session_'));
    expect(full.targetLabel, isNotEmpty);

    final minimal = sessions[1];
    expect(minimal.kind, RcKind.claudeBroker);
    expect(minimal.managed, isFalse);
    expect(minimal.displayName, 'fallback/brk900'); // omitted → fallback
    expect(minimal.workdir, isNull);
    expect(minimal.url, isNull);
    expect(minimal.id, isNull);
  });
}

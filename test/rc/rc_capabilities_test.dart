import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/rc/rc_capabilities.dart';
import 'package:shed_mobile/rc/rc_models.dart';

// A full capabilities block matching the shed repo's docs/extensions/rc-helper.md
// example (rc_version 3, claude installed, codex not).
const _fullJson = '''
{
  "rc_version": 3,
  "kinds": ["claude-broker", "claude-rc", "codex", "opencode", "cursor", "shell"],
  "agents": {
    "claude": { "installed": true, "version": "2.1.206" },
    "codex":  { "installed": false },
    "cursor": { "installed": true, "version": "2026.07.09" }
  },
  "features": ["generic-perm", "plan-stdin", "prompt-b64"],
  "kind_features": {
    "codex":  { "post_input": true, "approvals": "tui" },
    "cursor": { "post_input": true, "approvals": "tui" }
  }
}
''';

RcCapabilities _caps(String json) =>
    RcCapabilities.fromJson(jsonDecode(json) as Map<String, Object?>);

void main() {
  group('RcCapabilities.fromJson', () {
    test('parses rc_version, kinds, agents, features, kind_features', () {
      final c = _caps(_fullJson);
      expect(c.rcVersion, 3);
      expect(c.kinds, contains(RcKind.codex));
      expect(c.kinds, contains(RcKind.shell));
      expect(c.agents['claude']!.installed, isTrue);
      expect(c.agents['claude']!.version, '2.1.206');
      expect(c.agents['codex']!.installed, isFalse);
      expect(c.agents['codex']!.version, isNull); // omitted → null
      expect(c.features, containsAll(['generic-perm', 'plan-stdin']));
      expect(c.hasFeature('prompt-b64'), isTrue);
      expect(c.hasFeature('serve'), isFalse);
      expect(c.kindFeatures['codex']!.postInput, isTrue);
      expect(c.kindFeatures['codex']!.approvals, 'tui');
    });

    test('preserves an unknown kind in kinds (unknown-kind policy)', () {
      final c = _caps('{"rc_version":9,"kinds":["shell","some-future-agent"]}');
      expect(c.kinds, contains(RcKind.shell));
      final foreign = c.kinds.firstWhere((k) => !k.known);
      expect(foreign.wire, 'some-future-agent');
    });

    test('kind_features watch/input decode (codex gated feed)', () {
      final c = _caps('''
      {
        "rc_version": 3,
        "features": ["serve", "activity", "messages"],
        "kind_features": {
          "codex":  { "post_input": true, "approvals": "tui", "watch": true, "input": "gated" },
          "claude-rc": { "post_input": true, "approvals": "tui" }
        }
      }
      ''');
      final codex = c.kindFeatures['codex']!;
      expect(codex.watch, isTrue);
      expect(codex.input, 'gated');
      expect(codex.inputGated, isTrue);
      // A kind without the additive fields decodes to the safe defaults.
      final claude = c.kindFeatures['claude-rc']!;
      expect(claude.watch, isFalse);
      expect(claude.input, '');
      expect(claude.inputGated, isFalse);
      expect(c.hasFeature('messages'), isTrue);
    });

    test('tolerates a partial payload (missing lists/maps → empty)', () {
      final c = _caps('{"rc_version":3}');
      expect(c.kinds, isEmpty);
      expect(c.agents, isEmpty);
      expect(c.features, isEmpty);
      expect(c.kindFeatures, isEmpty);
    });
  });

  group('offers / creatableKinds', () {
    test('offers a kind only when advertised AND its agent is installed', () {
      final c = _caps(_fullJson);
      // claude installed + advertised → offered.
      expect(c.offers(RcKind.claudeRc), isTrue);
      // codex advertised but NOT installed → not offered.
      expect(c.offers(RcKind.codex), isFalse);
      // cursor advertised + installed → offered.
      expect(c.offers(RcKind.cursor), isTrue);
      // shell has no agent → offered whenever advertised.
      expect(c.offers(RcKind.shell), isTrue);
      // opencode advertised but has no agents{} entry → not installed → no.
      expect(c.offers(RcKind.opencode), isFalse);
    });

    test('creatableKinds is the gated create-form order (broker excluded)', () {
      final c = _caps(_fullJson);
      expect(c.creatableKinds(), [
        RcKind.claudeRc,
        RcKind.cursor,
        RcKind.shell,
      ]);
      // claude-broker is never creatable even though it's advertised.
      expect(c.creatableKinds(), isNot(contains(RcKind.claudeBroker)));
    });

    test('present-but-empty capabilities offer NO creatable kinds', () {
      final c = _caps('{"rc_version":3,"kinds":[],"agents":{}}');
      expect(c.kinds, isEmpty);
      expect(c.creatableKinds(), isEmpty);
      expect(c.offers(RcKind.shell), isFalse); // not advertised → not offered
    });
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/rc/rc_ui.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';

/// Coverage for the UI-only RC helpers re-homed onto the bridge types in B4
/// (`lib/rc/rc_ui.dart`) — the wire↔enum mapping, the kind predicates, the
/// capability gating, the permission-mode sets, and `genSlug`. The Rust-owned
/// halves (permission-mode VALIDATION, argv/decode) are covered by the Rust
/// `rc_runner`/`dto_rc` tests.

void main() {
  group('BridgeRcKind wire + predicates', () {
    test('wire round-trips every known kind + preserves an unknown', () {
      for (final k in rcKindValues) {
        expect(bridgeRcKindFromWire(k.wire), k);
      }
      final unknown = bridgeRcKindFromWire('gpt-next');
      expect(unknown, const BridgeRcKind.other(raw: 'gpt-next'));
      expect(unknown.wire, 'gpt-next');
      expect(unknown.known, isFalse);
      // A null/empty wire → an unknown with an empty raw.
      expect(bridgeRcKindFromWire(null).wire, '');
    });

    test('acceptsPrompt: known non-broker kinds only', () {
      expect(const BridgeRcKind.claudeRc().acceptsPrompt, isTrue);
      expect(const BridgeRcKind.shell().acceptsPrompt, isTrue);
      expect(const BridgeRcKind.claudeBroker().acceptsPrompt, isFalse);
      expect(const BridgeRcKind.other(raw: 'x').acceptsPrompt, isFalse);
    });

    test('runsClaude: the two claude kinds only', () {
      expect(const BridgeRcKind.claudeRc().runsClaude, isTrue);
      expect(const BridgeRcKind.claudeBroker().runsClaude, isTrue);
      expect(const BridgeRcKind.codex().runsClaude, isFalse);
      expect(const BridgeRcKind.shell().runsClaude, isFalse);
    });

    test('hasPermissionMode: every known agent kind except shell/unknown', () {
      expect(const BridgeRcKind.claudeRc().hasPermissionMode, isTrue);
      expect(const BridgeRcKind.codex().hasPermissionMode, isTrue);
      expect(const BridgeRcKind.shell().hasPermissionMode, isFalse);
      expect(const BridgeRcKind.other(raw: 'x').hasPermissionMode, isFalse);
    });

    test('tool token maps per kind (null for shell/unknown)', () {
      expect(const BridgeRcKind.claudeRc().tool, 'claude');
      expect(const BridgeRcKind.claudeBroker().tool, 'claude');
      expect(const BridgeRcKind.codex().tool, 'codex');
      expect(const BridgeRcKind.cursor().tool, 'cursor');
      expect(const BridgeRcKind.shell().tool, isNull);
      expect(const BridgeRcKind.other(raw: 'x').tool, isNull);
    });
  });

  group('BridgeRcState / BridgeRcActivity wire + activity gate', () {
    test('state wire strings', () {
      expect(BridgeRcState.ready.wire, 'ready');
      expect(BridgeRcState.needsTrust.wire, 'needs-trust');
      expect(BridgeRcState.needsAuth.wire, 'needs-auth');
    });

    test('activity wire strings', () {
      expect(BridgeRcActivity.working.wire, 'working');
      expect(BridgeRcActivity.needsInput.wire, 'needs_input');
    });

    test('rcStatePermitsActivity: blocking states suppress activity', () {
      expect(rcStatePermitsActivity(BridgeRcState.ready), isTrue);
      expect(rcStatePermitsActivity(BridgeRcState.starting), isTrue);
      expect(rcStatePermitsActivity(BridgeRcState.needsTrust), isFalse);
      expect(rcStatePermitsActivity(BridgeRcState.needsAuth), isFalse);
      expect(rcStatePermitsActivity(BridgeRcState.dead), isFalse);
    });
  });

  group('capabilities gating', () {
    BridgeRcCapabilities caps({
      required List<BridgeRcKind> kinds,
      Map<String, BridgeRcAgentInfo> agents = const {},
    }) => BridgeRcCapabilities(
      rcVersion: 3,
      kinds: kinds,
      agents: agents,
      features: const [],
      kindFeatures: const {},
    );

    test(
      'offers: advertised AND its agent installed (shell needs no agent)',
      () {
        final c = caps(
          kinds: const [BridgeRcKind.claudeRc(), BridgeRcKind.shell()],
          agents: const {'claude': BridgeRcAgentInfo(installed: true)},
        );
        expect(c.offers(const BridgeRcKind.claudeRc()), isTrue);
        expect(c.offers(const BridgeRcKind.shell()), isTrue);
        // Not advertised → not offered.
        expect(c.offers(const BridgeRcKind.codex()), isFalse);
      },
    );

    test('offers: advertised but agent not installed → gated out', () {
      final c = caps(
        kinds: const [BridgeRcKind.codex()],
        agents: const {'codex': BridgeRcAgentInfo(installed: false)},
      );
      expect(c.offers(const BridgeRcKind.codex()), isFalse);
      expect(c.creatableKinds(), isEmpty);
    });

    test('creatableKinds is the canonical-ordered offered subset', () {
      final c = caps(
        kinds: const [
          BridgeRcKind.shell(),
          BridgeRcKind.claudeRc(),
          BridgeRcKind.codex(),
        ],
        agents: const {
          'claude': BridgeRcAgentInfo(installed: true),
          'codex': BridgeRcAgentInfo(installed: true),
        },
      );
      // Canonical order = claude-rc, codex, …, shell (broker/unknown excluded).
      expect(c.creatableKinds(), const [
        BridgeRcKind.claudeRc(),
        BridgeRcKind.codex(),
        BridgeRcKind.shell(),
      ]);
    });
  });

  group('permission modes', () {
    test('the create-time default is a member of every kind set', () {
      expect(defaultRcPermissionMode, 'auto');
      expect(rcPermissionModes, contains(defaultRcPermissionMode));
      expect(rcGenericPermissionModes, contains(defaultRcPermissionMode));
      expect(
        permissionModesFor(const BridgeRcKind.claudeRc()),
        rcPermissionModes,
      );
      expect(
        permissionModesFor(const BridgeRcKind.codex()),
        rcGenericPermissionModes,
      );
    });

    test('claude set is the union of the generic + historical extras', () {
      expect(
        rcPermissionModes,
        rcGenericPermissionModes.union(rcClaudeExtraModes),
      );
      // The historical (caps-absent) set excludes the NEW generic `skip`.
      expect(rcClaudeHistoricalModes, isNot(contains('skip')));
      expect(rcClaudeHistoricalModes, contains('plan'));
    });
  });

  group('genSlug + provenance', () {
    test('is 6 chars from the unambiguous alphabet', () {
      const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
      for (var seed = 0; seed < 50; seed += 1) {
        final s = genSlug(Random(seed));
        expect(s, hasLength(6));
        for (final ch in s.split('')) {
          expect(alphabet, contains(ch));
        }
      }
    });

    test('excludes visually-confusable l/i/o/0/1', () {
      final joined = List.generate(200, (i) => genSlug(Random(i))).join();
      for (final bad in ['l', 'i', 'o', '0', '1']) {
        expect(
          joined.contains(bad),
          isFalse,
          reason: 'slug must not carry $bad',
        );
      }
    });

    test('rcCreatedBy is shed-mobile/<version> (no spaces)', () {
      expect(rcToolName, 'shed-mobile');
      expect(rcCreatedBy, startsWith('shed-mobile/'));
      expect(rcCreatedBy, isNot(contains(' ')));
    });
  });
}

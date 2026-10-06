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

    test('craze round-trips its wire spelling, and the retired kinds are '
        'plain unknown rows', () {
      // Plan 025: `craze` is a KNOWN kind — the arm that, if missing, would
      // let a craze-owned roost tab decode as `other(raw: 'craze')` and render
      // neutrally, with nothing anywhere saying a kind was lost.
      expect(bridgeRcKindFromWire('craze'), const BridgeRcKind.craze());
      expect(const BridgeRcKind.craze().wire, 'craze');
      expect(const BridgeRcKind.craze().known, isTrue);
      // The four retired kinds went the other way: unknown, raw kept, so a tab
      // running one of them directly is a plain row (shed#390).
      for (final retired in ['codex', 'cursor', 'gx', 'grok']) {
        final kind = bridgeRcKindFromWire(retired);
        expect(kind, BridgeRcKind.other(raw: retired));
        expect(kind.known, isFalse, reason: '$retired is retired');
        expect(kind.wire, retired, reason: 'the raw source is kept verbatim');
      }
    });

    test('acceptsPrompt: known non-broker, non-craze kinds only', () {
      expect(const BridgeRcKind.claudeRc().acceptsPrompt, isTrue);
      expect(const BridgeRcKind.opencode().acceptsPrompt, isTrue);
      expect(const BridgeRcKind.shell().acceptsPrompt, isTrue);
      expect(const BridgeRcKind.claudeBroker().acceptsPrompt, isFalse);
      // craze's own create sheet is its kickoff surface (plan 025 D6) —
      // `RcKind::accepts_typed_input` answers false for it explicitly.
      expect(const BridgeRcKind.craze().acceptsPrompt, isFalse);
      expect(const BridgeRcKind.other(raw: 'x').acceptsPrompt, isFalse);
    });

    test('runsClaude: the two claude kinds only', () {
      expect(const BridgeRcKind.claudeRc().runsClaude, isTrue);
      expect(const BridgeRcKind.claudeBroker().runsClaude, isTrue);
      expect(const BridgeRcKind.opencode().runsClaude, isFalse);
      expect(const BridgeRcKind.craze().runsClaude, isFalse);
      expect(const BridgeRcKind.shell().runsClaude, isFalse);
    });

    test('hasPermissionMode: every known agent kind except shell, craze and '
        'unknown', () {
      expect(const BridgeRcKind.claudeRc().hasPermissionMode, isTrue);
      expect(const BridgeRcKind.opencode().hasPermissionMode, isTrue);
      // craze's mode is its own settings sheet (plan 025 D7), not this
      // permission-mode vocabulary — `RcKind::has_permission_mode` is false.
      expect(const BridgeRcKind.craze().hasPermissionMode, isFalse);
      expect(const BridgeRcKind.shell().hasPermissionMode, isFalse);
      expect(const BridgeRcKind.other(raw: 'x').hasPermissionMode, isFalse);
    });

    test('tool token maps per kind (null for shell/unknown)', () {
      expect(const BridgeRcKind.claudeRc().tool, 'claude');
      expect(const BridgeRcKind.claudeBroker().tool, 'claude');
      expect(const BridgeRcKind.opencode().tool, 'opencode');
      expect(const BridgeRcKind.craze().tool, 'craze');
      expect(const BridgeRcKind.shell().tool, isNull);
      expect(const BridgeRcKind.other(raw: 'x').tool, isNull);
      // A retired kind is unknown now, so it has no tool either.
      expect(const BridgeRcKind.other(raw: 'codex').tool, isNull);
    });

    test('authHint: craze states none of its own (its providers do)', () {
      expect(
        const BridgeRcKind.opencode().authHint,
        'run `opencode auth login`',
      );
      expect(const BridgeRcKind.craze().authHint, isEmpty);
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
        expect(c.offers(const BridgeRcKind.opencode()), isFalse);
      },
    );

    test('offers: advertised but agent not installed → gated out', () {
      final c = caps(
        kinds: const [BridgeRcKind.opencode()],
        agents: const {'opencode': BridgeRcAgentInfo(installed: false)},
      );
      expect(c.offers(const BridgeRcKind.opencode()), isFalse);
      expect(c.creatableKinds(), isEmpty);
    });

    test('creatableKinds is the canonical-ordered offered subset', () {
      final c = caps(
        kinds: const [BridgeRcKind.opencode(), BridgeRcKind.claudeRc()],
        agents: const {
          'claude': BridgeRcAgentInfo(installed: true),
          'opencode': BridgeRcAgentInfo(installed: true),
        },
      );
      // Canonical order = claude-rc, opencode (plan 025 O3).
      expect(c.creatableKinds(), const [
        BridgeRcKind.claudeRc(),
        BridgeRcKind.opencode(),
      ]);
    });

    test('offers exactly claude-rc and opencode on a roost target, never the '
        'retired direct-agent kinds', () {
      // A roost target that advertises EVERY kind it recognizes on the wire,
      // plus the four retired ones as the unknown kinds they now decode to,
      // all installed — the widest input `creatableKinds()` can be handed.
      // Plan 025 O3: the roost create form offers exactly claude-rc and
      // opencode regardless of what the backend advertises, because
      // `rcCreatableKinds` is the gate, not `kinds`/`agents` — and craze is
      // not a roost-tab kind at all (its sessions come from its own source).
      final c = caps(
        kinds: const [
          BridgeRcKind.claudeRc(),
          BridgeRcKind.claudeBroker(),
          BridgeRcKind.opencode(),
          BridgeRcKind.craze(),
          BridgeRcKind.shell(),
          BridgeRcKind.other(raw: 'codex'),
          BridgeRcKind.other(raw: 'cursor'),
          BridgeRcKind.other(raw: 'gx'),
          BridgeRcKind.other(raw: 'grok'),
        ],
        agents: const {
          'claude': BridgeRcAgentInfo(installed: true),
          'opencode': BridgeRcAgentInfo(installed: true),
          'craze': BridgeRcAgentInfo(installed: true),
          'codex': BridgeRcAgentInfo(installed: true),
          'cursor': BridgeRcAgentInfo(installed: true),
          'gx': BridgeRcAgentInfo(installed: true),
          'grok': BridgeRcAgentInfo(installed: true),
        },
      );
      expect(c.creatableKinds(), const [
        BridgeRcKind.claudeRc(),
        BridgeRcKind.opencode(),
      ]);
    });
  });

  group('attachKind', () {
    BridgeRcKindFeatures features(String attach) => BridgeRcKindFeatures(
      postInput: false,
      approvals: 'none',
      watch: false,
      input: '',
      feed: '',
      interrupt: false,
      attach: attach,
    );

    test('an unknown kind gets NO attach affordance', () {
      // Not `tmux`: after S6 roost is the only producer of capabilities, so a
      // kind missing from the map is an unknown ROOST row and the xterm attach
      // would target a tmux session that does not exist. Not the peek either:
      // shed's `RcKind::Other` is defined as the unknown-kind policy that
      // "renders the raw kind with no affordances".
      expect(attachKind(null), 'none');
    });

    test('an empty attach string gets NO attach affordance', () {
      expect(attachKind(features('')), 'none');
    });

    test('native-remote passes through verbatim', () {
      expect(attachKind(features('native-remote')), 'native-remote');
    });

    test('any other non-empty value passes through verbatim', () {
      // Negative control alongside the two known values above: an
      // unrecognized attach string must not be silently coerced to either
      // known affordance — a caller decides "no affordance" for it.
      expect(attachKind(features('none')), 'none');
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
        permissionModesFor(const BridgeRcKind.opencode()),
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

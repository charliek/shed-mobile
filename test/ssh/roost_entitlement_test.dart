import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/roost_entitlement.dart';

/// **What this app run bootstrapped** (plan 020 §3.3, amendment A8, commit
/// C-M3b).
///
/// The claim these cells are about is the whole of shed's entitlement rule at
/// session protocol 5: roost's own gate on `session.set_agent_hooks` retired
/// there, so "shed wires a session it started and nothing else" is a rule with
/// nothing but this set behind it.
///
/// What the set is WIRED to is asserted where it can be: the bridge half — a
/// `bootstrapped: true` watcher re-sending on every cycle, under `shed-mobile`,
/// and a `false` one sending nothing at all — is pinned in Rust against a fake
/// roost (`rust/src/api/roost.rs`), and the feed half — an install recording the
/// claim, and the claim outliving the feed that earned it — in
/// `integration_test/roost_entitlement_test.dart`, which is the only place a
/// `MachineFeed` can be built at all (its constructor calls into the bridge).
void main() {
  group('RoostBootstrapEntitlements', () {
    test('a target this run bootstrapped is held, and nothing else is', () {
      final entitlements = RoostBootstrapEntitlements();

      expect(
        entitlements.holds('mini3'),
        isFalse,
        reason: 'a machine nobody bootstrapped is entitled to nothing',
      );

      entitlements.record('mini3');

      expect(entitlements.holds('mini3'), isTrue);
      expect(
        entitlements.holds('popos'),
        isFalse,
        reason: 'a claim is per target — one install does not entitle the rest',
      );
    });

    test('the same install recorded twice is one claim', () {
      final entitlements = RoostBootstrapEntitlements()
        ..record('mini3')
        ..record('mini3');

      expect(entitlements.targets, {'mini3'});
    });

    test('the claim does not survive a relaunch', () {
      final thisRun = RoostBootstrapEntitlements()..record('mini3');

      // What `roostEntitlementsProvider` builds when the app is launched again:
      // a new instance, because the fact was never written anywhere. A phone
      // that was killed has no claim on a session it did not start in the run
      // it is now in.
      final nextRun = RoostBootstrapEntitlements();

      expect(nextRun.holds('mini3'), isFalse);
      expect(
        nextRun.targets,
        isEmpty,
        reason: 'a relaunch starts with no claims at all',
      );
      // And the first one is untouched by the second existing — the two are
      // independent objects, not two views of one static.
      expect(thisRun.holds('mini3'), isTrue);
    });

    test('removing a machine drops its claim, and only its claim', () {
      final entitlements = RoostBootstrapEntitlements()
        ..record('mini3')
        ..record('popos');

      entitlements.forget('mini3');

      expect(
        entitlements.holds('mini3'),
        isFalse,
        reason: 'a different host added under this name must inherit nothing',
      );
      expect(entitlements.holds('popos'), isTrue);
    });

    test('forgetting a machine that was never bootstrapped is a no-op', () {
      final entitlements = RoostBootstrapEntitlements()..forget('mini3');

      expect(entitlements.targets, isEmpty);
    });
  });
}

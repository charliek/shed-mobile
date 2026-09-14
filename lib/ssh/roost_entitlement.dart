/// **What this app run bootstrapped** (plan 020 §3.3, amendment A8).
///
/// One fact, held for one app run: *did this phone put the `roost-session` on
/// that host?* It is the whole of shed's answer to "may this client wire that
/// host's agent hooks?" at session protocol 5 — roost's own gate on
/// `session.set_agent_hooks` retired there, and any same-UID client may now
/// wire any session it can reach, so what is left is shed's own rule that it
/// wires a session it started and nothing else.
///
/// The desktop keeps the identical fact in
/// `desktop/tauri/src-tauri/src/roost_hosts.rs` (`RoostHosts::armed`), for the
/// identical lifetime and for the identical reason.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The targets THIS APP RUN bootstrapped.
///
/// ## In memory, and deliberately never persisted
///
/// It is a claim about what this process did, not a durable grant. An app that
/// was killed and relaunched has no claim on a session it did not start in this
/// run, so a relaunch starts with an empty one — which is exactly what a fresh
/// instance is. It is emphatically **not** a lease: no token, no expiry, and
/// nothing the far side knows about.
///
/// ## App-scoped, because the readers are not
///
/// A `MachineFeed` is `autoDispose`, and the phone stops the whole feed on every
/// background and rebuilds it on every foreground. So the object that remembers
/// cannot be the feed: one instance is shared by every feed and every screen,
/// from a plain (non-`autoDispose`) provider, the same shape and the same
/// in-memory-only story as `machineHostKeysProvider`'s TOFU store.
class RoostBootstrapEntitlements {
  /// Keyed by the **target grammar token** — a machine's name, which is also
  /// what the watcher labels its rows with and what a `RoostHostTarget` carries.
  /// One vocabulary, so a claim cannot be recorded under one spelling and asked
  /// for under another.
  final Set<String> _targets = <String>{};

  /// **This app run bootstrapped [target].** Recorded when an install actually
  /// completed — never when one was merely offered, probed or attempted.
  ///
  /// Idempotent: a second install of the same machine records the same claim.
  void record(String target) => _targets.add(target);

  /// **May shed keep [target]'s agent hooks wired?** Read afresh at every
  /// watcher spawn (`MachineFeed.start`), which on a phone is many times a run.
  bool holds(String target) => _targets.contains(target);

  /// Drop the claim — the machine was removed from this device.
  ///
  /// Without this, deleting `mini3` and adding a different host under that same
  /// name in the same app run would inherit a claim nothing earned. The
  /// desktop's `RoostHosts::remove` clears its flag for the same reason.
  void forget(String target) => _targets.remove(target);

  /// Every claim, for a test that wants to assert the whole set rather than
  /// probe it one name at a time.
  @visibleForTesting
  Set<String> get targets => Set<String>.unmodifiable(_targets);
}

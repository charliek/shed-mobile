/// **The craze create sheet's pure rules** (plan 025 §3.8, CM4) — which
/// providers can be picked and which one is picked first, what a directory must
/// look like, the request id's lifecycle, the states' words, and what the sheet
/// says when its machine's craze stops being usable under it.
///
/// The desktop's `crazeCreate.ts`, ported rule for rule (shed `9a84ddf`): both
/// clients show one sheet, and a rule that read differently on the phone would
/// be a second product. Pure (no provider, no widget, no native call) so
/// `test/features/craze/craze_create_test.dart` pins every one without the
/// bridge; the sheet (`craze_create_sheet.dart`) only renders them. Where a
/// machine offers the sheet at all is a machine fact and lives beside its other
/// craze notes ([crazeCreateOffered] in `machines/machine_feed.dart`).
library;

import 'package:flutter/foundation.dart' show immutable;

import '../../machines/machine_feed.dart'
    show crazeCreateOffered, crazeCreateUpdateNote;
import '../../src/rust/api/craze.dart';
import '../../src/rust/api/dto_lane.dart';

// ---- providers --------------------------------------------------------------

/// **Only a ready provider is selectable** (D5: dim, not hide — and a dimmed
/// row that still created would only fail at start). A state this build does
/// not know (`other`) is NOT ready.
bool providerSelectable(BridgeLaneProvider p) =>
    p.state is BridgeLaneProviderState_Ready;

/// **The preselection**: craze's default provider IF it is listed AND ready,
/// else the first ready provider, else none (the sheet then says no provider is
/// ready, and Create is disabled).
String? preselectedProvider(BridgeLaneCreateOptions o) {
  final ready = o.providers.where(providerSelectable).toList();
  for (final p in ready) {
    if (p.id == o.defaultProvider) return p.id;
  }
  return ready.isEmpty ? null : ready.first.id;
}

/// A selection carried over from an earlier open of the sheet, kept only while
/// that provider is still listed and ready; else the preselection.
String? reconcileProvider(String? current, BridgeLaneCreateOptions o) {
  for (final p in o.providers) {
    if (p.id == current && providerSelectable(p)) return p.id;
  }
  return preselectedProvider(o);
}

/// What the sheet says when NO provider can be picked.
const noProviderReady = 'no provider is ready on this machine';

/// A provider's state, in words — what a dimmed row says beside its label.
String providerStateWords(BridgeLaneProviderState s) => switch (s) {
  BridgeLaneProviderState_Ready() => 'ready',
  BridgeLaneProviderState_NeedsSetup() => 'needs setup',
  BridgeLaneProviderState_Unavailable() => 'unavailable',
  BridgeLaneProviderState_Other(:final raw) => raw.replaceAll('_', ' '),
};

// ---- the directory ----------------------------------------------------------

/// The directory field's refusal, or null when it may be sent: a session's
/// directory must be ABSOLUTE (empty and relative are refused here; craze
/// checks that it exists, and says so as a `bad_request` beside the field).
String? directoryProblem(String cwd) {
  final dir = cwd.trim();
  if (dir.isEmpty) {
    return 'choose a directory: a recent one, or an absolute path';
  }
  if (!dir.startsWith('/')) return 'an absolute path, starting with /';
  return null;
}

// ---- the request id (plan 025 §3.8, the panel's Codex B) --------------------

/// Where one submission stands. A CREATED submission is not a phase: it spends
/// the draft ([CrazeDraft.spent]).
enum CrazePhase { idle, submitting, refused, unknown }

/// A refusal as the sheet reads it: a code (the desktop's own vocabulary —
/// `bad_request`, `failed`, `unavailable`, `outcome_unknown`, …) and the words.
@immutable
class CrazeRefusal {
  const CrazeRefusal(this.code, this.message);

  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is CrazeRefusal && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => '$code: $message';
}

/// **A create's failure, as the sheet reads it.**
///
/// The bridge's [BridgeLaneError] by variant — never by its text: the one that
/// keeps the request id, [BridgeLaneError_OutcomeUnknown], is Rust's own call
/// (`shed_craze::is_outcome_unknown`, plus a create the source's close cut
/// short mid-flight). Two more:
///
/// * a [StateError] is the feed refusing before it sent anything (no craze
///   source on that machine right now) — definite, as `unavailable`;
/// * anything else is an outcome nobody knows, and is read as one: keeping
///   the id is always safe (craze answers it with the session it started, or
///   starts one), while dropping it after a create that did land would start a
///   second session.
CrazeRefusal crazeRefusalOf(Object e) => switch (e) {
  BridgeLaneError_OutcomeUnknown(:final msg) => CrazeRefusal(
    'outcome_unknown',
    msg,
  ),
  BridgeLaneError_BadRequest(:final msg) => CrazeRefusal('bad_request', msg),
  BridgeLaneError_Failed(:final msg) => CrazeRefusal('failed', msg),
  BridgeLaneError_Unavailable(:final msg) => CrazeRefusal('unavailable', msg),
  BridgeLaneError_NotAccepting() => const CrazeRefusal(
    'not_accepting',
    'craze is not accepting that right now',
  ),
  BridgeLaneError_Unauthorized() => const CrazeRefusal(
    'unauthorized',
    'craze demanded a credential this build cannot supply',
  ),
  BridgeLaneError_UnknownSession() => const CrazeRefusal(
    'unknown_session',
    'craze does not know that session',
  ),
  BridgeLaneError_UnknownApproval() => const CrazeRefusal(
    'unknown_approval',
    'that ask is no longer open',
  ),
  BridgeLaneError_AlreadySubmitted() => const CrazeRefusal(
    'already_submitted',
    'an answer is already in flight',
  ),
  BridgeLaneError_AlreadyResolved() => const CrazeRefusal(
    'already_resolved',
    'that has already been answered',
  ),
  BridgeLaneError_NoLane(:final msg) => CrazeRefusal('no_lane', msg),
  BridgeLaneError_UnsupportedLane(:final kind) => CrazeRefusal(
    'unsupported_lane',
    'this build has no adapter for a "$kind" lane',
  ),
  StateError(:final message) => CrazeRefusal('unavailable', message),
  _ => CrazeRefusal('outcome_unknown', '$e'),
};

/// A created submission, as the sheet on screen learns of it — one object per
/// create, so a listener tells a new one from one it has already handled by
/// identity.
class CrazeCreated {
  CrazeCreated(this.created, {required this.ended});

  final BridgeLaneCreated created;

  /// craze answered with a session that has already ENDED (it replays a
  /// create's answer for ten minutes): nothing lists it, and there is no
  /// transcript to open.
  final bool ended;

  /// The new session's hostId (P11) — what its transcript opens on.
  String get hostId => created.session.id;
}

/// The marker for "leave the provider as it is" in [CrazeDraft.edit], because
/// null is a provider value (none selected).
const Object _keep = Object();

/// **A machine's create draft** — the typed form, the request id it holds, and
/// where its submission stands. It lives ABOVE the sheet
/// (`crazeDraftProvider`, per machine), so leaving the screen keeps a
/// submission running and a re-open finds the same form and the same id.
@immutable
class CrazeDraft {
  const CrazeDraft({
    this.provider,
    this.cwd = '',
    this.prompt = '',
    this.requestId,
    this.phase = CrazePhase.idle,
    this.refusal,
    this.lastCreated,
  });

  /// Nothing typed, no id, nothing in flight.
  static const empty = CrazeDraft();

  final String? provider;
  final String cwd;
  final String prompt;

  /// Held ONLY while the last submission's outcome is unknown (or while it is
  /// in flight): the retry that follows reuses it, so a lost answer never makes
  /// a second session. Null: the next submission mints a new one.
  final String? requestId;

  final CrazePhase phase;
  final CrazeRefusal? refusal;

  /// The last submission that CREATED a session — kept on the spent draft so
  /// the sheet on screen can open its transcript; see [CrazeCreated].
  final CrazeCreated? lastCreated;

  /// A submission starts: the id held from an unknown outcome is REUSED, else a
  /// new one is minted.
  CrazeDraft beginSubmit(String Function() mint) => _with(
    requestId: requestId ?? mint(),
    phase: CrazePhase.submitting,
    refusal: null,
  );

  /// A submission was refused. **Only an unknown outcome keeps the id** — craze
  /// stores a failure under its id and would replay that same failure for ten
  /// minutes, so after ANY definite answer the next submission mints a new
  /// one. The typed form is never touched.
  CrazeDraft settle(CrazeRefusal refusal) => refusal.code == 'outcome_unknown'
      ? _with(phase: CrazePhase.unknown, refusal: refusal)
      : _with(requestId: null, phase: CrazePhase.refused, refusal: refusal);

  /// A submission created a session: the draft is spent (the desktop's
  /// `EMPTY_DRAFT`), carrying only what was created.
  CrazeDraft spent(CrazeCreated created) => CrazeDraft(lastCreated: created);

  /// An edit of the form. **Any change mints a new id** for the next submission
  /// (it is another request now — reusing the id with other params is craze's
  /// `request_conflict`), and a settled refusal or unknown outcome no longer
  /// describes the form. Nothing typed is cleared. A submission in flight is
  /// not edited (its controls are disabled).
  CrazeDraft edit({Object? provider = _keep, String? cwd, String? prompt}) {
    if (phase == CrazePhase.submitting) return this;
    final nextProvider = identical(provider, _keep)
        ? this.provider
        : provider as String?;
    final nextCwd = cwd ?? this.cwd;
    final nextPrompt = prompt ?? this.prompt;
    if (nextProvider == this.provider &&
        nextCwd == this.cwd &&
        nextPrompt == this.prompt) {
      return this;
    }
    return CrazeDraft(
      provider: nextProvider,
      cwd: nextCwd,
      prompt: nextPrompt,
      lastCreated: lastCreated,
    );
  }

  /// The create this draft sends — the desktop's `create_request` rule: the
  /// directory trimmed; a blank provider is absent (craze's default); a blank
  /// prompt is absent (an idle session), any other prompt goes EXACTLY as
  /// typed, newlines and all. Only a draft that has begun a submission has an
  /// id to send.
  BridgeLaneCreateRequest request() {
    final p = provider?.trim() ?? '';
    return BridgeLaneCreateRequest(
      cwd: cwd.trim(),
      provider: p.isEmpty ? null : p,
      prompt: prompt.trim().isEmpty ? null : prompt,
      requestId: requestId!,
    );
  }

  CrazeDraft _with({
    Object? requestId = _keep,
    required CrazePhase phase,
    required CrazeRefusal? refusal,
  }) => CrazeDraft(
    provider: provider,
    cwd: cwd,
    prompt: prompt,
    requestId: identical(requestId, _keep)
        ? this.requestId
        : requestId as String?,
    phase: phase,
    refusal: refusal,
    lastCreated: lastCreated,
  );
}

/// The primary button's label.
String primaryLabel(CrazeDraft d) => switch (d.phase) {
  CrazePhase.submitting => 'Creating…',
  CrazePhase.refused || CrazePhase.unknown => 'Try again',
  CrazePhase.idle => 'Create',
};

/// What the sheet says about an UNKNOWN outcome (§3.8).
const outcomeUnknownNote =
    'craze did not answer, so the session may have been created: check the '
    'session list. Try again resumes the same request.';

/// Where a refusal is shown.
enum RefusalWhere { cwd, cause, general }

/// Where and how a refusal is shown (§3.8, by code): `bad_request` beside the
/// directory — except craze's `request_conflict` (an id reused with other
/// params, which this sheet never does on purpose), an internal error; a start
/// failure (`failed`) as craze's own cause, VERBATIM and monospace;
/// `unavailable` as "try again"; anything else as said.
({RefusalWhere where, String text}) refusalView(CrazeRefusal r) {
  if (r.code == 'bad_request') {
    if (RegExp(r'requestId .* was used already').hasMatch(r.message)) {
      return (
        where: RefusalWhere.general,
        text:
            'internal error (a new request id is used next time): ${r.message}',
      );
    }
    return (where: RefusalWhere.cwd, text: r.message);
  }
  if (r.code == 'failed') return (where: RefusalWhere.cause, text: r.message);
  if (r.code == 'unavailable') {
    return (where: RefusalWhere.general, text: '${r.message} — try again');
  }
  return (where: RefusalWhere.general, text: r.message);
}

/// What the screen says about a created session's FIRST PROMPT, when craze did
/// not take it — null when it did (or there was none). The session exists
/// either way: a refused or lost prompt is not a failed create.
List<String>? promptNotice(
  BridgeLaneCreated created,
) => switch (created.prompt) {
  BridgeLanePromptOutcome_Accepted() || BridgeLanePromptOutcome_None() => null,
  BridgeLanePromptOutcome_Refused() => [
    'craze started the session, and the session refused its first prompt.',
    if (created.promptError != null) created.promptError!,
  ],
  _ => [
    'craze started the session, and the answer to its first prompt was lost.',
    if (created.promptError != null) created.promptError!,
  ],
};

/// What the screen says when craze answered with a session that has already
/// ended (a replayed answer): there is nothing to open.
const crazeCreatedEnded =
    'craze answered with a session that has already ended.';

// ---- the sheet's machine note (plan 025 §3.8) --------------------------------
//
// Where the sheet is OFFERED is a machine fact, beside the machine's other
// craze notes: `crazeCreateOffered` / `crazeCreateUpdateNote` in
// `machines/machine_feed.dart`.

/// The note an OPEN sheet shows when its machine's craze stops being usable
/// under it (Create disabled, the form kept): offline, too old, not installed,
/// not connected yet. Null while it is live and can create.
String? crazeSheetNote(BridgeCrazeSnapshot? craze, String machine) {
  if (craze != null && craze.live) return crazeCreateUpdateNote(craze);
  return switch (craze?.offline?.cause) {
    BridgeSourceOffline_TooOld() =>
      'craze on this machine is too old for shed; update it',
    BridgeSourceOffline_NotInstalled() => 'craze is not installed on $machine',
    null => 'connecting to craze on $machine — your form is kept',
    final cause =>
      'craze on $machine is offline (${_offlineWords(cause)}) — your form is '
          'kept',
  };
}

String _offlineWords(BridgeSourceOffline cause) => switch (cause) {
  BridgeSourceOffline_NotInstalled() => 'not installed',
  BridgeSourceOffline_TooOld() => 'too old',
  BridgeSourceOffline_Unreachable() => 'unreachable',
  BridgeSourceOffline_Failed() => 'failed',
  BridgeSourceOffline_Other(:final raw) => raw.replaceAll('_', ' '),
};

// **The hermetic agent-lane harness** (plan 018 §3.13).
//
// One `LaneController` + one pumped `LaneScreen` per cell, driven through the
// REAL FRB bridge (`BridgeLaneSource`, not a stub) against shed's OWN gx and
// opencode fakes, hosted by `desktop/tools/shedtest/fake_lane_server.py` on a
// loopback control port. Nothing is mocked between Dart and the wire: the
// adapter, the fold, the staged view, the pump and the credential seam are all
// the shipped ones.
//
// ## Why this can be hermetic at all
//
// **The reach is LOCAL.** `dial_url == reported_url`, so there is no SSH, no
// forward and no sshd — the forward has its own hermetic tests (§3.10) and the
// probe line has a Rust golden against `tests/machine-transport`. gx's bearer
// token comes from the fake's own `write_home` on a temp `$GROK_HOME`, read
// through the `ProbeRunner` seam's LOCAL implementation: `sh -c` of exactly
// `gxProbeRemoteCommand()`, with `GROK_HOME` set. So the wire string, the POSIX
// script and Rust's `parse_probe` are exercised end to end with no network.
//
// ## What it found
//
// The first thing this harness caught is why the counters below are worth
// asserting: `LaneController._dropHandle` awaited `nudges.cancel()` BEFORE
// `lane_close`, and an FRB stream cancel does not complete until the Rust
// stream function returns — so every teardown path DEADLOCKED and the lane, its
// adapter and its connections leaked. No unit test could see it, because a
// stubbed `LaneSource` hands back an already-completed cancel. See
// `lane_controller.dart:_dropHandle`.
//
// ## Two gx knobs the control door does not expose yet
//
// Four of §3.13's cells are reduced here, and every reason is a shed-side
// allowlist gap in `fake_lane_server.py` (`GX_METHODS`) — not a weakened claim:
//
// * **`add_approval` is missing.** It is the ONLY producer that puts a gx
//   approval in the fake's STORE, and gx's `answer()` re-reads
//   `GET /v1/sessions/{id}/approvals/{id}` before it posts.
//   `push_approval_frame` is broadcast-only by design ("so a cell can make the
//   frame and the store disagree on purpose"), so an approval pushed as a frame
//   RENDERS but cannot be answered — the re-read 404s. The render halves are
//   asserted below; the post halves are left unwritten rather than aimed at a
//   placeholder whose kind would make the adapter refuse for the wrong reason.
//   This is what reduces `five_options_render_and_choice_posts_the_pressed_id`
//   (and its `Permission{AllowOnce}` → `bad_request` half),
//   `question_with_free_text_posts_annotations`, and — because a gx
//   `question_request` is the only multi-question ask either fake can build —
//   `custom_text_round_trips_through_frb`'s pinned two-entry literal.
// * **`body_of` is missing.** `requests()` deliberately drops each record's
//   body, so no gx POST body is observable from Dart. gx's send MODE
//   (`{"text":…,"mode":"interject"}`) is therefore asserted on opencode's side
//   of the pair (which refuses `Interject` locally, with `post_paths` empty) and
//   as a widget claim on gx's, not as a gx wire body.
//
// The opencode fake needs neither: `post_body`, `snapshot`, `add_permission`,
// `add_question` and `stream_question_asked` are all allowlisted, so every
// opencode cell asserts the real wire body. Two cells here are NOT in §3.13 and
// exist to cover what gx cannot:
// `a_placeholders_reject_posts_and_a_second_answer_is_refused` (the one gx
// answer path the control door can reach) and
// `a_pressed_option_id_posts_its_replys_wire_value` (the screen's own
// post-the-offered-id path, on opencode).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/features/lanes/lane_screen.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_state.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/bridge_rt.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';
import 'package:shed_mobile/ssh/lane_forward.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import 'support/fake_lane_server.dart';

/// gx's own sentinel token (`fake_gx.SENTINEL_TOKEN`) — 64 hex, chosen so it
/// can be grepped for. Named here so the sentinel cell can prove its grep is
/// not vacuous; the value is re-read off the fake's `$GROK_HOME` at runtime, so
/// this constant is a cross-check rather than the source of truth.
const _sentinelToken =
    '5e471e15e471e15e471e15e471e15e471e15e471e15e471e15e471e15e471e15';

/// A gx session id shaped like the real thing (the fake's own id shape), so the
/// event-id split — `<session>-<counter>`, at the LAST hyphen — is exercised
/// against a prefix carrying hyphens of its own.
const _gxSession = '01a0fake-0000-7000-8000-000000000001';
const _gxOther = '01a0fake-0000-7000-8000-000000000002';
const _ocSession = 'ses_root';
const _ocOther = 'ses_other';

/// The lane's identity on the phone: the machine, and the ROW's slug.
const _ref = (machine: 'local', slug: '7');

/// A loopback machine — [laneReachFor] answers [LaneReach.local] for it, which
/// is what makes the whole harness need no forward.
const _local = MachineRecord(name: 'local', host: '127.0.0.1');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  // -------------------------------------------------------------------------
  // gx
  // -------------------------------------------------------------------------

  group('gx', () {
    testWidgets('seed_renders_after_ready_and_never_partially', (tester) async {
      final rig = await _gx(tester, open: false);
      await rig.fake.call(
        'set_history',
        args: [
          _gxSession,
          [
            await rig.fake.envelope('chunk', {
              'session': _gxSession,
              'n': 1,
              'kind': 'agent_message_chunk',
              'text': 'the first thing it said',
            }),
            await rig.fake.envelope('turn_completed', {
              'session': _gxSession,
              'n': 2,
            }),
          ],
        ],
      );
      // The barrier. Parked BEFORE the lane opens, so "no partial view" is an
      // observed fact rather than a hope about scheduling.
      await rig.fake.call('hold_seed');

      await rig.open(tester);
      // The roster GET is not a seed route, so the lane is OPEN — capabilities
      // read, pump running — while the transcript read is still parked.
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane to open with its seed parked',
      );
      expect(
        rig.state.generation,
        BigInt.zero,
        reason: 'a seed that has not COMPLETED must not move the generation',
      );
      expect(rig.state.rows, isEmpty, reason: 'no partial transcript');
      // Held for a while, not glanced at: a partial view would appear DURING
      // the seed, and a single check right after `open` could miss it.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(rig.state.rows, isEmpty);
        expect(rig.state.generation, BigInt.zero);
      }
      expect(find.textContaining('the first thing it said'), findsNothing);

      await rig.fake.call('release_seed');
      await rig.pumpUntil(
        tester,
        () => rig.state.rows.isNotEmpty,
        what: 'the seed to complete',
      );

      // ONE atomic swap: generation 1, and the whole generation at once.
      expect(rig.state.generation, BigInt.one);
      expect(
        rig.state.rows.map((r) => r.text).join('\n'),
        contains('the first thing it said'),
      );
      expect(find.byKey(const ValueKey('lane-list')), findsOneWidget);
      expect(find.textContaining('the first thing it said'), findsOneWidget);
    }, timeout: _cell);

    testWidgets('live_row_appears_without_a_poll', (tester) async {
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      final before = rig.state.rows.length;
      await rig.fake.call('clear_requests');

      await rig.fake.call(
        'push_update',
        args: [
          _gxSession,
          await rig.fake.envelope('chunk', {
            'session': _gxSession,
            'n': 20,
            'kind': 'agent_message_chunk',
            'text': 'pushed down the live stream',
          }),
        ],
      );
      // A chunk streak becomes a row when the turn CLOSES; a cell that pushed
      // only the chunk would wait forever for a row correctly not there yet.
      await rig.fake.call(
        'push_update',
        args: [
          _gxSession,
          await rig.fake.envelope('turn_completed', {
            'session': _gxSession,
            'n': 21,
          }),
        ],
      );

      await rig.pumpUntil(
        tester,
        () => rig.rowText.contains('pushed down the live stream'),
        what: 'the live row',
      );
      expect(rig.state.rows.length, greaterThan(before));
      expect(
        find.textContaining('pushed down the live stream'),
        findsOneWidget,
      );

      // **Without a poll.** No history read, no roster read, and no new
      // subscription: the row arrived on the stream that was already open.
      final paths = await rig.gxPaths();
      expect(
        paths.where((p) => p.contains('/history')),
        isEmpty,
        reason: 'a history GET would mean it was polled, not pushed',
      );
      expect(paths.where((p) => p.endsWith('/events')), isEmpty);
      expect(rig.state.generation, BigInt.one, reason: 'no reseed happened');
    }, timeout: _cell);

    testWidgets('send_posts_to_the_pinned_session_only', (tester) async {
      // A SECOND session on the same fake, so "the pinned session" is a real
      // choice. Without it the assertion would also pass for an adapter that
      // posted to whatever session it found first.
      final rig = await _gx(tester, extraSession: _gxOther);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      await rig.fake.call('clear_requests');

      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'do the thing',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await rig.pumpUntil(
        tester,
        () async => (await rig.gxPaths()).any((p) => p.endsWith('/messages')),
        what: 'the send',
      );

      final records = await rig.gxRequests();
      final posts = records
          .where(
            (r) => r['path']! as String == '/v1/sessions/$_gxSession/messages',
          )
          .toList();
      expect(posts, hasLength(1));
      expect(posts.single['method'], 'POST');
      expect(
        records.where((r) => (r['path']! as String).contains(_gxOther)),
        isEmpty,
        reason: 'nothing may address the session the lane is not open on',
      );
      expect(rig.state.composerError, isNull);
    }, timeout: _cell);

    testWidgets(
      'interject_is_offered_only_while_working_and_the_toggle_is_absent_elsewhere',
      (tester) async {
        // gx advertises `interject`, so the chip EXISTS — and is enabled only
        // while a turn is running. Absent (opencode) and present-but-disabled
        // are different facts: collapsing them hides a capability or offers a
        // refusal.
        //
        // The `mode: "interject"` wire body is not asserted here: `requests()`
        // drops each record's body and `body_of` is not allowlisted, so no gx
        // POST body is observable from Dart. See this file's header.
        final rig = await _gx(tester);
        await rig.pumpUntil(
          tester,
          () => rig.state.capabilities != null,
          what: 'the lane',
        );
        expect(rig.state.capabilities!.interject, isTrue);
        expect(rig.state.capabilities!.historyCursor, isTrue);
        expect(rig.state.capabilities!.kind, 'gx');

        // Idle: the chip is rendered (the adapter can do it) and disabled
        // (there is no turn to interject).
        expect(rig.state.activity, isNot(BridgeRcActivity.working));
        expect(find.byKey(const ValueKey('lane-interject')), findsOneWidget);
        expect(
          tester
              .widget<FilterChip>(find.byKey(const ValueKey('lane-interject')))
              .onSelected,
          isNull,
          reason: 'an interject with nothing to interject is a refusal',
        );
        expect(find.byKey(const ValueKey('lane-cancel')), findsNothing);

        // A working turn, announced the way a leader announces one: the roster
        // row changes, then a `session` frame invalidates it.
        await rig.working();
        await rig.pumpUntil(
          tester,
          () => rig.state.activity == BridgeRcActivity.working,
          what: 'the working turn',
        );
        expect(
          tester
              .widget<FilterChip>(find.byKey(const ValueKey('lane-interject')))
              .onSelected,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('lane-interject')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester
              .widget<FilterChip>(find.byKey(const ValueKey('lane-interject')))
              .selected,
          isTrue,
        );
        // And the affordance a working turn also earns.
        expect(find.byKey(const ValueKey('lane-cancel')), findsOneWidget);
      },
      timeout: _cell,
    );

    testWidgets('cancel_posts_and_not_accepting_is_an_inline_error', (
      tester,
    ) async {
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      await rig.working();
      await rig.pumpUntil(
        tester,
        () => rig.state.activity == BridgeRcActivity.working,
        what: 'a turn to cancel',
      );
      await rig.fake.call('clear_requests');

      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await rig.pumpUntil(
        tester,
        () async => (await rig.gxPaths()).any((p) => p.endsWith('/cancel')),
        what: 'the cancel',
      );
      final records = await rig.gxRequests();
      final posts = records
          .where((r) => (r['path']! as String).endsWith('/cancel'))
          .toList();
      expect(posts, hasLength(1));
      expect(posts.single['method'], 'POST');
      expect(posts.single['path'], '/v1/sessions/$_gxSession/cancel');
      expect(
        rig.state.composerError,
        isNull,
        reason: 'a cancel that was accepted leaves no error',
      );

      // Now the refusal. `not_accepting` means "the turn ended between the
      // render and the tap" — an inline error next to the button, never a
      // swallowed no-op.
      await rig.fake.call(
        'fail',
        args: [
          '/cancel',
          409,
          'not_accepting',
          'the session is not accepting that',
        ],
      );
      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await rig.pumpUntil(
        tester,
        () => rig.state.composerError != null,
        what: 'the inline refusal',
      );
      expect(find.byKey(const ValueKey('lane-composer-error')), findsOneWidget);
      expect(
        rig.state.composerError!.message.toLowerCase(),
        contains('accepting'),
      );
      await rig.fake.call('clear_failures');
    }, timeout: _cell);

    testWidgets('five_options_render_from_the_real_request', (tester) async {
      // The RENDER half of §3.13's `five_options_render_and_choice_posts_the_
      // pressed_id`. The post half needs `add_approval` (see the header): an
      // approval delivered as a frame renders, but gx's `answer()` re-reads it
      // from the store, which only `add_approval` writes.
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );

      await rig.pushPermission('ap-five', 'rm -rf /tmp/scratch');
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.isNotEmpty,
        what: 'the permission',
      );

      final approval = rig.state.approvals.single;
      expect(approval.id, 'ap-five');
      expect(approval.kind, isA<BridgeLaneApprovalKind_Permission>());
      // FIVE options, and TWO of them `allow_once` — the live gx shape, and the
      // whole reason nothing here resolves a decision locally.
      expect(approval.options, hasLength(5));
      expect(
        approval.options.where((o) => o.kind == 'allow_once'),
        hasLength(2),
      );
      // Every one of them is on screen, keyed by its OPAQUE id.
      for (final option in approval.options) {
        expect(
          find.byKey(ValueKey('lane-option-${option.id}')),
          findsOneWidget,
          reason: option.id,
        );
      }
      // The contract's own answer for the ambiguous case, from the shipped
      // resolver rather than a Dart re-derivation: a decision that matches TWO
      // options names neither.
      expect(
        laneOptionFor(
          approval: approval,
          decision: BridgeLaneDecision.allowOnce,
        ),
        isNull,
        reason: 'two allow_once options — a decision cannot say which',
      );
      // The negative control: an UNAMBIGUOUS decision does resolve, so the null
      // above is about ambiguity and not about a resolver that answers null for
      // everything.
      expect(
        laneOptionFor(
          approval: approval,
          decision: BridgeLaneDecision.allowAlways,
        )?.kind,
        'allow_always',
      );
    }, timeout: _cell);

    testWidgets('question_with_free_text_renders_its_form', (tester) async {
      // The RENDER half of §3.13's `question_with_free_text_posts_annotations`.
      // The post half — `["Other"]` where no label, question 1 omitted, the
      // `annotations` map — needs `add_approval`; see the header.
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );

      await rig.pushQuestion('ap-q', const [
        {
          'question': 'Which branch should it push to?',
          'options': [
            {'label': 'main'},
            {'label': 'release'},
          ],
        },
        {
          'question': 'Anything else it should know?',
          'options': [
            {'label': 'no'},
          ],
        },
      ]);
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.isNotEmpty,
        what: 'the question',
      );

      final approval = rig.state.approvals.single;
      expect(approval.kind, isA<BridgeLaneApprovalKind_Question>());
      expect(approval.questions, hasLength(2));
      // gx files answers by the question's TEXT, so the key is visible on the
      // mirror — and every gx question advertises free text.
      expect(approval.questions.first.id, 'Which branch should it push to?');
      expect(approval.questions.every((q) => q.custom), isTrue);
      expect(approval.questions.every((q) => !q.multiple), isTrue);
      // A question's options carry the LABEL as their id (that is what gx's
      // answer array holds) and no permission posture.
      expect(approval.questions.first.options.map((o) => o.id), [
        'main',
        'release',
      ]);
      expect(
        approval.questions.first.options.every((o) => o.kind == null),
        isTrue,
      );

      // The form: chips scoped per question index, a text field per custom
      // question, and ONE Send answer — no one-click, because a text field on
      // screen means the first chip tap would throw away what was being typed.
      expect(find.byKey(const ValueKey('lane-option-0-main')), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-option-1-no')), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-custom-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-custom-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-question-send')), findsOneWidget);
    }, timeout: _cell);

    testWidgets(
      'placeholder_permission_has_no_allow_button_until_the_real_request',
      (tester) async {
        // gx announces every approval TWICE: first a placeholder with a null
        // method and no request, then the real thing under the SAME id. A card
        // that inferred "permission ⇒ allow/deny" would offer to approve
        // something it cannot describe.
        final rig = await _gx(tester);
        await rig.pumpUntil(
          tester,
          () => rig.state.capabilities != null,
          what: 'the lane',
        );

        final placeholder =
            (await rig.fake.call(
                  'add_placeholder_approval',
                  args: [_gxSession, 'ap-1'],
                ))!
                as Map<String, Object?>;
        await rig.fake.call(
          'push_approval_frame',
          args: [_gxSession, placeholder],
        );
        await rig.pumpUntil(
          tester,
          () => rig.state.approvals.isNotEmpty,
          what: 'the placeholder',
        );

        expect(rig.state.approvals.single.options, isEmpty);
        expect(_anyOption, findsNothing);
        expect(find.byKey(const ValueKey('lane-waiting-ap-1')), findsOneWidget);
        // **The note names the kind the FOLD gave it, and that is
        // `placeholder`, not `permission`.** gx's `lane_approval`
        // special-cases a null method with a null request into
        // `Other("placeholder")` BEFORE it reads the wire `kind`, so the
        // screen's "waiting for details" copy — the `Permission`/
        // `PlanApproval` arm of `_RawApproval._note` — is unreachable for a
        // real gx placeholder. What this cell is about holds either way: no
        // allow button, and a sentence saying why.
        expect(
          rig.state.approvals.single.kind,
          isA<BridgeLaneApprovalKind_Other>(),
        );
        expect(
          find.textContaining('no form for a "placeholder" ask'),
          findsOneWidget,
        );
        // The one answer that is always safe IS offered — and it really posts:
        // `Reject` needs no option list, and the placeholder is in the store, so
        // the whole re-read-then-POST path runs.
        expect(find.byKey(const ValueKey('lane-reject-ap-1')), findsOneWidget);

        // Then the real request lands under the same id. Built from the fake's
        // OWN placeholder resource and the fake's OWN `permission_request`
        // envelope — nothing about either shape is re-derived here.
        await rig.pushPermission('ap-1', 'rm -rf /tmp/scratch');
        await rig.pumpUntil(
          tester,
          () => rig.state.approvals.single.options.isNotEmpty,
          what: 'the real request',
        );
        expect(rig.state.approvals.single.options, hasLength(5));
        expect(_anyOption, findsNWidgets(5));
        expect(find.byKey(const ValueKey('lane-waiting-ap-1')), findsNothing);
      },
      timeout: _cell,
    );

    testWidgets('a_placeholders_reject_posts_and_a_second_answer_is_refused', (
      tester,
    ) async {
      // The one gx answer path the control door can reach: `Reject` against the
      // placeholder that `add_placeholder_approval` really does store. It
      // proves the re-read-then-POST path end to end, and that a double tap is
      // refused rather than posted twice.
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      final placeholder =
          (await rig.fake.call(
                'add_placeholder_approval',
                args: [_gxSession, 'ap-2'],
              ))!
              as Map<String, Object?>;
      await rig.fake.call(
        'push_approval_frame',
        args: [_gxSession, placeholder],
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.isNotEmpty,
        what: 'the placeholder',
      );

      expect(await rig.answeredWith('ap-2'), isNull, reason: 'nothing yet');
      await tester.tap(find.byKey(const ValueKey('lane-reject-ap-2')));
      await rig.pumpUntil(
        tester,
        () async => await rig.answeredWith('ap-2') != null,
        what: 'the reject to reach the fake',
      );
      expect(await rig.answeredWith('ap-2'), {'outcome': 'cancelled'});

      // A second answer to one approval is refused — and lands on THAT card,
      // which is the only place it means anything.
      await rig.controller.answer('ap-2', const BridgeLaneAnswer.reject());
      await tester.pump(const Duration(milliseconds: 50));
      expect(rig.state.approvalErrors['ap-2'], isNotNull);
    }, timeout: _cell);

    testWidgets('dropped_stream_resumes_silently_and_a_server_reset_reseeds', (
      tester,
    ) async {
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      final generation = rig.state.generation;

      // Staged into the stores, NOT broadcast — a frame pushed after the cut
      // would race the reconnect and could be delivered live, which passes the
      // cell for entirely the wrong reason.
      await rig.fake.call(
        'stage_update',
        args: [
          _gxSession,
          await rig.fake.envelope('chunk', {
            'session': _gxSession,
            'n': 30,
            'kind': 'agent_message_chunk',
            'text': 'replayed after the cut',
          }),
        ],
      );
      await rig.fake.call(
        'stage_update',
        args: [
          _gxSession,
          await rig.fake.envelope('turn_completed', {
            'session': _gxSession,
            'n': 31,
          }),
        ],
      );
      await rig.fake.call('close_streams');

      await rig.pumpUntil(
        tester,
        () => rig.rowText.contains('replayed after the cut'),
        what: 'the silent resume',
      );
      // **Silent.** The cursor was inside the ring, so gx replayed from memory
      // with no `reset` — Dart never saw a reconnect at all.
      expect(
        rig.state.generation,
        generation,
        reason: 'a resume is not a reseed; the generation must not move',
      );
      expect(rig.state.stale, isNull);

      // A SERVER reset is the other half: gx telling the client its view is not
      // resumable, which is a new generation.
      await rig.fake.call(
        'push_reset',
        args: [_gxSession, 'cursor_unresolvable'],
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > generation,
        what: 'the reseed',
      );
      expect(rig.state.stale, isNull, reason: 'a reseed is not a Down');
      expect(
        rig.rowText,
        contains('replayed after the cut'),
        reason: 'the reseeded generation is complete, not empty',
      );
    }, timeout: _cell);

    testWidgets('leader_restart_refreshes_credentials_in_place', (
      tester,
    ) async {
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      final generation = rig.state.generation;
      final probesAtOpen = rig.probes.length;
      expect(probesAtOpen, 1, reason: 'one probe opened the lane');

      // Staged first (see the resume cell): after `restart_leader` the ring is
      // EMPTY, so the cursor falls past it and gx's fourth replay rule serves
      // these off the persisted transcript.
      await rig.fake.call(
        'stage_update',
        args: [
          _gxSession,
          await rig.fake.envelope('chunk', {
            'session': _gxSession,
            'n': 40,
            'kind': 'agent_message_chunk',
            'text': 'after the restart',
          }),
        ],
      );
      await rig.fake.call(
        'stage_update',
        args: [
          _gxSession,
          await rig.fake.envelope('turn_completed', {
            'session': _gxSession,
            'n': 41,
          }),
        ],
      );

      // A leader RESTART: a new `instanceId`, the SAME token (it is per
      // `$GROK_HOME`, not per leader), an empty ring — and the discovery record
      // rewritten, which is what the re-probe has to find.
      await rig.fake.call(
        'restart_leader_and_rewrite_home',
        args: ['beefbeefbeefbeefbeefbeefbeefbeef'],
      );
      await rig.fake.call('close_streams');

      // The ask reaches Dart: the second `discover` of one pin does NOT re-serve
      // the stale value, it raises the flag and awaits.
      final asked = await rig.pumpFor(
        tester,
        () => rig.state.needsCredentials || rig.probes.length > probesAtOpen,
        what: 'the credential ask',
      );
      expect(asked, isTrue, reason: 'the leader restart raised no ask');

      await rig.pumpUntil(
        tester,
        () => rig.rowText.contains('after the restart'),
        what: 'the lane to recover in place',
      );

      // **In place.** No `Down`, no re-open: the generation and the ring are
      // intact, and exactly one extra probe ran.
      expect(rig.state.stale, isNull);
      expect(rig.state.generation, generation);
      expect(rig.probes, hasLength(probesAtOpen + 1));
      expect(rig.state.needsCredentials, isFalse);
      expect(rig.state.error, isNull);

      // The credential seam, on the wire: `healthz` is the ONE route answered
      // before the token gate, so a client that could not pin never adds a
      // bearer request — and everything else carried a bearer that was
      // ACCEPTED, which is how "the token survived the restart" is an assertion
      // rather than a hope.
      final records = await rig.gxRequests();
      final health = records
          .where((r) => (r['path']! as String) == '/v1/healthz')
          .toList();
      expect(health, isNotEmpty, reason: 'the pin rests on healthz');
      expect(health.every((r) => r['had_bearer'] == false), isTrue);
      for (final record in records) {
        if (record['path'] == '/v1/healthz') continue;
        expect(
          record['had_bearer'],
          isTrue,
          reason: 'every guarded route carries a bearer: ${record['path']}',
        );
        expect(
          record['bearer_ok'],
          isTrue,
          reason: 'the token is per-\$GROK_HOME and must not have changed',
        );
      }
    }, timeout: _cell);

    testWidgets('the_sentinel_token_is_in_no_dart_output', (tester) async {
      // A security assertion, so it is built to be non-vacuous FIRST: the
      // sentinel really is the credential in play (it is the byte string in the
      // fixture home the probe read it out of, and the fake accepted bearer
      // requests with it), and only then is every line of Dart output grepped
      // for it.
      final captured = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };
      addTearDown(() => debugPrint = previous);

      late _Rig rig;
      await runZoned(
        () async {
          rig = await _gx(tester);
          await rig.pumpUntil(
            tester,
            () => rig.state.generation > BigInt.zero,
            what: 'the seed',
          );
          // Everything a lane does with a credential in hand.
          await tester.enterText(
            find.byKey(const ValueKey('lane-input')),
            'say something',
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('lane-send')));
          await rig.pumpUntil(
            tester,
            () async =>
                (await rig.gxPaths()).any((p) => p.endsWith('/messages')),
            what: 'the send',
          );
          // A refusal path too: an error string is the classic place a token
          // gets interpolated.
          await rig.fake.call(
            'fail',
            args: ['/cancel', 500, 'internal', 'boom'],
          );
          await rig.controller.cancel();
          await rig.fake.call('clear_failures');
          await tester.pump(const Duration(milliseconds: 50));
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, String line) => captured.add(line),
        ),
      );

      // (1) The grep is not vacuous: the sentinel IS the token on disk.
      final onDisk = File(
        '${rig.grokHome!.path}/gx-remote.token',
      ).readAsStringSync();
      expect(
        onDisk.trim(),
        _sentinelToken,
        reason:
            'the fixture home does not hold the sentinel, so the greps '
            'below would search for a string nothing could contain',
      );
      final records = await rig.gxRequests();
      expect(
        records.where((r) => r['had_bearer'] == true && r['bearer_ok'] == true),
        isNotEmpty,
        reason: 'no request was ever made with it either',
      );
      // (2) …and the capture is not vacuous either: the lane's own MSTATE
      // lines are in it, so an empty buffer cannot pass this cell.
      expect(
        captured.where((l) => l.startsWith('MSTATE screen=lane')),
        isNotEmpty,
        reason: 'no Dart output was captured at all',
      );

      // (3) The audit. The sentinel, and ANY 64-hex run — a token that reached
      // a log under a different value is still a leaked token.
      final blob = captured.join('\n');
      expect(blob, isNot(contains(_sentinelToken)));
      expect(blob, isNot(contains(onDisk.trim())));
      final hex = RegExp('[0-9a-fA-F]{64}');
      final hits = hex.allMatches(blob).map((m) => m.group(0)!).toList();
      expect(hits, isEmpty, reason: 'a 64-hex run reached Dart output: $hits');
      // And the same rule applied line by line to the MSTATE/MRESULT contract
      // specifically, which is what a driver reads and a bug report pastes.
      for (final line in captured.where(
        (l) => l.startsWith('MSTATE') || l.startsWith('MRESULT'),
      )) {
        expect(line, isNot(contains(_sentinelToken)));
        expect(hex.hasMatch(line), isFalse, reason: line);
      }
    }, timeout: _cell);

    testWidgets('close_ends_the_pump_and_one_row_is_one_controller', (
      tester,
    ) async {
      final rig = await _gx(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      await rig.pumpUntil(
        tester,
        () async => (await liveCounters()).activeLanes == BigInt.one,
        what: 'exactly one live lane',
      );

      // **One lane per row.** The bridge has no registry, so this is the
      // provider's guarantee and nothing else's: two watchers on one ref share
      // one controller, and a different row is a different lane.
      final first = rig.container.read(laneControllerProvider(_ref));
      final second = rig.container.read(laneControllerProvider(_ref));
      expect(first, same(second));
      expect(first, same(rig.controller));

      // `lane_close` is the synchronous teardown the provider's `onDispose`
      // calls: it aborts the pump and drops the adapter. `dispose` waits for
      // the counter, so what follows is an assertion and not a race.
      await rig.dispose(tester);
      final counters = await liveCounters();
      expect(counters.activeLanes, BigInt.zero);
      expect(counters.activeLaneForwarders, BigInt.zero);
      await expectLater(first.updates, emitsDone);
    }, timeout: _cell);
  });

  // -------------------------------------------------------------------------
  // opencode
  // -------------------------------------------------------------------------

  group('opencode', () {
    testWidgets('seed_renders_after_ready_and_never_partially', (tester) async {
      final rig = await _oc(tester, open: false);
      await rig.fake.call(
        'set_simple_transcript',
        args: [_ocSession, 'describe this project', 'It is a reverse proxy.'],
      );
      await rig.fake.call('hold_seed');

      await rig.open(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane to open with its seed parked',
      );
      expect(rig.state.generation, BigInt.zero);
      expect(rig.state.rows, isEmpty);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(rig.state.rows, isEmpty);
        expect(rig.state.generation, BigInt.zero);
      }
      expect(find.textContaining('reverse proxy'), findsNothing);

      await rig.fake.call('release_seed');
      await rig.pumpUntil(
        tester,
        () => rig.state.rows.isNotEmpty,
        what: 'the seed to complete',
      );
      expect(rig.state.generation, BigInt.one);
      // Both turns at once — one atomic swap, not a user row then an assistant
      // row.
      expect(rig.rowText, contains('describe this project'));
      expect(rig.rowText, contains('It is a reverse proxy.'));
      expect(find.textContaining('It is a reverse proxy.'), findsOneWidget);
    }, timeout: _cell);

    testWidgets('live_row_appears_without_a_poll', (tester) async {
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      final before = rig.state.rows.length;
      final pathsAtSeed = (await rig.ocSnapshot())['get_paths']! as List;

      await rig.fake.call(
        'stream_part',
        args: [_ocSession],
        kwargs: {
          'message_id': 'msg_live',
          'part_id': 'prt_live',
          'text': 'pushed down the live stream',
        },
      );
      await rig.fake.call('stream_idle', args: [_ocSession]);

      await rig.pumpUntil(
        tester,
        () => rig.rowText.contains('pushed down the live stream'),
        what: 'the live row',
      );
      expect(rig.state.rows.length, greaterThan(before));
      expect(
        find.textContaining('pushed down the live stream'),
        findsOneWidget,
      );

      // **Without a poll.** No new GET at all since the seed: opencode has no
      // history cursor, so a reseed would be a fresh `/session/{id}/message`
      // read — and there is none.
      final after = (await rig.ocSnapshot())['get_paths']! as List;
      final added = after.skip(pathsAtSeed.length).cast<String>().toList();
      expect(
        added.where((p) => p.contains('/message')),
        isEmpty,
        reason: 'a message GET would mean it was polled, not pushed: $added',
      );
      expect(rig.state.generation, BigInt.one, reason: 'no reseed happened');
    }, timeout: _cell);

    testWidgets('send_posts_to_the_pinned_session_only', (tester) async {
      final rig = await _oc(tester, extraSession: _ocOther);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );

      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'do the thing',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await rig.pumpUntil(
        tester,
        () async =>
            (await rig.ocPostPaths()).any((p) => p.endsWith('/prompt_async')),
        what: 'the send',
      );

      final posts = await rig.ocPostPaths();
      expect(posts.where((p) => p.endsWith('/prompt_async')), [
        '/session/$_ocSession/prompt_async',
      ]);
      expect(
        posts.where((p) => p.contains(_ocOther)),
        isEmpty,
        reason: 'nothing may address the session the lane is not open on',
      );
      // The body, verbatim — opencode's own `parts` shape.
      expect(
        jsonDecode(
          (await rig.fake.call('post_body', args: ['/prompt_async']))!
              as String,
        ),
        {
          'parts': [
            {'text': 'do the thing', 'type': 'text'},
          ],
        },
      );
      expect(
        (await rig.ocSnapshot())['violations'],
        isEmpty,
        reason: "the fake's own pin guard saw no out-of-scope request",
      );
    }, timeout: _cell);

    testWidgets('interject_is_absent_and_refused_before_any_request', (
      tester,
    ) async {
      // The other half of the interject pair: opencode advertises
      // `interject: false`, so the chip is ABSENT (not disabled), and the
      // adapter refuses the mode LOCALLY — nothing reaches the wire.
      final rig = await _oc(tester, busy: true);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      expect(rig.state.capabilities!.kind, 'opencode');
      expect(rig.state.capabilities!.interject, isFalse);
      expect(rig.state.capabilities!.historyCursor, isFalse);

      await rig.pumpUntil(
        tester,
        () => rig.state.activity == BridgeRcActivity.working,
        what: 'a working turn',
      );
      // Working, and STILL no chip: the capability, not the activity, decides
      // whether it is rendered at all.
      expect(find.byKey(const ValueKey('lane-interject')), findsNothing);
      expect(find.byKey(const ValueKey('lane-cancel')), findsOneWidget);

      final before = await rig.ocPostPaths();
      await rig.controller.send('now', mode: BridgeSendMode.interject);
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.state.composerError, isNotNull);
      expect(
        rig.state.composerError!.message.toLowerCase(),
        contains('accepting'),
      );
      expect(
        await rig.ocPostPaths(),
        before,
        reason: 'a refusal that reached the wire is not a local refusal',
      );
    }, timeout: _cell);

    testWidgets('cancel_posts_and_not_accepting_is_an_inline_error', (
      tester,
    ) async {
      final rig = await _oc(tester, busy: true);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.activity == BridgeRcActivity.working,
        what: 'a turn to cancel',
      );

      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await rig.pumpUntil(
        tester,
        () async => (await rig.ocPostPaths()).any((p) => p.endsWith('/abort')),
        what: 'the cancel',
      );
      expect(await rig.ocPostPaths(), contains('/session/$_ocSession/abort'));
      expect(rig.state.composerError, isNull);
      expect(
        jsonDecode(
          (await rig.fake.call('post_body', args: ['/abort']))! as String,
        ),
        <String, Object?>{},
      );

      await rig.fake.call('fail_post', args: ['/abort', 409]);
      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await rig.pumpUntil(
        tester,
        () => rig.state.composerError != null,
        what: 'the inline refusal',
      );
      expect(find.byKey(const ValueKey('lane-composer-error')), findsOneWidget);
      expect(
        rig.state.composerError!.message.toLowerCase(),
        contains('accepting'),
      );
    }, timeout: _cell);

    testWidgets('three_options_render_and_the_semantic_form_is_accepted', (
      tester,
    ) async {
      // opencode synthesizes THREE options, and the third is the split case:
      // the wire id is `reject` while its ACP kind is `reject_once`. So a
      // client that read the id as the semantics would get it wrong, and the
      // SEMANTIC form resolves cleanly here — the exact opposite of gx's
      // five-option ambiguity.
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      await rig.fake.call(
        'stream_permission_asked',
        args: [_ocSession, 'per_root'],
        kwargs: {'command': 'ls -la'},
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.isNotEmpty,
        what: 'the permission',
      );

      final approval = rig.state.approvals.single;
      expect(approval.kind, isA<BridgeLaneApprovalKind_Permission>());
      expect(approval.options.map((o) => o.id), [
        'allow_once',
        'allow_always',
        'reject',
      ]);
      expect(approval.options.map((o) => o.kind), [
        'allow_once',
        'allow_always',
        'reject_once',
      ]);
      for (final option in approval.options) {
        expect(
          find.byKey(ValueKey('lane-option-${option.id}')),
          findsOneWidget,
        );
      }
      // Unambiguous by kind, unlike gx's: one option per kind.
      expect(
        laneOptionFor(
          approval: approval,
          decision: BridgeLaneDecision.allowOnce,
        )?.id,
        'allow_once',
      );

      // **The semantic form**, posted through the controller (the screen always
      // posts the pressed id; this is the other accepted shape).
      await rig.controller.answer(
        'per_root',
        const BridgeLaneAnswer.permission(
          decision: BridgeLaneDecision.allowOnce,
        ),
      );
      await rig.pumpUntil(
        tester,
        () async => (await rig.ocPostPaths()).any((p) => p.endsWith('/reply')),
        what: 'the reply',
      );
      expect(await rig.ocPostPaths(), contains('/permission/per_root/reply'));
      expect(
        jsonDecode(
          (await rig.fake.call(
                'post_body',
                args: ['/permission/per_root/reply'],
              ))!
              as String,
        ),
        {'reply': 'once'},
      );
      expect(rig.state.approvalErrors, isEmpty);
    }, timeout: _cell);

    testWidgets('a_pressed_option_id_posts_its_replys_wire_value', (
      tester,
    ) async {
      // The screen's own path: it posts the OFFERED ID, always. The id and the
      // kind differ on opencode's third option, so this also proves the
      // adapter resolves the reply by KIND rather than by echoing the id.
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      await rig.fake.call(
        'stream_permission_asked',
        args: [_ocSession, 'per_two'],
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.isNotEmpty,
        what: 'the permission',
      );

      await tester.tap(find.byKey(const ValueKey('lane-option-reject')));
      await rig.pumpUntil(
        tester,
        () async => (await rig.ocPostPaths()).any((p) => p.endsWith('/reply')),
        what: 'the reply',
      );
      expect(
        jsonDecode(
          (await rig.fake.call(
                'post_body',
                args: ['/permission/per_two/reply'],
              ))!
              as String,
        ),
        {'reply': 'reject'},
        reason: 'the pressed id resolved to its kind\'s wire value',
      );
    }, timeout: _cell);

    testWidgets('question_with_free_text_appends_the_string', (tester) async {
      // `custom` is OMITTED on the wire, which opencode's own schema documents
      // as "default: true" — so free text IS accepted, and it travels as one
      // more entry on that question's answer list rather than as a flag.
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );
      await rig.fake.call(
        'stream_question_asked',
        args: [_ocSession, 'que_1'],
        kwargs: {
          'header': 'Where should it land?',
          'question': 'Pick a branch, or type one.',
          'options': ['main', 'release'],
        },
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.isNotEmpty,
        what: 'the question',
      );

      final approval = rig.state.approvals.single;
      expect(approval.kind, isA<BridgeLaneApprovalKind_Question>());
      expect(approval.questions, hasLength(1));
      // Positional: opencode files by index, so there is no key at all.
      expect(approval.questions.single.id, isNull);
      expect(
        approval.questions.single.custom,
        isTrue,
        reason: 'an omitted flag means free text is accepted',
      );
      expect(approval.questions.single.header, 'Where should it land?');
      expect(
        find.byKey(const ValueKey('lane-question-header-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('lane-custom-0')), findsOneWidget);
      // No one-click while a text field is on screen: the first chip tap would
      // throw away what was being typed.
      expect(find.byKey(const ValueKey('lane-question-send')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lane-option-0-main')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(
        find.byKey(const ValueKey('lane-custom-0')),
        'or a branch I typed',
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('lane-question-send')));
      await rig.pumpUntil(
        tester,
        () async => (await rig.ocPostPaths()).any((p) => p.endsWith('/reply')),
        what: 'the answer',
      );

      expect(await rig.ocPostPaths(), contains('/question/que_1/reply'));
      expect(
        jsonDecode(
          (await rig.fake.call('post_body', args: ['/question/que_1/reply']))!
              as String,
        ),
        {
          'answers': [
            ['main', 'or a branch I typed'],
          ],
        },
        reason: 'the typed string is APPENDED, and no flag rides with it',
      );
    }, timeout: _cell);

    testWidgets('dropped_stream_reseeds_with_no_partial_view', (tester) async {
      // opencode has no history cursor, so a dropped stream is always a
      // RESEED — the whole generation is read again. With the seed parked, the
      // previous generation must stay whole on screen until the new one is
      // complete.
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      final generation = rig.state.generation;
      final rowsBefore = rig.rowText;
      expect(rowsBefore, contains('It is a reverse proxy.'));

      await rig.fake.call('hold_seed');
      await rig.fake.call('close_streams');
      // The stream is gone and the new seed is parked. The old generation is
      // still the whole truth on screen — held for a while, because a partial
      // view would appear DURING the reseed.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(rig.state.generation, generation);
        expect(rig.rowText, rowsBefore);
      }
      expect(rig.state.stale, isNull, reason: 'a reseed is not a Down');
      expect(find.textContaining('It is a reverse proxy.'), findsOneWidget);

      await rig.fake.call('release_seed');
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > generation,
        what: 'the reseed to complete',
      );
      // …and the new generation is complete, not a fragment.
      expect(rig.rowText, contains('describe this project'));
      expect(rig.rowText, contains('It is a reverse proxy.'));
      expect(rig.state.stale, isNull);
    }, timeout: _cell);

    testWidgets('close_ends_the_pump_and_one_row_is_one_controller', (
      tester,
    ) async {
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.generation > BigInt.zero,
        what: 'the seed',
      );
      await rig.pumpUntil(
        tester,
        () async => (await liveCounters()).activeLanes == BigInt.one,
        what: 'exactly one live lane',
      );

      final first = rig.container.read(laneControllerProvider(_ref));
      expect(first, same(rig.container.read(laneControllerProvider(_ref))));

      await rig.dispose(tester);
      final counters = await liveCounters();
      expect(counters.activeLanes, BigInt.zero);
      expect(counters.activeLaneForwarders, BigInt.zero);
      // The SERVER's own view, and it is polled rather than asserted: the
      // client dropped the socket, but the fake's handler only decrements when
      // its next write fails or its generation check runs (one `_TICK`), so an
      // instant read is a race the harness would lose about half the time.
      var live = -1;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        live = (await rig.fake.call('stream_count'))! as int;
        if (live == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        live,
        0,
        reason: 'closing the lane closed the connections it held',
      );
      await expectLater(first.updates, emitsDone);
    }, timeout: _cell);
  });

  // -------------------------------------------------------------------------
  // the bridge boundary — no agent involved
  // -------------------------------------------------------------------------

  group('the bridge boundary', () {
    testWidgets('unsupported_kind_is_refused_before_any_request', (
      tester,
    ) async {
      // A kind with no adapter is a PERMANENT property of the row, so it is
      // refused BY NAME before any I/O — there is no reason to spend a round
      // trip discovering it. The dial url points at a port nothing is
      // listening on, which is what makes "before any request" load-bearing:
      // a lane that dialled would answer `Unavailable`, not `UnsupportedLane`.
      final dead = await ServerSocket.bind('127.0.0.1', 0);
      final port = dead.port;
      await dead.close();
      // `ACTIVE_LANES` is process-global and this cell opens no lane of its
      // own, so the claim is "no NEW lane", read either side of the refusal.
      final before = (await liveCounters()).activeLanes;

      Object? error;
      try {
        await laneOpen(
          spec: BridgeLaneSpec(
            kind: 'codex',
            sessionId: 'sess-1',
            reportedUrl: 'http://127.0.0.1:$port',
            dialUrl: 'http://127.0.0.1:$port',
          ),
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<BridgeLaneError_UnsupportedLane>());
      expect((error! as BridgeLaneError_UnsupportedLane).kind, 'codex');
      expect(
        laneFailureIsPermanent(error),
        isTrue,
        reason:
            'the retry ladder must not run against an answer that cannot '
            'change',
      );
      expect(
        (await liveCounters()).activeLanes,
        before,
        reason: 'a refused open leaves no lane behind',
      );
    }, timeout: _cell);

    testWidgets('custom_text_round_trips_through_frb', (tester) async {
      // **FRB 2.13 is a beta, and `Vec<Option<String>>` → `List<String?>` is
      // the shape most likely to regress.** §3.13 asks for a bridge echo
      // function; there is none, and adding one is a bridge change rather than
      // a harness one — so the round trip is observed where the shape actually
      // travels: through the real `lane_answer`, onto opencode's wire, read
      // back with `post_body`. That is strictly more than an echo proves,
      // because the decoded value has to survive the adapter too.
      //
      // The pinned literal (`answers: [[]], customText: ['x', null]`) needs a
      // TWO-question approval, and neither fake's control door can build one
      // (`add_question`/`stream_question_asked` each carry exactly one
      // question, and gx's multi-question `question_request` cannot be stored
      // without `add_approval`). So the null element is carried at length one,
      // which still fails loudly on a decoder that cannot represent the hole.
      final rig = await _oc(tester);
      await rig.pumpUntil(
        tester,
        () => rig.state.capabilities != null,
        what: 'the lane',
      );

      // (a) `[null]` — a hole, and nothing is appended.
      await rig.fake.call(
        'stream_question_asked',
        args: [_ocSession, 'que_hole'],
        kwargs: {
          'header': 'h',
          'question': 'q',
          'options': ['left', 'right'],
        },
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.any((a) => a.id == 'que_hole'),
        what: 'the question',
      );
      await rig.controller.answer(
        'que_hole',
        const BridgeLaneAnswer.question(
          answers: [
            ['left'],
          ],
          customText: [null],
        ),
      );
      await rig.pumpUntil(
        tester,
        () async => (await rig.ocPostPaths()).any(
          (p) => p == '/question/que_hole/reply',
        ),
        what: 'the answer with a hole',
      );
      expect(rig.state.approvalErrors['que_hole'], isNull);
      expect(
        jsonDecode(
          (await rig.fake.call(
                'post_body',
                args: ['/question/que_hole/reply'],
              ))!
              as String,
        ),
        {
          'answers': [
            ['left'],
          ],
        },
        reason: 'a null must append nothing at all',
      );

      // (b) `['x']` — the same list shape, a value in it, and it lands. The
      // pair is the control: if `List<String?>` decoded as garbage, exactly one
      // of these two would still have passed by luck.
      await rig.fake.call('remove_request', args: ['que_hole']);
      await rig.fake.call(
        'stream_question_asked',
        args: [_ocSession, 'que_text'],
        kwargs: {
          'header': 'h',
          'question': 'q',
          'options': ['left', 'right'],
        },
      );
      await rig.pumpUntil(
        tester,
        () => rig.state.approvals.any((a) => a.id == 'que_text'),
        what: 'the second question',
      );
      await rig.controller.answer(
        'que_text',
        const BridgeLaneAnswer.question(
          answers: [<String>[]],
          customText: ['x'],
        ),
      );
      await rig.pumpUntil(
        tester,
        () async => (await rig.ocPostPaths()).any(
          (p) => p == '/question/que_text/reply',
        ),
        what: 'the answer with free text',
      );
      expect(rig.state.approvalErrors['que_text'], isNull);
      expect(
        jsonDecode(
          (await rig.fake.call(
                'post_body',
                args: ['/question/que_text/reply'],
              ))!
              as String,
        ),
        {
          'answers': [
            ['x'],
          ],
        },
      );
    }, timeout: _cell);
  });
}

// ---------------------------------------------------------------------------
// the rig
// ---------------------------------------------------------------------------

/// Every cell gets sixty seconds. Long enough for a Rust resubscribe ladder and
/// a parked seed, short enough that a hung cell is a failure rather than a
/// hung CI job.
const _cell = Timeout(Duration(seconds: 60));

/// Every option button on screen, whatever its id — the finder the
/// placeholder-permission cell needs. Asserting a SPECIFIC absent key would
/// prove nothing: no widget could ever carry it.
Finder get _anyOption => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> && key.value.startsWith('lane-option-');
});

/// Poll a condition while pumping real frames. `pumpAndSettle` is never usable
/// here: a WORKING lane pulses its activity badge, and a repeating animation
/// never settles.
///
/// **It keeps pumping after the condition is met**, and that is the important
/// part. Every predicate in this file reads [LaneState] off the controller,
/// which is one broadcast-stream hop and one frame AHEAD of the widget tree —
/// the state is right, `laneStateProvider` has not delivered it yet, and a find
/// run at that instant sees the previous tree. Four frames is the difference
/// between asserting the state and asserting the screen.
extension _PumpUntil on WidgetTester {
  Future<bool> pumpUntil(
    FutureOr<bool> Function() done, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var ok = false;
    while (DateTime.now().isBefore(deadline)) {
      if (await done()) {
        ok = true;
        break;
      }
      await pump(const Duration(milliseconds: 40));
    }
    ok = ok || await done();
    if (ok) await settleTree();
    return ok;
  }

  /// Let the state stream reach the widget tree. Bounded, never
  /// `pumpAndSettle`.
  Future<void> settleTree() async {
    for (var i = 0; i < 4; i++) {
      await pump(const Duration(milliseconds: 30));
    }
  }
}

/// One cell's world: the fake, the container the REAL providers were built in,
/// and the probe ledger.
class _Rig {
  _Rig({
    required this.fake,
    required this.container,
    required this.probes,
    required this.grokHome,
    required this.feed,
  });

  final FakeLaneServer fake;
  final ProviderContainer container;

  /// Every wire command the local [ProbeRunner] was asked to run — so "one
  /// probe" is a count rather than an impression.
  final List<String> probes;
  final Directory? grokHome;
  final _LocalFeed feed;

  bool _disposed = false;

  LaneController get controller => container.read(laneControllerProvider(_ref));
  LaneState get state => controller.state;

  /// The transcript as one string — what a cell greps.
  String get rowText => state.rows.map((r) => r.text).join('\n');

  /// Pump the screen up. Split from construction so a cell can script the fake
  /// (park a seed, seed a history) BEFORE the lane opens.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: shedLightTheme,
          home: const LaneScreen(machine: 'local', slug: '7', title: 'row7'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<bool> pumpUntil(
    WidgetTester tester,
    FutureOr<bool> Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final ok = await tester.pumpUntil(done, timeout: timeout);
    if (!ok) fail('timed out waiting for $what');
    return ok;
  }

  /// Like [pumpUntil] but ANSWERS rather than failing — for a condition a cell
  /// asserts on itself.
  Future<bool> pumpFor(
    WidgetTester tester,
    FutureOr<bool> Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 25),
  }) => tester.pumpUntil(done, timeout: timeout);

  // -- the gx ledger --------------------------------------------------------

  Future<List<Map<String, Object?>>> gxRequests() async =>
      ((await fake.call('requests'))! as List)
          .cast<Map<String, Object?>>()
          .toList();

  Future<List<String>> gxPaths() async =>
      (await gxRequests()).map((r) => r['path']! as String).toList();

  Future<Object?> answeredWith(String approvalId) =>
      fake.call('answered_with', args: [_gxSession, approvalId]);

  /// A working turn, announced the way a leader announces one: the roster row
  /// moves, then a `session` frame invalidates what the client holds.
  ///
  /// `add_session` is re-callable and overwrites the row, which is how the
  /// activity moves without `set_activity` (not allowlisted).
  Future<void> working() async {
    await fake.call(
      'add_session',
      args: [_gxSession],
      kwargs: {'activity': 'working'},
    );
    await fake.call('push_session_frame', args: [_gxSession]);
  }

  /// The real five-option permission, delivered as an `approval` frame.
  ///
  /// Both halves come from Python: the resource envelope is the one
  /// `add_placeholder_approval` returned, and the request payload is the fake's
  /// own `permission_request` builder. Nothing about either shape is
  /// re-derived here.
  Future<void> pushPermission(String id, String command) async {
    final resource = await _resource(
      id,
      'permission',
      'session/request_permission',
      await fake.envelope('permission_request', {
        'session': _gxSession,
        'command': command,
      }),
    );
    await fake.call('push_approval_frame', args: [_gxSession, resource]);
  }

  Future<void> pushQuestion(String id, List<Object?> questions) async {
    final resource = await _resource(
      id,
      'question',
      'x.ai/ask_user_question',
      await fake.envelope('question_request', {
        'session': _gxSession,
        'questions': questions,
      }),
    );
    await fake.call('push_approval_frame', args: [_gxSession, resource]);
  }

  /// The fake's OWN approval-resource envelope, with the method and request it
  /// deliberately leaves null on a placeholder filled in.
  ///
  /// This exists because `add_approval` is not on the control door's allowlist
  /// (see this file's header). It reaches only the FRAME, never the store, so
  /// an approval built this way renders and cannot be answered.
  Future<Map<String, Object?>> _resource(
    String id,
    String kind,
    String method,
    Map<String, Object?> request,
  ) async {
    final placeholder =
        (await fake.call('add_placeholder_approval', args: [_gxSession, id]))!
            as Map<String, Object?>;
    return {...placeholder, 'kind': kind, 'method': method, 'request': request};
  }

  // -- the opencode ledger --------------------------------------------------

  Future<Map<String, Object?>> ocSnapshot() async =>
      (await fake.call('snapshot'))! as Map<String, Object?>;

  Future<List<String>> ocPostPaths() async =>
      ((await fake.call('post_paths'))! as List).cast<String>().toList();

  // -- teardown -------------------------------------------------------------

  /// Tear the lane down through the provider's own `onDispose`, then WAIT for
  /// the counter to come back to zero.
  ///
  /// The wait is not tidiness. `ACTIVE_LANES` is process-global, Riverpod does
  /// not await the `Future` its `onDispose` returns, and `LaneController.close`
  /// awaits a `StreamSubscription.cancel()` before it reaches `lane_close` — so
  /// a cell that returned the instant `dispose()` did would leave its lane
  /// counted, and the NEXT cell's `activeLanes == 1` would read 2. That was a
  /// real cascade: every leak assertion in the file failed for the previous
  /// cell's reason.
  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 50));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final c = await liveCounters();
      // BOTH, because the forwarder's decrement is not the lane's to wait on: a
      // cell that waited only on `activeLanes` handed the next one a non-zero
      // forwarder count, and its leak assertion then failed for the PREVIOUS
      // cell's reason.
      if (c.activeLanes == BigInt.zero &&
          c.activeLaneForwarders == BigInt.zero) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// A gx rig: a temp `$GROK_HOME`, a fake that wrote its discovery record and
/// `0600` token into it, one idle session, and (unless `open: false`) the screen
/// already pumped.
Future<_Rig> _gx(
  WidgetTester tester, {
  bool open = true,
  String? extraSession,
}) async {
  final home = await Directory.systemTemp.createTemp('shed-lane-gx-');
  addTearDown(() => home.delete(recursive: true).catchError((_) => home));
  final fake = await FakeLaneServer.start('gx', home: home.path);
  addTearDown(fake.stop);
  await fake.call(
    'add_session',
    args: [_gxSession],
    kwargs: {'activity': 'idle', 'title': 'the lane session'},
  );
  if (extraSession != null) {
    await fake.call('add_session', args: [extraSession]);
  }
  if (open) {
    await fake.call(
      'set_history',
      args: [
        _gxSession,
        [
          await fake.envelope('chunk', {
            'session': _gxSession,
            'n': 1,
            'kind': 'agent_message_chunk',
            'text': 'seeded from the persisted transcript',
          }),
          await fake.envelope('turn_completed', {
            'session': _gxSession,
            'n': 2,
          }),
        ],
      ],
    );
  }
  return _rig(
    tester,
    fake: fake,
    kind: 'gx',
    sessionId: _gxSession,
    grokHome: home,
    open: open,
  );
}

/// An opencode rig: a fake, one session with a two-turn transcript, and (unless
/// `open: false`) the screen already pumped. No credentials — opencode needs
/// none, and a password-protected server would answer 401.
Future<_Rig> _oc(
  WidgetTester tester, {
  bool open = true,
  String? extraSession,
  bool busy = false,
}) async {
  final fake = await FakeLaneServer.start('opencode');
  addTearDown(fake.stop);
  await fake.call(
    'add_session',
    args: [_ocSession],
    kwargs: {'title': 'the lane session', 'directory': '/work'},
  );
  // **Before the lane opens, because the boundary is SEEDED.** opencode's
  // activity is `working` unless the last boundary was idle, and the only
  // boundary a cell can set through the control door is the one
  // `GET /session/status` reports at seed time — there is no
  // `stream_session_status` knob and the raw `stream` is not allowlisted. So a
  // cell that wants a working turn scripts it before the read, not after.
  if (busy) await fake.call('set_status', args: [_ocSession, 'busy']);
  if (extraSession != null) {
    await fake.call(
      'add_session',
      args: [extraSession],
      kwargs: {'directory': '/elsewhere'},
    );
  }
  if (open) {
    await fake.call(
      'set_simple_transcript',
      args: [_ocSession, 'describe this project', 'It is a reverse proxy.'],
    );
  }
  return _rig(
    tester,
    fake: fake,
    kind: 'opencode',
    sessionId: _ocSession,
    grokHome: null,
    open: open,
  );
}

Future<_Rig> _rig(
  WidgetTester tester, {
  required FakeLaneServer fake,
  required String kind,
  required String sessionId,
  required Directory? grokHome,
  required bool open,
}) async {
  final probes = <String>[];
  final feed = _LocalFeed(
    kind: kind,
    sessionId: sessionId,
    // The REPORTED url — and, because the reach is local, the dial url too.
    serverUrl: fake.reportedUrl,
    grokHome: grokHome?.path,
    probes: probes,
  );
  final container = ProviderContainer(
    // A provider that threw must stay thrown: a retry ladder inside Riverpod
    // would race the controller's own.
    retry: (_, _) => null,
    overrides: [
      machinesProvider.overrideWith((ref) async => const [_local]),
      identitiesProvider.overrideWith((ref) async => []),
      machineFeedControllerProvider('local').overrideWith((ref) => feed),
      machineFeedProvider(
        'local',
      ).overrideWith((ref) => Stream.value(feed.state)),
      // `laneSourceProvider` is NOT overridden. The real FRB bridge is the
      // whole point of this file.
    ],
  );
  final rig = _Rig(
    fake: fake,
    container: container,
    probes: probes,
    grokHome: grokHome,
    feed: feed,
  );
  // Registered before the first pump, so a cell that fails mid-flight still
  // closes its lane and stops its fake.
  addTearDown(() => rig.dispose(tester));
  if (open) await rig.open(tester);
  return rig;
}

/// The machine feed, as a lane needs it — and nothing else.
///
/// The real one dials SSH and calls the FRB-sync `roostCapabilities()` in its
/// constructor. What a lane actually asks of it is four things: the machine
/// record (which decides the reach), the row that carries the stamp, the probe
/// runner, and a forward. Its host is loopback, so [laneReachFor] answers
/// [LaneReach.local] and `acquireForward` is never reached — a call to it is a
/// bug, so it throws rather than returning something plausible.
class _LocalFeed implements MachineFeed {
  _LocalFeed({
    required this.kind,
    required this.sessionId,
    required this.serverUrl,
    required this.grokHome,
    required this.probes,
  });

  final String kind;
  final String sessionId;
  final String serverUrl;
  final String? grokHome;
  final List<String> probes;

  @override
  MachineRecord get machine => _local;

  @override
  MachineFeedState get state => MachineFeedState(
    machine: _local,
    // Authoritative: a feed that has never connected carries no rows, and
    // mapping that to "the row is gone" would abandon the lane at once.
    connectedOnce: true,
    reachable: true,
    sessions: [
      BridgeRcSession(
        host: '',
        shed: '',
        slug: '7',
        displayName: 'row7',
        kind: const BridgeRcKind.gx(),
        state: BridgeRcState.ready,
        managed: true,
        attention: false,
        tabId: 7,
        agentLane: BridgeAgentLaneStamp(
          kind: kind,
          sessionId: sessionId,
          serverUrl: serverUrl,
        ),
      ),
    ],
  );

  @override
  Stream<MachineFeedState> get updates =>
      const Stream<MachineFeedState>.empty();

  /// **The `ProbeRunner` seam's local implementation.** `wireCommand` is
  /// `gxProbeRemoteCommand()` VERBATIM — a single string the far side
  /// re-parses, so running it through `sh -c` here is exactly what an sshd
  /// would do with it. `GROK_HOME` points at the fake's temp home, which is the
  /// only thing that differs from production.
  ///
  /// The bytes come back UNDECODED: they carry a bearer token, and it is parsed
  /// inside Rust's `discovery_from_probe` and dropped there.
  @override
  Future<Uint8List> probe(String wireCommand) async {
    probes.add(wireCommand);
    final result = await Process.run(
      'sh',
      ['-c', wireCommand],
      environment: grokHome == null
          ? const <String, String>{}
          : <String, String>{'GROK_HOME': grokHome!},
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    return Uint8List.fromList((result.stdout as List<Object?>).cast<int>());
  }

  @override
  Future<LaneLease> acquireForward(int remotePort) =>
      throw StateError('a local-reach lane must never ask for a forward');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

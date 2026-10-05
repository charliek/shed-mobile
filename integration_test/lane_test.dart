// **The hermetic agent-lane harness** (plan 018 §3.13).
//
// One `LaneController` + one pumped `LaneScreen` per cell, driven through the
// REAL FRB bridge (`BridgeLaneSource`, not a stub) against shed's OWN opencode
// fake, hosted by `desktop/tools/shedtest/fake_lane_server.py` on a loopback
// control port. Nothing is mocked between Dart and the wire: the adapter, the
// fold, the staged view and the pump are all the shipped ones.
//
// **The gx lane was retired in plan 025** (shed-mobile#33, CM1) — its half of
// this harness (the probe seam, the credential-refresh cell, the five-option
// and question cells recorded off a live gx leader) went with it. What is
// left is the opencode half plus the bridge-boundary cells below, which exist
// for no adapter in particular.
//
// ## Why this can be hermetic at all
//
// **The reach is LOCAL, because this harness SAYS so.** `_rig` overrides
// `laneReachProvider` with [LaneReach.local] — the one caller that does. It is
// never inferred from the fake's loopback host: production always forwards (see
// `laneReachProvider`'s docstring for the shed-VM case that killed the
// hostname heuristic). With the override, `dial_url == reported_url`, so there
// is no SSH, no forward and no sshd — the forward has its own hermetic tests
// (§3.10).
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
// ## The opencode wire ledger
//
// `requests()`'s shape is unchanged and stays that way —
// `{method, path, query, had_bearer, bearer_ok}`, no body: shed's own
// `test_fake_lane_server.py` pins that key set exactly, and widening it would
// put a token-bearing body into the one ledger a failure prints.
//
// The opencode fake has its own pair (`post_body`, `post_paths`), so every
// opencode cell asserts the real wire body too. Two cells here are NOT in §3.13
// and exist because the contract's refusals need approvals the §3.13 cells
// cannot also be: `a_placeholders_reject_posts_and_a_second_answer_is_refused`
// (`Reject` against a placeholder — the one answer that needs no option list —
// and then the `409 already_submitted` a second answer earns) and
// `a_pressed_option_id_posts_its_replys_wire_value` (opencode's id/kind split,
// where the pressed id and its reply value differ).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

const _ocSession = 'ses_root';
const _ocOther = 'ses_other';

/// The lane's identity on the phone: the machine, and the ROW's slug.
const _ref = (machine: 'local', slug: '7');

/// The machine record the lane's feed is built from. Its host is loopback only
/// because the fake really is on this device's loopback — it is NOT what makes
/// the reach local. That comes from `_rig`'s explicit [laneReachProvider]
/// override; production forwards whatever the host says.
const _local = MachineRecord(name: 'local', host: '127.0.0.1');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

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
      // **§3.13's pinned literal (`answers: [[]], customText: ['x', null]`)**
      // needed a TWO-question approval before plan 025 retired the gx lane
      // (only gx's `question_request` carried more than one; opencode's
      // `add_question`/`stream_question_asked` each carry exactly one). This
      // pair stands in for it now: it proves something a single two-entry
      // literal cannot — the hole and the value at the SAME length, one answer
      // apart, so a decoder that DROPPED nulls (rather than mis-aligning them)
      // is caught by the (a)/(b) contrast, where a single two-entry literal
      // would still have landed `'x'`
      // in slot 0 and passed.
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
  _Rig({required this.fake, required this.container, required this.feed});

  final FakeLaneServer fake;
  final ProviderContainer container;
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

  /// Type into the composer, re-focusing it first, and prove the text landed.
  ///
  /// **The tap is load-bearing the SECOND time a cell types.**
  /// `WidgetTester.enterText` requests the keyboard only for an editable the
  /// binding has not focused before (`binding.dart:set focusedEditable`), so
  /// once anything else has taken focus — the interject chip — the engine-side
  /// connection is closed and the new value is delivered to a client that is no
  /// longer current (`test_text_input.dart:updateEditingValue` sends
  /// `_client ?? -1`). It is dropped in SILENCE: the composer stays empty,
  /// `_send` returns before logging anything, and the cell times out on a send
  /// that never happened. Tapping the field re-attaches it; the expectation
  /// below is what makes the next regression legible instead of a timeout.
  Future<void> typeInComposer(WidgetTester tester, String text) async {
    final input = find.byKey(const ValueKey('lane-input'));
    await tester.tap(input);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(input, text);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.widget<TextField>(input).controller!.text,
      text,
      reason: 'the composer never received the text, so no send could follow',
    );
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
  return _rig(tester, fake: fake, sessionId: _ocSession, open: open);
}

Future<_Rig> _rig(
  WidgetTester tester, {
  required FakeLaneServer fake,
  required String sessionId,
  required bool open,
}) async {
  final feed = _LocalFeed(
    sessionId: sessionId,
    // The REPORTED url — and, because this rig overrides the reach to local,
    // the dial url too.
    serverUrl: fake.reportedUrl,
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
      // **The one override that makes this harness hermetic.** Production is
      // `LaneReach.machine` unconditionally — the fake's loopback host means
      // nothing to it — so the no-forward, no-sshd path has to be ASKED for
      // here rather than fallen into.
      laneReachProvider.overrideWithValue(LaneReach.local),
      // `laneSourceProvider` is NOT overridden. The real FRB bridge is the
      // whole point of this file.
    ],
  );
  final rig = _Rig(fake: fake, container: container, feed: feed);
  // Registered before the first pump, so a cell that fails mid-flight still
  // closes its lane and stops its fake.
  addTearDown(() => rig.dispose(tester));
  if (open) await rig.open(tester);
  return rig;
}

/// The machine feed, as a lane needs it — and nothing else.
///
/// The real one dials SSH and calls the FRB-sync `roostCapabilities()` in its
/// constructor. What a lane actually asks of it is three things: the machine
/// record, the row that carries the stamp, and a forward. The record does NOT
/// decide the reach: nothing on this fake is read for that. `_rig` overrides
/// [laneReachProvider] to [LaneReach.local], so `acquireForward` is never
/// reached. A call to it means the override is gone, so it throws rather than
/// returning something plausible.
class _LocalFeed implements MachineFeed {
  _LocalFeed({required this.sessionId, required this.serverUrl});

  final String sessionId;
  final String serverUrl;

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
        kind: const BridgeRcKind.opencode(),
        state: BridgeRcState.ready,
        managed: true,
        attention: false,
        tabId: 7,
        agentLane: BridgeAgentLaneStamp(
          kind: 'opencode',
          sessionId: sessionId,
          serverUrl: serverUrl,
        ),
      ),
    ],
  );

  @override
  Stream<MachineFeedState> get updates =>
      const Stream<MachineFeedState>.empty();

  @override
  Future<LaneLease> acquireForward(int remotePort) =>
      throw StateError('a local-reach lane must never ask for a forward');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

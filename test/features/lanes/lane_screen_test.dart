import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/lanes/lane_screen.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';
import 'package:shed_mobile/ssh/lane_forward.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import '../../lanes/fake_lane_lease.dart';

/// **The lane screen** (plan 018 §3.12) — every affordance driven through the
/// [LaneSource] stub, so no native library is loaded and no machine is dialled.
///
/// The wiring under test is the REAL one: `laneStateProvider` →
/// `laneControllerProvider` → `LaneController`, with only the bridge and the
/// machine feed replaced. That matters, because most of what can go wrong here
/// is a screen that reads the right value from the wrong place.
///
/// The claims that would fail SILENTLY in production, each with its negative
/// control:
///
/// 1. **An option button posts the id it was labelled with.** A live gx
///    permission offers FIVE options of which TWO declare `allow_once`, so a
///    by-kind decision cannot name one — the control is that pressing the
///    SECOND allow-once posts ITS id, not the first's, and not a
///    [BridgeLaneAnswer_Permission] at all.
/// 2. **A placeholder permission renders no allow button.** gx announces every
///    approval twice, the first time with no options; the control is that a
///    real five-option card DOES render buttons under the same predicate.
/// 3. **Interject is absent vs present-but-disabled.** Absent means the adapter
///    cannot do it (opencode); disabled means it can but there is no turn to
///    interject. Collapsing the two hides a capability or offers a refusal.
/// 4. **The send MODE is recomputed at send time.** A turn that ended between
///    the render and the tap must send `Queue`, whatever the toggle still says.
void main() {
  group('the composer lifecycle', () {
    testWidgets('a send that lands after the screen is gone touches nothing', (
      tester,
    ) async {
      // The regression: `_guarded` called its `onSuccess` before the `mounted`
      // check, and `_send` passes `_input.clear`. A send still in flight when
      // the route went away therefore reached a disposed
      // `TextEditingController`, which throws.
      //
      // `runAsync` is required, not decoration: the controller's teardown
      // awaits a `StreamSubscription.cancel()` that hands back Dart's
      // root-zone null future, and `FakeAsync` never resumes that one.
      await tester.runAsync(() async {
        final rig = _Rig();
        rig.source.holdSend = Completer<void>();
        await _pump(tester, rig);

        await tester.enterText(find.byKey(const ValueKey('lane-input')), 'hi');
        await tester.tap(find.byKey(const ValueKey('lane-send')));
        await tester.pump();
        expect(rig.source.sends, hasLength(1), reason: 'the send is in flight');

        // The screen goes away with the verb still unresolved.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // ...and only now does it come back.
        rig.source.holdSend!.complete();
        await tester.pump(const Duration(milliseconds: 50));
      });

      // The assertion is that nothing was thrown into the zone: a `clear()` on
      // a disposed controller surfaces here.
      expect(tester.takeException(), isNull);
    });
  });

  group('the permission card', () {
    testWidgets('renders every offered option and posts the PRESSED id', (
      tester,
    ) async {
      // The real gx shape: five options, two of them `allow_once`. A client
      // that resolved a DECISION to an option here would have to pick between
      // two equally-valid matches — which is exactly why `lane_option_for`
      // answers `None` for it and why this posts `Choice{optionId}`.
      final rig = _Rig(
        snapshot: _snap(
          approvals: [
            _approval(
              kind: const BridgeLaneApprovalKind.permission(),
              options: const [
                BridgeLaneApprovalOption(
                  id: 'opt-allow-session',
                  label: 'Allow once',
                  kind: 'allow_once',
                ),
                BridgeLaneApprovalOption(
                  id: 'opt-allow-tool',
                  label: 'Allow once for this tool',
                  kind: 'allow_once',
                ),
                BridgeLaneApprovalOption(
                  id: 'opt-allow-always',
                  label: 'Always allow',
                  kind: 'allow_always',
                ),
                BridgeLaneApprovalOption(
                  id: 'opt-reject',
                  label: 'Reject',
                  kind: 'reject_once',
                ),
                BridgeLaneApprovalOption(
                  id: 'opt-reject-always',
                  label: 'Reject and stop asking',
                  kind: 'reject_always',
                ),
              ],
            ),
          ],
        ),
      );
      await _pump(tester, rig);

      expect(_anyOption, findsNWidgets(5));
      // Labelled by the AGENT, not by kind — two options share `allow_once`
      // and read completely differently.
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.text('Allow once for this tool'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('lane-option-opt-allow-tool')),
      );
      await _settle(tester);

      final posted = rig.source.answers.single;
      expect(posted.approvalId, 'ask-1');
      expect(
        posted.answer,
        isA<BridgeLaneAnswer_Choice>().having(
          (a) => a.optionId,
          'optionId',
          'opt-allow-tool',
        ),
        reason: 'the pressed id, not the first allow_once and not a decision',
      );
      expect(
        posted.answer,
        isNot(isA<BridgeLaneAnswer_Permission>()),
        reason: 'a decision cannot name one of two allow_once options',
      );
    });

    testWidgets('a plan_approval with options is answered the same way', (
      tester,
    ) async {
      final rig = _Rig(
        snapshot: _snap(
          approvals: [
            _approval(
              kind: const BridgeLaneApprovalKind.planApproval(),
              title: 'Approve this plan?',
              options: const [
                BridgeLaneApprovalOption(
                  id: 'plan-yes',
                  label: 'Approve',
                  kind: 'allow_once',
                ),
                BridgeLaneApprovalOption(
                  id: 'plan-no',
                  label: 'Reject',
                  kind: 'reject_once',
                ),
              ],
            ),
          ],
        ),
      );
      await _pump(tester, rig);

      expect(_anyOption, findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('lane-option-plan-yes')));
      await _settle(tester);

      expect(
        rig.source.answers.single.answer,
        isA<BridgeLaneAnswer_Choice>().having(
          (a) => a.optionId,
          'optionId',
          'plan-yes',
        ),
      );
    });

    testWidgets('a refused answer lands on THAT card, and does not throw', (
      tester,
    ) async {
      // gx refuses a decision that matches no offered option with
      // `bad_request`, and either adapter refuses a second answer to one ask.
      // The verb never throws — the refusal is state, keyed by the approval
      // that raised it, because a toast would not say which card.
      final rig =
          _Rig(
              snapshot: _snap(
                approvals: [
                  _approval(
                    kind: const BridgeLaneApprovalKind.permission(),
                    options: const [
                      BridgeLaneApprovalOption(id: 'opt-a', label: 'Allow'),
                    ],
                  ),
                ],
              ),
            )
            ..source.answerFailure = const BridgeLaneError.badRequest(
              msg: 'no such option',
            );
      await _pump(tester, rig);

      await tester.tap(find.byKey(const ValueKey('lane-option-opt-a')));
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('lane-approval-error-ask-1')),
        findsOneWidget,
      );
      expect(find.text('no such option'), findsOneWidget);
    });
  });

  group('the placeholder approval', () {
    testWidgets('a permission with NO options shows no allow button', (
      tester,
    ) async {
      // THE gx wire fact: every approval is announced twice, and the first
      // announcement is a placeholder with a null method and no request. A
      // card that inferred "permission ⇒ allow/deny" would offer to approve an
      // ask it cannot describe.
      final rig = _Rig(
        snapshot: _snap(
          approvals: [
            _approval(kind: const BridgeLaneApprovalKind.permission()),
          ],
        ),
      );
      await _pump(tester, rig);

      expect(
        _anyOption,
        findsNothing,
        reason: 'nothing here is answerable yet',
      );
      // …and the card DID render, with the one answer that is always safe.
      expect(find.byKey(const ValueKey('lane-waiting-ask-1')), findsOneWidget);
      expect(find.textContaining('waiting for details'), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-reject-ask-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lane-reject-ask-1')));
      await _settle(tester);
      expect(rig.source.answers.single.answer, isA<BridgeLaneAnswer_Reject>());
    });

    testWidgets('an unknown approval kind falls to the raw card', (
      tester,
    ) async {
      final rig = _Rig(
        snapshot: _snap(
          approvals: [
            _approval(
              kind: const BridgeLaneApprovalKind.other(raw: 'tool_elicitation'),
              // Options are present, and are still NOT offered: an unknown
              // kind's options mean something this build has not been told.
              options: const [
                BridgeLaneApprovalOption(id: 'opt-a', label: 'Sure'),
              ],
              requestJson: '{"method":"tool_elicitation","weird":true}',
            ),
          ],
        ),
      );
      await _pump(tester, rig);

      expect(_anyOption, findsNothing);
      expect(find.textContaining('tool_elicitation'), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-reject-ask-1')), findsOneWidget);

      // The raw body is COLLAPSED until asked for — a request payload is a wall
      // of JSON, and it is evidence rather than something to read first.
      expect(find.byKey(const ValueKey('lane-raw-body-ask-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('lane-raw-ask-1')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-raw-body-ask-1')), findsOneWidget);
    });
  });

  group('the question form', () {
    testWidgets('a custom question shows the field and posts customText', (
      tester,
    ) async {
      final rig = _Rig(
        snapshot: _snap(
          approvals: [
            _approval(
              kind: const BridgeLaneApprovalKind.question(),
              questions: const [
                BridgeLaneQuestion(
                  header: 'Which branch?',
                  question: 'pick one, or say something else',
                  options: [
                    BridgeLaneApprovalOption(id: 'main', label: 'main'),
                    BridgeLaneApprovalOption(id: 'dev', label: 'dev'),
                  ],
                  multiple: false,
                  // gx advertises this on its questions now, which is exactly
                  // why gx questions lose one-click.
                  custom: true,
                ),
              ],
            ),
          ],
        ),
      );
      await _pump(tester, rig);

      expect(find.byKey(const ValueKey('lane-custom-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lane-question-send')),
        findsOneWidget,
        reason: 'a custom question is never one-click',
      );

      await tester.enterText(
        find.byKey(const ValueKey('lane-custom-0')),
        'the release branch',
      );
      await _settle(tester);
      expect(
        rig.source.answers,
        isEmpty,
        reason: 'typing is not answering — Send answer is',
      );

      await tester.tap(find.byKey(const ValueKey('lane-question-send')));
      await _settle(tester);

      final posted = rig.source.answers.single.answer;
      expect(
        posted,
        isA<BridgeLaneAnswer_Question>()
            .having((a) => a.answers, 'answers', [<String>[]])
            .having((a) => a.customText, 'customText', ['the release branch']),
      );
    });

    testWidgets(
      'one-click ONLY for a single non-multiple non-custom question',
      (tester) async {
        final rig = _Rig(
          snapshot: _snap(
            approvals: [
              _approval(
                kind: const BridgeLaneApprovalKind.question(),
                questions: const [
                  BridgeLaneQuestion(
                    header: 'Continue?',
                    question: '',
                    options: [
                      BridgeLaneApprovalOption(id: 'yes', label: 'Yes'),
                      BridgeLaneApprovalOption(id: 'no', label: 'No'),
                    ],
                    multiple: false,
                    custom: false,
                  ),
                ],
              ),
            ],
          ),
        );
        await _pump(tester, rig);

        expect(
          find.byKey(const ValueKey('lane-question-send')),
          findsNothing,
          reason: 'the tap IS the whole answer here',
        );
        // Question options are keyed by question index as well as by id: two
        // questions in one form can both offer "yes".
        await tester.tap(find.byKey(const ValueKey('lane-option-0-yes')));
        await _settle(tester);

        expect(
          rig.source.answers.single.answer,
          isA<BridgeLaneAnswer_Question>()
              .having((a) => a.answers, 'answers', [
                ['yes'],
              ])
              .having((a) => a.customText, 'customText', isEmpty),
        );
      },
    );

    testWidgets('a multi-select form collects before it posts', (tester) async {
      final rig = _Rig(
        snapshot: _snap(
          approvals: [
            _approval(
              kind: const BridgeLaneApprovalKind.question(),
              questions: const [
                BridgeLaneQuestion(
                  header: 'Which files?',
                  question: '',
                  options: [
                    BridgeLaneApprovalOption(id: 'a', label: 'a.dart'),
                    BridgeLaneApprovalOption(id: 'b', label: 'b.dart'),
                  ],
                  multiple: true,
                  custom: false,
                ),
              ],
            ),
          ],
        ),
      );
      await _pump(tester, rig);

      await tester.tap(find.byKey(const ValueKey('lane-option-0-a')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-option-0-b')));
      await _settle(tester);
      expect(
        rig.source.answers,
        isEmpty,
        reason: 'a multi-select must not post on the first tap',
      );

      await tester.tap(find.byKey(const ValueKey('lane-question-send')));
      await _settle(tester);

      expect(
        rig.source.answers.single.answer,
        isA<BridgeLaneAnswer_Question>().having((a) => a.answers, 'answers', [
          ['a', 'b'],
        ]),
      );
    });

    testWidgets('a question kind with no questions falls to the raw card', (
      tester,
    ) async {
      // The question-shaped placeholder — the same double-announcement, one
      // kind over.
      final rig = _Rig(
        snapshot: _snap(
          approvals: [_approval(kind: const BridgeLaneApprovalKind.question())],
        ),
      );
      await _pump(tester, rig);

      expect(_anyOption, findsNothing);
      expect(find.byKey(const ValueKey('lane-reject-ask-1')), findsOneWidget);
    });
  });

  group('the composer', () {
    testWidgets('sends what was typed, in Queue mode by default', (
      tester,
    ) async {
      final rig = _Rig();
      await _pump(tester, rig);

      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'describe this project',
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);

      expect(rig.source.sends.single.text, 'describe this project');
      expect(rig.source.sends.single.mode, BridgeSendMode.queue);
    });

    testWidgets('a refused send is an inline error, not a thrown exception', (
      tester,
    ) async {
      final rig = _Rig()
        ..source.sendFailure = const BridgeLaneError.notAccepting();
      await _pump(tester, rig);

      await tester.enterText(find.byKey(const ValueKey('lane-input')), 'go');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);

      expect(find.byKey(const ValueKey('lane-composer-error')), findsOneWidget);
      expect(find.textContaining('not accepting'), findsOneWidget);
    });

    testWidgets('Cancel is offered only while a turn is running', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _snap(activity: BridgeRcActivity.idle));
      await _pump(tester, rig);
      expect(
        find.byKey(const ValueKey('lane-cancel')),
        findsNothing,
        reason: 'nothing is running to cancel',
      );
      // The control: the row DID render.
      expect(find.byKey(const ValueKey('lane-send')), findsOneWidget);

      rig.bump(_snap(activity: BridgeRcActivity.working));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-cancel')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await _settle(tester);
      expect(rig.source.cancels, 1);
    });
  });

  group('interject', () {
    testWidgets('is absent for an adapter that cannot do it', (tester) async {
      // opencode answers `interject: false`. Absent, not disabled: a greyed
      // toggle promises a capability that will never light up.
      final rig = _Rig(
        kind: 'opencode',
        capabilities: _caps(kind: 'opencode', interject: false),
        snapshot: _snap(activity: BridgeRcActivity.working),
      );
      await _pump(tester, rig);

      expect(find.byKey(const ValueKey('lane-interject')), findsNothing);
      // The control: a WORKING opencode lane renders the rest of that row, so
      // the absence is about the capability and not about an empty composer.
      expect(find.byKey(const ValueKey('lane-cancel')), findsOneWidget);
    });

    testWidgets('is present but DISABLED for gx while nothing is running', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _snap(activity: BridgeRcActivity.idle));
      await _pump(tester, rig);

      final chip = find.byKey(const ValueKey('lane-interject'));
      expect(chip, findsOneWidget, reason: 'gx advertises interject');
      expect(
        tester.widget<FilterChip>(chip).onSelected,
        isNull,
        reason: 'there is no turn to interject into',
      );

      rig.bump(_snap(activity: BridgeRcActivity.working));
      await _settle(tester);
      expect(tester.widget<FilterChip>(chip).onSelected, isNotNull);
    });

    testWidgets('the send mode is recomputed at SEND time', (tester) async {
      // The toggle records an intent. A turn that ended between the render
      // that enabled it and the tap that used it must not send `Interject` —
      // the adapter would answer `not_accepting`, for a mode the person never
      // really chose.
      final rig = _Rig(snapshot: _snap(activity: BridgeRcActivity.working));
      await _pump(tester, rig);

      await tester.tap(find.byKey(const ValueKey('lane-interject')));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('lane-input')), 'stop');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);
      expect(rig.source.sends.single.mode, BridgeSendMode.interject);

      // The turn ends; the toggle is still on.
      rig.bump(_snap(activity: BridgeRcActivity.idle));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('lane-input')), 'again');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);

      expect(rig.source.sends.last.mode, BridgeSendMode.queue);
    });
  });

  group('the header and the transcript', () {
    testWidgets('renders the rows, newest last, through the shared tile', (
      tester,
    ) async {
      final rig = _Rig(
        snapshot: _snap(
          rows: [
            _row(1, 'user', 'describe this project'),
            _row(2, 'assistant', 'It is a reverse proxy.'),
          ],
          activity: BridgeRcActivity.idle,
        ),
      );
      await _pump(tester, rig);

      expect(find.byKey(const ValueKey('lane-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-msg-1')), findsOneWidget);
      expect(find.text('It is a reverse proxy.'), findsOneWidget);
      // Newest at the bottom.
      expect(
        tester.getCenter(find.byKey(const ValueKey('lane-msg-1'))).dy,
        lessThan(tester.getCenter(find.byKey(const ValueKey('lane-msg-2'))).dy),
      );
      // The activity chip, in the shared activity colours.
      expect(find.byKey(const ValueKey('lane-activity')), findsOneWidget);
      expect(find.text('idle'), findsOneWidget);
      // The row's own name is the title — a lane's snapshot carries no session
      // title at all (the fold projects only `activity`).
      expect(find.text('row7'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a stale lane names the reason, and a dead one says so', (
      tester,
    ) async {
      // `unknown_session` is the one reason that ends the retries: the agent
      // does not know this session, so re-opening would ask the same question
      // forever. The screen renders that terminal state rather than a live
      // transcript from a transport nobody holds.
      final rig = _Rig(
        snapshot: _snap(
          rows: [_row(1, 'assistant', 'last thing I said')],
          stale: 'down: unknown_session',
        ),
      );
      await _pump(tester, rig);

      expect(find.byKey(const ValueKey('lane-stale')), findsOneWidget);
      expect(
        find.textContaining('unknown_session'),
        findsOneWidget,
        reason: 'the reason, not a generic "disconnected"',
      );
      // The last complete generation is still readable.
      expect(find.text('last thing I said'), findsOneWidget);

      // Then the teardown lands — and it needs the REAL event loop. The
      // controller's `_dropHandle` awaits `StreamSubscription.cancel()`, and a
      // cancel with no `onCancel` hands back Dart's root-zone
      // `Future._nullFuture`, which `FakeAsync` never resumes however many
      // frames a test pumps. `runAsync` is the only thing that finishes it.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);

      expect(find.byKey(const ValueKey('lane-note')), findsOneWidget);
      expect(find.textContaining('given up on'), findsOneWidget);
      // …and nothing pretends the lane can still be steered.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('lane-send')))
            .onPressed,
        isNull,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// the rig
// ---------------------------------------------------------------------------

const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');
const _ref = (machine: 'mini3', slug: '7');

/// Every option button on screen, whatever its id — the finder the
/// placeholder-permission control needs. Asserting a SPECIFIC absent key would
/// prove nothing: no widget could ever carry it.
Finder get _anyOption => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> && key.value.startsWith('lane-option-');
});

/// Bounded pumps, not `pumpAndSettle`: a WORKING lane pulses its activity
/// badge, and a repeating animation never settles (the watch screen's tests
/// bound their pumps for the same reason).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The overrides are built HERE rather than handed back from the rig, because
/// Riverpod does not export the `Override` type a `List<Override>` getter would
/// have to name (the target-picker test's precedent).
Future<void> _pump(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        machinesProvider.overrideWith((ref) async => const [_mini3]),
        identitiesProvider.overrideWith((ref) async => []),
        machineFeedControllerProvider('mini3').overrideWith((ref) => rig.feed),
        machineFeedProvider(
          'mini3',
        ).overrideWith((ref) => Stream.value(rig.feed.state)),
        laneSourceProvider.overrideWithValue(rig.source),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const LaneScreen(machine: 'mini3', slug: '7', title: 'row7'),
      ),
    ),
  );
  await _settle(tester);
}

BridgeRcFeedMessage _row(int seq, String role, String text) =>
    BridgeRcFeedMessage(
      seq: BigInt.from(seq),
      role: role,
      msgType: 'text',
      text: text,
    );

BridgeLaneSnapshot _snap({
  List<BridgeRcFeedMessage> rows = const [],
  BridgeRcActivity activity = BridgeRcActivity.idle,
  List<BridgeLaneApproval> approvals = const [],
  String? stale,
  int generation = 1,
}) => BridgeLaneSnapshot(
  messages: rows,
  full: true,
  activity: activity,
  generation: BigInt.from(generation),
  stale: stale,
  approvals: approvals,
  needsCredentials: false,
);

BridgeLaneApproval _approval({
  required BridgeLaneApprovalKind kind,
  String id = 'ask-1',
  String title = 'Run `rm -rf build`?',
  List<BridgeLaneApprovalOption> options = const [],
  List<BridgeLaneQuestion> questions = const [],
  String requestJson = '{"method":null}',
}) => BridgeLaneApproval(
  id: id,
  sessionId: 'sess-7',
  kind: kind,
  status: const BridgeLaneApprovalStatus.pending(),
  title: title,
  options: options,
  questions: questions,
  requestJson: requestJson,
);

BridgeLaneCapabilities _caps({String kind = 'gx', bool interject = true}) =>
    BridgeLaneCapabilities(
      kind: kind,
      interject: interject,
      create: true,
      cancel: true,
      approvals: true,
      historyCursor: true,
    );

/// The screen, the real providers, and a stubbed bridge + machine feed.
class _Rig {
  _Rig({
    BridgeLaneSnapshot? snapshot,
    BridgeLaneCapabilities? capabilities,
    String kind = 'gx',
  }) : source = _FakeSource(
         current: snapshot ?? _snap(),
         caps: capabilities ?? _caps(),
       ),
       feed = _FakeFeed(kind: kind);

  final _FakeSource source;
  final _FakeFeed feed;

  /// Replace what the bridge will answer with, and nudge — which is how every
  /// change reaches this screen in production too.
  void bump(BridgeLaneSnapshot next) => source.bump(next);
}

class _FakeSource implements LaneSource {
  _FakeSource({required this.current, required this.caps});

  /// What the next `snapshot()` will answer with. `current`, not `snapshot` —
  /// that name is a method on [LaneSource].
  BridgeLaneSnapshot current;
  final BridgeLaneCapabilities caps;
  final _nudges = StreamController<bool>.broadcast();

  final specs = <BridgeLaneSpec>[];
  final sends = <({String text, BridgeSendMode mode})>[];
  final answers = <({String approvalId, BridgeLaneAnswer answer})>[];
  int cancels = 0;

  /// When set, the next `send`/`answer` is refused with it — the refusal path
  /// the controller turns into state rather than an exception.
  Object? sendFailure;
  Object? answerFailure;

  /// When set, `send` awaits this before returning, so a test can unmount the
  /// screen while the verb is still in flight.
  Completer<void>? holdSend;

  void bump(BridgeLaneSnapshot next) {
    current = next;
    _nudges.add(true);
  }

  @override
  String gxProbeCommand() => "sh -c 'probe'";

  @override
  Future<LaneHandle> open(BridgeLaneSpec spec) async {
    specs.add(spec);
    return _FakeHandle();
  }

  @override
  Stream<bool> nudges(LaneHandle handle) => _nudges.stream;

  @override
  BridgeLaneCapabilities capabilities(LaneHandle handle) => caps;

  @override
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq) => current;

  @override
  Future<void> send(
    LaneHandle handle, {
    required String text,
    required BridgeSendMode mode,
  }) async {
    sends.add((text: text, mode: mode));
    final hold = holdSend;
    if (hold != null) await hold.future;
    final failure = sendFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> cancel(LaneHandle handle) async {
    cancels++;
    final failure = sendFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> answer(
    LaneHandle handle, {
    required String approvalId,
    required BridgeLaneAnswer answer,
  }) async {
    answers.add((approvalId: approvalId, answer: answer));
    final failure = answerFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> refreshCredentials(
    LaneHandle handle,
    Uint8List gxProbeStdout,
  ) async {}

  @override
  void close(LaneHandle handle) {}
}

class _FakeHandle implements LaneHandle {}

/// A [MachineFeed] the provider can be handed: the real one dials SSH and calls
/// the FRB-sync `roostCapabilities()` in its constructor, so it cannot exist in
/// a widget test at all.
class _FakeFeed implements MachineFeed {
  _FakeFeed({required this.kind});

  final String kind;

  @override
  MachineRecord get machine => _mini3;

  @override
  MachineFeedState get state => MachineFeedState(
    machine: _mini3,
    connectedOnce: true,
    reachable: true,
    sessions: [
      BridgeRcSession(
        host: '',
        shed: '',
        slug: _ref.slug,
        displayName: 'row7',
        kind: const BridgeRcKind.gx(),
        state: BridgeRcState.ready,
        managed: true,
        attention: false,
        tabId: 7,
        agentLane: BridgeAgentLaneStamp(
          kind: kind,
          sessionId: 'sess-7',
          serverUrl: 'http://127.0.0.1:2421',
        ),
      ),
    ],
  );

  @override
  Stream<MachineFeedState> get updates =>
      const Stream<MachineFeedState>.empty();

  @override
  Future<Uint8List> probe(String wireCommand) async =>
      Uint8List.fromList([9, 9]);

  @override
  Future<LaneLease> acquireForward(int remotePort) async =>
      FakeLaneLease(41000);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

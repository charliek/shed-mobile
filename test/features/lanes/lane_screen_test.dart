import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/lanes/lane_screen.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_settings.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/lanes/lane_state.dart';
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
/// 5. **Capabilities and the header come from the SNAPSHOT** (plan 025): the
///    session's capabilities ride the lane's stream — there is no getter to
///    cache them from at open — and the header reads the live session row.
/// 6. **Stop, Cancel and the banner** (plan 025 §3.7.3): Stop exists only when
///    the capabilities say `stop` and asks before it ends the session; Cancel
///    only when they say `cancel` (and a turn is running); the banner tells a
///    lane reconnecting on its own (`stale`, not `ended`) from one that is
///    over.
/// 7. **The settings chip and sheet** (plan 025 §3.10): offered only where the
///    capabilities say `settings`, drawn from the session's own settings and
///    re-drawn from its next `Settings` (a model change redraws the options, a
///    change from another client appears in the open sheet), a refusal inline
///    on its row, and a change lost to a drop "not confirmed" — never shown as
///    applied — until the next `Settings`.
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

    testWidgets('a send whose answer was LOST keeps its text and says so in '
        'the desktop\'s words', (tester) async {
      final rig = _Rig()
        ..source.sendFailure = const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: the connection dropped',
        );
      await _pump(tester, rig);

      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'did it land?',
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('lane-composer-error')))
            .data,
        laneSendOutcomeUnknown,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('lane-input')))
            .controller!
            .text,
        'did it land?',
        reason: 'never resent, never cleared: the person decides',
      );
    });

    testWidgets('Cancel is gated on the snapshot\'s capabilities', (
      tester,
    ) async {
      // A working session whose capabilities say `cancel: false` gets NO
      // Cancel — a button whose only outcome is a refusal is worse than none.
      final rig = _Rig(
        snapshot: _snap(
          activity: BridgeRcActivity.working,
          capabilities: _caps(interject: false, cancel: false),
        ),
      );
      await _pump(tester, rig);
      expect(find.byKey(const ValueKey('lane-cancel')), findsNothing);
      // The control: the same working session, saying `cancel`, gets one.
      rig.bump(
        _snap(
          activity: BridgeRcActivity.working,
          capabilities: _caps(interject: false),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-cancel')), findsOneWidget);

      // And before any seed has stated them, there is nothing to offer.
      rig.bump(_snap(activity: BridgeRcActivity.working, capabilities: null));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-cancel')), findsNothing);
    });

    test('laneCancelOffered: the capability AND a running turn', () {
      const working = BridgeRcActivity.working;
      expect(laneCancelOffered(_caps(), working), isTrue);
      expect(laneCancelOffered(_caps(cancel: false), working), isFalse);
      expect(laneCancelOffered(null, working), isFalse);
      expect(laneCancelOffered(_caps(), BridgeRcActivity.idle), isFalse);
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
        snapshot: _snap(
          activity: BridgeRcActivity.working,
          capabilities: _caps(kind: 'opencode', interject: false),
        ),
      );
      await _pump(tester, rig);

      expect(find.byKey(const ValueKey('lane-interject')), findsNothing);
      // The control: a WORKING opencode lane renders the rest of that row, so
      // the absence is about the capability and not about an empty composer.
      expect(find.byKey(const ValueKey('lane-cancel')), findsOneWidget);
    });

    testWidgets(
      'is present but DISABLED for an interject-capable adapter while '
      'nothing is running',
      (tester) async {
        final rig = _Rig(snapshot: _snap(activity: BridgeRcActivity.idle));
        await _pump(tester, rig);

        final chip = find.byKey(const ValueKey('lane-interject'));
        expect(
          chip,
          findsOneWidget,
          reason: 'the fixture session advertises interject — in its SNAPSHOT',
        );
        expect(
          tester.widget<FilterChip>(chip).onSelected,
          isNull,
          reason: 'there is no turn to interject into',
        );

        rig.bump(_snap(activity: BridgeRcActivity.working));
        await _settle(tester);
        expect(tester.widget<FilterChip>(chip).onSelected, isNotNull);
      },
    );

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
      // No live session row yet, so the row's own name is the title.
      expect(find.text('row7'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('the header reads the LIVE session row — its title and its '
        'permission posture', (tester) async {
      // Plan 025 §3.6.5: the row the lane was opened from is whatever the
      // machine listed at that instant; the stream's row is the session's
      // current state. A sheet-created craze session runs `bypass`, and the
      // header is where that consequence is visible.
      final rig = _Rig(snapshot: _snap());
      await _pump(tester, rig);
      // Before a seed carries a row: the machine feed's name, no posture.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lane-title'))).data,
        'row7',
      );
      expect(find.byKey(const ValueKey('lane-permission')), findsNothing);

      rig.bump(
        _snap(
          session: _session(
            title: 'fix the flaky test',
            permissionMode: 'bypass',
          ),
        ),
      );
      await _settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lane-title'))).data,
        'fix the flaky test',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lane-permission'))).data,
        'runs tools without asking',
      );

      // The live row is the newer truth about what it does NOT say, too: a
      // row with no posture takes the line away, and one with no title falls
      // back to the row's name rather than an empty subtitle.
      rig.bump(_snap(session: _session(title: '')));
      await _settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lane-title'))).data,
        'row7',
      );
      expect(find.byKey(const ValueKey('lane-permission')), findsNothing);
    });

    test('the permission line speaks the desktop\'s words', () {
      expect(lanePermissionLine('bypass'), 'runs tools without asking');
      expect(lanePermissionLine('prompt'), 'asks before running tools');
      expect(lanePermissionLine('auto-edits'), 'permissions: auto-edits');
      expect(lanePermissionLine('  '), isNull);
      expect(lanePermissionLine(null), isNull);
    });

    test('the banner tells reconnecting from ended', () {
      // Reconnecting: a craze lane resuming from its cursor — nothing is over.
      expect(
        laneStaleBannerText('hub connection lost', ended: false),
        'reconnecting… · hub connection lost',
      );
      expect(
        laneStaleBannerText('reconnecting', ended: false),
        'reconnecting…',
      );
      expect(laneStaleBannerText('', ended: false), 'reconnecting…');
      // Ended: the reason, as it always was — never "reconnecting".
      expect(
        laneStaleBannerText('session_closed', ended: true),
        'session_closed',
      );
      expect(
        laneStaleBannerText('unreachable', ended: true),
        isNot(contains('reconnecting')),
      );
    });

    testWidgets('a STALE lane that has not ended says reconnecting, and its '
        'resume clears it', (tester) async {
      final rig = _Rig(
        snapshot: _snap(
          rows: [_row(1, 'assistant', 'still here')],
          stale: 'hub connection lost',
        ),
      );
      await _pump(tester, rig);
      expect(
        tester.widget<Text>(_bannerText('lane-stale')).data,
        'reconnecting… · hub connection lost',
      );
      expect(find.byKey(const ValueKey('lane-note')), findsNothing);
      expect(find.text('still here'), findsOneWidget);
      // The input stays live: nothing is over.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('lane-send')))
            .onPressed,
        isNotNull,
      );

      // The silent resume lands: a lone same-generation Ready.
      rig.bump(_snap(rows: [_row(1, 'assistant', 'still here')]));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stale')), findsNothing);
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
          stale: 'unknown_session',
          ended: true,
        ),
      );
      await _pump(tester, rig);

      expect(find.byKey(const ValueKey('lane-stale')), findsOneWidget);
      expect(
        tester.widget<Text>(_bannerText('lane-stale')).data,
        'unknown_session',
        reason:
            'the reason, not a generic "disconnected" — and not '
            '"reconnecting": this lane ENDED',
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

  group('Stop (plan 025 §3.7.3)', () {
    testWidgets('is absent where the capabilities say no stop', (tester) async {
      // Every opencode session, and a TUI-hosted craze one: `stop: false`.
      final rig = _Rig(snapshot: _snap());
      await _pump(tester, rig);
      expect(find.byKey(const ValueKey('lane-stop')), findsNothing);
      // The control: the same lane, once its capabilities say `stop`.
      rig.bump(_snap(capabilities: _caps(stop: true)));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop')), findsOneWidget);
    });

    testWidgets('asks first: Keep stops nothing, Stop session stops it', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _snap(capabilities: _caps(stop: true)));
      await _pump(tester, rig);

      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsOneWidget);
      expect(
        find.text('The agent ends; the transcript stays.'),
        findsOneWidget,
      );
      expect(rig.source.stops, 0, reason: 'never one tap');

      await tester.tap(find.byKey(const ValueKey('lane-stop-keep')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsNothing);
      expect(rig.source.stops, 0, reason: 'Keep keeps');

      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);
      expect(rig.source.stops, 1);
      expect(find.byKey(const ValueKey('lane-stop-error')), findsNothing);
    });

    testWidgets('a refused stop is said beside the header, not thrown', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _snap(capabilities: _caps(stop: true)))
        ..source.stopFailure = const BridgeLaneError.failed(
          msg: 'unsupported: this host cannot stop its session',
        );
      await _pump(tester, rig);

      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);

      expect(
        tester.widget<Text>(_bannerText('lane-stop-error')).data,
        'unsupported: this host cannot stop its session',
      );
      expect(find.byKey(const ValueKey('lane-composer-error')), findsNothing);
    });

    testWidgets('a session that ENDS while the confirm is open is not '
        'stopped: the answer is moot', (tester) async {
      // Another client stops the session while this one's dialog sits open.
      final rig = _Rig(snapshot: _snap(capabilities: _caps(stop: true)));
      await _pump(tester, rig);
      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsOneWidget);

      rig.bump(
        _snap(
          capabilities: _caps(stop: true),
          stale: 'session_closed',
          ended: true,
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);

      expect(rig.source.stops, 0, reason: 'nothing is sent');
      expect(
        find.byKey(const ValueKey('lane-stop-error')),
        findsNothing,
        reason: 'and nothing is refused: there was nothing left to stop',
      );
    });

    testWidgets('a session that stops OFFERING stop while the confirm is open '
        'is not stopped', (tester) async {
      // A new incarnation whose capabilities say `stop: false` (a TUI host).
      final rig = _Rig(snapshot: _snap(capabilities: _caps(stop: true)));
      await _pump(tester, rig);
      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);

      rig.bump(_snap(capabilities: _caps()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);

      expect(
        rig.source.stops,
        0,
        reason: 'the capability is the gate, then too',
      );
      expect(find.byKey(const ValueKey('lane-stop')), findsNothing);
    });

    test('laneStopOffered: the capability, on a lane that has not ended', () {
      LaneState lane({
        bool stop = true,
        bool ended = false,
        bool done = false,
      }) => LaneState(
        capabilities: _caps(stop: stop),
        ended: ended,
        abandoned: done,
      );
      expect(laneStopOffered(lane()), isTrue);
      expect(laneStopOffered(lane(stop: false)), isFalse);
      expect(laneStopOffered(lane(ended: true)), isFalse);
      expect(laneStopOffered(lane(done: true)), isFalse);
      expect(laneStopOffered(LaneState()), isFalse, reason: 'no seed yet');
    });

    testWidgets('goes quiet once the lane has ended', (tester) async {
      final rig = _Rig(snapshot: _snap(capabilities: _caps(stop: true)));
      await _pump(tester, rig);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('lane-stop')))
            .onPressed,
        isNotNull,
      );

      rig.bump(
        _snap(
          capabilities: _caps(stop: true),
          stale: 'session_closed',
          ended: true,
        ),
      );
      await _settle(tester);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('lane-stop')))
            .onPressed,
        isNull,
        reason: 'there is nothing left to stop',
      );
      expect(
        tester.widget<Text>(_bannerText('lane-stale')).data,
        'session_closed',
      );
    });
  });

  group('the settings chip and sheet (plan 025 §3.10)', () {
    const chip = ValueKey('lane-settings-chip');
    const sheet = ValueKey('lane-settings');

    /// A tall surface, so the whole sheet lays out and every row is on screen.
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(chip));
      await _settle(tester);
      expect(find.byKey(sheet), findsOneWidget);
    }

    testWidgets('CONTROL: offered only where the capabilities say settings — '
        'no chip, and no sheet to reach, otherwise', (tester) async {
      tall(tester);
      // Every opencode session: `settings: false`, even with a settings tree
      // a producer sent against the contract.
      final rig = _Rig(snapshot: _snap(settings: _grok46));
      await _pump(tester, rig);
      expect(find.byKey(chip), findsNothing);
      expect(find.byKey(sheet), findsNothing);

      // The control: the same lane once its capabilities say `settings`.
      rig.bump(_snap(capabilities: _settingsCaps, settings: _grok46));
      await _settle(tester);
      expect(find.byKey(chip), findsOneWidget);
      expect(_chipText(tester), 'Grok 4.6 · High · fast');
    });

    testWidgets('CONTROL: an open sheet LEAVES when the session stops offering '
        'settings — hidden, never disabled', (tester) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      );
      await _pump(tester, rig);
      await openSheet(tester);

      // A new incarnation whose capabilities say `settings: false`.
      rig.bump(_snap(capabilities: _caps(kind: 'craze')));
      await _settle(tester);
      expect(find.byKey(sheet), findsNothing);
      expect(find.byKey(chip), findsNothing);
      expect(find.byKey(const ValueKey('lane-screen')), findsOneWidget);
    });

    testWidgets('before the first Settings: a "Settings" chip and an empty '
        'sheet', (tester) async {
      tall(tester);
      final rig = _Rig(snapshot: _snap(capabilities: _settingsCaps));
      await _pump(tester, rig);
      expect(_chipText(tester), 'Settings');
      await openSheet(tester);
      expect(find.byKey(const ValueKey('lane-settings-empty')), findsOneWidget);
    });

    testWidgets('the sheet draws the session\'s rows: the model a list, the '
        'options and the mode segmented, the current values selected', (
      tester,
    ) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      );
      await _pump(tester, rig);
      await openSheet(tester);

      expect(_rowKeys(), [
        'model:model',
        'config:effort',
        'config:fast',
        'mode:mode',
      ]);
      for (final m in ['grok-4.6', 'composer-2.5', 'claude-opus-5']) {
        expect(find.byKey(ValueKey('lane-setting-model:model-$m')), findsOne);
      }
      expect(_selected(tester, 'model:model', 'grok-4.6'), isTrue);
      expect(_selected(tester, 'model:model', 'composer-2.5'), isFalse);
      // A list line is checked; a segment is not a list line.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lane-setting-model:model-grok-4.6')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lane-setting-config:effort-high')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
        reason: 'four values: a segmented control',
      );
      expect(_selected(tester, 'config:effort', 'high'), isTrue);
      expect(_selected(tester, 'config:fast', 'true'), isTrue);
      expect(_selected(tester, 'mode:mode', 'agent'), isTrue);
      expect(find.byKey(const ValueKey('lane-settings-meter')), findsNothing);
    });

    testWidgets('a press is pending — "applying…", no optimistic value, no '
        'second press — and sends the option bound to the model SHOWN', (
      tester,
    ) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      );
      rig.source.holdSet = Completer<void>();
      await _pump(tester, rig);
      await openSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('lane-setting-config:effort-low')),
      );
      await _settle(tester);
      expect(_markText('config:effort'), pendingText);
      expect(_selected(tester, 'config:effort', 'high'), isTrue);
      await tester.tap(
        find.byKey(const ValueKey('lane-setting-config:effort-medium')),
      );
      await _settle(tester);
      expect(
        rig.source.sets,
        [
          const BridgeLaneSettingChange.config(
            id: 'effort',
            value: 'low',
            forModel: 'grok-4.6',
          ),
        ],
        reason: 'one change, bound to the model this sheet drew (A13)',
      );

      // craze's delta, ahead of its answer.
      rig.bump(
        _snap(
          capabilities: _settingsCaps,
          settings: _with(_grok46, effort: 'low'),
          settingsFrames: 1,
        ),
      );
      rig.source.holdSet!.complete();
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('lane-setting-mark-config:effort')),
        findsNothing,
      );
      expect(_selected(tester, 'config:effort', 'low'), isTrue);
      expect(_chipText(tester), 'Grok 4.6 · Low · fast');
    });

    testWidgets('CONTROL: a model change re-renders the options from the NEXT '
        'Settings — never from the press', (tester) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      );
      await _pump(tester, rig);
      await openSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('lane-setting-model:model-claude-opus-5')),
      );
      await _settle(tester);
      expect(rig.source.sets, [
        const BridgeLaneSettingChange.model(id: 'claude-opus-5'),
      ]);
      expect(_rowKeys(), [
        'model:model',
        'config:effort',
        'config:fast',
        'mode:mode',
      ], reason: 'grok-4.6\'s options until the session says otherwise');

      rig.bump(
        _snap(capabilities: _settingsCaps, settings: _opus, settingsFrames: 1),
      );
      await _settle(tester);
      expect(_rowKeys(), [
        'model:model',
        'config:thinking',
        'config:effort',
        'config:context',
        'config:fast',
        'mode:mode',
      ], reason: 'claude-opus-5\'s OWN options');
      expect(_selected(tester, 'model:model', 'claude-opus-5'), isTrue);
      // Five effort values now: a list.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lane-setting-config:effort-max')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(_chipText(tester), 'Claude Opus 5 · Max');
    });

    testWidgets('CONTROL: a change made by another client appears in the open '
        'sheet', (tester) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      );
      await _pump(tester, rig);
      await openSheet(tester);
      expect(_selected(tester, 'mode:mode', 'agent'), isTrue);

      // Nobody pressed anything here: an attached TUI moved the mode.
      rig.bump(
        _snap(
          capabilities: _settingsCaps,
          settings: _with(_grok46, mode: 'plan'),
          settingsFrames: 1,
        ),
      );
      await _settle(tester);
      expect(_selected(tester, 'mode:mode', 'plan'), isTrue);
      expect(_selected(tester, 'mode:mode', 'agent'), isFalse);
      expect(rig.source.sets, isEmpty);
    });

    testWidgets('CONTROL: a refusal is shown inline on ITS row', (
      tester,
    ) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      )..source.setFailure = const BridgeLaneError.notAccepting();
      await _pump(tester, rig);
      await openSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('lane-setting-config:effort-low')),
      );
      await _settle(tester);
      expect(_markText('config:effort'), staleModelText);
      for (final other in ['model:model', 'config:fast', 'mode:mode']) {
        expect(
          find.byKey(ValueKey('lane-setting-mark-$other')),
          findsNothing,
          reason: 'only the row that was refused',
        );
      }
      expect(_selected(tester, 'config:effort', 'high'), isTrue);
      expect(find.byKey(const ValueKey('lane-composer-error')), findsNothing);
    });

    testWidgets('CONTROL: a change lost to a drop is "not confirmed" — never '
        'shown as applied — until the next Settings', (tester) async {
      tall(tester);
      final rig =
          _Rig(
              snapshot: _snap(
                capabilities: _settingsCaps,
                settings: _grok46,
                settingsFrames: 2,
              ),
            )
            ..source.setFailure = const BridgeLaneError.outcomeUnknown(
              msg: 'outcome unknown: the connection to craze dropped',
            );
      await _pump(tester, rig);
      await openSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('lane-setting-config:fast-false')),
      );
      await _settle(tester);
      expect(_markText('config:fast'), notConfirmedText);
      expect(
        _selected(tester, 'config:fast', 'true'),
        isTrue,
        reason: 'the old value until the session says otherwise',
      );

      // A read with nothing new to say: still not confirmed.
      rig.bump(
        _snap(
          capabilities: _settingsCaps,
          settings: _grok46,
          settingsFrames: 2,
        ),
      );
      await _settle(tester);
      expect(_markText('config:fast'), notConfirmedText);

      // The next Settings: the change DID run.
      rig.bump(
        _snap(
          capabilities: _settingsCaps,
          settings: _with(_grok46, fast: 'false'),
          settingsFrames: 3,
        ),
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('lane-setting-mark-config:fast')),
        findsNothing,
      );
      expect(_selected(tester, 'config:fast', 'false'), isTrue);
      expect(rig.source.sets, hasLength(1), reason: 'never resent');
    });

    testWidgets('closing the sheet mid-change loses nothing: the mark is the '
        'lane\'s', (tester) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(capabilities: _settingsCaps, settings: _grok46),
      );
      rig.source.holdSet = Completer<void>();
      await _pump(tester, rig);
      await openSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('lane-setting-mode:mode-ask')),
      );
      await _settle(tester);
      expect(_markText('mode:mode'), pendingText);

      Navigator.of(tester.element(find.byKey(sheet))).pop();
      await _settle(tester);
      expect(find.byKey(sheet), findsNothing);
      await openSheet(tester);
      expect(_markText('mode:mode'), pendingText, reason: 'still in flight');

      rig.source.setFailure = const BridgeLaneError.failed(msg: 'nope');
      rig.source.holdSet!.complete();
      await _settle(tester);
      expect(_markText('mode:mode'), 'nope');
    });

    testWidgets('a context meter only when the usage has tokens AND a window', (
      tester,
    ) async {
      tall(tester);
      final rig = _Rig(
        snapshot: _snap(
          capabilities: _settingsCaps,
          settings: _with(
            _grok46,
            usage: BridgeLaneUsage(
              contextTokens: BigInt.from(68000),
              contextWindow: BigInt.from(200000),
            ),
          ),
        ),
      );
      await _pump(tester, rig);
      await openSheet(tester);
      expect(find.byKey(const ValueKey('lane-settings-meter')), findsOneWidget);
      expect(find.text('68k / 200k tokens · 34%'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// the settings fixtures (craze's permodel cursor, as shed-craze orders it)
// ---------------------------------------------------------------------------

/// A craze session that offers settings.
final _settingsCaps = _caps(kind: 'craze', settings: true);

List<BridgeLaneChoice> _offOn(String on) => [
  const BridgeLaneChoice(id: 'false', name: 'Off'),
  BridgeLaneChoice(id: 'true', name: on),
];

const _models = [
  BridgeLaneChoice(id: 'grok-4.6', name: 'Grok 4.6'),
  BridgeLaneChoice(id: 'composer-2.5', name: 'Composer 2.5'),
  BridgeLaneChoice(id: 'claude-opus-5', name: 'Claude Opus 5'),
  BridgeLaneChoice(id: 'glm-5.2', name: 'GLM 5.2'),
];

const _modes = [
  BridgeLaneChoice(id: 'agent', name: 'Agent'),
  BridgeLaneChoice(id: 'plan', name: 'Plan'),
  BridgeLaneChoice(id: 'ask', name: 'Ask'),
];

/// grok-4.6: effort (four values) and fast.
final _grok46 = _with(
  const BridgeLaneSettings(models: _models, modes: _modes, options: []),
);

/// claude-opus-5: thinking, effort (five values), context and fast.
final _opus = BridgeLaneSettings(
  model: 'claude-opus-5',
  models: _models,
  mode: 'agent',
  modes: _modes,
  options: [
    BridgeLaneSetting(
      id: 'thinking',
      name: 'Thinking',
      category: 'thought_level',
      current: 'true',
      values: _offOn('On'),
    ),
    const BridgeLaneSetting(
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      current: 'max',
      values: [
        BridgeLaneChoice(id: 'low', name: 'Low'),
        BridgeLaneChoice(id: 'medium', name: 'Medium'),
        BridgeLaneChoice(id: 'high', name: 'High'),
        BridgeLaneChoice(id: 'xhigh', name: 'Extra High'),
        BridgeLaneChoice(id: 'max', name: 'Max'),
      ],
    ),
    const BridgeLaneSetting(
      id: 'context',
      name: 'Context',
      category: 'model_config',
      current: '300k',
      values: [
        BridgeLaneChoice(id: '300k', name: '300K'),
        BridgeLaneChoice(id: '1m', name: '1M'),
      ],
    ),
    BridgeLaneSetting(
      id: 'fast',
      name: 'Fast',
      category: 'model_config',
      current: 'false',
      values: _offOn('Fast'),
    ),
  ],
);

/// A grok-4.6 session with the values given.
BridgeLaneSettings _with(
  BridgeLaneSettings base, {
  String effort = 'high',
  String fast = 'true',
  String mode = 'agent',
  BridgeLaneUsage? usage,
}) => BridgeLaneSettings(
  model: 'grok-4.6',
  models: base.models,
  mode: mode,
  modes: base.modes,
  options: [
    BridgeLaneSetting(
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      current: effort,
      values: const [
        BridgeLaneChoice(id: 'low', name: 'Low'),
        BridgeLaneChoice(id: 'medium', name: 'Medium'),
        BridgeLaneChoice(id: 'high', name: 'High'),
        BridgeLaneChoice(id: 'xhigh', name: 'Extra High'),
      ],
    ),
    BridgeLaneSetting(
      id: 'fast',
      name: 'Fast',
      category: 'model_config',
      current: fast,
      values: _offOn('Fast'),
    ),
  ],
  usage: usage,
);

/// The chip's words.
String _chipText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('lane-settings-chip')),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// The sheet's rows, by key, in the order drawn.
List<String> _rowKeys() => find
    .byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          RegExp(r'^lane-setting-[a-z]+:[^-]+$').hasMatch(k.value);
    })
    .evaluate()
    .map(
      (e) => (e.widget.key! as ValueKey<String>).value.substring(
        'lane-setting-'.length,
      ),
    )
    .toList();

/// Whether [row]'s [value] is the one it shows as current.
bool _selected(WidgetTester tester, String row, String value) => tester
    .widget<Semantics>(
      find
          .descendant(
            of: find.byKey(ValueKey('lane-setting-$row-$value')),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .selected!;

/// The mark [row] shows inline, or null when it shows none.
String? _markText(String row) {
  final mark = find.byKey(ValueKey('lane-setting-mark-$row')).evaluate();
  return mark.isEmpty ? null : (mark.single.widget as Text).data;
}

// ---------------------------------------------------------------------------
// the rig
// ---------------------------------------------------------------------------

const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');
const _ref = (machine: 'mini3', kind: 'opencode', slug: '7');

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
        home: const LaneScreen(
          machine: 'mini3',
          kind: 'opencode',
          slug: '7',
          title: 'row7',
        ),
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

/// The fixture session's capabilities: interject-capable, so the interject
/// cells have something to gate on. They ride the snapshot, as a real seed's
/// do — an explicit `capabilities: null` is "no seed yet".
const _fixtureCaps = BridgeLaneCapabilities(
  kind: 'opencode',
  interject: true,
  cancel: true,
  approvals: true,
  historyCursor: true,
  settings: false,
  stop: false,
);

BridgeLaneSnapshot _snap({
  List<BridgeRcFeedMessage> rows = const [],
  BridgeRcActivity activity = BridgeRcActivity.idle,
  List<BridgeLaneApproval> approvals = const [],
  String? stale,
  bool ended = false,
  BridgeLaneSession? session,
  BridgeLaneCapabilities? capabilities = _fixtureCaps,
  BridgeLaneSettings? settings,
  int settingsFrames = 0,
  int generation = 1,
}) => BridgeLaneSnapshot(
  messages: rows,
  full: true,
  activity: activity,
  session: session,
  generation: BigInt.from(generation),
  stale: stale,
  ended: ended,
  capabilities: capabilities,
  settings: settings,
  settingsFrames: BigInt.from(settingsFrames),
  approvals: approvals,
);

BridgeLaneSession _session({required String title, String? permissionMode}) =>
    BridgeLaneSession(
      id: 'sess-7',
      title: title,
      cwd: '/home/shed/proj',
      activity: BridgeRcActivity.idle,
      pendingApprovals: 0,
      approximate: false,
      permissionMode: permissionMode,
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

BridgeLaneCapabilities _caps({
  String kind = 'opencode',
  bool interject = true,
  bool cancel = true,
  bool stop = false,
  bool settings = false,
}) => BridgeLaneCapabilities(
  kind: kind,
  interject: interject,
  cancel: cancel,
  approvals: true,
  historyCursor: true,
  settings: settings,
  stop: stop,
);

/// The [Text] inside the banner keyed [key].
Finder _bannerText(String key) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text));

/// The screen, the real providers, and a stubbed bridge + machine feed.
class _Rig {
  _Rig({BridgeLaneSnapshot? snapshot, String kind = 'opencode'})
    : source = _FakeSource(current: snapshot ?? _snap()),
      feed = _FakeFeed(kind: kind);

  final _FakeSource source;
  final _FakeFeed feed;

  /// Replace what the bridge will answer with, and nudge — which is how every
  /// change reaches this screen in production too.
  void bump(BridgeLaneSnapshot next) => source.bump(next);
}

class _FakeSource implements LaneSource {
  _FakeSource({required this.current});

  /// What the next `snapshot()` will answer with — the session's capabilities
  /// included, since that is where they ride. `current`, not `snapshot` — that
  /// name is a method on [LaneSource].
  BridgeLaneSnapshot current;
  final _nudges = StreamController<bool>.broadcast();

  final specs = <BridgeLaneSpec>[];
  final sends = <({String text, BridgeSendMode mode})>[];
  final answers = <({String approvalId, BridgeLaneAnswer answer})>[];
  int cancels = 0;

  /// When set, the next `send`/`answer` is refused with it — the refusal path
  /// the controller turns into state rather than an exception.
  Object? sendFailure;
  Object? answerFailure;
  Object? stopFailure;
  int stops = 0;

  /// When set, `send` awaits this before returning, so a test can unmount the
  /// screen while the verb is still in flight.
  Completer<void>? holdSend;

  void bump(BridgeLaneSnapshot next) {
    current = next;
    _nudges.add(true);
  }

  @override
  Future<LaneHandle> open(BridgeLaneSpec spec) async {
    specs.add(spec);
    return _FakeHandle();
  }

  /// A craze row's open — no spec, its hostId. Recorded, so a cell can say
  /// which way a lane was opened.
  final crazeOpens = <String>[];

  @override
  Future<LaneHandle> openCraze(CrazeLaneOpen open, String hostId) async {
    crazeOpens.add(hostId);
    return _FakeHandle();
  }

  @override
  Stream<bool> nudges(LaneHandle handle) => _nudges.stream;

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
  Future<void> stop(LaneHandle handle) async {
    stops++;
    final failure = stopFailure;
    if (failure != null) throw failure;
  }

  /// Every settings change sent, in order.
  final sets = <BridgeLaneSettingChange>[];
  Object? setFailure;

  /// When set, `set` awaits it — a change held PENDING.
  Completer<void>? holdSet;

  @override
  Future<void> set(LaneHandle handle, BridgeLaneSettingChange change) async {
    sets.add(change);
    final hold = holdSet;
    if (hold != null) await hold.future;
    final failure = setFailure;
    if (failure != null) throw failure;
  }

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
        kind: const BridgeRcKind.opencode(),
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
  Future<LaneLease> acquireForward(int remotePort) async =>
      FakeLaneLease(41000);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

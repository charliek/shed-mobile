import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/features/lanes/lane_screen.dart';
import 'package:shed_mobile/features/lanes/slash_keys.dart';
import 'package:shed_mobile/features/lanes/slash_menu_panel.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_settings.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/lanes/lane_state.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';
import 'package:shed_mobile/ssh/lane_forward.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import '../../lanes/fake_lane_lease.dart';
import 'fake_slash_rules.dart';

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

  // A composer call disables the field while it runs, which drops its focus
  // (and on a phone, the keyboard). Every cell here HOLDS its verb across a
  // settle and proves the disabled frame happened first (`held`): a verb that
  // answers before the next frame never draws the field disabled at all, so a
  // focused composer after it would prove nothing.
  group('the composer keeps its focus (plan 033 §3.6)', () {
    /// The verb is out and a frame has drawn it: the field disabled and,
    /// with that, unfocused.
    void held(WidgetTester tester) {
      expect(
        _composerOn(tester),
        isFalse,
        reason: 'disabled while the verb runs',
      );
      expect(
        _composerFocused(tester),
        isFalse,
        reason: 'and the disabled field dropped the focus',
      );
    }

    testWidgets('INPUT: a verb that takes from a hardware Enter (/rename x) '
        'ends focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['x'], reason: 'the rename is in flight');
      held(tester);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'it took');
      expect(_composerFocused(tester), isTrue, reason: 'the caret came back');
    });

    testWidgets('INPUT: a verb that takes from the IME\'s Send action (/plan) '
        'ends focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSet = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/plan');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(rig.source.sets, [const BridgeLaneSettingChange.mode(id: 'plan')]);
      held(tester);

      rig.source.holdSet!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'it took');
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('INPUT: a verb that takes from a touch tap on a menu row '
        '(/pl → plan) ends focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSet = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/pl');
      await tester.tap(find.byKey(const ValueKey('lane-slash-row-plan')));
      await _settle(tester);
      expect(rig.rules.accepts.last.key, BridgeSlashAcceptKey.pick);
      expect(rig.source.sets, [const BridgeLaneSettingChange.mode(id: 'plan')]);
      held(tester);

      rig.source.holdSet!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'it took');
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('INPUT: a plain send that takes ends focused', (tester) async {
      final rig = _Rig()..source.holdSend = Completer<void>();
      await _pump(tester, rig);
      await _type(tester, 'describe this project');
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);
      expect(rig.source.sends.single.text, 'describe this project');
      held(tester);

      rig.source.holdSend!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'it took');
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('INPUT: a plain send that is refused ends focused', (
      tester,
    ) async {
      final rig = _Rig()
        ..source.holdSend = Completer<void>()
        ..source.sendFailure = const BridgeLaneError.notAccepting();
      await _pump(tester, rig);
      await _type(tester, 'go');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends.single.text, 'go');
      held(tester);

      rig.source.holdSend!.complete();
      await _settle(tester);
      expect(_composerError(tester), contains('not accepting'));
      expect(_draft(tester), 'go', reason: 'kept, to fix or resend');
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('OUTCOME: done — a prompt row and an /effort level each end '
        'focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap(menu: effortMenu));
      await _pumpSlash(tester, rig);

      rig.source.holdSend = Completer<void>();
      await _type(tester, '/research deep dive');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends.single.text, '/research deep dive');
      held(tester);
      rig.source.holdSend!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'the prompt row took');
      expect(_composerFocused(tester), isTrue, reason: 'the prompt row');

      rig.source.holdSet = Completer<void>();
      await _type(tester, '/effort low');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sets, [
        const BridgeLaneSettingChange.config(
          id: 'effort',
          value: 'low',
          forModel: 'grok-4.6',
        ),
      ]);
      held(tester);
      rig.source.holdSet!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'the effort took');
      expect(_composerFocused(tester), isTrue, reason: '/effort low');
    });

    testWidgets('OUTCOME: the verb\'s own refusal (craze refuses the rename) '
        'ends focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>()
        ..source.setTitleFailure = const BridgeLaneError.badRequest(
          msg: 'params.title is blank once normalized: send none instead',
        );
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['x']);
      held(tester);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(
        _composerError(tester),
        contains('params.title is blank once normalized'),
      );
      expect(_draft(tester), '/rename x');
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('OUTCOME: unknown ("may have applied") ends focused', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>()
        ..source.setTitleFailure = const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: the connection dropped',
        );
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename lost');
      await _press(tester, LogicalKeyboardKey.enter);
      held(tester);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_composerError(tester), laneCommandOutcomeUnknown);
      expect(_draft(tester), '/rename lost');
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('OUTCOME: superseded — the lane REBUILT before the verb '
        'answered — ends focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename held');
      await _press(tester, LogicalKeyboardKey.enter);
      held(tester);
      await _rebuildLane(tester);
      held(tester);

      // An Ok, but the lane that would have said how it went let it go.
      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_composerError(tester), laneCommandOutcomeUnknown);
      expect(_draft(tester), '/rename held', reason: 'kept: not a success');
      expect(_composerFocused(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HELD: while the verb is out the field is disabled and '
        'unfocused; once it answers, focused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      expect(_composerFocused(tester), isTrue, reason: 'typed into');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['x']);
      expect(
        find.byKey(const ValueKey('lane-send')),
        findsNothing,
        reason: 'the spinner in Send\'s place: the verb is out',
      );
      expect(_composerOn(tester), isFalse);
      expect(_composerFocused(tester), isFalse);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_composerOn(tester), isTrue);
      expect(_composerFocused(tester), isTrue);
    });

    testWidgets('GUARD: a settings sheet opened while the verb is out keeps '
        'the focus — the verb answering steals nothing', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      held(tester);
      await tester.tap(find.byKey(const ValueKey('lane-settings-chip')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-settings')), findsOneWidget);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'the verb took');
      expect(_composerOn(tester), isTrue, reason: 'it could take the focus');
      expect(_composerFocused(tester), isFalse, reason: 'the sheet keeps it');
      expect(find.byKey(const ValueKey('lane-settings')), findsOneWidget);
    });

    testWidgets('GUARD: a page pushed over the lane while the verb is out '
        'keeps the focus — the verb answering steals nothing', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      held(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(LaneScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: TextField(key: ValueKey('elsewhere'))),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('elsewhere')));
      await _settle(tester);
      final elsewhere = tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('elsewhere')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(elsewhere.hasFocus, isTrue, reason: 'the page took the focus');

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(rig.source.titles, ['x']);
      expect(_composerOn(tester), isTrue, reason: 'it could take the focus');
      expect(_composerFocused(tester), isFalse);
      expect(elsewhere.hasFocus, isTrue, reason: 'the page keeps it');
    });

    testWidgets('GUARD: a screen that goes away while the verb is out throws '
        'nothing and requests nothing', (tester) async {
      // `runAsync`, as in "a send that lands after the screen is gone": the
      // controller's teardown awaits a cancel FakeAsync never resumes.
      await tester.runAsync(() async {
        final rig = _Rig(snapshot: _slashSnap())
          ..source.holdSetTitle = Completer<void>();
        await _pumpSlash(tester, rig);
        await _type(tester, '/rename x');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(rig.source.titles, ['x'], reason: 'the rename is in flight');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        rig.source.holdSetTitle!.complete();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      });
      expect(tester.takeException(), isNull);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('lane-input'),
        reason: 'nothing focused the gone composer',
      );
    });

    testWidgets('GUARD: a lane given up on while the verb is out leaves the '
        'composer unfocused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      held(tester);

      // A final Down: the lane is given up on (see "FU9: an ABANDONED lane").
      rig.bump(_slashSnap(stale: 'session_closed', ended: true));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_sendEnabled(tester), isFalse, reason: 'given up on');
      expect(_composerFocused(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('GUARD: a lane that is GONE while the verb is out leaves the '
        'composer unfocused', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      held(tester);

      // A machine-feed rebuild with no lane stamp for this row (see "A
      // MISSING LANE"): the screen stays up, its composer enabled.
      rig.feed.laneGone = true;
      ProviderScope.containerOf(
        tester.element(find.byType(LaneScreen)),
      ).invalidate(laneControllerProvider(_ref));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-unavailable')), findsOneWidget);

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(
        _composerOn(tester),
        isTrue,
        reason: 'the field could take the focus',
      );
      expect(_composerFocused(tester), isFalse, reason: 'no lane, no focus');
      expect(tester.takeException(), isNull);
    });

    testWidgets('GUARD: a verb begun without the focus grabs none', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      expect(_composerFocused(tester), isFalse);

      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);
      expect(rig.source.titles, ['x']);
      expect(_composerOn(tester), isFalse, reason: 'the verb is out');

      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_draft(tester), '', reason: 'it took');
      expect(_composerFocused(tester), isFalse);
    });

    testWidgets('GUARD: a bare /effort (the picker) grabs none — the sheet '
        'it opens keeps the focus', (tester) async {
      final rig = await _slashRig(tester, _slashSnap(menu: effortMenu));
      await _type(tester, '/effort');
      expect(_composerFocused(tester), isTrue);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-settings')), findsOneWidget);
      expect(_draft(tester), '');
      expect(rig.source.sets, isEmpty);
      expect(_composerFocused(tester), isFalse);
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

    testWidgets('a stale lane names the reason, and a dead one says so — '
        'in its ended banner ALONE (plan 032 §3.1.2)', (tester) async {
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

      // Given up on — nothing re-opens a session the agent does not know —
      // but the banner's reason is the whole story: a final end says nothing
      // more ("given up on" is for a lane that ended WITHOUT one).
      expect(
        tester.widget<Text>(_bannerText('lane-stale')).data,
        'unknown_session',
      );
      expect(find.byKey(const ValueKey('lane-note')), findsNothing);
      expect(find.textContaining('given up on'), findsNothing);
      // …and nothing pretends the lane can still be steered.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('lane-send')))
            .onPressed,
        isNull,
      );
    });
  });

  group('the lane note and a craze row that leaves (plan 032 §3.1.2)', () {
    const host = 'cccccccccccc';
    const givenUp =
        'This lane has been given up on — its row or session is gone.';
    final crazeCaps = _caps(kind: 'craze', stop: true);
    final before = _row(1, 'assistant', 'before the stop');

    /// A craze session's transcript, open, its row listed by a live roster.
    Future<_Rig> crazeLane(WidgetTester tester) async {
      final rig = _Rig(
        crazeHost: host,
        snapshot: _snap(rows: [before], capabilities: crazeCaps),
      );
      await _pump(tester, rig);
      expect(rig.source.crazeOpens, [host]);
      return rig;
    }

    /// The roster's next round no longer lists the session.
    Future<void> rowLeaves(WidgetTester tester, _Rig rig) async {
      rig.feed.crazeRowGone = true;
      rig.feed.publish();
      await _settle(tester);
    }

    test('laneNoteText: a final end says nothing; an end that is not final, '
        'a vanished row and an error each still say "given up on"', () {
      for (final reason in [
        'session_closed',
        'unknown_session',
        'start_failed: KEYCHAIN LOCKED',
      ]) {
        expect(
          laneNoteText(LaneState(stale: reason, ended: true, abandoned: true)),
          isNull,
          reason: '$reason: the ended banner alone',
        );
      }
      expect(
        laneNoteText(
          LaneState(stale: 'unreachable', ended: true, abandoned: true),
        ),
        givenUp,
        reason: 'an end, but not a final one',
      );
      expect(laneNoteText(LaneState(abandoned: true)), givenUp);
      expect(
        laneNoteText(
          LaneState(
            abandoned: true,
            error: AppError('LANE_UNSUPPORTED_KIND', 'no adapter for codex'),
          ),
        ),
        'This lane has been given up on: no adapter for codex',
      );
      expect(laneNoteText(LaneState(retrying: true)), 'Reconnecting…');
      expect(laneNoteText(LaneState()), isNull);
      expect(
        laneNoteText(LaneState(stale: 'session_closed', ended: true)),
        isNull,
        reason: 'ended but not yet acted on: nothing to note',
      );
    });

    testWidgets('a craze lane stays live through its grace, and a final Down '
        'in it shows the ended banner ALONE — no "given up on"', (
      tester,
    ) async {
      await _withLog((lines) async {
        final rig = await crazeLane(tester);
        String state() =>
            lines.lastWhere((l) => l.startsWith('MSTATE screen=lane '));
        expect(state(), contains(' departing=f '));

        await rowLeaves(tester, rig);
        expect(state(), contains(' departing=t '), reason: 'the drive log');
        expect(
          find.byKey(const ValueKey('lane-note')),
          findsNothing,
          reason: 'nothing is over yet',
        );
        expect(_sendEnabled(tester), isTrue);

        // The session's last words, after its row left.
        final after = _row(2, 'assistant', 'after the row left');
        rig.bump(_snap(rows: [before, after], capabilities: crazeCaps));
        await _settle(tester);
        expect(find.text('after the row left'), findsOneWidget);

        // The Stop's end.
        rig.bump(
          _snap(
            rows: [before, after],
            stale: 'session_closed',
            ended: true,
            capabilities: crazeCaps,
          ),
        );
        await _settle(tester);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await _settle(tester);
        expect(
          tester.widget<Text>(_bannerText('lane-stale')).data,
          'session_closed',
        );
        expect(find.byKey(const ValueKey('lane-note')), findsNothing);
        expect(find.textContaining('given up on'), findsNothing);
        expect(find.text('after the row left'), findsOneWidget);
        expect(_sendEnabled(tester), isFalse, reason: 'over for good');
        expect(state(), contains(' departing=f '));

        // The grace went with the end: past where it would have run out,
        // nothing changes.
        await tester.pump(crazeDepartGrace);
        await _settle(tester);
        expect(find.byKey(const ValueKey('lane-note')), findsNothing);
      });
    });

    testWidgets('a craze lane whose grace runs out with no final Down reads '
        'once more, then is given up on WITH the note', (tester) async {
      final rig = await crazeLane(tester);
      await rowLeaves(tester, rig);
      // A row that arrived in the grace's last moment, no nudge for it yet:
      // only the grace's own read can show it.
      rig.source.current = _snap(
        rows: [before, _row(2, 'assistant', 'one last row')],
        capabilities: crazeCaps,
      );

      await tester.pump(crazeDepartGrace);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(find.text('one last row'), findsOneWidget);
      expect(tester.widget<Text>(_bannerText('lane-note')).data, givenUp);
      expect(find.byKey(const ValueKey('lane-stale')), findsNothing);
      expect(_sendEnabled(tester), isFalse);
    });

    testWidgets('a NON-craze lane whose row leaves is given up on at once, '
        'with the note', (tester) async {
      final rig = _Rig(snapshot: _snap(rows: [before]));
      await _pump(tester, rig);
      rig.feed.laneGone = true;
      rig.feed.publish();
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(tester.widget<Text>(_bannerText('lane-note')).data, givenUp);
      expect(find.text('before the stop'), findsOneWidget);
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

    testWidgets('the chip names the effort the SNAPSHOT names — none named, '
        'none shown (plan 032 PC14h)', (tester) async {
      tall(tester);
      // The same settings, an `effort` select among them — but the shared
      // core named no effort option: the chip guesses none.
      final rig = _Rig(
        snapshot: _snap(
          capabilities: _settingsCaps,
          settings: _grok46,
          effortOption: null,
        ),
      );
      await _pump(tester, rig);
      expect(_chipText(tester), 'Grok 4.6 · fast');

      rig.bump(_snap(capabilities: _settingsCaps, settings: _grok46));
      await _settle(tester);
      expect(_chipText(tester), 'Grok 4.6 · High · fast');
    });

    testWidgets('a model other than the current one says where its effort '
        'lands; the current one and a model with no facts say nothing (plan '
        '032 §3.3)', (tester) async {
      tall(tester);
      await _withLog((lines) async {
        final rig = _Rig(
          snapshot: _snap(capabilities: _settingsCaps, settings: _native),
        );
        await _pump(tester, rig);
        await openSheet(tester);
        expect(_secondary('grok-4.6'), isNull, reason: 'the current model');
        expect(_secondary('claude-opus-5'), 'effort → low');
        expect(_secondary('glm-5.2'), 'effort → high', reason: 'its default');
        expect(_secondary('composer-2.5'), isNull, reason: 'no facts');
        String state() => lines.lastWhere((l) => l.startsWith('MSTATE'));
        expect(state(), contains(' effort=effort '));
        expect(state(), endsWith(' lands=claude-opus-5→low,glm-5.2→high'));

        // A switch moves the line with the current model: grok-4.6 now says
        // where a switch back lands, claude-opus-5 says nothing.
        rig.bump(
          _snap(
            capabilities: _settingsCaps,
            settings: BridgeLaneSettings(
              model: 'claude-opus-5',
              models: _native.models,
              mode: _native.mode,
              modes: _native.modes,
              options: _native.options,
            ),
            settingsFrames: 1,
          ),
        );
        await _settle(tester);
        expect(_secondary('grok-4.6'), 'effort → high');
        expect(_secondary('claude-opus-5'), isNull);
        expect(state(), endsWith(' lands=grok-4.6→high,glm-5.2→high'));

        // An ACP session's models state no facts: no line anywhere.
        rig.bump(
          _snap(
            capabilities: _settingsCaps,
            settings: _grok46,
            settingsFrames: 2,
          ),
        );
        await _settle(tester);
        for (final m in _models) {
          expect(_secondary(m.id), isNull, reason: m.id);
        }
        expect(state(), endsWith(' lands=-'));
      });
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

  // -------------------------------------------------------------------------
  // the `/` menu (plan 029 §3.5, D17)
  // -------------------------------------------------------------------------
  //
  // The screen RENDERS what the shared rules answer and handles keys; the
  // rules here are `fake_slash_rules.dart`'s stand-in (no native library in a
  // widget test), recorded, and every effect is read off the fake SOURCE's
  // recorded calls (P26) — a send, a rename, a set, a stop — never off the
  // screen alone.
  group('the / menu (plan 029 §3.5)', () {
    test('the key table with the menu UP', () {
      ComposerKey k(LogicalKeyboardKey key, {bool shift = false}) =>
          composerKey(key: key, shift: shift, composing: false, menuUp: true);
      expect(k(LogicalKeyboardKey.enter), ComposerKey.accept);
      expect(k(LogicalKeyboardKey.numpadEnter), ComposerKey.accept);
      expect(k(LogicalKeyboardKey.tab), ComposerKey.complete);
      expect(k(LogicalKeyboardKey.escape), ComposerKey.dismiss);
      expect(k(LogicalKeyboardKey.arrowUp), ComposerKey.up);
      expect(k(LogicalKeyboardKey.arrowDown), ComposerKey.down);
      expect(k(LogicalKeyboardKey.keyA), ComposerKey.none, reason: 'typing');
      expect(
        k(LogicalKeyboardKey.tab, shift: true),
        ComposerKey.none,
        reason: 'Shift+Tab moves focus back',
      );
    });

    test('CONTROL: with the menu closed — zero matches included — Enter '
        'sends and the rest are the field\'s', () {
      ComposerKey k(LogicalKeyboardKey key) =>
          composerKey(key: key, shift: false, composing: false, menuUp: false);
      expect(k(LogicalKeyboardKey.enter), ComposerKey.send);
      for (final key in [
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.keyA,
      ]) {
        expect(k(key), ComposerKey.none, reason: key.debugName);
      }
    });

    test('CONTROL: Shift+Enter is a newline, menu or not', () {
      for (final up in [true, false]) {
        expect(
          composerKey(
            key: LogicalKeyboardKey.enter,
            shift: true,
            composing: false,
            menuUp: up,
          ),
          ComposerKey.newline,
        );
      }
    });

    test('CONTROL: every key is ignored while an IME composes — the menu\'s '
        'and Enter-to-send alike', () {
      for (final up in [true, false]) {
        for (final shift in [true, false]) {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.tab,
            LogicalKeyboardKey.escape,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
          ]) {
            expect(
              composerKey(key: key, shift: shift, composing: true, menuUp: up),
              ComposerKey.none,
              reason: '${key.debugName} up=$up shift=$shift',
            );
          }
        }
      }
    });

    test('composing is a non-empty composing range', () {
      expect(isComposing(const TextEditingValue(text: '/re')), isFalse);
      expect(
        isComposing(
          const TextEditingValue(
            text: '/re',
            composing: TextRange(start: 1, end: 3),
          ),
        ),
        isTrue,
      );
      expect(
        isComposing(
          const TextEditingValue(
            text: '/re',
            composing: TextRange.collapsed(3),
          ),
        ),
        isFalse,
      );
    });

    test('an Esc dismissal lasts exactly until the token changes', () {
      expect(dismissalAfter('/re', '/re'), '/re', reason: 'still dismissed');
      expect(dismissalAfter('/re', '/ren'), isNull, reason: 'typed on');
      expect(dismissalAfter(null, '/re'), isNull);
      // Once gone it stays gone: typing back does not re-close the menu.
      expect(dismissalAfter(dismissalAfter('/re', '/ren'), '/re'), isNull);
    });

    test('the highlight wraps at either end', () {
      expect(moveHighlight(0, 1, 3), 1);
      expect(moveHighlight(2, 1, 3), 0);
      expect(moveHighlight(0, -1, 3), 2);
      expect(moveHighlight(1, -1, 3), 0);
      expect(moveHighlight(4, 1, 0), 0, reason: 'no rows: the first');
    });

    test('the menu is up only while the filter says open and Esc has not '
        'dismissed this token', () {
      final open = BridgeSlashFilter(
        open: true,
        token: '/re',
        rows: [BridgeSlashFilterRow(row: crazeMenu.rows[1], dimmed: false)],
        start: 0,
      );
      expect(slashMenuUp(open, null), isTrue);
      expect(slashMenuUp(open, '/re'), isFalse, reason: 'dismissed for it');
      expect(slashMenuUp(open, '/r'), isTrue, reason: 'another token');
      expect(
        slashMenuUp(
          const BridgeSlashFilter(
            open: false,
            token: '/zz',
            rows: [],
            start: 0,
          ),
          null,
        ),
        isFalse,
        reason: 'zero matches is a closed menu',
      );
      expect(slashMenuUp(null, null), isFalse, reason: 'no menu at all');
    });

    testWidgets('/ lists the session\'s rows in the shared order, the first '
        'highlighted, the caret read in UTF-16', (tester) async {
      final rig = await _slashRig(tester);
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);

      await _type(tester, '/');
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsOneWidget);
      expect(_slashRows(), crazeMenuNames);
      expect(_slashHighlighted(tester), 'model');
      expect(find.byKey(const ValueKey('lane-slash-after-plan')), findsNothing);
      expect(rig.rules.filters.last, (draft: '/', caret: 1, working: false));

      // A caret past an astral character is counted in UTF-16 code units —
      // what the shared filter reads (E10), with nothing converted here.
      await _type(tester, '/re 🦀');
      expect(rig.rules.filters.last.caret, '/re 🦀'.length);
      expect('/re 🦀'.length, 6, reason: 'the crab is two code units');
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);
    });

    testWidgets('the / button: only on an EMPTY draft of a session with a '
        'menu; a tap inserts / and opens the menu', (tester) async {
      final rig = await _slashRig(tester);
      final button = find.byKey(const ValueKey('lane-slash-button'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await _settle(tester);
      expect(_draft(tester), '/');
      expect(_selection(tester), const TextSelection.collapsed(offset: 1));
      expect(_slashRows(), crazeMenuNames, reason: 'the menu, on every row');
      expect(button, findsNothing, reason: 'the draft is no longer empty');

      await _type(tester, 'hello');
      expect(button, findsNothing);
      await _type(tester, '');
      expect(button, findsOneWidget, reason: 'empty again');
      expect(rig.source.sends, isEmpty);
    });

    testWidgets('FU9: an ABANDONED lane with a catalog shows no / button; a '
        'live one does (plan 030)', (tester) async {
      final rig = await _slashRig(tester);
      final button = find.byKey(const ValueKey('lane-slash-button'));
      expect(button, findsOneWidget, reason: 'a live lane keeps it');
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);

      // A final Down: the lane is given up on, its catalog still on the
      // state. The abandon's teardown needs the real event loop (see "a
      // stale lane names the reason").
      rig.bump(_slashSnap(stale: 'session_closed', ended: true));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(
        _sendEnabled(tester),
        isFalse,
        reason: 'given up on (its banner alone says so, plan 032 §3.1.2)',
      );
      expect(button, findsNothing, reason: 'nothing can run here');
    });

    testWidgets('FU9: a lane RE-OPENING after a non-final Down keeps its / '
        'button, enabled — `ended` is not `abandoned` (plan 030, PC7)', (
      tester,
    ) async {
      final rig = await _slashRig(tester);
      final button = find.byKey(const ValueKey('lane-slash-button'));

      rig.bump(_slashSnap(stale: 'hub connection lost', ended: true));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(
        tester.widget<Text>(_bannerText('lane-note')).data,
        'Reconnecting…',
        reason: 'ended, waiting out the re-open backoff',
      );
      expect(button, findsOneWidget, reason: 'no blink while it re-opens');
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('lane-send')))
            .onPressed,
        isNotNull,
        reason: 'as Send stays enabled',
      );

      // The re-open lands on a healthy session: still there.
      rig.source.current = _slashSnap();
      await tester.pump(laneRetryBase * 2);
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stale')), findsNothing);
      expect(button, findsOneWidget);
    });

    testWidgets('CONTROL: no menu without caps.slash or without a catalog — '
        'no button, no panel, and /help goes out as TEXT', (tester) async {
      for (final snapshot in [
        // A catalog the capabilities do not vouch for is not offered.
        _slashSnap(caps: _caps(kind: 'craze', stop: true)),
        // `slash`, but no catalog (yet, or truncated away): none either.
        _snap(capabilities: _slashCaps),
      ]) {
        final rig = await _slashRig(tester, snapshot);
        expect(find.byKey(const ValueKey('lane-slash-button')), findsNothing);
        await _type(tester, '/help');
        expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);
        await _press(tester, LogicalKeyboardKey.enter);
        expect(rig.source.sends.map((s) => s.text), ['/help']);
        expect(find.byKey(const ValueKey('lane-slash-refusal')), findsNothing);
        expect(rig.rules.filters, isEmpty, reason: 'no rule was asked');
        expect(rig.rules.dispatches, isEmpty);
        // The controls: the same session WITH a menu lists it.
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await _slashRig(tester);
      expect(find.byKey(const ValueKey('lane-slash-button')), findsOneWidget);
    });

    testWidgets('Enter on /re ACCEPTS — the draft completes and nothing is '
        'sent; with a title typed Enter RENAMES and the draft clears', (
      tester,
    ) async {
      final rig = await _slashRig(tester);

      await _type(tester, '/re');
      expect(_slashRows().first, 'rename');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(_draft(tester), '/rename ');
      expect(_selection(tester), const TextSelection.collapsed(offset: 8));
      expect(rig.rules.accepts.last.key, BridgeSlashAcceptKey.enter);
      expect(rig.source.titles, isEmpty, reason: 'accepting sends nothing');
      expect(
        find.byKey(const ValueKey('lane-slash-menu')),
        findsNothing,
        reason: 'the caret is past the token now',
      );

      // A token that already spells the row: Enter SENDS — here a rename
      // with no title, refused by the shared guard, the draft kept.
      await _type(tester, '/rename');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(_slashRefusal(tester), 'type a title after /rename');
      expect(_draft(tester), '/rename');
      expect(rig.source.titles, isEmpty);

      await _type(tester, '/rename   plan 029 desk ');
      expect(
        find.byKey(const ValueKey('lane-slash-refusal')),
        findsNothing,
        reason: 'an edit clears the refusal',
      );
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['plan 029 desk'], reason: 'trimmed, literal');
      expect(_draft(tester), '', reason: 'success clears the draft');
      expect(find.byKey(const ValueKey('lane-slash-refusal')), findsNothing);
      expect(find.byKey(const ValueKey('lane-slash-warning')), findsNothing);
      expect(find.byKey(const ValueKey('lane-composer-error')), findsNothing);
      expect(rig.source.sends, isEmpty, reason: 'never sent as text');
    });

    testWidgets('Tab completes and never runs; Enter on a row that takes no '
        'argument runs it at once', (tester) async {
      final rig = await _slashRig(tester);

      await _type(tester, '/pl');
      await _press(tester, LogicalKeyboardKey.tab);
      expect(_draft(tester), '/plan ');
      expect(rig.rules.accepts.last.key, BridgeSlashAcceptKey.tab);
      expect(rig.source.sets, isEmpty, reason: 'Tab never runs a row');

      await _type(tester, '/pl');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sets, [const BridgeLaneSettingChange.mode(id: 'plan')]);
      expect(_draft(tester), '');
    });

    testWidgets('↑/↓ move the highlight — wrapping, the draft untouched — and '
        'Enter accepts the highlighted row', (tester) async {
      final rig = await _slashRig(tester);

      await _type(tester, '/');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_slashHighlighted(tester), 'rename');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_slashHighlighted(tester), 'research', reason: 'wrapped');
      expect(_draft(tester), '/', reason: 'the arrows moved the highlight');
      expect(_selection(tester), const TextSelection.collapsed(offset: 1));

      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.rules.accepts.last.row, 'research');
      expect(_draft(tester), '/research ', reason: 'a prompt row completes');
      expect(rig.source.sends, isEmpty);
    });

    testWidgets('the highlight goes back to the first row when the filter or '
        'the catalog changes', (tester) async {
      final rig = await _slashRig(tester);

      await _type(tester, '/');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_slashHighlighted(tester), 'plan');

      await _type(tester, '/a');
      expect(_slashRows(), ['ask', 'agent', 'rename', 'plan', 'research']);
      expect(_slashHighlighted(tester), 'ask', reason: 'a new filter');

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_slashHighlighted(tester), 'agent');
      // A streamed frame with the SAME menu moves nothing.
      rig.bump(_slashSnap(rows: [_row(1, 'assistant', 'hi')]));
      await _settle(tester);
      expect(_slashHighlighted(tester), 'agent');
      // A new catalog does.
      rig.bump(
        _slashSnap(
          menu: BridgeSlashMenu(
            rows: [
              slashRow(
                'alpha',
                const BridgeSlashAction.prompt(),
                source: const BridgeSlashSource.agent(),
              ),
              ...crazeMenu.rows,
            ],
            hidden: crazeMenu.hidden,
          ),
        ),
      );
      await _settle(tester);
      expect(_slashRows().take(3), ['alpha', 'ask', 'agent']);
      expect(_slashHighlighted(tester), 'alpha', reason: 'a new catalog');
    });

    testWidgets('Esc closes the menu and it stays closed until the token '
        'changes; a second Esc does nothing', (tester) async {
      final rig = await _slashRig(tester);

      await _type(tester, '/');
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);
      expect(_draft(tester), '/', reason: 'only the menu closed');
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('lane-screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);
      expect(_draft(tester), '/');

      await _type(tester, '/r');
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsOneWidget);
      // Typing back to the dismissed token does not re-close it.
      await _type(tester, '/');
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsOneWidget);
      expect(rig.source.sends, isEmpty);
    });

    testWidgets('IME: while composing, Enter / Esc / ↓ / Tab change nothing, '
        'and a composing Enter on plain text sends nothing', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/');
      const composing = TextEditingValue(
        text: '/',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.tab,
      ]) {
        tester.testTextInput.updateEditingValue(composing);
        await _settle(tester);
        await tester.sendKeyEvent(key);
        await _settle(tester);
        expect(_draft(tester), '/', reason: key.debugName);
        expect(_slashHighlighted(tester), 'model', reason: key.debugName);
        expect(
          find.byKey(const ValueKey('lane-slash-menu')),
          findsOneWidget,
          reason: key.debugName,
        );
      }
      expect(rig.rules.accepts, isEmpty);
      expect(rig.rules.dispatches, isEmpty);

      await _type(tester, 'hello ime');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello ime',
          selection: TextSelection.collapsed(offset: 9),
          composing: TextRange(start: 6, end: 9),
        ),
      );
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends, isEmpty, reason: 'a composing Enter');
      expect(_draft(tester), 'hello ime');

      // The composition committed, a real Enter sends.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello ime',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends.map((s) => s.text), ['hello ime']);
    });

    testWidgets('Shift+Enter is a newline: the menu closes on a multi-line '
        'draft and nothing is sent', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _settle(tester);
      expect(_draft(tester), '/\n');
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);
      expect(rig.source.sends, isEmpty);
      expect(rig.rules.accepts, isEmpty);
    });

    testWidgets('the keyboard\'s Send action takes the same rule as Enter', (
      tester,
    ) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/re');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(_draft(tester), '/rename ', reason: 'it accepted');
      expect(rig.source.titles, isEmpty);

      await _type(tester, '/rename from the keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(rig.source.titles, ['from the keyboard']);
      expect(_draft(tester), '');
    });

    testWidgets('Send goes through the dispatch: a typed hidden builtin is '
        'refused inline and NOTHING is sent', (tester) async {
      final rig = await _slashRig(tester);
      for (final typed in ['/help', ' /help', '/HELP']) {
        await _type(tester, typed);
        await tester.tap(find.byKey(const ValueKey('lane-send')));
        await _settle(tester);
        expect(
          _slashRefusal(tester),
          '/help: not available here yet',
          reason: typed,
        );
        expect(_draft(tester), typed, reason: 'the draft is kept');
      }
      expect(rig.source.sends, isEmpty, reason: 'never sent as text');
      expect(rig.source.titles, isEmpty);
      expect(rig.source.sets, isEmpty);

      // A `/x` the menu does not know is text, as it always was.
      await _type(tester, '/zz top');
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);
      expect(rig.source.sends.map((s) => s.text), ['/zz top']);
    });

    testWidgets('a prompt row sends its CANONICAL spelling, and queues while '
        'a turn runs', (tester) async {
      final rig = _Rig(
        snapshot: _slashSnap(activity: BridgeRcActivity.working),
      );
      await _pumpSlash(tester, rig);
      await _type(tester, '/Research   deep dive ');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends.single.text, '/research deep dive');
      expect(rig.source.sends.single.mode, BridgeSendMode.queue);
      expect(_draft(tester), '');
    });

    testWidgets('while a turn runs, waiting rows are DIMMED — "after this '
        'turn" — and choosing one is refused, nothing sent', (tester) async {
      final rig = _Rig(
        snapshot: _slashSnap(activity: BridgeRcActivity.needsApproval),
      );
      await _pumpSlash(tester, rig);
      await _type(tester, '/');
      expect(_slashRows(), crazeMenuNames, reason: 'listed, not hidden');
      final dimmed = {
        for (final name in crazeMenuNames)
          if (find
              .byKey(ValueKey('lane-slash-after-$name'))
              .evaluate()
              .isNotEmpty)
            name,
      };
      expect(dimmed, crazeWaitingRows);

      await tester.tap(find.byKey(const ValueKey('lane-slash-row-plan')));
      await _settle(tester);
      expect(_slashRefusal(tester), '/plan: runs after this turn');
      expect(_draft(tester), '/', reason: 'the draft is kept');
      expect(rig.rules.accepts.last.key, BridgeSlashAcceptKey.pick);

      await _type(tester, '/ask');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(_slashRefusal(tester), '/ask: runs after this turn');
      expect(rig.source.sets, isEmpty, reason: 'nothing was sent');

      // `rename` works during a turn (whileWorking).
      await _type(tester, '/rename mid-turn');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['mid-turn']);
    });

    testWidgets('a mode from the composer needs no settings capability, and '
        're-selecting the current mode still sends', (tester) async {
      final rig = _Rig(
        snapshot: _slashSnap(
          caps: _caps(kind: 'craze', slash: true, setTitle: true),
          menu: BridgeSlashMenu(
            rows: crazeMenu.rows
                .where((r) => r.action is! BridgeSlashAction_ModelPicker)
                .toList(),
            hidden: crazeMenu.hidden,
          ),
        ),
      );
      await _pumpSlash(tester, rig);
      expect(find.byKey(const ValueKey('lane-settings-chip')), findsNothing);
      for (var i = 0; i < 2; i++) {
        await _type(tester, '/plan');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(_draft(tester), '');
      }
      expect(rig.source.sets, [
        const BridgeLaneSettingChange.mode(id: 'plan'),
        const BridgeLaneSettingChange.mode(id: 'plan'),
      ]);
      expect(find.byKey(const ValueKey('lane-settings')), findsNothing);

      // A refused mode is the composer's: craze's words, the draft kept.
      rig.source.setFailure = const BridgeLaneError.notAccepting();
      await _type(tester, '/ask');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-composer-error')), findsOneWidget);
      expect(_draft(tester), '/ask');
    });

    testWidgets('a rename craze REFUSES keeps the draft and says craze\'s '
        'words', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.setTitleFailure = const BridgeLaneError.badRequest(
          msg: 'params.title is blank once normalized: send none instead',
        );
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename x');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['x']);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('lane-composer-error')))
            .data,
        contains('params.title is blank once normalized'),
      );
      expect(_draft(tester), '/rename x');
    });

    testWidgets('an unknown outcome keeps the draft: "may have applied — '
        'check the session" — a rename and a prompt row alike', (tester) async {
      final rig = _Rig(snapshot: _slashSnap());
      rig.source.setTitleFailure = const BridgeLaneError.outcomeUnknown(
        msg: 'outcome unknown: the connection dropped',
      );
      rig.source.sendFailure = const BridgeLaneError.outcomeUnknown(
        msg: 'outcome unknown: the connection dropped',
      );
      await _pumpSlash(tester, rig);
      String error() => tester
          .widget<Text>(find.byKey(const ValueKey('lane-composer-error')))
          .data!;

      await _type(tester, '/rename lost');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(error(), laneCommandOutcomeUnknown);
      expect(laneCommandOutcomeUnknown, 'may have applied — check the session');
      expect(_draft(tester), '/rename lost');

      await _type(tester, '/research lost too');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(error(), laneCommandOutcomeUnknown);
      expect(_draft(tester), '/research lost too');

      // A plain send keeps today's words.
      await _type(tester, 'plain text');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(error(), laneSendOutcomeUnknown);
      expect(rig.source.sends.map((s) => s.text), [
        '/research lost too',
        'plain text',
      ]);
    });

    testWidgets('a rename craze could not RECORD clears the draft and shows '
        'the warning', (tester) async {
      const warning =
          'renamed, but craze could not record it: write index: disk full';
      final rig = _Rig(snapshot: _slashSnap())
        ..source.setTitleWarning = warning;
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename kept anyway');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['kept anyway']);
      expect(_draft(tester), '');
      expect(find.byKey(const ValueKey('lane-slash-warning')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('lane-slash-warning')))
            .data,
        warning,
      );
      expect(find.byKey(const ValueKey('lane-slash-refusal')), findsNothing);
      expect(find.byKey(const ValueKey('lane-composer-error')), findsNothing);
      // An edit clears it.
      await _type(tester, 'x');
      expect(find.byKey(const ValueKey('lane-slash-warning')), findsNothing);
    });

    testWidgets('/exit asks first: Keep sends NOTHING and keeps the draft; '
        'Stop session stops once and clears it', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/exit');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsOneWidget);
      expect(rig.source.stops, 0, reason: 'never one key');

      await tester.tap(find.byKey(const ValueKey('lane-stop-keep')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsNothing);
      expect(rig.source.stops, 0, reason: 'Keep sent nothing');
      expect(_draft(tester), '/exit', reason: 'and kept the draft');

      await _type(tester, '/exit');
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);
      expect(rig.source.stops, 1);
      expect(_draft(tester), '', reason: 'the stop went through');
    });

    testWidgets('/model opens the settings sheet and clears the draft; '
        '/model <id> is refused, nothing opened', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/model grok-4.6');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(
        _slashRefusal(tester),
        '/model: takes no argument — pick a model from the list',
      );
      expect(find.byKey(const ValueKey('lane-settings')), findsNothing);
      expect(_draft(tester), '/model grok-4.6');

      await _type(tester, '/model');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-settings')), findsOneWidget);
      expect(_draft(tester), '', reason: 'the picker clears the draft');
      expect(rig.source.sets, isEmpty, reason: 'opening it changes nothing');
    });

    testWidgets('a bare /effort opens the settings sheet and clears the '
        'draft, as /model does — by Enter, and by a pick on /eff (plan 032 '
        '§3.2)', (tester) async {
      final rig = await _slashRig(tester, _slashSnap(menu: effortMenu));
      await _type(tester, '/effort');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-settings')), findsOneWidget);
      expect(_draft(tester), '', reason: 'the picker clears the draft');

      Navigator.of(
        tester.element(find.byKey(const ValueKey('lane-settings'))),
      ).pop();
      await _settle(tester);
      await _type(tester, '/eff');
      await tester.tap(find.byKey(const ValueKey('lane-slash-row-effort')));
      await _settle(tester);
      expect(rig.rules.accepts.last.key, BridgeSlashAcceptKey.pick);
      expect(find.byKey(const ValueKey('lane-settings')), findsOneWidget);
      expect(_draft(tester), '');
      expect(rig.source.sets, isEmpty, reason: 'opening it changes nothing');
    });

    testWidgets('/effort <level> sends the effort bound to its model — the '
        'current level too — and a refusal is the composer\'s (plan 032 '
        '§3.2)', (tester) async {
      await _withLog((lines) async {
        final rig = await _slashRig(tester, _slashSnap(menu: effortMenu));
        const low = BridgeLaneSettingChange.config(
          id: 'effort',
          value: 'low',
          forModel: 'grok-4.6',
        );
        await _type(tester, '/effort low');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(rig.source.sets, [low]);
        expect(_draft(tester), '', reason: 'it took: the draft clears');
        expect(find.byKey(const ValueKey('lane-settings')), findsNothing);
        expect(lines, contains('MRESULT lane-effort ok'));

        // The same level again — by id in any case — still sends: an inline
        // level always does (craze's rule), unlike the sheet's press.
        await _type(tester, '/effort LOW');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(rig.source.sets, [low, low]);

        // craze's own refusal of a level the option does not offer: inline,
        // the draft kept, nothing sent.
        await _type(tester, '/effort bogus');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(
          _slashRefusal(tester),
          'no effort bogus: one of low, medium, high, xhigh',
        );
        expect(_draft(tester), '/effort bogus');
        expect(rig.source.sets, hasLength(2));

        // A refusal from the session (`stale_model`: the model moved since
        // the menu) is the composer's, as a mode's is: the draft kept.
        rig.source.setFailure = const BridgeLaneError.notAccepting();
        await _type(tester, '/effort high');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(
          rig.source.sets.last,
          const BridgeLaneSettingChange.config(
            id: 'effort',
            value: 'high',
            forModel: 'grok-4.6',
          ),
        );
        expect(
          _composerError(tester),
          'the session is not accepting that right now',
        );
        expect(_draft(tester), '/effort high');
        expect(
          lines.where((l) => l.startsWith('MRESULT lane-effort')).last,
          startsWith('MRESULT lane-effort error='),
        );
      });
    });

    testWidgets('mid-turn a valid /effort level is refused for the turn, and '
        'one naming nothing for that first', (tester) async {
      final rig = await _slashRig(
        tester,
        _slashSnap(menu: effortMenu, activity: BridgeRcActivity.working),
      );
      await _type(tester, '/effort low');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(_slashRefusal(tester), '/effort: runs after this turn');
      await _type(tester, '/effort bogus');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(
        _slashRefusal(tester),
        'no effort bogus: one of low, medium, high, xhigh',
      );
      expect(rig.source.sets, isEmpty);
    });

    testWidgets('a 600-row menu renders in a panel capped at 40% of the '
        'viewport, and scrolls to the highlight', (tester) async {
      final names = [
        for (var i = 0; i < 600; i++) 'cmd-${i.toString().padLeft(3, '0')}',
      ];
      final rig = _Rig(
        snapshot: _slashSnap(
          menu: BridgeSlashMenu(
            rows: [
              for (final name in names)
                slashRow(
                  name,
                  const BridgeSlashAction.prompt(),
                  source: const BridgeSlashSource.agent(),
                ),
            ],
            hidden: const [],
          ),
        ),
      );
      await _pumpSlash(tester, rig);
      await _type(tester, '/');
      final list = find.byKey(const ValueKey('lane-slash-list'));
      final viewport =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getSize(list).height, lessThanOrEqualTo(viewport * 0.4));
      expect(rig.rules.filters.last.draft, '/');
      expect(_slashRows().first, 'cmd-000');
      expect(
        find.byKey(const ValueKey('lane-slash-row-cmd-599')),
        findsNothing,
        reason: 'laid out lazily',
      );

      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_slashHighlighted(tester), 'cmd-599', reason: 'wrapped');
      final last = find.byKey(const ValueKey('lane-slash-row-cmd-599'));
      expect(last, findsOneWidget, reason: 'scrolled into view');
      expect(
        tester.getRect(list).contains(tester.getRect(last).center),
        isTrue,
      );

      // And a finger scrolls it: back up the list, the last row out of view.
      await tester.drag(list, const Offset(0, 2000));
      await _settle(tester);
      expect(_slashRows(), isNot(contains('cmd-599')), reason: 'it scrolls');
      expect(
        int.parse(_slashRows().first.substring('cmd-'.length)),
        lessThan(560),
      );
    });

    // ---- the draft's ownership, one command at a time, the highlight and
    // ---- the dismissal (the coordinator's corrections to C4, mirrored)

    testWidgets('OWNERSHIP: a rename\'s success clears only the draft it was '
        'sent from — a newer one stays — and its warning still shows', (
      tester,
    ) async {
      const warning = 'renamed, but craze could not record it: disk full';
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>()
        ..source.setTitleWarning = warning;
      await _pumpSlash(tester, rig);
      await _type(tester, '/rename held');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['held'], reason: 'the rename is in flight');

      // The box moves under the verb.
      _inputController(tester).text = 'a newer draft';
      await _settle(tester);
      rig.source.holdSetTitle!.complete();
      await _settle(tester);
      expect(_draft(tester), 'a newer draft', reason: 'never erased');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('lane-slash-warning')))
            .data,
        warning,
        reason: 'the outcome is still said',
      );
    });

    testWidgets('OWNERSHIP: a plain send\'s success clears only the draft it '
        'was sent from', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSend = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, 'first words');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends.map((s) => s.text), ['first words']);
      _inputController(tester).text = 'second words';
      await _settle(tester);
      rig.source.holdSend!.complete();
      await _settle(tester);
      expect(_draft(tester), 'second words');
    });

    testWidgets('OWNERSHIP: /exit\'s stop clears only its own draft — typing '
        'on while the stop is in flight keeps what was typed', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdStop = Completer<void>();
      await _pumpSlash(tester, rig);
      await _type(tester, '/exit');
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);
      expect(rig.source.stops, 1, reason: 'the stop is in flight');

      // The composer stays live during a stop: the person types on.
      await _type(tester, 'still typing');
      rig.source.holdStop!.complete();
      await _settle(tester);
      expect(_draft(tester), 'still typing');
    });

    testWidgets('OWNERSHIP: a draft that changed while /exit\'s confirm was '
        'up calls the stop off — nothing is sent', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/exit');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsOneWidget);

      _inputController(tester).text = '/exit later';
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);
      expect(rig.source.stops, 0, reason: 'dropped, silently');
      expect(find.byKey(const ValueKey('lane-stop-error')), findsNothing);
      expect(_draft(tester), '/exit later');
    });

    testWidgets('ONE AT A TIME: two submits in one turn — before the first '
        'one\'s confirm is up — open ONE confirm and ask the rules once', (
      tester,
    ) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/exit');
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('lane-input')),
      );
      // Back to back, no await between them: the second lands while the
      // first is between its decision (Stop) and its outcome (the confirm,
      // pushed and not yet answered). Taps cannot show this — a pushed route
      // absorbs pointers until its first frame — but a keyboard's submits
      // can.
      field.onSubmitted!('/exit');
      field.onSubmitted!('/exit');
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('lane-stop-confirm')),
        findsOneWidget,
        reason: 'one confirm',
      );
      expect(rig.rules.accepts, hasLength(1), reason: 'one confirm');
      await tester.tap(find.byKey(const ValueKey('lane-stop-keep')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsNothing);
      expect(rig.source.stops, 0);
      expect(_draft(tester), '/exit');
    });

    testWidgets('HIGHLIGHT: a new token resets it even when the rows are the '
        'same ones (/r → /re)', (tester) async {
      await _slashRig(tester);
      await _type(tester, '/r');
      expect(_slashRows(), ['rename', 'research']);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_slashHighlighted(tester), 'research');

      await _type(tester, '/re');
      expect(_slashRows(), ['rename', 'research'], reason: 'the same rows');
      expect(_slashHighlighted(tester), 'rename', reason: 'a new token');

      // A caret move inside the token is no new filter.
      await _press(tester, LogicalKeyboardKey.arrowDown);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '/re',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await _settle(tester);
      expect(_slashHighlighted(tester), 'research');
    });

    testWidgets('HIGHLIGHT: a new CATALOG resets it even when every row\'s '
        'name is the same — `plan` now behind another mode', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_slashHighlighted(tester), 'plan');

      // CONTROL: a catalog equal BY VALUE — a fresh copy, as a new read
      // converts — is no new catalog: the highlight stays.
      rig.bump(
        _slashSnap(
          menu: BridgeSlashMenu(
            rows: [...crazeMenu.rows],
            hidden: [...crazeMenu.hidden],
          ),
        ),
      );
      await _settle(tester);
      expect(_slashHighlighted(tester), 'plan', reason: 'the same catalog');

      // The same names in the same order, but `plan` is another mode now:
      // Enter must not run its newly bound action from a highlight the
      // person put on the old one.
      rig.bump(
        _slashSnap(
          menu: BridgeSlashMenu(
            rows: [
              for (final row in crazeMenu.rows)
                row.name == 'plan'
                    ? slashRow(
                        'plan',
                        const BridgeSlashAction.setMode(id: 'architect'),
                        description: 'Plan mode',
                      )
                    : row,
            ],
            hidden: crazeMenu.hidden,
          ),
        ),
      );
      await _settle(tester);
      expect(_slashRows(), crazeMenuNames, reason: 'every name the same');
      expect(_slashHighlighted(tester), 'model', reason: 'a new catalog');
    });

    testWidgets('HIGHLIGHT: opened mid-turn it starts on the first LIVE row, '
        'past a dimmed one, so Enter acts at once (plan 030 FU8)', (
      tester,
    ) async {
      final rig = await _slashRig(
        tester,
        _slashSnap(activity: BridgeRcActivity.working),
      );

      await _type(tester, '/');
      expect(_slashRows().take(2), ['model', 'rename']);
      expect(
        find.byKey(const ValueKey('lane-slash-after-model')),
        findsOneWidget,
        reason: 'row 0 is dimmed: the start is not row 0 by accident',
      );
      expect(_slashHighlighted(tester), 'rename', reason: 'the first live row');

      // `rename` takes a title: Enter COMPLETES it — no refusal, nothing sent.
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.rules.accepts.last.row, 'rename');
      expect(_draft(tester), '/rename ');
      expect(_slashRefusal(tester), isNull);
      expect(rig.source.titles, isEmpty);
      expect(rig.source.sends, isEmpty);

      // A new token resets to ITS start: `/a` lists two waiting rows first.
      await _type(tester, '/a');
      expect(_slashRows(), ['ask', 'agent', 'rename', 'plan', 'research']);
      expect(_slashHighlighted(tester), 'rename');
    });

    testWidgets('HIGHLIGHT: a start below more dimmed rows than the panel has '
        'room for is SCROLLED INTO VIEW as the panel opens — Enter never '
        'accepts a row nobody can see (plan 030 FU8)', (tester) async {
      // A phone with its keyboard up: the panel gets a few rows' height, and
      // the first live row sits under twelve that wait for the turn.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      addTearDown(tester.view.reset);
      final rig = _Rig(
        snapshot: _slashSnap(
          activity: BridgeRcActivity.working,
          menu: _deepWorkingMenu,
        ),
      );
      await _pump(tester, rig);

      await _type(tester, '/');
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final list = tester.getRect(
        find.byKey(const ValueKey('lane-slash-list')),
      );
      expect(
        list.height,
        lessThan(12 * slashMenuRowExtent),
        reason: 'at scroll 0 the start row would be below the panel',
      );
      expect(_slashHighlighted(tester), 'live');
      final row = tester.getRect(
        find.byKey(const ValueKey('lane-slash-row-live')),
      );
      expect(row.top, greaterThanOrEqualTo(list.top - 0.5), reason: 'shown');
      expect(row.bottom, lessThanOrEqualTo(list.bottom + 0.5), reason: 'shown');

      // Enter takes the row on screen: a prompt row completes.
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.rules.accepts.last.row, 'live');
      expect(_draft(tester), '/live ');
      expect(rig.source.sends, isEmpty);
    });

    testWidgets('HIGHLIGHT: the keyboard opening UNDER an open menu shrinks '
        'the panel and the highlight is scrolled back into view — Enter '
        'still takes a row on screen (plan 030 FU8)', (tester) async {
      // The menu opens with the keyboard down — the `/` button tapped — and
      // the live row sits under twelve that wait for the turn.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig(
        snapshot: _slashSnap(
          activity: BridgeRcActivity.working,
          menu: _deepWorkingMenu,
        ),
      );
      await _pump(tester, rig);
      await tester.tap(find.byKey(const ValueKey('lane-slash-button')));
      await _settle(tester);
      final list = find.byKey(const ValueKey('lane-slash-list'));
      final live = find.byKey(const ValueKey('lane-slash-row-live'));
      void liveShown(String when) {
        final l = tester.getRect(list);
        final r = tester.getRect(live);
        expect(r.top, greaterThanOrEqualTo(l.top - 0.5), reason: when);
        expect(r.bottom, lessThanOrEqualTo(l.bottom + 0.5), reason: when);
      }

      expect(_slashHighlighted(tester), 'live');
      liveShown('the keyboard down');
      final roomy = tester.getRect(list).height;

      // Then the keyboard comes up: the dock shrinks, the rows and the
      // highlight do not change.
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(
        tester.getRect(list).height,
        lessThan(roomy - slashMenuRowExtent),
        reason: 'the panel lost more than a row of room',
      );
      expect(_slashHighlighted(tester), 'live');
      liveShown('the keyboard up');

      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.rules.accepts.last.row, 'live');
      expect(_draft(tester), '/live ');
    });

    testWidgets('HIGHLIGHT: a working flip moves no highlight — the row the '
        'person arrowed to stays; Enter on it is refused "runs after this '
        'turn", Tab still completes it (plan 030 FU8)', (tester) async {
      final rig = await _slashRig(tester);

      await _type(tester, '/');
      expect(_slashHighlighted(tester), 'model', reason: 'idle: row 0 is live');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_slashHighlighted(tester), 'plan');
      expect(find.byKey(const ValueKey('lane-slash-after-plan')), findsNothing);

      rig.bump(_slashSnap(activity: BridgeRcActivity.working));
      await _settle(tester);
      expect(rig.rules.filters.last.working, isTrue, reason: 'refiltered');
      expect(
        find.byKey(const ValueKey('lane-slash-after-plan')),
        findsOneWidget,
      );
      expect(
        _slashHighlighted(tester),
        'plan',
        reason: 'kept, not moved to the start',
      );

      await _press(tester, LogicalKeyboardKey.enter);
      expect(_slashRefusal(tester), '/plan: runs after this turn');
      expect(_draft(tester), '/');
      expect(rig.source.sets, isEmpty, reason: 'nothing was sent');

      await _press(tester, LogicalKeyboardKey.tab);
      expect(_draft(tester), '/plan ', reason: 'completed for after the turn');
      expect(rig.source.sets, isEmpty);
    });

    testWidgets('SUPERSEDED: a rename whose lane was REBUILT before it '
        'answered keeps the draft and says "may have applied" — never a '
        'success — and a plain send says its own words', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdSetTitle = Completer<void>()
        ..source.setTitleFailure = const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: the connection dropped',
        )
        ..source.holdSend = Completer<void>()
        ..source.sendFailure = const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: the connection dropped',
        );
      await _pumpSlash(tester, rig);
      String? composerError() => _composerError(tester);
      Future<void> rebuild() => _rebuildLane(tester);

      await _type(tester, '/rename held');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['held'], reason: 'the rename is in flight');
      await rebuild();
      rig.source.holdSetTitle!.complete();
      await _settle(tester);

      expect(_draft(tester), '/rename held', reason: 'kept: not a success');
      expect(composerError(), laneCommandOutcomeUnknown);
      expect(find.byKey(const ValueKey('lane-slash-warning')), findsNothing);
      expect(tester.takeException(), isNull);

      // A plain send the lane moved on from: kept, in the send's words.
      await _type(tester, 'plain words');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.sends.map((s) => s.text), ['plain words']);
      expect(composerError(), isNull, reason: 'a new verb clears the last');
      await rebuild();
      rig.source.holdSend!.complete();
      await _settle(tester);
      expect(_draft(tester), 'plain words');
      expect(composerError(), laneSendOutcomeUnknown);

      // The next verb, on the live lane, clears what the screen said.
      rig.source
        ..holdSend = null
        ..sendFailure = null;
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);
      expect(rig.source.sends, hasLength(2));
      expect(_draft(tester), '', reason: 'this one took');
      expect(composerError(), isNull);
    });

    testWidgets('SUPERSEDED: a Cancel whose lane was REBUILT before it '
        'answered says "may have run" in the composer — not nothing — and '
        'the next composer verb clears it (plan 030 FU11)', (tester) async {
      // Even an Ok: the lane that would have said how it went let it go.
      final rig = _Rig(snapshot: _slashSnap(activity: BridgeRcActivity.working))
        ..source.holdCancel = Completer<void>();
      await _pumpSlash(tester, rig);

      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await _settle(tester);
      expect(rig.source.cancels, 1, reason: 'the cancel is in flight');
      await _rebuildLane(tester);
      rig.source.holdCancel!.complete();
      await _settle(tester);

      expect(_composerError(tester), laneCommandOutcomeUnknown);
      expect(find.byKey(const ValueKey('lane-stop-error')), findsNothing);
      expect(tester.takeException(), isNull);

      // The next composer verb, on the live lane, clears what it said.
      rig.source.holdCancel = null;
      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await _settle(tester);
      expect(rig.source.cancels, 2);
      expect(_composerError(tester), isNull);
    });

    testWidgets('SUPERSEDED: a header Stop whose lane was REBUILT before it '
        'answered says "may have run" in the Stop banner, and the next Stop '
        'clears it (plan 030 FU11)', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.holdStop = Completer<void>();
      await _pumpSlash(tester, rig);

      await _confirmHeaderStop(tester);
      expect(rig.source.stops, 1, reason: 'the stop is in flight');
      await _rebuildLane(tester);
      rig.source.holdStop!.complete();
      await _settle(tester);

      expect(
        tester.widget<Text>(_bannerText('lane-stop-error')).data,
        laneCommandOutcomeUnknown,
      );
      expect(
        _composerError(tester),
        isNull,
        reason: 'the header\'s, not the composer\'s',
      );
      expect(tester.takeException(), isNull);

      // The next Stop clears it — here one that goes through.
      rig.source.holdStop = null;
      await _confirmHeaderStop(tester);
      expect(rig.source.stops, 2);
      expect(find.byKey(const ValueKey('lane-stop-error')), findsNothing);
    });

    testWidgets('SUPERSEDED: what a lost Cancel or header Stop said belongs '
        'to the SESSION it was said for — a reconnect to that session keeps '
        'both; a new stamp naming another session shows neither (plan 030 '
        'FU11)', (tester) async {
      const working = BridgeRcActivity.working;
      final rig = _Rig(snapshot: _slashSnap(activity: working))
        ..source.holdCancel = Completer<void>()
        ..source.holdStop = Completer<void>();
      await _pumpSlash(tester, rig);
      String? banner() {
        final f = _bannerText('lane-stop-error');
        return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
      }

      void bothSaid(String why) {
        expect(_composerError(tester), laneCommandOutcomeUnknown, reason: why);
        expect(banner(), laneCommandOutcomeUnknown, reason: why);
      }

      // Session A (`sess-7`): a Cancel, then a header Stop, each lost to a
      // provider rebuild — itself a reconnect to A, so the Cancel's note
      // outlives the second one.
      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await _settle(tester);
      await _rebuildLane(tester);
      rig.source.holdCancel!.complete();
      await _settle(tester);
      await _confirmHeaderStop(tester);
      await _rebuildLane(tester);
      rig.source.holdStop!.complete();
      await _settle(tester);
      bothSaid('session A, across a rebuild');

      // CONTROL: a non-final Down re-opened on the same stamp — A again.
      rig.bump(
        _slashSnap(
          activity: working,
          stale: 'hub connection lost',
          ended: true,
        ),
      );
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      rig.source.current = _slashSnap(activity: working);
      await tester.pump(laneRetryBase * 2);
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stale')), findsNothing);
      bothSaid('a reconnect to A');

      // CONTROL: a restarted tab — a new stamp, but A's session on a new
      // port. Still A.
      rig.feed.restamp(url: 'http://127.0.0.1:2500');
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(rig.source.specs.last.reportedUrl, 'http://127.0.0.1:2500');
      bothSaid('the same session on a new port');

      // A new stamp naming session B: neither of A's notes is B's.
      rig.feed.restamp(session: 'sess-8');
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(rig.source.specs.last.sessionId, 'sess-8', reason: 'B is open');
      expect(banner(), isNull, reason: 'A\'s Stop is not B\'s');
      expect(_composerError(tester), isNull, reason: 'nor A\'s Cancel');
      expect(tester.takeException(), isNull);
    });

    testWidgets('NOTES: a rename\'s "could not record" warning belongs to the '
        'session it was said for — a reconnect to it keeps the note; a new '
        'stamp naming another session, menu and all, does not show it (plan '
        '030)', (tester) async {
      const warning =
          'renamed, but craze could not record it: write index: disk full';
      final rig = _Rig(snapshot: _slashSnap())
        ..source.setTitleWarning = warning;
      await _pumpSlash(tester, rig);
      final note = find.byKey(const ValueKey('lane-slash-warning'));
      Future<void> restamp({String? session, String? url}) async {
        rig.feed.restamp(session: session, url: url);
        await _settle(tester);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await _settle(tester);
      }

      await _type(tester, '/rename on A');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.source.titles, ['on A']);
      expect(note, findsOneWidget);

      // CONTROLS: reconnects to A — the lane's provider rebuilt, then A on a
      // new port (a restarted tab).
      await _rebuildLane(tester);
      expect(note, findsOneWidget, reason: 'a rebuild: still A');
      await restamp(url: 'http://127.0.0.1:2500');
      expect(rig.source.specs.last.reportedUrl, 'http://127.0.0.1:2500');
      expect(note, findsOneWidget, reason: 'the same session on a new port');

      // Session B, which offers the menu too: A's caveat is not B's.
      await restamp(session: 'sess-8');
      expect(rig.source.specs.last.sessionId, 'sess-8', reason: 'B is open');
      expect(
        find.byKey(const ValueKey('lane-slash-button')),
        findsOneWidget,
        reason: 'B offers the menu: the note goes with A, not with a catalog',
      );
      expect(note, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DISMISSAL: a moment with no menu (a catalog on its way back) '
        'does not end an Esc dismissal; a different token does', (
      tester,
    ) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/');
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsNothing);

      rig.bump(_snap(capabilities: _slashCaps)); // the menu gone for a read
      await _settle(tester);
      rig.bump(_slashSnap()); // and back
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('lane-slash-menu')),
        findsNothing,
        reason: 'still dismissed for "/"',
      );

      await _type(tester, '/m');
      expect(find.byKey(const ValueKey('lane-slash-menu')), findsOneWidget);
    });

    // ---- the M3 review's fixes (soft Send's composition, /exit's outcome,
    // ---- the keyboard, no catalog → no note, a missing lane)

    testWidgets('IME: a soft-keyboard Send COMMITS the composition, the focus '
        'kept — a refused draft is not left composing, and the next hardware '
        'key acts', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/help');
      // The IME is still composing the token when its Send arrives, and no
      // editing update follows the Send.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '/help',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 1, end: 5),
        ),
      );
      await _settle(tester);
      expect(isComposing(_inputController(tester).value), isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);

      expect(_slashRefusal(tester), '/help: not available here yet');
      expect(_draft(tester), '/help', reason: 'refused: the draft is kept');
      expect(
        _inputController(tester).value.composing,
        TextRange.empty,
        reason: 'the Send committed the composition',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('lane-input')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
        reason: 'the caret stays, to fix the draft in place',
      );
      expect(rig.rules.dispatches, hasLength(1));

      // With nothing more from the IME, a hardware Enter is no longer
      // swallowed by the composing guard: it dispatches again.
      await _press(tester, LogicalKeyboardKey.enter);
      expect(rig.rules.dispatches, hasLength(2), reason: 'the key acted');
      expect(rig.source.sends, isEmpty);
    });

    testWidgets('/exit\'s outcome is the COMMAND\'s: a lost answer keeps the '
        'draft and says "may have applied" in the composer, a refusal says '
        'craze\'s words there — the header\'s Stop keeps its banner', (
      tester,
    ) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.stopFailure = const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: the connection dropped with session.stop',
        );
      await _pumpSlash(tester, rig);
      String? composerError() {
        final f = find.byKey(const ValueKey('lane-composer-error'));
        return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
      }

      Future<void> exitConfirmed() async {
        await _type(tester, '/exit');
        await _press(tester, LogicalKeyboardKey.enter);
        await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
        await _settle(tester);
      }

      await exitConfirmed();
      expect(rig.source.stops, 1);
      expect(composerError(), laneCommandOutcomeUnknown);
      expect(_draft(tester), '/exit', reason: 'kept: it may not have run');
      expect(
        find.byKey(const ValueKey('lane-stop-error')),
        findsNothing,
        reason: 'the composer\'s, not the header\'s',
      );

      rig.source.stopFailure = const BridgeLaneError.failed(
        msg: 'unsupported: this host cannot stop its session',
      );
      await exitConfirmed();
      expect(rig.source.stops, 2);
      expect(
        composerError(),
        'unsupported: this host cannot stop its session',
        reason: 'craze\'s words',
      );
      expect(_draft(tester), '/exit');
      expect(find.byKey(const ValueKey('lane-stop-error')), findsNothing);

      // The header's Stop is unchanged: its lost answer is the banner's, as
      // the controller said it.
      rig.source.stopFailure = const BridgeLaneError.outcomeUnknown(
        msg: 'outcome unknown: the connection dropped with session.stop',
      );
      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);
      expect(rig.source.stops, 3);
      expect(
        tester.widget<Text>(_bannerText('lane-stop-error')).data,
        'outcome unknown: the connection dropped with session.stop',
      );

      // And `/exit` that goes through clears the draft and what it said.
      rig.source.stopFailure = null;
      await exitConfirmed();
      expect(rig.source.stops, 4);
      expect(_draft(tester), '');
      expect(composerError(), isNull);
    });

    testWidgets('THE KEYBOARD: with the keyboard up and a catalog taller than '
        'the body, the menu shrinks and scrolls — the composer\'s input and '
        'Send stay on screen, nothing overflows', (tester) async {
      // A phone: 400×800, a 350-pixel keyboard, the header's settings chip
      // (the session offers settings) — 354 pixels of body for the status
      // strip, the transcript, the menu (40 % of the viewport would be 320)
      // and the composer (its Interject/Cancel row included).
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      addTearDown(tester.view.reset);
      final names = [
        for (var i = 0; i < 600; i++) 'cmd-${i.toString().padLeft(3, '0')}',
      ];
      final big = BridgeSlashMenu(
        rows: [
          for (final name in names)
            slashRow(
              name,
              const BridgeSlashAction.prompt(),
              source: const BridgeSlashSource.agent(),
            ),
        ],
        hidden: const [],
      );
      final rig = _Rig(snapshot: _slashSnap(menu: big));
      await _pump(tester, rig);
      await _type(tester, '/');
      expect(tester.takeException(), isNull, reason: 'no overflow');

      const visibleBottom = 800.0 - 350.0;
      void composerOnScreen(String when) {
        for (final key in ['lane-input', 'lane-send']) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(
            rect.bottom,
            lessThanOrEqualTo(visibleBottom),
            reason: '$key above the keyboard ($when)',
          );
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$key ($when)');
        }
        final menu = tester.getRect(
          find.byKey(const ValueKey('lane-slash-menu')),
        );
        final input = tester.getRect(find.byKey(const ValueKey('lane-input')));
        expect(menu.height, greaterThan(0), reason: 'the menu is up ($when)');
        expect(
          menu.bottom,
          lessThanOrEqualTo(input.top),
          reason: 'the menu sits above the composer ($when)',
        );
      }

      composerOnScreen('the menu alone');
      expect(_slashRows().first, 'cmd-000');
      // It still scrolls to the highlight inside what it was given.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_slashHighlighted(tester), 'cmd-599');
      expect(
        tester
            .getRect(find.byKey(const ValueKey('lane-slash-list')))
            .contains(
              tester
                  .getRect(find.byKey(const ValueKey('lane-slash-row-cmd-599')))
                  .center,
            ),
        isTrue,
      );

      // An approval arrives while the menu is up: the two share what is left,
      // and the composer still does not move off.
      rig.bump(
        _snap(
          capabilities: _slashCaps,
          slashMenu: big,
          approvals: [
            _approval(
              kind: const BridgeLaneApprovalKind.permission(),
              options: const [
                BridgeLaneApprovalOption(id: 'opt-a', label: 'Allow once'),
                BridgeLaneApprovalOption(id: 'opt-b', label: 'Always allow'),
                BridgeLaneApprovalOption(id: 'opt-c', label: 'Reject'),
              ],
            ),
          ],
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.byKey(const ValueKey('lane-approvals')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('lane-approvals'))).height,
        greaterThan(0),
        reason: 'the approvals keep a share',
      );
      composerOnScreen('the menu and an approval');
    });

    testWidgets('NO CATALOG, NO NOTE: a refusal or a warning goes when the '
        'catalog or caps.slash does — no edit needed', (tester) async {
      final rig = _Rig(snapshot: _slashSnap())
        ..source.setTitleWarning =
            'renamed, but craze could not record it: disk full';
      await _pumpSlash(tester, rig);

      await _type(tester, '/help');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(_slashRefusal(tester), '/help: not available here yet');
      // The catalog goes (truncated away; a reseed without it).
      rig.bump(_snap(capabilities: _slashCaps));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-slash-refusal')), findsNothing);
      expect(find.byKey(const ValueKey('lane-slash-button')), findsNothing);
      expect(_draft(tester), '/help', reason: 'no edit made it go');
      // The note is the menu's: with the menu back, so is what it said of
      // this very draft.
      rig.bump(_slashSnap());
      await _settle(tester);
      expect(_slashRefusal(tester), '/help: not available here yet');

      // A rename's warning, and the capability (not the catalog) going.
      await _type(tester, '/rename noted');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(const ValueKey('lane-slash-warning')), findsOneWidget);
      rig.bump(_slashSnap(caps: _caps(kind: 'craze', stop: true)));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-slash-warning')), findsNothing);
      expect(find.byKey(const ValueKey('lane-slash-refusal')), findsNothing);
    });

    testWidgets('A MISSING LANE: the lane provider failing under a mounted '
        'screen — a Stop confirm, a key and Send do nothing and throw '
        'nothing, and the composer is not left busy', (tester) async {
      final rig = await _slashRig(tester);
      await _type(tester, '/rename gone');
      // The header's confirm is up when the lane goes.
      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsOneWidget);

      // A machine-feed rebuild with no lane stamp for this row: from now on
      // every read of the lane's provider refuses — Riverpod rethrowing the
      // provider's StateError wrapped in a ProviderException.
      rig.feed.laneGone = true;
      ProviderScope.containerOf(
        tester.element(find.byType(LaneScreen)),
      ).invalidate(laneControllerProvider(_ref));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'rendering is safe');
      expect(
        find.byKey(const ValueKey('lane-unavailable')),
        findsOneWidget,
        reason: 'the screen stays up on the last state, saying so',
      );
      expect(
        tester.widget<Text>(_bannerText('lane-unavailable')).data,
        'This lane is gone: no agent lane on mini3/7 (opencode)',
        reason: 'the cause, not Riverpod\'s wrapper and its stack trace',
      );

      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'the confirm');
      expect(rig.source.stops, 0);

      await _type(tester, '/rename gone');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(tester.takeException(), isNull, reason: 'Enter');
      await _type(tester, '/re');
      await _press(tester, LogicalKeyboardKey.tab);
      expect(tester.takeException(), isNull, reason: 'Tab');
      await _type(tester, 'plain words');
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'Send');

      expect(rig.source.titles, isEmpty, reason: 'nothing to send to');
      expect(rig.source.sends, isEmpty);
      expect(
        find.byKey(const ValueKey('lane-send')),
        findsOneWidget,
        reason: 'not left busy: the Send button, not a spinner',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('lane-input')))
            .enabled,
        isTrue,
      );
      expect(_draft(tester), 'plain words', reason: 'nothing cleared it');
    });

    testWidgets('MSTATE says slash=<shown>/<open>; the composer verbs log '
        'lane-rename and lane-mode', (tester) async {
      await _withLog((lines) async {
        await _slashRig(tester);
        String state() => lines.lastWhere((l) => l.startsWith('MSTATE'));
        expect(state(), endsWith(' slash=7/0'));
        await _type(tester, '/re');
        expect(state(), endsWith(' slash=7/2'), reason: 'rename, research');
        await _type(tester, '/');
        expect(state(), endsWith(' slash=7/7'));

        await _type(tester, '/rename logged');
        await _press(tester, LogicalKeyboardKey.enter);
        await _type(tester, '/agent');
        await _press(tester, LogicalKeyboardKey.enter);
        expect(lines, contains('MRESULT lane-rename ok'));
        expect(lines, contains('MRESULT lane-mode ok'));

        await tester.pumpWidget(const SizedBox.shrink());
        await _slashRig(tester, _snap());
        expect(state(), endsWith(' slash=-/-'), reason: 'no menu at all');
      });
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

/// A NATIVE session on grok-4.6 (plan 032 §3.3): its models state craze
/// 0.2.0's effort facts — claude-opus-5 a switch level, glm-5.2 a default
/// only, composer-2.5 none — over grok-4.6's options.
final _native = BridgeLaneSettings(
  model: 'grok-4.6',
  models: const [
    BridgeLaneChoice(
      id: 'grok-4.6',
      name: 'Grok 4.6',
      effort: BridgeLaneModelEffort(
        efforts: ['low', 'medium', 'high', 'xhigh'],
        defaultEffort: 'high',
      ),
    ),
    BridgeLaneChoice(id: 'composer-2.5', name: 'Composer 2.5'),
    BridgeLaneChoice(
      id: 'claude-opus-5',
      name: 'Claude Opus 5',
      effort: BridgeLaneModelEffort(
        efforts: ['low', 'max'],
        defaultEffort: 'max',
        switchEffort: 'low',
      ),
    ),
    BridgeLaneChoice(
      id: 'glm-5.2',
      name: 'GLM 5.2',
      effort: BridgeLaneModelEffort(
        efforts: ['high', 'max'],
        defaultEffort: 'high',
      ),
    ),
  ],
  mode: 'agent',
  modes: _modes,
  options: _grok46.options,
);

/// The dim line the sheet's model list draws under [model], or null.
String? _secondary(String model) {
  final f = find
      .byKey(ValueKey('lane-setting-secondary-model:model-$model'))
      .evaluate();
  return f.isEmpty ? null : (f.single.widget as Text).data;
}

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
  final craze = rig.feed.crazeHost;
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
        // No native library in a widget test: the `/` menu's shared rules
        // are the rig's stand-in (`fake_slash_rules.dart`).
        slashRulesProvider.overrideWithValue(rig.rules),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: craze == null
            ? const LaneScreen(
                machine: 'mini3',
                kind: 'opencode',
                slug: '7',
                title: 'row7',
              )
            : LaneScreen(
                machine: 'mini3',
                kind: crazeLaneKind,
                slug: craze,
                title: 'craze $craze',
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
  slash: false,
  setTitle: false,
);

/// Run [body] with every `debugPrint` line — the drive log's MSTATE and
/// MRESULT lines — collected into the list it is handed. Restored INSIDE the
/// test body: the binding checks its debug variables before any tear-down
/// runs.
Future<void> _withLog(Future<void> Function(List<String> lines) body) async {
  final lines = <String>[];
  final saved = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    await body(lines);
  } finally {
    debugPrint = saved;
  }
}

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
  BridgeSlashMenu? slashMenu,
  // What the shared core names on every settings fixture here — each has an
  // `effort` select; an explicit null says it named none. No settings, no
  // effort option, as the core reads it.
  String? effortOption = 'effort',
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
  slashMenu: slashMenu,
  effortOption: settings == null ? null : effortOption,
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
  bool slash = false,
  bool setTitle = false,
}) => BridgeLaneCapabilities(
  kind: kind,
  interject: interject,
  cancel: cancel,
  approvals: true,
  historyCursor: true,
  settings: settings,
  stop: stop,
  slash: slash,
  setTitle: setTitle,
);

/// The [Text] inside the banner keyed [key].
Finder _bannerText(String key) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text));

/// The screen, the real providers, and a stubbed bridge + machine feed.
class _Rig {
  _Rig({
    BridgeLaneSnapshot? snapshot,
    String kind = 'opencode',
    String? crazeHost,
  }) : source = _FakeSource(current: snapshot ?? _snap()),
       feed = _FakeFeed(kind: kind, crazeHost: crazeHost);

  final _FakeSource source;
  final _FakeFeed feed;

  /// The `/` menu's rules, recorded.
  final rules = FakeSlashRules();

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

  /// When set, `cancel` awaits it — a cancel in flight.
  Completer<void>? holdCancel;

  @override
  Future<void> cancel(LaneHandle handle) async {
    cancels++;
    final hold = holdCancel;
    if (hold != null) await hold.future;
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

  /// When set, `stop` awaits it — a stop in flight.
  Completer<void>? holdStop;

  @override
  Future<void> stop(LaneHandle handle) async {
    stops++;
    final hold = holdStop;
    if (hold != null) await hold.future;
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

  /// Every rename sent, in order.
  final titles = <String>[];
  Object? setTitleFailure;

  /// What a rename that TOOK answers with — craze's `index_write` warning.
  String? setTitleWarning;

  /// When set, `setTitle` awaits it — a rename in flight.
  Completer<void>? holdSetTitle;

  @override
  Future<String?> setTitle(LaneHandle handle, String title) async {
    titles.add(title);
    final hold = holdSetTitle;
    if (hold != null) await hold.future;
    final failure = setTitleFailure;
    if (failure != null) throw failure;
    return setTitleWarning;
  }

  @override
  void close(LaneHandle handle) {}
}

class _FakeHandle implements LaneHandle {}

/// A [MachineFeed] the provider can be handed: the real one dials SSH and calls
/// the FRB-sync `roostCapabilities()` in its constructor, so it cannot exist in
/// a widget test at all.
class _FakeFeed implements MachineFeed {
  _FakeFeed({required this.kind, this.crazeHost});

  final String kind;

  /// When set, the machine's one row is a CRAZE session with this hostId,
  /// listed by a live craze roster (and the screen opens its lane) — instead
  /// of the roost tab. [crazeRowGone] takes it off the roster.
  final String? crazeHost;
  bool crazeRowGone = false;

  /// The roster's next round, as the feed would publish it.
  void publish() => _updates.add(state);

  /// The row's lane stamp is gone — what a machine-feed rebuild without it
  /// leaves: the next build of `laneControllerProvider` refuses.
  bool laneGone = false;

  /// The row's lane stamp — the agent session behind the tab, and where its
  /// server answers. Moved by [restamp].
  String sessionId = 'sess-7';
  String serverUrl = 'http://127.0.0.1:2421';

  final _updates = StreamController<MachineFeedState>.broadcast();

  /// A new lane stamp on the row, as the machine feed's next poll says it:
  /// another agent session behind the same tab ([session]), or the same one
  /// on a new port (a restarted tab, [url]). The lane reconciles against it.
  void restamp({String? session, String? url}) {
    sessionId = session ?? sessionId;
    serverUrl = url ?? serverUrl;
    publish();
  }

  @override
  MachineRecord get machine => _mini3;

  @override
  MachineFeedState get state => crazeHost == null ? _roostState : _crazeState;

  MachineFeedState get _crazeState {
    final rows = [
      if (!crazeRowGone)
        BridgeLaneSession(
          id: crazeHost!,
          title: 'craze row',
          cwd: '/home/shed/proj',
          activity: BridgeRcActivity.idle,
          pendingApprovals: 0,
          approximate: false,
        ),
    ];
    return MachineFeedState(
      machine: _mini3,
      connectedOnce: true,
      reachable: true,
      craze: BridgeCrazeSnapshot(rows: rows, live: true, truncated: false),
      foldedRows: [
        for (final row in rows) CrazeMachineRow(session: row, stale: false),
      ],
    );
  }

  /// The machine's craze source — one, live, never replaced.
  @override
  int? get crazeLiveEpoch => 1;

  @override
  Stream<int?> get crazeSources => const Stream.empty();

  MachineFeedState get _roostState => MachineFeedState(
    machine: _mini3,
    connectedOnce: true,
    reachable: true,
    sessions: [
      if (!laneGone)
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
            sessionId: sessionId,
            serverUrl: serverUrl,
          ),
        ),
    ],
  );

  @override
  Stream<MachineFeedState> get updates => _updates.stream;

  @override
  Future<LaneLease> acquireForward(int remotePort) async =>
      FakeLaneLease(41000);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// the `/` menu fixtures and finders (plan 029)
// ---------------------------------------------------------------------------

/// A craze session with a `/` menu: `slash` and `setTitle`, and `stop` and
/// `settings` too — so `/exit` and `/model` show.
final _slashCaps = _caps(
  kind: 'craze',
  stop: true,
  settings: true,
  slash: true,
  setTitle: true,
);

/// Twelve rows that wait for a turn, then one that does not (`live`, a
/// prompt): mid-turn the highlight starts below more dimmed rows than a
/// keyboard-squeezed panel has room for.
final _deepWorkingMenu = BridgeSlashMenu(
  rows: [
    for (var i = 0; i < 12; i++)
      slashRow('wait-$i', BridgeSlashAction.setMode(id: 'mode-$i')),
    slashRow(
      'live',
      const BridgeSlashAction.prompt(),
      source: const BridgeSlashSource.agent(),
    ),
  ],
  hidden: const [],
);

/// A seeded craze session carrying [menu] (the hub-created session's menu by
/// default).
BridgeLaneSnapshot _slashSnap({
  BridgeRcActivity activity = BridgeRcActivity.idle,
  BridgeLaneCapabilities? caps,
  BridgeSlashMenu? menu,
  List<BridgeRcFeedMessage> rows = const [],
  String? stale,
  bool ended = false,
}) => _snap(
  rows: rows,
  activity: activity,
  capabilities: caps ?? _slashCaps,
  slashMenu: menu ?? crazeMenu,
  stale: stale,
  ended: ended,
);

/// [_pump], on a view tall enough that a menu of the hub's seven rows lays
/// out whole under the panel's 40 % cap.
Future<void> _pumpSlash(WidgetTester tester, _Rig rig) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _pump(tester, rig);
}

/// A `/`-menu cell's lane on [snapshot] (by default a craze session carrying
/// the hub's menu), pumped ([_pumpSlash]).
Future<_Rig> _slashRig(
  WidgetTester tester, [
  BridgeLaneSnapshot? snapshot,
]) async {
  final rig = _Rig(snapshot: snapshot ?? _slashSnap());
  await _pumpSlash(tester, rig);
  return rig;
}

/// Press [key] on the focused composer and let the screen settle.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester);
}

/// Type [text] into the composer (focusing it), the caret at its end.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('lane-input')), text);
  await _settle(tester);
}

TextEditingController _inputController(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('lane-input')))
    .controller!;

String _draft(WidgetTester tester) => _inputController(tester).text;

/// The composer, offstage too: a page pushed over the lane keeps it built,
/// out of the finders' default view.
Finder get _laneInputAnywhere =>
    find.byKey(const ValueKey('lane-input'), skipOffstage: false);

/// Whether the composer has the focus (its [EditableText]'s node, as the IME
/// cell reads it).
bool _composerFocused(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: _laneInputAnywhere,
        matching: find.byType(EditableText, skipOffstage: false),
        skipOffstage: false,
      ),
    )
    .focusNode
    .hasFocus;

/// Whether the composer's field is enabled — off while a verb is out.
bool _composerOn(WidgetTester tester) =>
    tester.widget<TextField>(_laneInputAnywhere).enabled ?? true;

TextSelection _selection(WidgetTester tester) =>
    _inputController(tester).selection;

/// The menu panel's rows on screen (built), by name, in the order drawn.
List<String> _slashRows() => find
    .byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('lane-slash-row-');
    })
    .evaluate()
    .map(
      (e) => (e.widget.key! as ValueKey<String>).value.substring(
        'lane-slash-row-'.length,
      ),
    )
    .toList();

/// The row the panel highlights — the one its own semantics say is selected.
String? _slashHighlighted(WidgetTester tester) {
  for (final name in _slashRows()) {
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(ValueKey('lane-slash-row-$name')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    if (semantics.properties.selected ?? false) return name;
  }
  return null;
}

/// The header's Stop, confirmed: its button, then the dialog's "Stop
/// session".
Future<void> _confirmHeaderStop(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('lane-stop')));
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
  await _settle(tester);
}

/// Whether Send can be pressed — off once the lane is over.
bool _sendEnabled(WidgetTester tester) =>
    tester
        .widget<IconButton>(find.byKey(const ValueKey('lane-send')))
        .onPressed !=
    null;

/// What the composer's error slot says, or null.
String? _composerError(WidgetTester tester) {
  final f = find.byKey(const ValueKey('lane-composer-error'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

/// The lane's provider rebuilds — a new controller for the same row — and
/// the old one is closed, its generation moved, with any verb still out. Its
/// teardown awaits a subscription cancel that only the real event loop
/// finishes (see "a stale lane names the reason").
Future<void> _rebuildLane(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(LaneScreen)),
  ).invalidate(laneControllerProvider(_ref));
  await _settle(tester);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

/// The refusal the composer shows for a `/` command, or null.
String? _slashRefusal(WidgetTester tester) {
  final f = find.byKey(const ValueKey('lane-slash-refusal'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

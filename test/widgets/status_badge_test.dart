import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/theme/shed_colors.dart';
import 'package:shed_mobile/theme/shed_theme.dart';
import 'package:shed_mobile/widgets/status_badge.dart';

Future<void> _pumpDot(WidgetTester tester, {required bool animate}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: shedLightTheme,
        home: Scaffold(
          body: StatusDot(tone: ShedStatusTone.ok, animate: animate),
        ),
      ),
    );

void main() {
  testWidgets(
    'StatusDot survives animate true→false→true on one ticker '
    '(regression: a second AnimationController threw createTicker\'s assert)',
    (tester) async {
      await _pumpDot(tester, animate: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      // Pulse off: the animation stops, the dot renders static.
      await _pumpDot(tester, animate: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);

      // Pulse back ON — the old code created a SECOND controller against the
      // single ticker here and red-screened the tree with the
      // '_dependents.isEmpty' assert.
      await _pumpDot(tester, animate: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isTrue); // pulsing again
      // Scoped under StatusDot: MaterialApp's route transitions add their own
      // FadeTransitions elsewhere in the tree.
      expect(
        find.descendant(
          of: find.byType(StatusDot),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );

      // Tear down while animating must not leak or throw either.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('StatusBadge pulse flag drives the dot animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: shedLightTheme,
        home: const Scaffold(
          body: StatusBadge(
            tone: ShedStatusTone.ok,
            label: 'working',
            pulse: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

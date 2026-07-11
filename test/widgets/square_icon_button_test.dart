import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/theme/shed_theme.dart';
import 'package:shed_mobile/widgets/square_icon_button.dart';

void main() {
  testWidgets(
    'a tap on the keyed element reaches the InkWell (tooltip variant) — the '
    'ValueKey must sit on the gesture target for drive-harness key-taps',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: shedLightTheme,
          home: Scaffold(
            body: Center(
              child: SquareIconButton(
                key: const ValueKey('sib-under-test'),
                icon: Icons.visibility_outlined,
                tooltip: 'Watch',
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      // The keyed widget's root must be the InkWell itself (the OpenPill
      // pattern), so tapping by key fires onPressed.
      await tester.tap(find.byKey(const ValueKey('sib-under-test')));
      expect(taps, 1);
      // Structural assertion: the Tooltip is INSIDE the InkWell (the InkWell
      // is the widget's root, so a key-tap lands on the gesture target). The
      // pre-fix structure (Tooltip wrapping InkWell) fails this.
      expect(
        find.ancestor(of: find.byType(Tooltip), matching: find.byType(InkWell)),
        findsOneWidget,
      );
    },
  );
}

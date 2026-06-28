import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/session_card.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _session = RcSession(
  slug: 'abc123',
  tmuxSession: 'rc-abc123',
  displayName: 'frontend',
  kind: RcKind.claudeRc,
  state: RcState.ready,
  managed: true,
);

Future<void> _pump(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: shedLightTheme,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: const Scaffold(
            body: SessionCard(
              serverName: 'h',
              shedName: 'web',
              session: _session,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('desktop: open/delete actions, name, kind chip, status badge', (
    tester,
  ) async {
    await _pump(tester, 1100);
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-session-delete-h-web-abc123')),
      findsOneWidget,
    );
    expect(find.text('frontend'), findsOneWidget); // displayName
    expect(find.text('claude-rc'), findsOneWidget); // kind chip (kind.wire)
    expect(find.text('ready'), findsOneWidget); // status badge (state.wire)
  });

  testWidgets('mobile: still has open + delete (both layouts carry them)', (
    tester,
  ) async {
    await _pump(tester, 400);
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-session-delete-h-web-abc123')),
      findsOneWidget,
    );
  });
}

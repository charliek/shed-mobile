import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/app/desktop_scaffold.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _rec = ServerRecord(
  name: 'mini2',
  host: 'mini2',
  sshPort: 2222,
  apiUrl: 'https://mini2:8443',
  tlsCertFingerprint: 'sha256:x',
  hostKeyPin: 'pin',
);

void main() {
  testWidgets('sidebar nav is Sheds/Sessions/Hosts (no System) + host rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serversProvider.overrideWith((ref) => <ServerRecord>[_rec]),
        ],
        child: MaterialApp(
          theme: shedLightTheme,
          home: const DesktopScaffold(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('nav-sheds')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-sessions')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-hosts')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-system')), findsNothing);
    // The saved-host quick-reference row survives the merge.
    expect(find.byKey(const ValueKey('desktop-host-mini2')), findsOneWidget);

    // The Sheds/Sessions panes carry the create header buttons; Hosts does not.
    await tester.tap(find.byKey(const ValueKey('nav-sheds')));
    await tester.pump();
    expect(find.byKey(const ValueKey('desktop-new-shed')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-sessions')));
    await tester.pump();
    expect(find.byKey(const ValueKey('desktop-new-session')), findsOneWidget);
  });
}

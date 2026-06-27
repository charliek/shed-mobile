import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/main.dart';

void main() {
  testWidgets('app renders the home placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ShedMobileApp()));
    expect(find.byKey(const ValueKey('home-placeholder')), findsOneWidget);
  });
}

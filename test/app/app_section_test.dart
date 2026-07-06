import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/app/app_section.dart';

void main() {
  group('isDesktopWidth', () {
    test('the boundary is exclusive below / inclusive at 900', () {
      expect(isDesktopWidth(899), isFalse);
      expect(isDesktopWidth(899.99), isFalse);
      expect(isDesktopWidth(900), isTrue);
      expect(isDesktopWidth(1200), isTrue);
      expect(isDesktopWidth(0), isFalse);
    });
  });

  group('AppSection', () {
    test('is exactly the three merged sections (System folded into Hosts)', () {
      expect(AppSection.values, [
        AppSection.hosts,
        AppSection.sheds,
        AppSection.sessions,
      ]);
    });
  });
}

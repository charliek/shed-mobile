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

  group('sectionForDesktop', () {
    test('hosts maps to sheds (desktop has no Hosts pane)', () {
      expect(sectionForDesktop(AppSection.hosts), AppSection.sheds);
    });
    test('every other section is unchanged', () {
      expect(sectionForDesktop(AppSection.sheds), AppSection.sheds);
      expect(sectionForDesktop(AppSection.sessions), AppSection.sessions);
      expect(sectionForDesktop(AppSection.system), AppSection.system);
    });
  });
}

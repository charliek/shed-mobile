import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/shed/shed_status.dart';
import 'package:shed_mobile/theme/shed_colors.dart';

void main() {
  group('runtimeBadge', () {
    test('vz → the blue tokens + "vz" label', () {
      final badge = runtimeBadge(ShedColors.light, 'vz');
      expect(badge, isNotNull);
      final (bg, fg, label) = badge!;
      expect(label, 'vz');
      expect(bg, ShedColors.light.runtimeVzBg);
      expect(fg, ShedColors.light.runtimeVzFg);
    });

    test('firecracker → the amber tokens + "firecracker" label (dark)', () {
      final (bg, fg, label) = runtimeBadge(ShedColors.dark, 'firecracker')!;
      expect(label, 'firecracker');
      expect(bg, ShedColors.dark.runtimeFcBg);
      expect(fg, ShedColors.dark.runtimeFcFg);
    });

    test('an unknown / runtime-less / null backend shows no badge', () {
      expect(runtimeBadge(ShedColors.light, 'none'), isNull);
      expect(runtimeBadge(ShedColors.light, null), isNull);
      expect(runtimeBadge(ShedColors.light, 'xen'), isNull);
    });
  });
}

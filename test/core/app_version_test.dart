import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_version.dart';

void main() {
  // kAppVersion is hand-maintained (no build-time codegen on the unit-test path),
  // so this guards against it drifting from pubspec.yaml's `version:` and shipping
  // a stale provenance tag in SHED_RC_CREATED_BY.
  test('kAppVersion matches pubspec.yaml version (minus +build)', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere(
      (l) => l.startsWith('version:'),
      orElse: () => '',
    );
    expect(line, isNotEmpty, reason: 'pubspec.yaml must declare a version');
    final raw = line.split(':')[1].trim();
    final semver = raw.split('+').first;
    expect(kAppVersion, semver);
  });
}

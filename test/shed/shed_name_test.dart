import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/shed/format.dart';
import 'package:shed_mobile/shed/shed_name.dart';

void main() {
  group('validateShedName', () {
    test('accepts valid DNS-label-ish names', () {
      for (final ok in ['a', 'ab', 'my-shed', 'shed1', 'a1-b2-c3', 'x' * 63]) {
        expect(validateShedName(ok), isNull, reason: ok);
      }
    });

    test('rejects invalid names', () {
      expect(validateShedName(''), isNotNull); // empty
      expect(validateShedName('   '), isNotNull); // blank
      expect(validateShedName('1shed'), isNotNull); // leading digit
      expect(validateShedName('-shed'), isNotNull); // leading hyphen
      expect(validateShedName('shed-'), isNotNull); // trailing hyphen
      expect(validateShedName('My-Shed'), isNotNull); // uppercase
      expect(validateShedName('my_shed'), isNotNull); // underscore
      expect(validateShedName('my.shed'), isNotNull); // dot
      expect(validateShedName('x' * 64), isNotNull); // too long
    });
  });

  group('suggestShedName', () {
    test('basics', () {
      expect(suggestShedName('owner/my-project'), 'my-project');
      expect(suggestShedName('owner/repo.git'), 'repo');
      expect(suggestShedName('owner/My_Repo'), 'my-repo');
      expect(suggestShedName('owner/awesome.dotfiles'), 'awesome-dotfiles');
      expect(suggestShedName(''), '');
    });

    test('handles URLs and trailing slashes', () {
      expect(
        suggestShedName('https://github.com/owner/my-project.git'),
        'my-project',
      );
      expect(suggestShedName('git@github.com:owner/repo.git'), 'repo');
      expect(suggestShedName('owner/repo/'), 'repo');
      expect(
        suggestShedName('https://github.com/owner/repo?tab=readme'),
        'repo',
      );
    });

    test(
      'yields empty when nothing valid remains (must start with a letter)',
      () {
        expect(
          suggestShedName('owner/2048'),
          '',
        ); // all digits -> no leading letter
        expect(suggestShedName('owner/---'), '');
      },
    );

    test('every non-empty suggestion is itself a valid shed name', () {
      final repos = [
        'owner/My_Repo',
        'owner/repo.git',
        'owner/awesome.dotfiles',
        'https://github.com/o/Some.Weird_Name.git',
        'o/${'z' * 80}',
        'o/a--b__c',
      ];
      for (final r in repos) {
        final s = suggestShedName(r);
        if (s.isNotEmpty) {
          expect(validateShedName(s), isNull, reason: 'suggest($r)=$s invalid');
        }
      }
    });
  });

  group('validatePositiveIntField', () {
    test('empty is valid (use server default)', () {
      expect(validatePositiveIntField(''), isNull);
      expect(validatePositiveIntField('  '), isNull);
    });
    test('positive integers are valid', () {
      expect(validatePositiveIntField('1'), isNull);
      expect(validatePositiveIntField('4'), isNull);
      expect(validatePositiveIntField(' 8192 '), isNull);
    });
    test('zero, negatives, and non-integers are rejected', () {
      expect(validatePositiveIntField('0'), isNotNull);
      expect(validatePositiveIntField('-2'), isNotNull);
      expect(validatePositiveIntField('4x'), isNotNull);
      expect(validatePositiveIntField('1.5'), isNotNull);
    });
  });

  // NOTE (B3 FRB swap): the former `CreateShedRequest.fromForm` shaping tests
  // were removed with `shed_dtos.dart`. The create request is now built inline in
  // `create_shed_screen._create()` as a `BridgeCreateShedRequest` (blank/zero
  // omission via `_blank`/`parsePositiveInt`); the field-omission shaping is
  // exercised by driving the create flow. `parsePositiveInt` itself is covered by
  // the `validatePositiveIntField` group above (they share the one rule).
}

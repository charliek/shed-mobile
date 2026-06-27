import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/shell_quote.dart';

void main() {
  group('shellQuote', () {
    test('passes through bare-safe tokens', () {
      expect(shellQuote('abc'), 'abc');
      expect(shellQuote('a/b_c.d-e'), 'a/b_c.d-e');
      expect(shellQuote('rc-abc123'), 'rc-abc123');
    });

    test('empty string becomes an explicit empty arg', () {
      expect(shellQuote(''), "''");
    });

    test('quotes spaces and shell metacharacters', () {
      expect(shellQuote('a b'), "'a b'");
      expect(shellQuote(r'$HOME'), r"'$HOME'");
      expect(shellQuote('a*b?c'), "'a*b?c'");
      expect(shellQuote('a;b'), "'a;b'");
    });

    test('escapes embedded single quotes', () {
      expect(shellQuote("it's"), "'it'\\''s'");
    });

    test('wireCmd quotes each token and joins with spaces', () {
      expect(
        wireCmd(['tmux', 'attach', '-t', 'rc-x y']),
        "tmux attach -t 'rc-x y'",
      );
      expect(wireCmd(['control', 'shed-mobile']), 'control shed-mobile');
    });
  });
}

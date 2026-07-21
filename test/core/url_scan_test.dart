import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/url_scan.dart';

void main() {
  group('latestUrlIn', () {
    test('plain http(s) URLs are found', () {
      expect(
        latestUrlIn('go to https://claude.ai/login now'),
        'https://claude.ai/login',
      );
      expect(latestUrlIn('http://example.com/x'), 'http://example.com/x');
    });

    test('no URL -> null; non-http(s) schemes are rejected', () {
      expect(latestUrlIn('nothing to see here'), isNull);
      expect(latestUrlIn(''), isNull);
      for (final s in const [
        'ftp://host/file',
        'file:///etc/passwd',
        'mailto:a@b.com',
        'javascript:alert(1)',
        'ssh://host',
      ]) {
        expect(latestUrlIn('open $s please'), isNull, reason: s);
      }
    });

    test(
      'several URLs -> the LAST one wins (newest is what the user sees)',
      () {
        expect(
          latestUrlIn('a https://one.example/x b https://two.example/y c'),
          'https://two.example/y',
        );
      },
    );

    test(
      'a duplicate re-emit yields the same result (caller de-dups on equality)',
      () {
        const text = 'login at https://claude.ai/auth/tok';
        final a = latestUrlIn(text);
        final b = latestUrlIn(text);
        expect(a, 'https://claude.ai/auth/tok');
        expect(b, equals(a));
      },
    );

    test(
      'chunk accumulation: a URL split across two appended writes is found whole',
      () {
        var tail = '';
        tail = appendBoundedTail(tail, 'visit https://claude.ai/log');
        // Mid-URL: nothing complete has arrived past the split point yet, but the
        // prefix is a valid (shorter) URL — that's fine; the point is the join.
        tail = appendBoundedTail(tail, 'in/abc123?tok=xyz');
        expect(latestUrlIn(tail), 'https://claude.ai/login/abc123?tok=xyz');
      },
    );

    group('terminal escape stripping', () {
      test('CSI (SGR colour) codes flush against the URL are stripped', () {
        // ESC[32m … ESC[0m wrapping the link, plus a cursor move mid-string.
        const text = '\x1B[32mhttps://ex.example/path\x1B[0m done';
        expect(latestUrlIn(text), 'https://ex.example/path');
      });

      test('an OSC title-set sequence adjacent to the URL is stripped', () {
        // ESC]0;window title BEL immediately before the URL.
        const text = '\x1B]0;my terminal\x07https://ex.example/y';
        expect(latestUrlIn(text), 'https://ex.example/y');
        // OSC terminated by ST (ESC \) instead of BEL.
        const text2 = '\x1B]0;t\x1B\\https://ex.example/z';
        expect(latestUrlIn(text2), 'https://ex.example/z');
      });

      test(
        'stray C0 control bytes (non-whitespace) are stripped, whitespace still delimits',
        () {
          // A NUL and a bell wedged in are removed; the trailing space still ends it.
          expect(
            latestUrlIn('\x00\x07https://ex.example/w rest'),
            'https://ex.example/w',
          );
        },
      );
    });

    group('URL shape: query / fragment / port / IPv6 preserved', () {
      test('query string + fragment kept', () {
        expect(
          latestUrlIn('open https://ex.example/p?a=b&c=d#frag here'),
          'https://ex.example/p?a=b&c=d#frag',
        );
      });

      test('explicit port kept', () {
        expect(
          latestUrlIn('https://ex.example:8443/login'),
          'https://ex.example:8443/login',
        );
      });

      test('bracketed IPv6 host (with port, path, query, fragment) kept', () {
        expect(
          latestUrlIn('https://[2001:db8::1]:8080/x?a=b#f'),
          'https://[2001:db8::1]:8080/x?a=b#f',
        );
      });

      test(
        'a bare IPv6 host keeps its closing bracket (balanced -> not trimmed)',
        () {
          expect(latestUrlIn('go https://[::1]'), 'https://[::1]');
        },
      );
    });

    group('trailing punctuation trimming', () {
      test('a trailing period / comma / semicolon is trimmed', () {
        expect(
          latestUrlIn('see https://ex.example/a.'),
          'https://ex.example/a',
        );
        expect(
          latestUrlIn('see https://ex.example/a,'),
          'https://ex.example/a',
        );
        expect(
          latestUrlIn('see https://ex.example/a;'),
          'https://ex.example/a',
        );
      });

      test('a trailing close-paren hugging the link is trimmed', () {
        expect(
          latestUrlIn('(see https://ex.example/a)'),
          'https://ex.example/a',
        );
      });

      test('a balanced close-paren inside the path is kept', () {
        expect(
          latestUrlIn('https://ex.example/wiki/Foo_(bar) done'),
          'https://ex.example/wiki/Foo_(bar)',
        );
      });

      test(
        'trailing punctuation is trimmed but a real query/fragment is kept',
        () {
          // ".", ")", "," at the very end go; "?a=b#frag" (mid-string) stays.
          expect(
            latestUrlIn('link: https://ex.example/p?a=b#frag).'),
            'https://ex.example/p?a=b#frag',
          );
        },
      );
    });

    group('bounded rolling tail (appendBoundedTail)', () {
      test('short output accumulates verbatim', () {
        final t = appendBoundedTail('', 'hello ');
        expect(appendBoundedTail(t, 'world'), 'hello world');
      });

      test('a URL older than the ~4 KB window falls out of detection', () {
        var tail = '';
        tail = appendBoundedTail(tail, 'https://old.example/should-fall-out ');
        // Push far more than the window of unrelated bytes through.
        tail = appendBoundedTail(tail, 'x' * 5000);
        tail = appendBoundedTail(tail, ' https://new.example/kept');
        expect(tail.length, lessThanOrEqualTo(4096));
        expect(latestUrlIn(tail), 'https://new.example/kept');
        // The old URL is gone entirely (not merely out-ranked).
        expect(latestUrlIn(tail), isNot(contains('old')));
      });

      test('a custom window size truncates to the last maxChars', () {
        final t = appendBoundedTail('abcdef', 'ghij', maxChars: 4);
        expect(t, 'ghij');
      });
    });
  });
}

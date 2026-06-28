import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/pty_session.dart';

void main() {
  group('clampPtyDim', () {
    test('clamps to [1, 1000]', () {
      expect(clampPtyDim(0), 1);
      expect(clampPtyDim(-5), 1);
      expect(clampPtyDim(1), 1);
      expect(clampPtyDim(80), 80);
      expect(clampPtyDim(1000), 1000);
      expect(clampPtyDim(1001), 1000);
      expect(clampPtyDim(99999), 1000);
    });
  });

  group('rcAttachCommand', () {
    test('attaches to rc-<slug> (bare-safe slug needs no quoting)', () {
      expect(rcAttachCommand('abc234'), 'tmux attach -t rc-abc234');
    });

    test('POSIX-quotes a slug that contains shell metacharacters', () {
      // Slugs are generated from a safe alphabet, but the command must still be
      // injection-safe for any caller-supplied value.
      expect(rcAttachCommand('x; rm -rf /'), "tmux attach -t 'rc-x; rm -rf /'");
    });
  });

  group('rcSlugFromTmux', () {
    test('recovers the slug from an rc-<slug> tmux name', () {
      expect(rcSlugFromTmux('rc-baxjjh'), 'baxjjh');
    });

    test('round-trips the rc-<slug> convention rcAttachCommand relies on', () {
      // `GET /api/sessions` returns the tmux `name`; opening a terminal must
      // recover the exact slug rcAttachCommand re-prefixes.
      const slug = 'abc234';
      expect(rcSlugFromTmux('rc-$slug'), slug);
    });

    test('passes a non rc- prefixed name through (foreign/legacy session)', () {
      expect(rcSlugFromTmux('mysession'), 'mysession');
    });

    test('a bare "rc-" yields empty (caller treats as not-openable)', () {
      expect(rcSlugFromTmux('rc-'), '');
    });
  });
}

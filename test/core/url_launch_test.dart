import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/url_launch.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test(
    'valid https URL → launcher called with external mode, returns success',
    () async {
      Uri? seenUri;
      LaunchMode? seenMode;
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) {
        seenUri = url;
        seenMode = mode;
        return Future.value(true);
      }

      final outcome = await launchExternalUrl(
        'https://claude.ai/login/abc?x=1#frag',
        launcher: fake,
      );

      expect(outcome, UrlLaunchOutcome.success);
      expect(seenUri, Uri.parse('https://claude.ai/login/abc?x=1#frag'));
      // The helper always requests an external application, never an in-app view.
      expect(seenMode, LaunchMode.externalApplication);
    },
  );

  test('http scheme is accepted too', () async {
    var called = false;
    Future<bool> fake(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) {
      called = true;
      return Future.value(true);
    }

    expect(
      await launchExternalUrl('http://example.com/x', launcher: fake),
      UrlLaunchOutcome.success,
    );
    expect(called, isTrue);
  });

  test('non-http(s) scheme → rejected, launcher NOT called', () async {
    var called = false;
    Future<bool> fake(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) {
      called = true;
      return Future.value(true);
    }

    for (final bad in const [
      'mailto:someone@example.com',
      'ftp://host/file',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'about:blank',
    ]) {
      expect(
        await launchExternalUrl(bad, launcher: fake),
        UrlLaunchOutcome.rejected,
        reason: bad,
      );
    }
    expect(called, isFalse);
  });

  test(
    'scheme-less / malformed string → rejected, launcher NOT called',
    () async {
      var called = false;
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) {
        called = true;
        return Future.value(true);
      }

      // No scheme at all, and an unterminated IPv6 host that Uri.tryParse rejects.
      expect(
        await launchExternalUrl('not a url', launcher: fake),
        UrlLaunchOutcome.rejected,
      );
      expect(
        await launchExternalUrl('http://[', launcher: fake),
        UrlLaunchOutcome.rejected,
      );
      expect(called, isFalse);
    },
  );

  test('launcher returns false → failed', () async {
    Future<bool> fake(
      Uri url, {
      LaunchMode mode = LaunchMode.platformDefault,
    }) => Future.value(false);

    expect(
      await launchExternalUrl('https://claude.ai', launcher: fake),
      UrlLaunchOutcome.failed,
    );
  });

  test(
    'launcher throws → failed (exception swallowed, not rethrown)',
    () async {
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) {
        throw Exception('no browser installed');
      }

      // Must not throw out of the helper.
      expect(
        await launchExternalUrl('https://claude.ai', launcher: fake),
        UrlLaunchOutcome.failed,
      );
    },
  );
}

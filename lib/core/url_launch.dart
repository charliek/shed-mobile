import 'package:url_launcher/url_launcher.dart';

/// The signature of the platform URL opener — [launchUrl]'s shape, narrowed to
/// the two arguments this helper passes. Injecting a fake of this in a test lets
/// [launchExternalUrl] be exercised without touching the real platform channel.
typedef UrlLauncher = Future<bool> Function(Uri url, {LaunchMode mode});

/// How a [launchExternalUrl] attempt resolved, so a caller can pick the right
/// user feedback:
/// * [success] — the OS accepted the URL and reported it opened.
/// * [failed]  — the URL was well-formed and handed to the OS, but the launch
///   was declined (returned `false`) or threw a platform error.
/// * [rejected] — the string didn't parse, or its scheme isn't http/https, so
///   nothing was ever handed to the OS (never launch an arbitrary scheme).
enum UrlLaunchOutcome { success, failed, rejected }

/// Safely open [url] in an external application.
///
/// Parses [url], rejects anything that isn't an `http`/`https` URL (so a
/// malformed or non-web scheme can't reach the platform launcher), then hands it
/// to [launcher] (defaulting to url_launcher's [launchUrl] with
/// [LaunchMode.externalApplication]). A launcher that returns `false` or throws
/// a platform exception is reported as [UrlLaunchOutcome.failed] rather than
/// propagating — the caller decides how to surface it (typically a snackbar).
///
/// [launcher] is the test seam: pass a fake to assert the exact [Uri] handed to
/// the platform and to simulate success / false / throw without a real channel.
Future<UrlLaunchOutcome> launchExternalUrl(
  String url, {
  UrlLauncher? launcher,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return UrlLaunchOutcome.rejected;
  }
  final UrlLauncher launch = launcher ?? launchUrl;
  try {
    final ok = await launch(uri, mode: LaunchMode.externalApplication);
    return ok ? UrlLaunchOutcome.success : UrlLaunchOutcome.failed;
  } catch (_) {
    // Swallow platform exceptions (e.g. no handler / ActivityNotFoundException):
    // a caller wants a "couldn't open" snackbar, not a crash.
    return UrlLaunchOutcome.failed;
  }
}

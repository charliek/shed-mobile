/// Max shed-name length (mirrors the server).
const int kMaxShedNameLength = 63;

// Shed-name grammar, ported from the server (shed/internal/config/types.go):
// `^[a-z][a-z0-9-]*[a-z0-9]$ | ^[a-z]$` — a DNS-label-ish name: lowercase
// letters/digits/hyphens, must start with a letter and not end with a hyphen.
final RegExp _shedNameRe = RegExp(r'^[a-z]([a-z0-9-]*[a-z0-9])?$');

/// Validate a shed name client-side so a bad name fails fast in the UI instead
/// of as a mid-create server error. Returns null when valid, else a short
/// human-readable reason.
String? validateShedName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Name is required';
  if (n.length > kMaxShedNameLength) {
    return 'Name must be at most $kMaxShedNameLength characters';
  }
  if (!_shedNameRe.hasMatch(n)) {
    return 'Use lowercase letters, digits and hyphens; start with a letter, '
        'no trailing hyphen';
  }
  return null;
}

/// Suggest a valid shed name from a repo reference (`owner/repo`, a full
/// https/ssh URL, or a path). Takes the last path segment, strips a trailing
/// `.git`, lowercases, replaces invalid runs with `-`, drops leading
/// non-letters, collapses/trims hyphens, and truncates to [kMaxShedNameLength].
/// Returns '' when nothing valid remains (e.g. an all-digit repo like `2048`),
/// so the caller leaves the field for the user to fill. The result is always
/// either empty or a value that passes [validateShedName].
String suggestShedName(String repo) {
  var s = repo.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(RegExp(r'[?#].*$'), ''); // drop query/fragment
  s = s.replaceAll(RegExp(r'/+$'), ''); // drop trailing slashes
  final segments = s.split(RegExp(r'[/:]')).where((p) => p.isNotEmpty).toList();
  if (segments.isEmpty) return '';
  var name = segments.last;
  if (name.toLowerCase().endsWith('.git')) {
    name = name.substring(0, name.length - 4);
  }
  name = name.toLowerCase();
  name = name.replaceAll(RegExp(r'[^a-z0-9-]+'), '-'); // invalid runs -> '-'
  name = name.replaceAll(RegExp(r'-{2,}'), '-'); // collapse repeats
  name = name.replaceAll(RegExp(r'^[^a-z]+'), ''); // must start with a letter
  name = name.replaceAll(RegExp(r'-+$'), ''); // no trailing hyphen
  if (name.length > kMaxShedNameLength) {
    name = name.substring(0, kMaxShedNameLength);
    name = name.replaceAll(RegExp(r'-+$'), '');
  }
  return name;
}

import '../src/rust/api/dto.dart';

/// Pure UI formatters relocated from the deleted `shed_dtos.dart` (B3 FRB swap).
/// These take primitive fields (or the bridge `BridgeShed`), so they stay pure
/// and unit-testable, decoupled from transport.

/// Human-readable bytes (binary units), e.g. `1610612736 → "1.5 GB"`. Zero renders
/// as "Zero KB" to match the design's empty label. Pure.
String formatBytes(int bytes) {
  if (bytes <= 0) return 'Zero KB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  // Two fixed decimals, then trim trailing zeros (and a dangling dot) without a
  // per-call regex: "1.50" → "1.5", "1.00" → "1", "13.51" → "13.51".
  final s = size.toStringAsFixed(2);
  var end = s.length;
  while (s[end - 1] == '0') {
    end--;
  }
  if (s[end - 1] == '.') end--;
  return '${s.substring(0, end)} ${units[i]}';
}

/// Parse a server RFC3339 timestamp, returning null for an empty/invalid value or
/// the Go zero value `0001-01-01T00:00:00Z` (which `GET /api/sessions` frequently
/// reports for `created_at`).
DateTime? parseServerTime(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final t = DateTime.tryParse(v);
  if (t == null || t.year <= 1) return null;
  return t;
}

/// Compact relative age ("2d"/"3h"/"30m"/"0m") since a timestamp; null when the
/// timestamp is null or in the future (clock skew). Pure.
String? _compactAge(DateTime? t, {DateTime? now}) {
  if (t == null) return null;
  final d = (now ?? DateTime.now()).difference(t);
  if (d.isNegative) return null;
  if (d.inDays > 0) return '${d.inDays}d';
  if (d.inHours > 0) return '${d.inHours}h';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '0m';
}

/// "up Nd"/"up Nh"/"up Nm" from a VM start time; null when unknown. Pure.
String? uptimeLabel(DateTime? startedAt, {DateTime? now}) {
  final a = _compactAge(startedAt, now: now);
  return a == null ? null : 'up $a';
}

/// Compact relative age for a "made … ago" line; null when unknown. Pure.
String? ageLabel(DateTime? t, {DateTime? now}) => _compactAge(t, now: now);

String _memLabel(int mb) => mb % 1024 == 0 ? '${mb ~/ 1024} GB' : '$mb MB';

/// The cross-host shed card's mono meta line — `repo · N vCPU · mem · up Nh`,
/// dropping any absent part. Pure (pass [now] in tests).
String shedMetaLine(BridgeShed s, {DateTime? now}) => [
  ?_nonEmpty(s.repo),
  if (s.cpus != null) '${s.cpus} vCPU',
  if (s.memoryMb != null) _memLabel(s.memoryMb!),
  ?uptimeLabel(parseServerTime(s.startedAt), now: now),
].join(' · ');

/// The cross-host session card's mono meta line — `shed · tmux rc-… · made N ago`,
/// dropping the age for a missing/zero/unparseable created_at. Pure.
String sessionMetaLine(
  String shedName,
  String tmuxSession,
  String? createdAtIso, {
  DateTime? now,
}) {
  final age = ageLabel(parseServerTime(createdAtIso), now: now);
  return [
    shedName,
    'tmux $tmuxSession',
    if (age != null) 'made $age ago',
  ].join(' · ');
}

/// Parse an optional positive-integer create-shed field (cpus, memory_mb).
/// Returns the value when it's a positive whole number, else null.
int? parsePositiveInt(String s) {
  final v = int.tryParse(s.trim());
  return (v == null || v <= 0) ? null : v;
}

/// Validate an optional positive-integer create-shed field for the UI. Returns
/// null when valid (empty means "use the server default"), else a short message.
String? validatePositiveIntField(String s) {
  if (s.trim().isEmpty) return null;
  return parsePositiveInt(s) == null ? 'Must be a positive whole number' : null;
}

String? _nonEmpty(String? v) =>
    (v != null && v.trim().isNotEmpty) ? v.trim() : null;

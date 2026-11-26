import '../src/rust/api/dto.dart';

/// A cloud shed's row facts (plan 041), mirroring the desktop's `CloudRow`
/// rules: the badge, the size words, the lease words and state, and which
/// actions a cloud shed offers. Pure: every function takes its `now`.

/// The tag a cloud shed wears.
const cloudBadgeLabel = 'Cloud';

/// Where a cloud shed's lease stands at `now`.
enum LeaseState {
  /// More than its warning time left.
  ok,

  /// Within its warning time of the end (shown amber).
  soon,

  /// At or past its end: the machine is being deleted (shown red).
  ended,

  /// Not known: the service has not answered yet, or its time does not parse.
  unknown,
}

/// `2 vCPU · 8 GB` (`1.5 GB` for a part gigabyte); the size's name when it says
/// neither; "" when nothing.
String cloudSizeWords(BridgeShedCloud c) {
  final parts = <String>[
    if (c.cpus > 0) '${c.cpus} vCPU',
    if (c.memoryMb > 0)
      c.memoryMb % 1024 == 0
          ? '${c.memoryMb ~/ 1024} GB'
          : '${(c.memoryMb / 1024).toStringAsFixed(1)} GB',
  ];
  return parts.isEmpty ? c.sizeName : parts.join(' · ');
}

/// A span as the lease words say it: `1d 2h`, `1h 20m`, `20m` (minutes rounded
/// down, never negative) — the server's `FormatLeft`.
String formatLeft(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  final days = s ~/ 86400, hours = s ~/ 3600 % 24, minutes = s ~/ 60 % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// The lease's state and words at [now]: `deleted in 5h 10m`, `lease ended`, or
/// `lease unknown`.
({LeaseState state, String words}) cloudLease(BridgeShedCloud c, DateTime now) {
  final end = c.lease?.expiresAtMs;
  if (c.lease == null || end == null) {
    return (state: LeaseState.unknown, words: 'lease unknown');
  }
  final left = Duration(milliseconds: end - now.millisecondsSinceEpoch);
  if (left <= Duration.zero) {
    return (state: LeaseState.ended, words: 'lease ended');
  }
  final warn = c.lease!.warnS;
  final soon = warn > 0 && left.inSeconds < warn;
  return (
    state: soon ? LeaseState.soon : LeaseState.ok,
    words: 'deleted in ${formatLeft(left)}',
  );
}

/// Which actions a cloud shed offers at [now]. Restart is never one.
typedef CloudActions = ({bool start, bool stop, bool delete, bool extend});

CloudActions cloudActions(BridgeShed s, BridgeShedCloud c, DateTime now) {
  final ended = cloudLease(c, now).state == LeaseState.ended;
  final running = s.status == BridgeShedStatus.running;
  final busy =
      s.status == BridgeShedStatus.starting ||
      s.status == BridgeShedStatus.stopping;
  final settled = running || s.status == BridgeShedStatus.stopped;
  final lease = c.lease;
  return (
    start: s.status == BridgeShedStatus.stopped && !ended,
    stop: running && !ended,
    delete: !running && !busy,
    // The server says it may be extended and there is an hour to the cap
    // (`extendMaxH`), the lease has not ended, and no earlier extend's outcome
    // is still unknown.
    extend:
        settled &&
        !ended &&
        lease != null &&
        lease.extendMaxH > 0 &&
        s.extendUnknownHours == null,
  );
}

/// The line a cloud shed shows while an extend of [hours] has an unknown
/// outcome.
String unresolvedExtendWords(int hours) =>
    'An extend by $hours h: not known whether it was applied; '
    'Extend stays unavailable until that is known';

/// The usage line under a server's heading:
/// `2 of 4 machines (1 running, 1 stopped) · organization 7 of 10`, or
/// `organization 7 of 10` for a caller who is not a person of the service.
String cloudUsageWords(BridgeCloudUsage u) {
  final org = 'organization ${u.org.machines} of ${u.org.max}';
  final p = u.person;
  if (p == null) return org;
  return '${p.machines} of ${p.max} machines '
      '(${p.running} running, ${p.stopped} stopped) · $org';
}

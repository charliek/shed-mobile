import '../rc/rc_capabilities.dart';
import '../rc/rc_models.dart';

/// A shed as returned by the shed-server HTTP API. Tolerant: name + status +
/// the raw map, with a few common typed fields surfaced for the UI.
class Shed {
  const Shed({
    required this.name,
    required this.status,
    this.backend,
    this.image,
    this.repo,
    this.cpus,
    this.memoryMb,
    this.startedAt,
    this.raw = const {},
  });

  final String name;
  final String status;
  final String? backend; // "vz" | "firecracker"
  final String? image; // image variant the shed was created from
  final String? repo; // source repo (e.g. github.com:owner/name)
  final int? cpus; // vCPUs, when reported
  final int? memoryMb; // memory in MiB, when reported
  final DateTime? startedAt; // VM boot time (VM backends only) for uptime
  final Map<String, Object?> raw;

  bool get isRunning => status == 'running';

  factory Shed.fromJson(Map<String, Object?> j) => Shed(
    name: _nonEmpty(j['name']) ?? '?',
    status: _nonEmpty(j['status']) ?? 'unknown',
    backend: _nonEmpty(j['backend']),
    image: _nonEmpty(j['image']),
    repo: _nonEmpty(j['repo']),
    cpus: _posIntOrNull(j['cpus']),
    memoryMb: _posIntOrNull(j['memory_mb']),
    startedAt: _parseServerTime(j['started_at']),
    raw: j,
  );
}

/// The cross-host shed card's mono meta line — `repo · N vCPU · mem · up Nh`,
/// dropping any absent part. Pure (pass [now] in tests). Mirrors the design's
/// `meta:[s.repo, s.vcpu+' vCPU', s.mem, s.uptime].filter(Boolean).join(' · ')`.
String shedMetaLine(Shed s, {DateTime? now}) => [
  // `repo` is parsed via _nonEmpty, so it's already null-or-non-blank.
  ?s.repo,
  if (s.cpus != null) '${s.cpus} vCPU',
  if (s.memoryMb != null) _memLabel(s.memoryMb!),
  ?uptimeLabel(s.startedAt, now: now),
].join(' · ');

/// Compact relative age ("2d"/"3h"/"30m"/"0m") since a timestamp; null when the
/// timestamp is null or in the future (clock skew). The shared core of
/// [uptimeLabel] and [ageLabel]. Pure.
String? _compactAge(DateTime? t, {DateTime? now}) {
  if (t == null) return null;
  final d = (now ?? DateTime.now()).difference(t);
  if (d.isNegative) return null;
  if (d.inDays > 0) return '${d.inDays}d';
  if (d.inHours > 0) return '${d.inHours}h';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '0m';
}

/// "up Nd"/"up Nh"/"up Nm" from a VM start time; null when unknown (stopped sheds,
/// firecracker without a boot heartbeat, or a future timestamp). Pure.
String? uptimeLabel(DateTime? startedAt, {DateTime? now}) {
  final a = _compactAge(startedAt, now: now);
  return a == null ? null : 'up $a';
}

/// Compact relative age for a "made … ago" line; null when unknown. Pure.
String? ageLabel(DateTime? t, {DateTime? now}) => _compactAge(t, now: now);

String _memLabel(int mb) => mb % 1024 == 0 ? '${mb ~/ 1024} GB' : '$mb MB';

/// The cross-host session card's mono meta line — `shed · tmux rc-… · made N ago`,
/// dropping the age for a missing/zero/unparseable created_at. Pure; takes plain
/// fields (the rc DTO's createdAt is an ISO string) so it stays decoupled.
String sessionMetaLine(
  String shedName,
  String tmuxSession,
  String? createdAtIso, {
  DateTime? now,
}) {
  final age = ageLabel(_parseServerTime(createdAtIso), now: now);
  return [
    shedName,
    'tmux $tmuxSession',
    if (age != null) 'made $age ago',
  ].join(' · ');
}

/// A tmux session inside a shed (`GET /api/sheds/:name/sessions`).
class Session {
  const Session({required this.name, this.isRemoteControl = false});
  final String name;
  final bool isRemoteControl;

  factory Session.fromJson(Map<String, Object?> j) => Session(
    name: (j['name'] as String?) ?? (j['session'] as String?) ?? '?',
    isRemoteControl: j['is_remote_control'] == true,
  );
}

/// An image variant available on a shed host (`GET /api/images`).
class ImageInfo {
  const ImageInfo({required this.name});
  final String name;

  factory ImageInfo.fromJson(Map<String, Object?> j) => ImageInfo(
    name: (j['name'] as String?) ?? (j['variant'] as String?) ?? '?',
  );
}

/// Parse an optional positive-integer create-shed field (cpus, memory_mb).
/// Returns the value when it's a positive whole number, else null. The single
/// rule shared by [CreateShedRequest.fromForm] (which omits the field) and
/// [validatePositiveIntField] (which surfaces a UI message) so they can't drift.
int? parsePositiveInt(String s) {
  final v = int.tryParse(s.trim());
  return (v == null || v <= 0) ? null : v;
}

/// Validate an optional positive-integer create-shed field for the UI. Returns
/// null when valid — empty means "use the server default", otherwise it must be a
/// positive whole number — else a short message. Lets a bad value fail in the UI
/// instead of being silently dropped by [CreateShedRequest.fromForm].
String? validatePositiveIntField(String s) {
  if (s.trim().isEmpty) return null;
  return parsePositiveInt(s) == null ? 'Must be a positive whole number' : null;
}

/// Request body for `POST /api/sheds`. `repo` and `localDir` are exclusive.
class CreateShedRequest {
  const CreateShedRequest({
    required this.name,
    this.repo,
    this.localDir,
    this.image,
    this.backend,
    this.cpus,
    this.memoryMb,
    this.noProvision,
  });

  /// Build from raw create-shed form fields, omitting blanks/zeros. Pure, so the
  /// "empty/zero -> omitted" shaping is unit-tested. The image/numeric/no_provision
  /// fields are wired by the create-shed Advanced section (Phase 2).
  factory CreateShedRequest.fromForm({
    required String name,
    String repo = '',
    String image = '',
    String cpus = '',
    String memoryMb = '',
    bool noProvision = false,
  }) {
    String? str(String s) => s.trim().isEmpty ? null : s.trim();

    return CreateShedRequest(
      name: name.trim(),
      repo: str(repo),
      image: str(image),
      cpus: parsePositiveInt(cpus),
      memoryMb: parsePositiveInt(memoryMb),
      noProvision: noProvision ? true : null,
    );
  }

  final String name;
  final String? repo;
  final String? localDir;
  final String? image;
  final String? backend;
  final int? cpus;
  final int? memoryMb;
  final bool? noProvision;

  Map<String, Object?> toJson() => {
    'name': name,
    if (repo != null) 'repo': repo,
    if (localDir != null) 'local_dir': localDir,
    if (image != null) 'image': image,
    if (backend != null) 'backend': backend,
    if (cpus != null) 'cpus': cpus,
    if (memoryMb != null) 'memory_mb': memoryMb,
    if (noProvision != null) 'no_provision': noProvision,
  };
}

/// One event from the create-shed SSE stream.
sealed class ShedCreateEvent {
  const ShedCreateEvent();
}

class ShedProgress extends ShedCreateEvent {
  const ShedProgress(this.phase, this.message);
  final String phase;
  final String message;
}

class ShedComplete extends ShedCreateEvent {
  const ShedComplete(this.shed);
  final Shed shed;
}

class ShedCreateError extends ShedCreateEvent {
  const ShedCreateError(this.code, this.message);
  final String code;
  final String message;
}

// ---- GET /api/overview single-call host snapshot --------------------------

/// The `server` block of GET /api/overview: the server's version and the
/// feature-token set (mirrored from GET /api/info). A client learns which
/// endpoints/behaviors a server supports from [features] without probing each.
class OverviewServer {
  const OverviewServer({required this.version, required this.features});
  final String version;
  final List<String> features;

  bool hasFeature(String feature) => features.contains(feature);

  factory OverviewServer.fromJson(Map<String, Object?>? j) {
    final raw = j?['features'];
    return OverviewServer(
      version: _nonEmpty(j?['version']) ?? '',
      features: <String>[
        if (raw is List)
          for (final f in raw)
            if (f is String) f,
      ],
    );
  }
}

/// One shed in GET /api/overview: the full shed record plus the shed's RC
/// sessions (only the rc-enriched tmux rows are surfaced) and, for a running
/// shed, its rc capabilities. A stopped shed carries no sessions and omits
/// capabilities ([capabilities] == null), which the create form treats as
/// "absent" (fall back to claude + shell).
class OverviewShed {
  const OverviewShed({
    required this.shed,
    required this.sessions,
    this.capabilities,
  });

  final Shed shed;
  final List<RcSession> sessions;
  final RcCapabilities? capabilities;

  factory OverviewShed.fromJson(Map<String, Object?> j) {
    final shed = Shed.fromJson(j);
    final rawSessions = j['sessions'];
    final sessions = <RcSession>[];
    if (rawSessions is List) {
      for (final e in rawSessions) {
        if (e is! Map<String, Object?>) continue;
        final rc = e['rc'];
        // Only rc-enriched tmux rows carry an `rc` block; a plain tmux session
        // (or an un-enriched rc-* row on a degraded shed) has none — skip it, so
        // the Sessions view lists exactly the RC sessions (parity with the old
        // `shed-ext-rc list` fan-out).
        if (rc is! Map<String, Object?>) continue;
        final name = _nonEmpty(e['name']) ?? '';
        final slug = name.startsWith('rc-') ? name.substring(3) : name;
        // The server's SessionRC is a display subset (no slug/tmux/id); derive
        // slug + tmux from the session name and pull created_at from the outer
        // row, then reuse the neutral-DTO decoder.
        sessions.add(
          RcSession.fromJson(<String, Object?>{
            'slug': slug,
            'tmux_session': name,
            'created_at': e['created_at'],
            ...rc,
          }, displayNameFallback: (s) => '${shed.name}/$s'),
        );
      }
    }
    final caps = j['rc_capabilities'];
    return OverviewShed(
      shed: shed,
      sessions: sessions,
      capabilities: caps is Map<String, Object?>
          ? RcCapabilities.fromJson(caps)
          : null,
    );
  }
}

/// GET /api/overview — a single call a client renders a whole host from: server
/// identity + feature set, disk usage, and every shed with its (rc-enriched)
/// sessions and capabilities. Each sub-block degrades independently into
/// [warnings] server-side, so a null [df] or an empty session list is a
/// tolerated partial, not a failure.
class Overview {
  const Overview({
    required this.server,
    this.df,
    required this.sheds,
    required this.warnings,
  });

  final OverviewServer server;
  final SystemDiskUsage? df;
  final List<OverviewShed> sheds;
  final List<String> warnings;

  factory Overview.fromJson(Map<String, Object?> j) {
    final rawSheds = j['sheds'];
    final df = j['df'];
    final warns = j['warnings'];
    return Overview(
      server: OverviewServer.fromJson(_map(j['server'])),
      df: df is Map<String, Object?> ? SystemDiskUsage.fromJson(df) : null,
      sheds: <OverviewShed>[
        if (rawSheds is List)
          for (final s in rawSheds)
            if (s is Map<String, Object?>) OverviewShed.fromJson(s),
      ],
      warnings: <String>[
        if (warns is List)
          for (final w in warns)
            if (w is String) w,
      ],
    );
  }
}

// ---- System / disk usage (`GET /api/system/df`) ---------------------------

/// A logical+physical byte pair (`{logical_bytes, physical_bytes}`). Physical is
/// the actual on-disk footprint (CoW/dedup makes it diverge from logical); the
/// System view renders physical.
class DiskSize {
  const DiskSize({this.logicalBytes = 0, this.physicalBytes = 0});
  final int logicalBytes;
  final int physicalBytes;

  factory DiskSize.fromJson(Map<String, Object?>? j) => DiskSize(
    logicalBytes: _asInt(j?['logical_bytes']),
    physicalBytes: _asInt(j?['physical_bytes']),
  );
}

/// Per-category disk totals (`df.totals`): the four buckets plus their sum.
class DiskTotals {
  const DiskTotals({
    this.images = const DiskSize(),
    this.sheds = const DiskSize(),
    this.snapshots = const DiskSize(),
    this.orphans = const DiskSize(),
    this.all = const DiskSize(),
  });

  final DiskSize images;
  final DiskSize sheds;
  final DiskSize snapshots;
  final DiskSize orphans;
  final DiskSize all;

  factory DiskTotals.fromJson(Map<String, Object?>? j) => DiskTotals(
    images: DiskSize.fromJson(_map(j?['images'])),
    sheds: DiskSize.fromJson(_map(j?['sheds'])),
    snapshots: DiskSize.fromJson(_map(j?['snapshots'])),
    orphans: DiskSize.fromJson(_map(j?['orphans'])),
    all: DiskSize.fromJson(_map(j?['all'])),
  );
}

/// One host's disk usage (`GET /api/system/df`). Tolerant: a missing `totals`
/// (or an old agent that 404s, surfaced as an error upstream) yields zeros.
class SystemDiskUsage {
  const SystemDiskUsage({
    required this.serverName,
    this.backend,
    this.totals = const DiskTotals(),
  });

  final String serverName;
  final String? backend; // "vz" | "firecracker" | "none"
  final DiskTotals totals;

  factory SystemDiskUsage.fromJson(Map<String, Object?> j) => SystemDiskUsage(
    serverName: _nonEmpty(j['server_name']) ?? '?',
    backend: _nonEmpty(j['backend']),
    totals: DiskTotals.fromJson(_map(j['totals'])),
  );
}

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
  // per-call regex — this renders on the System view's refresh path:
  // "1.50" → "1.5", "1.00" → "1", "13.51" → "13.51".
  final s = size.toStringAsFixed(2);
  var end = s.length;
  while (s[end - 1] == '0') {
    end--;
  }
  if (s[end - 1] == '.') end--;
  return '${s.substring(0, end)} ${units[i]}';
}

// ---- shared tolerant parsing helpers --------------------------------------

String? _nonEmpty(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

int _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

int? _posIntOrNull(Object? v) {
  final n = _asInt(v);
  return n > 0 ? n : null;
}

Map<String, Object?>? _map(Object? v) => v is Map<String, Object?> ? v : null;

/// Parse a server RFC3339 timestamp, returning null for an empty/invalid value or
/// the Go zero value `0001-01-01T00:00:00Z` (which `GET /api/sessions` frequently
/// reports for `created_at`).
DateTime? _parseServerTime(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final t = DateTime.tryParse(v);
  if (t == null || t.year <= 1) return null;
  return t;
}

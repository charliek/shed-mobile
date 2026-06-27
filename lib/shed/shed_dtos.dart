/// A shed as returned by the shed-server HTTP API. Tolerant: name + status +
/// the raw map, with a few common typed fields surfaced for the UI.
class Shed {
  const Shed({
    required this.name,
    required this.status,
    this.backend,
    this.raw = const {},
  });

  final String name;
  final String status;
  final String? backend;
  final Map<String, Object?> raw;

  bool get isRunning => status == 'running';

  factory Shed.fromJson(Map<String, Object?> j) => Shed(
    name: (j['name'] as String?) ?? '?',
    status: (j['status'] as String?) ?? 'unknown',
    backend: j['backend'] as String?,
    raw: j,
  );
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

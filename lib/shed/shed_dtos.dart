/// A shed as returned by the shed-server HTTP API. Kept tolerant for M0 (name +
/// status + the raw map); M1 fleshes out the typed fields used by the UI.
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

  factory Shed.fromJson(Map<String, Object?> j) => Shed(
    name: (j['name'] as String?) ?? '?',
    status: (j['status'] as String?) ?? 'unknown',
    backend: j['backend'] as String?,
    raw: j,
  );
}

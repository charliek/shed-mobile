/// A configured machine — a native host (not a shed VM) reached over SSH,
/// running a `roost-session` (plan 012, roadmap R4; re-sourced onto roost by
/// plan 013 S3m).
///
/// Deliberately NOT a [ServerRecord]: a shed server is an HTTP API with a TLS
/// pin, a control token, and an auth mode; a machine is only ever SSH. Modelling
/// them together would mean a record where half the fields are meaningless for
/// half the rows, and a UI that has to keep asking which kind it is holding.
///
/// Mirrors `shed_core::config::MachineEntry` field-for-field, so a machine
/// configured on the phone and one in `~/.shed/config.yaml` describe the same
/// thing — the desktop and the phone must agree about what "mini3" means.
class MachineRecord {
  const MachineRecord({
    required this.name,
    required this.host,
    this.user,
    this.sshPort = 22,
    this.rcBin,
  });

  /// The handle the user types and the UI labels rows with (`machine:<name>`).
  final String name;

  /// Where to dial. Defaults to [name] upstream when absent; here it is
  /// required, because a phone has no `~/.ssh/config` to fall back on and a
  /// silent "the name is the host" would fail as an opaque DNS error.
  final String host;

  /// SSH login user. `null` lets the far side decide — which on a phone means
  /// dartssh2's default, so the add-machine form asks for it.
  final String? user;

  final int sshPort;

  /// Where the `sx` binary lives on the machine.
  ///
  /// **Dead since plan 013 S3m — nothing reads it.** It existed for the `sx rc
  /// …` one-shots the RC-hub machine path ran over SSH; a machine's sessions
  /// now come from its `roost-session`, whose remote command roost composes
  /// itself (`roostRemoteCommand`), so there is no engine path for the phone to
  /// pin. The field survives only so a record stored by an older build still
  /// decodes and round-trips unchanged — it goes with the rest of the hub path
  /// in S6, along with the form field that used to set it.
  final String? rcBin;

  Map<String, Object?> toJson() => {
    'name': name,
    'host': host,
    if (user != null) 'user': user,
    'ssh_port': sshPort,
    if (rcBin != null) 'rc_bin': rcBin,
  };

  static MachineRecord fromJson(Map<String, Object?> j) => MachineRecord(
    name: (j['name'] as String?) ?? '',
    host: (j['host'] as String?) ?? '',
    user: j['user'] as String?,
    rcBin: j['rc_bin'] as String?,
    // Tolerant of a stored string (an older write, or a hand-edited blob):
    // a bad port must not make the whole machine list undecodable.
    sshPort: switch (j['ssh_port']) {
      final int p => p,
      final String s => int.tryParse(s) ?? 22,
      _ => 22,
    },
  );

  MachineRecord copyWith({
    String? host,
    String? user,
    int? sshPort,
    String? rcBin,
  }) => MachineRecord(
    name: name,
    host: host ?? this.host,
    user: user ?? this.user,
    sshPort: sshPort ?? this.sshPort,
    rcBin: rcBin ?? this.rcBin,
  );

  /// The origin handle a session row is keyed and labelled by.
  ///
  /// **Rows must key on this, never on a session's `shed`.** A machine's rows
  /// carry an EMPTY shed (there is no shed to name), so two machines that happen
  /// to share a slug would collide into one row.
  String get origin => 'machine:$name';

  @override
  bool operator ==(Object other) =>
      other is MachineRecord &&
      other.name == name &&
      other.host == host &&
      other.user == user &&
      other.sshPort == sshPort &&
      other.rcBin == rcBin;

  @override
  int get hashCode => Object.hash(name, host, user, sshPort, rcBin);
}

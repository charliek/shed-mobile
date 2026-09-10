import 'dart:typed_data';

/// **Run one already-composed wire command on the far side and return its raw
/// stdout** (plan 018 §3.11).
///
/// The gx credential probe, and nothing else, goes through here. Three
/// properties are load-bearing, and all three fail silently if they are wrong:
///
/// * **The command is composed in Rust** (`gxProbeRemoteCommand()`) and is run
///   VERBATIM. SSH has no argv API, so the probe crosses as one string the far
///   side re-parses; the phone quoting any part of it would put different bytes
///   on the wire than the desktop does, and shed's `tests/machine-transport`
///   pins that line as a golden.
/// * **The bytes come back UNDECODED.** The probe's stdout carries a bearer
///   token. It is parsed inside Rust's `discovery_from_probe` and dropped
///   there; nothing on this side decodes it, logs it, stores it past the call,
///   or interpolates any part of it into an error string.
/// * **It is a seam, so no test needs an sshd.** Production is
///   `MachineFeed.probe`, i.e. `execOn(client, cmd)` over the ONE SSH client
///   the machine's feed already holds — the roost tunnel and the lane's
///   forwards ride it too, so the probe costs no second connection. The
///   hermetic harness (§3.13) runs the same string as a local `Process` with
///   `GROK_HOME` pointed at a fake's temp home, which exercises the wire
///   string, the script and `parse_probe` end to end with no SSH at all.
typedef ProbeRunner = Future<Uint8List> Function(String wireCommand);

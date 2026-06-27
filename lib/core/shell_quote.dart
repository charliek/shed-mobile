// POSIX shell quoting. Port of shed-remote-agent apps/api/src/lib/shell.ts.
//
// dartssh2 has no argv API: a command is sent as one string that the remote
// shell re-parses. shed wraps that string in `bash -lc <raw>`, so one quoting
// layer here maps to exactly one bash parse (no double-quoting).

final RegExp _safe = RegExp(r'^[A-Za-z0-9_./-]+$');

/// Single-quote [s] for safe interpolation into a POSIX shell command, skipping
/// quoting when it contains only bare-safe characters. The empty string is not
/// bare-safe, so it becomes `''` (an explicit empty argument).
String shellQuote(String s) {
  if (_safe.hasMatch(s)) return s;
  return "'${s.replaceAll("'", "'\\''")}'";
}

/// Quote each token and join with spaces into one wire command.
String wireCmd(List<String> argv) => argv.map(shellQuote).join(' ');

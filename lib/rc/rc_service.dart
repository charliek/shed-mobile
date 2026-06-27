import 'dart:convert';
import 'dart:math';

import '../core/app_error.dart';
import '../core/app_version.dart';
import '../ssh/ssh_connection.dart';
import '../ssh/ssh_runner.dart';
import 'rc_models.dart';

/// Stable tool identifier for SHED_RC_CREATED_BY (must not contain '/').
const String rcToolName = 'shed-mobile';

/// `<tool>/<version>` provenance stored as SHED_RC_CREATED_BY at create time.
const String rcCreatedBy = '$rcToolName/$kAppVersion';

/// The guest binary name (on PATH in the shed `full` image).
const String _rcBin = 'shed-ext-rc';

/// claude's `--permission-mode` value set. Empty means "don't pass the flag"
/// (claude's own default). Mirrors shed-extensions `validPermissionModes`.
const Set<String> rcPermissionModes = {
  'default',
  'acceptEdits',
  'plan',
  'auto',
  'dontAsk',
  'bypassPermissions',
};

/// claude's full-bypass mode (the `--skip` shorthand).
const String rcPermissionBypass = 'bypassPermissions';

/// Slug alphabet without visually-confusable characters (no l/i/o/0/1), so a
/// short slug survives being read off a screen or typed. Port of rc.ts genSlug.
const String _slugAlphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

/// A 6-char slug. [rng] is injectable for deterministic tests; production uses a
/// secure RNG (slugs aren't a secret, but it gives a clean uniform draw).
String genSlug([Random? rng]) {
  final r = rng ?? Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < 6; i += 1) {
    b.write(_slugAlphabet[r.nextInt(_slugAlphabet.length)]);
  }
  return b.toString();
}

/// Drives the `shed-ext-rc` guest binary over SSH to manage a shed's RC sessions.
/// Port of apps/api/src/lib/shedRc.ts: create / list / kill / prompt, the
/// exit-code → AppError mapping, and the stdout-JSON contract. Classification of
/// pane state/url is owned by the binary (it runs inside the shed), so this layer
/// trusts the DTO's `state`/`url` rather than re-parsing panes.
class RcService {
  RcService({
    required this.runner,
    required this.shedName,
    required this.serverLabel,
    String Function()? slugGen,
  }) : _slug = slugGen ?? genSlug;

  /// The SSH command runner (injectable so command shape and error mapping are
  /// unit-testable without a real shed).
  final SshRun runner;

  /// The shed (== the SSH username) the binary runs inside.
  final String shedName;

  /// The server alias, used only for the advisory `shed:<shed>@<server>` label.
  final String serverLabel;
  final String Function() _slug;

  String _fallback(String slug) => '$shedName/$slug';

  String get _targetLabel => 'shed:$shedName@$serverLabel';

  /// List the shed's RC sessions via `shed-ext-rc list`.
  Future<List<RcSession>> list() async {
    final res = await _exec([
      _rcBin,
      'list',
    ], timeout: const Duration(seconds: 15));
    if (res.code != 0) throw _rcError(res);
    final raw = _decodeObj(res.stdout)['rc_sessions'];
    if (raw is! List) throw _invalidDto();
    // Fail the whole decode if any entry is malformed (matching the TS Zod
    // safeParse), rather than silently dropping sessions.
    return raw.map(_toSession).toList();
  }

  /// Create a session via `shed-ext-rc create --wait` (the binary resolves the
  /// workdir, pre-seeds trust, bootstraps, polls to ready, accepts trust, and
  /// delivers the prompt). The app generates the slug so it owns the
  /// `<shed>/<slug>` display convention. claude-broker has no pane to type into,
  /// so any [prompt] is dropped (the binary would reject it).
  Future<RcSession> create({
    required RcKind kind,
    String? displayName,
    String? slug,
    String? workdir,
    String? prompt,
    String? permissionMode,
  }) async {
    if (permissionMode != null && !rcPermissionModes.contains(permissionMode)) {
      throw AppError('RC_BAD_REQUEST', 'invalid permission mode', 400);
    }
    final theSlug = slug ?? _slug();
    final name = displayName ?? _fallback(theSlug);
    // Normalize empty → null once, so the prompt flag and the stdin payload stay
    // in lockstep. claude-broker has no pane, so its prompt is already dropped.
    final trimmed = kind.acceptsPrompt ? prompt?.trim() : null;
    final kickoff = (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    final args = [
      _rcBin,
      'create',
      '--kind',
      kind.wire,
      '--name',
      name,
      '--slug',
      theSlug,
      '--created-by',
      rcCreatedBy,
      '--target',
      _targetLabel,
      '--wait',
    ];
    if (workdir != null && workdir.isNotEmpty) {
      args.addAll(['--workdir', workdir]);
    }
    if (permissionMode != null) {
      args.addAll(['--permission-mode', permissionMode]);
    }
    if (kickoff != null) args.add('--prompt-stdin');

    // --wait blocks up to ~20s inside the shed; give SSH headroom over that.
    final res = await _exec(
      args,
      stdin: kickoff,
      timeout: const Duration(seconds: 30),
    );
    if (res.code != 0) throw _rcError(res);
    return _toSession(_decodeObj(res.stdout));
  }

  /// Kill a session via `shed-ext-rc kill` (idempotent — the binary exits 0 for
  /// an already-gone session).
  Future<void> kill(String slug) async {
    final res = await _exec([
      _rcBin,
      'kill',
      '--slug',
      slug,
    ], timeout: const Duration(seconds: 10));
    if (res.code != 0) throw _rcError(res);
  }

  /// Deliver a kickoff line to a ready claude-rc/shell session via
  /// `shed-ext-rc prompt` (text on stdin). [sessionId] guards against a recreated
  /// slug (it must match the session's SHED_RC_ID).
  Future<void> prompt(String slug, String text, {String? sessionId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw AppError('RC_BAD_REQUEST', 'prompt text is empty', 400);
    }
    final args = [_rcBin, 'prompt', '--slug', slug];
    if (sessionId != null && sessionId.isNotEmpty) {
      args.addAll(['--session-id', sessionId]);
    }
    final res = await _exec(
      args,
      stdin: trimmed,
      timeout: const Duration(seconds: 15),
    );
    if (res.code != 0) throw _rcError(res);
  }

  /// Run a command and map dartssh2 transport failures to AppError via the shared
  /// [classifySshException]. A command that runs but exits non-zero is returned
  /// (the caller maps it via [_rcError]); a non-transport error propagates as-is.
  Future<SshResult> _exec(
    List<String> argv, {
    String? stdin,
    required Duration timeout,
  }) async {
    try {
      return await runner(argv, stdin: stdin, timeout: timeout);
    } catch (e) {
      final mapped = classifySshException(e);
      if (mapped != null) throw mapped;
      rethrow;
    }
  }

  /// Map a non-zero `shed-ext-rc` invocation to an AppError. The binary's domain
  /// exit codes (2/3/4) are checked FIRST, so a domain message that happens to
  /// contain "command not found" isn't misread as a missing binary.
  AppError _rcError(SshResult r) {
    final detail = (r.stderr.trim().isNotEmpty ? r.stderr : r.stdout).trim();
    switch (r.code) {
      case 3:
        return AppError(
          'RC_SLUG_TAKEN',
          detail.isEmpty ? 'rc slug already taken' : detail,
          409,
        );
      case 4:
        return AppError(
          'RC_NOT_FOUND',
          detail.isEmpty ? 'rc session not found' : detail,
          404,
        );
      case 2:
        return AppError(
          'RC_BAD_REQUEST',
          detail.isEmpty ? 'invalid rc request' : detail,
          400,
        );
    }
    if (r.code == 127 ||
        RegExp('command not found', caseSensitive: false).hasMatch(r.stderr)) {
      return AppError(
        'SHED_EXT_RC_MISSING',
        'shed-ext-rc is not installed on this shed — update the shed image',
        502,
      );
    }
    return AppError(
      'RC_FAILED',
      detail.isEmpty ? 'shed-ext-rc exited ${r.code}' : detail,
      500,
    );
  }

  Map<String, Object?> _decodeObj(String stdout) {
    Object? raw;
    try {
      raw = jsonDecode(stdout);
    } on FormatException {
      throw AppError('RC_FAILED', 'shed-ext-rc returned non-JSON output', 502);
    }
    if (raw is! Map<String, Object?>) throw _invalidDto();
    return raw;
  }

  /// Decode one DTO, mapping a wrong-shape entry (a stale/broken shed-ext-rc) to a
  /// typed 502 rather than letting a raw cast TypeError escape. The guest binary's
  /// contract violation is a 502, never a client 400.
  RcSession _toSession(Object? raw) {
    if (raw is! Map<String, Object?>) throw _invalidDto();
    try {
      return RcSession.fromJson(raw, displayNameFallback: _fallback);
    } on AppError {
      rethrow;
    } catch (_) {
      throw _invalidDto();
    }
  }

  AppError _invalidDto() =>
      AppError('RC_FAILED', 'shed-ext-rc returned an invalid session DTO', 502);
}

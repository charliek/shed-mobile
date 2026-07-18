import '../bridge/bridge_adapters.dart';
import '../core/app_error.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/error.dart';
import '../src/rust/api/rc_runner.dart';
import '../ssh/ssh_connection.dart';
import '../ssh/ssh_runner.dart';
import 'rc_ui.dart';

/// Drives the `shed-ext-rc` guest binary over SSH to manage a shed's RC sessions
/// (option-a: plan §3.5). A THIN Dart transport — argv building, the create-time
/// permission-mode gate, stdout decode, and exit-code mapping all live in Rust
/// (`shed_core::rc`, behind `rcListArgv`/`rcCreateInvocation`/`rcKillArgv`/
/// `rcPromptArgv`/`rcDecodeSessions`/`rcDecodeSession`/`rcErrorFromExit`). This
/// layer keeps only what is genuinely platform-bound: the dartssh2 transport, the
/// `classifySshException` mapping, the per-op timeouts, the slug / display-name /
/// target-label orchestration, and the empty-prompt gate for the running-session
/// `prompt` op.
class RcService {
  RcService({
    required this.runner,
    required this.shedName,
    required this.serverLabel,
    String Function()? slugGen,
  }) : _slug = slugGen ?? genSlug;

  /// The SSH command runner (injectable so timeouts + error mapping are
  /// unit-testable without a real shed).
  final SshRun runner;

  /// The shed (== the SSH username) the binary runs inside.
  final String shedName;

  /// The server alias — the advisory `shed:<shed>@<server>` target label AND the
  /// `host` field injected into the enriched session (mobile's server identity).
  final String serverLabel;
  final String Function() _slug;

  String get _targetLabel => 'shed:$shedName@$serverLabel';

  /// List the shed's RC sessions via `shed-ext-rc list`. Rust enriches the rows
  /// (host/shed inject + `<shed>/<slug>` display-name fallback).
  Future<List<BridgeRcSession>> list() async {
    final res = await _exec(
      await rcListArgv(),
      timeout: const Duration(seconds: 15),
    );
    if (res.code != 0) throw await _exitError(res);
    return _decode(
      () => rcDecodeSessions(
        stdout: res.stdout,
        host: serverLabel,
        shed: shedName,
      ),
    );
  }

  /// Create a session via `shed-ext-rc create --wait`. The app generates the slug
  /// so it owns the `<shed>/<slug>` display convention; the Rust builder is the
  /// validating gate for `permissionMode` (an invalid mode → RC_BAD_REQUEST with
  /// no SSH call) and drops the prompt for a non-typed-input kind (claude-broker).
  /// Provenance (`created_by`) carries the app version via [rcCreatedBy].
  Future<BridgeRcSession> create({
    required BridgeRcKind kind,
    String? displayName,
    String? slug,
    String? workdir,
    String? prompt,
    String? permissionMode,
  }) async {
    final theSlug = slug ?? _slug();
    final name = displayName ?? '$shedName/$theSlug';
    // Normalize the kickoff line here (empty/blank → null) so an empty prompt
    // never produces a `--prompt-stdin` with empty stdin — the Rust builder
    // does NOT trim/empty-drop. It DOES gate the mode and drop the prompt for a
    // non-typed-input kind, so we pass both straight through.
    final trimmed = prompt?.trim();
    final kickoff = (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    final BridgeRcInvocation inv;
    try {
      inv = await rcCreateInvocation(
        kind: kind.wire,
        name: name,
        slug: theSlug,
        target: _targetLabel,
        createdBy: rcCreatedBy,
        workdir: (workdir == null || workdir.isEmpty) ? null : workdir,
        permissionMode: permissionMode,
        prompt: kickoff,
      );
    } on BridgeError catch (e) {
      // The mode gate rejects before any SSH call (RC_BAD_REQUEST).
      throw appErrorFromBridge(e);
    }

    // --wait blocks up to ~20s inside the shed; give SSH headroom over that.
    final res = await _exec(
      inv.argv,
      stdin: inv.stdin,
      timeout: const Duration(seconds: 30),
    );
    if (res.code != 0) throw await _exitError(res);
    return _decode(
      () => rcDecodeSession(
        stdout: res.stdout,
        host: serverLabel,
        shed: shedName,
      ),
    );
  }

  /// Kill a session via `shed-ext-rc kill` (idempotent — the binary exits 0 for
  /// an already-gone session).
  Future<void> kill(String slug) async {
    final res = await _exec(
      await rcKillArgv(slug: slug),
      timeout: const Duration(seconds: 10),
    );
    if (res.code != 0) throw await _exitError(res);
  }

  /// Deliver a kickoff line to a ready claude-rc/shell session via
  /// `shed-ext-rc prompt` (text on stdin). [sessionId] guards against a recreated
  /// slug. The empty-text gate stays Dart-side (a client 400 before any SSH).
  Future<void> prompt(String slug, String text, {String? sessionId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw AppError('RC_BAD_REQUEST', 'prompt text is empty', 400);
    }
    final res = await _exec(
      await rcPromptArgv(slug: slug, sessionId: sessionId),
      stdin: trimmed,
      timeout: const Duration(seconds: 15),
    );
    if (res.code != 0) throw await _exitError(res);
  }

  /// Run a command and map dartssh2 transport failures to AppError via the shared
  /// [classifySshException]. A command that runs but exits non-zero is returned
  /// (the caller maps it via [_exitError]); a non-transport error propagates.
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

  /// Map a non-zero `shed-ext-rc` exit to an [AppError] via the Rust
  /// classifier (`error_from_exit` → typed `BridgeError`, then the shared
  /// bridge→AppError map). The binary's domain exit codes (2/3/4) and the
  /// missing-binary (127) case are decided in Rust.
  Future<AppError> _exitError(SshResult r) async => appErrorFromBridge(
    await rcErrorFromExit(exitCode: r.code, stderr: r.stderr, stdout: r.stdout),
  );

  /// Decode a bridge round-trip result, re-mapping a decode failure to
  /// `RC_FAILED`/502 via [rcDecodeError].
  Future<T> _decode<T>(Future<T> Function() decode) async {
    try {
      return await decode();
    } on BridgeError catch (e) {
      throw rcDecodeError(e);
    }
  }
}

/// Map a decode-path bridge failure to `RC_FAILED`/502.
/// `rcDecodeSessions`/`rcDecodeSession` surface a non-JSON stdout or an invalid DTO
/// as `shed_core::rc`'s `RcError::Failed` → [BridgeError_RcFailed], whose shared
/// [appErrorFromBridge] mapping is the exit-path `RC_FAILED`/500. A decode-contract
/// violation (a stale/broken shed-ext-rc) is historically a **502** (matching the
/// old Dart `_decodeObj`/`_invalidDto`), so re-stamp the status here while
/// preserving the Rust detail message. Pure (crosses no FFI) so it's unit-testable.
AppError rcDecodeError(BridgeError e) =>
    AppError('RC_FAILED', appErrorFromBridge(e).message, 502);

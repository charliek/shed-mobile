import '../core/app_error.dart';
import '../servers/server_target.dart';
import 'token_bundle.dart';

/// Source of a bearer control token for the shed HTTP client.
abstract class TokenSource {
  /// The current token, or null for a legacy (non-secure) server.
  Future<String?> get();

  /// Signal that [token] was rejected (HTTP 401) so it is never reused.
  void invalidate(String token);
}

const int _refreshWindowMsDefault = 2 * 60 * 60 * 1000 + 5 * 60 * 1000;
const int _jitterMsDefault = 5 * 60 * 1000;
const int _cooldownMsDefault = 60 * 1000;

/// Per-server control-token provider. Faithful port of the orchestrator's
/// controlToken.ts `ControlTokenProvider`:
///   - in-memory token is authoritative; the config/persisted token is a seed
///   - single-flight mint shared by concurrent callers
///   - proactive refresh within the refresh window (keeps a valid token if the
///     refresh mint fails)
///   - reactive: a 401 (`invalidate`) forces a fresh mint and never reuses the
///     rejected token; a stale 401 for an already-rotated token is ignored
///   - cooldown after a failed mint so a polling caller can't storm a host
///   - transport-identity binding: a host/port/baseUrl/pin change drops the
///     cached token so it is never sent to a different endpoint
class ControlTokenProvider implements TokenSource {
  ControlTokenProvider(
    String name, {
    required this.resolve,
    required this.minter,
    int Function()? now,
    this.refreshWindowMs = _refreshWindowMsDefault,
    this.cooldownMs = _cooldownMsDefault,
    int jitterMs = _jitterMsDefault,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _jitter = nameJitter(name, jitterMs);

  final Future<ServerTarget?> Function() resolve;
  final Minter minter;
  final int refreshWindowMs;
  final int cooldownMs;
  final int Function() _now;
  final int _jitter;

  MintedToken? _cached;
  String? _cachedIdentity;
  Future<MintedToken>? _inflight;
  String? _inflightIdentity;
  int _cooldownUntil = 0;
  AppError? _lastError;
  bool _mustMint = false;

  @override
  Future<String?> get() async {
    final target = await resolve();
    if (target == null || !target.secure) return null; // legacy: no token
    final now = _now();

    // Identity change (re-key or open->secure flip) invalidates the cache.
    final id = targetIdentity(target);
    if (_cached != null && _cachedIdentity != id) {
      _cached = null;
      _cachedIdentity = null;
      _mustMint = false;
    }

    // Reactive: a prior 401 means the current token is rejected — mint, and do
    // not fall back to it.
    if (_mustMint) {
      final minted = await _mint(target, now);
      if (minted != null) {
        _mustMint = false;
        return minted.token;
      }
      throw _lastError ?? AppError.authExpired();
    }

    final current = _cached ?? _seedToken(target);
    if (current != null && !_expired(current, now)) {
      if (_needsRefresh(current, now)) {
        final minted = await _mint(target, now);
        if (minted != null) return minted.token;
      }
      if (_cached == null) {
        _cached = current;
        _cachedIdentity = id;
      }
      return current.token;
    }

    final minted = await _mint(target, now);
    if (minted != null) return minted.token;
    throw _lastError ?? AppError.authExpired();
  }

  @override
  void invalidate(String token) {
    // Ignore a 401 for a token already rotated past.
    if (_cached != null && _cached!.token != token) return;
    _cached = null;
    _mustMint = true;
  }

  /// Single-flight mint with a failure cooldown. Returns null on (or during)
  /// failure; side effects (cooldown, lastError) are recorded once in [_doMint].
  Future<MintedToken?> _mint(ServerTarget target, int now) async {
    if (now < _cooldownUntil) return null;
    final id = targetIdentity(target);
    // Single-flight only WITHIN the same transport identity. If the identity
    // changed while a mint is in flight, start a fresh one rather than hand the
    // old endpoint's token to the new one (closes a race the TS source leaves
    // open; see PLAN §13 S5).
    final reuse = _inflight != null && _inflightIdentity == id;
    final pending = reuse ? _inflight! : _startMint(target, id);
    try {
      return await pending;
    } catch (_) {
      return null;
    }
  }

  Future<MintedToken> _startMint(ServerTarget target, String id) {
    final p = _doMint(target);
    _inflight = p;
    _inflightIdentity = id;
    // Free the slot once settled; every awaiter observes errors via `await`.
    p.whenComplete(() {
      if (identical(_inflight, p)) {
        _inflight = null;
        _inflightIdentity = null;
      }
    }).ignore();
    return p;
  }

  Future<MintedToken> _doMint(ServerTarget target) async {
    try {
      final minted = await minter(target);
      _cached = minted;
      _cachedIdentity = targetIdentity(target);
      _lastError = null;
      return minted;
    } catch (e) {
      _cooldownUntil = _now() + cooldownMs;
      _lastError = e is AppError ? e : AppError.authExpired();
      rethrow;
    }
  }

  MintedToken? _seedToken(ServerTarget target) {
    final t = target.controlToken;
    if (t == null) return null;
    return MintedToken(t, target.controlTokenExpiresAt);
  }

  bool _expired(MintedToken t, int now) =>
      t.expiresAt != null && now >= t.expiresAt!.millisecondsSinceEpoch;

  bool _needsRefresh(MintedToken t, int now) {
    final exp = t.expiresAt;
    if (exp == null) return false;
    return now >= exp.millisecondsSinceEpoch - refreshWindowMs - _jitter;
  }
}

/// Transport identity a token is bound to; a change must invalidate the token.
String targetIdentity(ServerTarget t) =>
    '${t.host}|${t.sshPort}|${t.baseUrl}|${t.tlsCertFingerprint ?? ''}';

/// Deterministic per-name jitter in `[0, maxMs)` — stable across restarts, no
/// RNG. Mirrors controlToken.ts `nameJitter` (32-bit signed hash like JS `|0`).
int nameJitter(String name, int maxMs) {
  var h = 0;
  for (var i = 0; i < name.length; i++) {
    h = (h * 31 + name.codeUnitAt(i)).toSigned(32);
  }
  return h.abs() % (maxMs < 1 ? 1 : maxMs);
}

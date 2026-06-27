# shed-mobile — Execution Plan v2 (Desktop-First Flutter Fat-Client)

> A single-codebase Flutter app that talks **directly** to `shed` servers with **no orchestrator**. The device *is* the orchestrator. This is the authoritative, execution-ready plan: it merges four layer specs with adversarially **source-verified** technical facts (dartssh2 2.18.0 read at tag; shed Go source read directly). v2 resolves every prior UNCONFIRMED item.

## 0. What changed v1 → v2 (all verified)

| Item | Resolution |
|---|---|
| **ed25519 keygen** (was the #1 High risk) | **Easy.** dartssh2 exports `OpenSSHEd25519KeyPair(pub32, priv64, comment).toPem()`; `pinenacl` (already a transitive dep) does CSPRNG keygen. No hand-rolled OpenSSH container. `SSHKeyPair.fromPem` round-trips by construction. GitHub public line = 5-line helper. |
| **Mint wire-string** (was Risk #8) | **`control shed-mobile`** — `bootstrap.go:88` does `strings.Fields(rawCmd)` → `parts[0]`=scope, `parts[1]`=client-kind. Unknown kind (`shed-mobile`) → recorded empty, mint still succeeds (same as orchestrator's `shed-remote-agent`). |
| **flutter_secure_storage** | Pin **`^10.3.1`** (NOT 9.x; avoid 11-beta). macOS Keychain entitlement in **both** Debug+Release; Android **`allowBackup=false`**; Linux needs libsecret (headless-hostile) → passphrase-encrypted-file fallback if libsecret absent. |
| **dart:io TLS pinning** | **Solid.** `badCertificateCallback` + `X509Certificate.der` + constant-time sha256 compare; also re-check expiry (callback bypasses it). `WebSocket.connect(customClient:)` + streamed SSE GET ride the pinned client. |
| **Android FGS** | `flutter_foreground_task ^9.2.2`, type **`specialUse`** (dodges Android 15's 6h `dataSync` cap; fine for sideload). dartssh2 in the FGS background isolate; SSH keepalive + auto-reconnect + `tmux` re-attach. |
| **Toolchain** | System Flutter **3.44.2 / Dart 3.12.2** stable (no FVM, matches tapper's approach). Hand-written riverpod (no codegen). |
| **Repo + CI** | New **private** GitHub repo `charliek/shed-mobile` + CI modeled on tapper's `flutter-check` + sideload-APK release workflow (this §6 / §9.0). |
| **v1 feature scope** | MVP = **type the repo as `owner/repo` text** for create-shed (or host local-dir). Architecture leaves clean **interface seams** for deferred features so they slot in without rework: `RepoSource` (text now → OAuth picker / public-repo picker later), `KeyProvisioner` (manual GitHub paste now → in-app key-upload later), `RcTarget` (sheds now → `machine:` SSH targets later). Build a deferred feature now only if trivial; a public-repo (unauthenticated) picker is a stretch goal, not required. iOS out of scope (no scaffold). Test sheds: `shed-mobile-test` on mac-mini + mini3. Android device: google-pixel-8. |

---

## 1. Overview & Viability Verdict

**Verdict: viable, desktop-first, no remaining High-risk unknowns.** The control/credential/transport stack is a faithful port of production code (`controlToken.ts`, `secureTransport.ts`, `shedClient.ts`, `rc.ts`, Go `sdk/bootstrap.go`). dartssh2 2.18.0 covers every SSH need — host-key pinning (SHA256 fmt, matches Go `ssh.FingerprintSHA256`), OpenSSH-ed25519 generate+import, `runWithResult` for JSON RPC, PTY for `tmux attach`, AES-GCM rekey fix for long terminals. Pinned-TLS is pure `dart:io`.

The two former risk pockets are resolved: in-app keygen reuses dartssh2's own serializer; Android background survival uses a `specialUse` foreground service. Both are mobile-only; **desktop (macOS/Linux) sidesteps both** (reuse `~/.ssh/id_ed25519`; no Doze). So we build and adversarially test the entire risky vertical on desktop first (M1–M3), then port to Android (M4) where keygen + FGS become mandatory. A standalone keygen round-trip test is front-loaded as cheap insurance.

---

## 2. Architecture

**Device-as-orchestrator.** No process runs anywhere we control except the shed servers. The app holds all state (server registry, pins, tokens, keys) on-device and drives each shed over three transports, all riding the **system Tailscale VPN** (normal sockets; no embedded Tailscale).

| Transport | Purpose | Mechanism | Trust root |
|---|---|---|---|
| **Pinned-TLS HTTPS** | shed control API: list/get/create(SSE)/start/stop/delete sheds, sessions, images | `dart:io HttpClient`, `badCertificateCallback` pins `sha256(DER leaf)`, fail-closed before any byte (incl. bearer) is written | TLS pin `sha256:<hex>` |
| **SSH (dartssh2 2.18.0)** | (a) mint token via `_bootstrap@host` running `control shed-mobile`; (b) RC lifecycle via `<shed>@host shed-ext-rc <cmd>`; (c) terminal via `<shed>@host tmux attach -t rc-<slug>` over PTY | One per-device ed25519 identity; host-key pinned; argv POSIX-quoted (no argv API in dartssh2) | SSH host-key pin `SHA256:<base64>` + GitHub-allowlisted client key |
| **GitHub API** (optional, M5) | repo picker only | `dio`; OAuth/PAT TBD | n/a (not control plane) |

> **Two fingerprint formats, never conflated.** TLS pin = `sha256:`+lowercase hex of `SHA256(DER leaf)` (`^sha256:[0-9a-f]{64}$`). SSH host-key pin = OpenSSH `SHA256:<base64-no-pad>` (what dartssh2 hands `onVerifyHostKey`; what Go `FingerprintSHA256` + `/api/ssh-host-key` produce). Separate stores.

```
UI isolate (Flutter widgets, riverpod, xterm.dart)
  │  providers → services;  SendPort/ReceivePort to SSH isolate
  ├─ net/      PinnedHttpClient (dart:io)  ── HTTPS ──▶ shed control API
  ├─ shed/     ShedClient (typed) + SSE create
  ├─ control/  ControlTokenProvider (single-flight, refresh, 401, cooldown, identity-bind)
  ├─ servers/  ServerStore + AddServerFlow (port runServerAdd)
  └─ keys/     KeyManager (generate via OpenSSHEd25519KeyPair / import ~/.ssh)
        ▼  (all SSH crypto + sockets here; bytes streamed back)
SSH isolate (one long-lived background isolate; on Android hosted by the FGS)
  ├─ SshConnectionPool   (one SSHClient per host:user)
  ├─ HostKeyStore        (TOFU pins, fail-closed on mismatch)
  ├─ BootstrapService    (_bootstrap → control mint)
  ├─ RcService           (shed-ext-rc list/create/probe/kill over SSH)
  └─ TerminalSession(s)  (tmux attach PTY ↔ xterm; own ReceivePort per stream)
```

Single-owner SSH isolate keeps the host-key TOFU cache + connection pool consistent and keeps dartssh2's continuous decrypt/rekey loop off the UI thread. Each terminal stream gets its **own `ReceivePort`** so a busy PTY can't head-of-line-block RPC replies.

---

## 3. SSH Identity & Key Management

**One per-device ed25519 key.** No server-side device enrollment exists — the allowlist is GitHub-driven (`auth.ssh.github_users` in `keyauth.go`, refreshed ~hourly). Bootstrap additionally requires server `auth.ssh.mode: enforce`.

### Generate in-app (mobile-forced; M4) — VERIFIED Easy

```dart
import 'package:pinenacl/ed25519.dart';
import 'package:dartssh2/dartssh2.dart';

final sk      = SigningKey.generate();        // CSPRNG (Random.secure via TweetNaCl)
final pub32   = sk.verifyKey.asTypedList;     // 32 bytes
final priv64  = sk.asTypedList;               // 64 bytes == seed||pub  (MUST be 64)
final privatePem = OpenSSHEd25519KeyPair(
    Uint8List.fromList(pub32), Uint8List.fromList(priv64), 'shed-mobile@<device>').toPem();
// round-trips: SSHKeyPair.fromPem(privatePem) == [OpenSSHEd25519KeyPair]
```

Public line for GitHub (hand-rolled, format confirmed from `hostkey_ed25519.dart`):
```dart
String ed25519PublicOpenSsh(Uint8List pub32, String comment) {
  final b = BytesBuilder();
  void s(List<int> x){ final n=x.length; b.add([n>>24&255,n>>16&255,n>>8&255,n&255]); b.add(x); }
  s(ascii.encode('ssh-ed25519')); s(pub32);
  return 'ssh-ed25519 ${base64.encode(b.toBytes())} $comment';
}
```
- Store `privatePem` in `flutter_secure_storage`; `publicOpenSsh` in plain prefs (public).
- UI: show the `ssh-ed25519 AAAA…` string + **Copy** + "Paste into GitHub → Settings → SSH and GPG keys." Warn: GitHub key propagation is ~hourly server-side; offer a "Test connection" retry (no-op SSH).

### Import existing key (desktop M0; unblocks the vertical without keygen) — VERIFIED

```dart
Future<DeviceKey> importFromFile(String path, {String? passphrase}); // default ~/.ssh/id_ed25519
```
- `SSHKeyPair.fromPem` accepts `OPENSSH PRIVATE KEY` / `RSA PRIVATE KEY` / `EC PRIVATE KEY` — **no PKCS8**. Encrypted **OpenSSH** ed25519 (passphrase, bcrypt_pbkdf+aes) **works**; wrong passphrase → `SSHKeyDecryptError`. Only **legacy encrypted EC** (`-----BEGIN EC PRIVATE KEY-----` + DEK-Info) is unsupported → typed "unsupported, generate in-app".
- Persist re-serialized as unencrypted OPENSSH PEM in secure storage (don't depend on FS perms).

### Host-key TOFU (dartssh2 2.18.0)

```dart
SSHHostkeyVerifyHandler pinnedHostKey(HostRef h, HostKeyStore store) {
  final key = '${h.host}:${h.sshPort}';        // bind host/port from OUR context
  return (type, fingerprint) async {           // callback has NO host/port arg
    final fp = utf8.decode(fingerprint);       // "SHA256:<base64>"
    final known = await store.read(key);
    if (known == null) { await store.write(key, fp); return true; }  // TOFU
    return known == fp;                         // fail-closed on mismatch
  };
}
```
- Always pass the handler; never `disableHostkeyVerification`. Mismatch is a hard `hostKeyMismatch` class (≈ Go `ErrHostKeyMismatch`).
- **Close the add-time MITM window:** seed `HostKeyStore` from pinned-TLS `GET /api/ssh-host-key` **before** the first SSH connect, so bootstrap verifies against a TLS-derived pin. Blind TOFU is the SSH-first fallback only, with the fingerprint shown for confirmation (mirrors `runServerAdd:confirmHostKey`).

### Prereqs / cipher notes
- Prefer ed25519 end-to-end (KEX curve25519, hostkey + client-auth ssh-ed25519). A chacha20-poly1305-**only** sshd fails the dartssh2 handshake → surface as config error, not transient. shed offers AES-GCM/CTR (verify in M0).

---

## 4. Onboarding / Add-Server Flow (mirrors `cmd/shed/server.go:runServerAdd`)

Pin the host key **before** issuing the credential. Each step is a discrete, testable state.

| # | Step | Detail |
|---|---|---|
| 1 | **Input** | `host` (Tailscale name or `100.x` IP), optional display-name. |
| 2 | **`GET /api/info`** (pinned-TLS — but pin not yet known → TOFU-pin TLS here too, or accept on first fetch then confirm) | → `{name, version, ssh_port, https_port, auth_mode, default_image}`. **Require secure/enforce**; reject open mode. Build `apiUrl='https://$host:${httpsPort}'`. |
| 3 | **`GET /api/ssh-host-key`** | compute `SHA256:<base64>`, confirm with user, seed `HostKeyStore` → `hostKeyPin`. |
| 4 | **SSH bootstrap mint** | as `_bootstrap`, host key verified vs the just-confirmed pin, run **`control shed-mobile`** → bundle. |
| 5 | **Persist** | `ServerRecord` (incl. `keyIdentityId`). |

**Bundle shape** (port to Dart DTO; authoritative `internal/sshd/bootstrap.go:bootstrapBundle`):
```jsonc
{ "token":"...", "scope":"control", "https_port":8443, "http_port":0,
  "tls_cert_fingerprint":"sha256:...", "token_id":"...", "expires_at":"<RFC3339>" }
```
**Validation (fail-closed, port `parseTokenBundle`):** bad JSON · `scope!='control'` · empty token · missing/unparseable `expires_at` · minted `tls_cert_fingerprint` ≠ already-configured pin (no silent re-pin) → typed auth error. **Never surface mint stdout/stderr on failure** (token material) — log-and-fail (`mintViaSSH`). Common rejections: not `enforce` ("server not in enforce mode"), key not authorized ("paste your key into GitHub / wait ~1h").

---

## 5. Layered Design

### 5a. Core networking / data layer

HTTP is **`dart:io HttpClient`** on the control plane (only primitive that fails closed on a self-signed cert *and* exposes the leaf DER). `dio` is GitHub-only. Keep `secureTransport.ts`'s pinning + fail-closed posture, **not** its hand-rolled HTTP/1.1 parser (dart:io frames for us).

```dart
// core/fingerprint.dart
final RegExp kTlsFingerprintRe = RegExp(r'^sha256:[0-9a-f]{64}$');
String certFingerprint(Uint8List der);          // 'sha256:'+hex(sha256(der))
bool constantTimeEquals(String a, String b);

// net/pinned_http_client.dart
class PinnedHttpClient {
  PinnedHttpClient({required String host, required int port, required String fingerprint});
  Future<SecureResponse> send({required String method, required String path,
      String? token, Object? jsonBody, String accept='application/json',
      Duration? idleTimeout, CancelToken? cancel});   // pin checked pre-write; recheck expiry
  void close({bool force=false});
}

// core/sse_parser.dart — PORT packages/shared/src/sse.ts (NOT tapper's looser one)
Stream<SseRawEvent> parseSseStream(Stream<List<int>> bytes); // event:/data:/multiline/comments/EOF-flush/UTF-8 split

// control/control_token_provider.dart — PORT controlToken.ts state machine 1:1
class MintedToken { final String token; final DateTime? expiresAt; }
MintedToken parseTokenBundle(String stdout, ServerTarget target);   // fail-closed
abstract class TokenSource { Future<String?> get(); void invalidate(String token); }
class ControlTokenProvider implements TokenSource {
  ControlTokenProvider(String name, {required Future<ServerTarget?> Function() resolve,
    Minter? minter, Now? now,
    Duration refreshWindow=const Duration(hours:2,minutes:5),
    Duration cooldown=const Duration(seconds:60), Duration jitter=const Duration(minutes:5)});
}
```
Ported invariants (verbatim): in-memory token authoritative; config token = seed until first mint; single-flight `_inflight` (attach a `.catchError` sink so awaiters' rejection isn't unhandled); cooldown after failed mint; transport-identity binding (host|sshPort|baseUrl|tlsFp change drops cache + clears mustMint); reactive `invalidate` is CAS (ignore stale-token 401s); proactive refresh keeps still-valid token on failure; never return a 401-rejected token. Constants: `_bootstrap`, `shed-mobile`, mint timeout 15s, refresh 2h05m, jitter 5m, cooldown 60s, deterministic `nameJitter` (no RNG).

```dart
// shed/shed_client.dart — PORT shedClient.ts (401→invalidate→retry once; {error:{code,message,details}})
class ShedClient {
  Future<List<Shed>> listSheds();   Future<Shed> getShed(String n);
  Future<Shed> startShed(String n); Future<Shed> stopShed(String n); Future<void> deleteShed(String n);
  Future<SessionsResult> listSessions(String n); Future<void> killSession(String shed, String s);
  Future<List<ImageInfo>> listImages();
  Stream<ShedCreateEvent> createShedSSE(CreateShedRequest req);  // POST /api/sheds, text/event-stream
}
// servers/server_store.dart  (FlutterSecureStorage; add/list/remove; resolveTarget)
// servers/add_server_flow.dart — PORT runServerAdd (steps §4)
```

### 5b. SSH / RC / terminal layer (background isolate)

```dart
// ssh/ssh_channel.dart — isolate handshake + correlated RPC + per-stream ReceivePort
class SshChannel {
  static Future<SshChannel> spawn();
  Future<T> call<T>(SshRequest req);                  // MintControlToken|RcList|RcCreate|RcKill|RcProbe
  Stream<SshEvent> openStream(SshStreamRequest req);  // TerminalAttach{shed,slug,cols,rows}
}
// ssh/ssh_connection_pool.dart — keyed (host,port,user); _bootstrap & <shed> distinct; evict on key change
// core/shell_quote.dart — PORT shell.ts verbatim (dartssh2 has NO argv API)
String shellQuote(String s); String wireCmd(List<String> argv);  // map(shellQuote).join(' ')
// ssh/ssh_error.dart — PORT classifySSHError (type + remote exitCode + stderr)
enum SshErrorClass { ok, authDenied, hostKeyMismatch, hostUnreachable, connectionRefused, timeout, commandFailed }
// ssh/bootstrap_service.dart — PORT mintViaSSH + sdk.Bootstrap; runWithResult('control shed-mobile')
// keys/key_manager.dart — generate (OpenSSHEd25519KeyPair) / load / identities() / publicKeyString() / importFromFile()
```

All RPC uses `runWithResult(wireCmd(argv))` (gives exitCode + separate stdout/stderr); never `run()`. Short RPC clients are transient; the terminal client is long-lived/pooled.

```dart
// rc/rc_models.dart — convention v2
enum RcKind { claudeBroker, claudeRc, shell }      enum RcState { starting, ready, reconnecting, needsTrust, needsAuth, dead }
// rc/rc_service.dart — PORT shedRc.ts (shed-ext-rc over SSH as <shed>@host)
//   create --kind <k> --name <display> --slug <slug> --created-by shed-mobile/<ver> --target <label> --wait [--workdir d] [--prompt-stdin]
//   genSlug(): 6 of "abcdefghjkmnpqrstuvwxyz23456789"
// rc/rc_classify.dart — PORT classifyPane/extractUrl regexes VERBATIM (pure; local fallback + validation)
```
**RC exit-code → typed error (check domain BEFORE transport):** 0 ok · 2 `RcBadRequest` · 3 `RcSlugTaken`→retry fresh slug · 4 `RcNotFound` · 127/"command not found" `ShedExtRcMissing` · else `classifySshError`.

```dart
// terminal/terminal_session.dart — tmux attach over PTY (NOT via shed-ext-rc)
final s = await client.execute(wireCmd(['tmux','attach','-t','rc-$slug']),
    pty: SSHPtyConfig(width: cols, height: rows));   // PTY required
s.stdout.listen((d)=>sendToUi(TermData(d)));         // read stdout only (PTY folds stderr)
// UI Terminal(maxLines:10000); onOutput→TermInput; onResize→TermResize→resizeTerminal; events→terminal.write
// Clamp cols/rows 1..1000; long sessions survive rekey (dartssh2 2.18.0 GCM fix). Android: keep alive via FGS; SSH keepalive + auto-reconnect + re-attach on drop.
```

---

## 6. Project Structure, Packages, Repo + CI

**Repo:** new **private** `github.com/charliek/shed-mobile`, cloned at `/Users/charliek/projects/shed-mobile`.

```bash
gh repo create charliek/shed-mobile --private --description "Direct fat-client for shed servers (no orchestrator)"
cd /Users/charliek/projects
flutter create --org com.charliek.shed --project-name shed_mobile --platforms=macos,linux \
  --description "Direct fat-client for shed servers (no orchestrator)" shed-mobile
# android added in place at M4: flutter create --platforms=android .
```

### Packages (`pubspec.yaml`)

| Package | Pin | Role |
|---|---|---|
| `dartssh2` | **`2.18.0` (exact)** | SSH; SHA256 hostkey, AES-GCM rekey, `OpenSSHEd25519KeyPair` |
| `pinenacl` | `^0.6.0` | ed25519 CSPRNG keygen (already transitive) |
| `flutter_riverpod` | `^3.x` | state mgmt (match tapper; hand-written, no codegen) |
| `flutter_secure_storage` | `^10.3.1` | private key/token/pins at rest |
| `flutter_foreground_task` | `^9.2.2` | Android FGS (`specialUse`) for long-lived PTY (M4) |
| `crypto` | `^3.x` | sha256 over DER |
| `xterm` | `^4.x` | in-app terminal (v1 required); `lollipopkit` fork on standby |
| `uuid` | `^4.x` | ids |
| `dio` | latest | GitHub API only (M5) |
| dev: `flutter_lints` `^6.x`, `fake_async` `^1.x`, `marionette_flutter` `^0.5.x` | | lint / clock injection / local-test driving |

### `.github/workflows/ci.yml` (modeled on tapper's flutter-check; repo-root app)
```yaml
name: CI
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  flutter-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test
```
### `.github/workflows/release-android.yml` (sideload APK, not Play Store)
`workflow_dispatch` → flutter-action → `pub get`/`analyze`/`test` → decode `KEYSTORE_BASE64` → `flutter build apk --release --build-number … --dart-define-from-file=env/production.json` → upload the signed APK as a run artifact (no fastlane/Play). macOS/Linux desktop build smoke added once M3 lands.

### `analysis_options.yaml` (tapper-strictness)
`include: package:flutter_lints/flutter.yaml`; `strict-casts`/`strict-raw-types: true`; `unawaited_futures: warning` (security code must not swallow futures); `prefer_single_quotes`, `require_trailing_commas`.

### `lib/` layout
```
lib/{main.dart,app.dart}
core/{result,shell_quote,fingerprint,sse_parser,clock}.dart
net/{pinned_http_client,secure_response}.dart
control/{token_bundle,control_token_provider}.dart
shed/{shed_dtos,shed_create_event,shed_client}.dart
ssh/{ssh_channel,ssh_isolate,ssh_connection_pool,host_key_store,bootstrap_service,ssh_error}.dart
keys/{ed25519_keygen,key_manager}.dart
rc/{rc_models,rc_classify,rc_service}.dart
servers/{server_record,server_target,server_store,add_server_flow}.dart
terminal/{terminal_session}.dart
features/{servers,sheds,sessions,terminal}/  providers/  marionette/{marionette_init,drive_state}.dart
test/  integration_test/  .claude/skills/drive-shed-mobile/
docs/PLAN.md  PROGRESS.md
```

### Local command set (`tool/check.sh`, also the CI gate)
`flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `flutter analyze` (zero) → `flutter test` → `flutter test integration_test` (desktop).

---

## 7. Milestones (Desktop-First) + dependency path

**Per-milestone gate** = Acceptance Criteria pass under the §9 loop (analyze/format/test clean + drive-skill against a test shed + manual checklist where automation can't reach).

### M-init — Repo + CI + skeleton · **S**
`gh repo create … --private`; `flutter create` (macos,linux); pubspec + analysis_options; `.github/workflows/ci.yml` + `release-android.yml`; `tool/check.sh`; commit `PLAN.md` + seed `PROGRESS.md`; first green CI. **Accept:** CI passes on an empty-but-analyzing app; repo private; `PROGRESS.md` lists all milestones/phases.

### M0 — Transport spike (desktop, imported key) · **M**
Pure ports (`shell_quote`, `sse_parser`, `fingerprint`, `result`); `key_manager.importFromFile` (+passphrase guard); `host_key_store` TOFU; `bootstrap_service` mint + validate; `pinned_http_client`; minimal `control_token_provider`; `shed_client.listSheds()`. *(Parallel: keygen round-trip test — generate→toPem→fromPem→authenticate.)* **Accept:** against a real secure shed → confirm `/api/ssh-host-key` pin → mint `control shed-mobile` over SSH → pinned-TLS `GET /api/sheds` lists. Host-key mismatch aborts; TLS-pin mismatch aborts; tampered/expired token → exactly one re-mint. Pure ports have table tests from the TS originals.

### M1 — Server mgmt + shed CRUD + create-SSE (desktop) · **M**
Server registry (add/remove/persist pins+seed; multi-host); rest of `shedClient.ts` port; `createShedSSE` (120s idle); riverpod + desktop UI (list/detail/create with live SSE). Create form takes **repo as `owner/repo` text** or a host local-dir, behind a `RepoSource` seam (no picker in MVP). **Accept:** add/remove server; list; create→watch SSE→complete; start/stop/delete; sessions+images; token auto-refresh over a long session; all errors typed.

### M2 — RC sessions + URL hand-off (desktop) · **M**
`rc_models`/`rc_service`/`rc_classify`/`genSlug`; per-kind inner command; UI (list w/ derived state, create [kind+workdir], kill, copy/open URL, send prompt). **Accept:** create each kind; correct derived state; URL when ready; prompt delivers; kill removes; sessions byte-compatible with the `shed` CLI (`SHED_RC_*`, `SHED_RC_CREATED_BY=shed-mobile/<ver>`); POSIX quoting safe vs adversarial workdir/name.

### M3 — In-app terminal (desktop) · **L**
xterm.dart ↔ `tmux attach -t rc-<slug>` PTY; reconnect/resize; survive rekey; theming/copy-paste/scrollback. **Accept:** attach to a live RC session, type interactively, remote PTY tracks resize, multi-minute session stable across a rekey, detach/reattach + clean teardown.

### M4 — Android port + keygen + FGS · **L**
`flutter create --platforms=android .`; **`specialUse` foreground service** hosting the SSH isolate (notification, battery-opt whitelist, keepalive+reconnect); realize in-app `ed25519_keygen` + GitHub-paste onboarding UI + "Test connection"; soft-keyboard handling for xterm; MagicDNS `100.x` raw-IP fallback; verify Keystore durability (`allowBackup=false`). **Accept:** fresh install → generate key → paste into GitHub → connect to a `github_users`-trusting host → full M0–M3 flow on **google-pixel-8**; terminal usable with soft keyboard; PTY survives backgrounding for a documented window; keygen round-trip server-accepted.

### M5 — Polish · **M** (scope-dependent)
Repo picker via GitHub API (if in scope); machines (`machine:` targets) if in scope; empty/error states/a11y; macOS signing/notarization + Linux packaging + Android signing; iOS scaffold (deferred). **Accept:** per chosen feature; no M0–M4 regression; full analyze/format/test/build matrix green (macOS+Linux+Android).

```
M-init ─▶ M0 ─┬─▶ M1 ─┐
              └─▶ M2 ─┼─▶ M3 ─▶ M4 ─▶ M5
keygen spike (early; full UX at M4) ┘
```
Critical path: M-init→M0→M2→M3→M4. M1 ∥ M2 (both need only M0). M3 needs M2's slug. M4 needs M3 + realized keygen.

---

## 8. Local Test Skill, Validation Matrix & Fake-Server Harness

### `drive-shed-mobile` skill (clone tapper's `drive-tapper-app`)
`scripts/launch-and-connect.sh` (port: `flutter run -d macos|linux --dart-define-from-file`, grep Dart VM Service URI, http→ws, `marionette register shed-mobile <ws>`, keep-alive trap); `scripts/fake-shed-up.sh` (harness below); `references/{marionette-commands,shed-mobile-context,instrumenting-new-features}.md`.

**Instrumentation (port tapper's `marionette/`, `kDebugMode`-gated so it tree-shakes):** structured channels for what the tree can't show — `MSTATE screen=shed-list server=<host> shed-count=N mint=valid`, `MSTATE screen=rc state=ready slug=… url=…`, `MSTATE terminal bytes=N`; `MRESULT mint ok` / `shed-create ok` / `rc-kill ok`. `ValueKey`s on every control. **Hard-won tapper rules:** verify *effect* via `MSTATE`/`MRESULT` (poll, don't sleep); disabled tap = silent no-op; never drive GitHub-paste / native-permission surfaces → debug bypass `--dart-define DEV_SEED_KEY=true` loads a pre-generated test key (like tapper's dev-login OAuth bypass). `env/dev.json`: `SHED_FAKE_HOST/HTTPS_PORT/SSH_PORT`, `DEV_SEED_KEY`.

### Validation matrix — tiers (a) pure unit · (b) vs fake server · (c) real shed · (d) manual
Heaviest unit coverage on the 5 pure ports (SSE parser, RC classifier, token provider, fingerprint, POSIX quoting) — each has a golden TS test to translate case-for-case (`sse.ts`, `rc.test.ts`, `controlToken.test.ts`, `secureTransport.test.ts`, `exec.test.ts`). Keygen: (a) deterministic-from-seed + **round-trip via `fromPem`** + `ssh-keygen -y/-l` golden (c). Pinned-TLS + shed HTTP + SSE: (b) `HttpServer.bindSecure` self-signed (good pin connects, wrong pin rejects). Mint + shed-ext-rc + PTY: (b)→(c) real `sshd` with `authorized_keys` forced-commands (see harness); GitHub-paste→trust + real-infra E2E: (d).

### Fake-server harness
- **Fake HTTPS shed (pure Dart):** `HttpServer.bindSecure('127.0.0.1',0, SecurityContext()..useCertificateChain..usePrivateKey)`; expected pin = `sha256(DER leaf)`; canned JSON for CRUD + canned SSE for create; verify pinning both ways. Port of `secureTransport.test.ts`.
- **Fake SSH shed (REAL `sshd`, not embedded):** `fake-shed-up.sh` writes throwaway `sshd_config` + host key, runs `/usr/sbin/sshd -D -f <cfg> -p <port>` on 127.0.0.1 with `authorized_keys` forced commands: `_bootstrap`→shim prints a canned mint bundle (with `tls_cert_fingerprint` = the HTTPS harness pin); `<shed>`→shim dispatches on `$SSH_ORIGINAL_COMMAND` (`shed-ext-rc …`→canned DTO; `tmux attach …`→`exec bash`/`cat` for a real PTY). Gate sshd tests behind `command -v sshd`; degrade to (c) otherwise.

---

## 9. Per-Phase Execution Loop, Continuity (`/loop`), and Commits

### 9.0 Continuity model (large autonomous build)
- **Source of truth = committed `PROGRESS.md`** — every milestone→phase→task with `[ ]/[x]` + the commit SHA that closed it. State lives in git, so a context summarization/restart never loses the thread.
- **A self-paced (dynamic) `/loop`** drives execution: each iteration reads `PROGRESS.md`, picks the next unchecked unit, runs **one phase increment** through the gate below, commits, ticks the box, re-schedules. Stops when `PROGRESS.md` is complete (or at a milestone gate needing a human check). Heavy per-phase work uses a Workflow; commit cadence stays one-phase-at-a-time so progress is always reviewable/resumable. User can interrupt anytime; the loop resumes from `PROGRESS.md`.

### 9.1 Per-commit gate (NO PR)
| Gate | Action |
|---|---|
| **1 — Working + analyzed** | `tool/check.sh`: `pub get` → `dart format --set-exit-if-changed` → `flutter analyze` (zero) → `flutter test` (unit + (b) fake-harness; sshd tests skip where absent). New pure logic gets tests **before** UI; port TS test tables. |
| **1.5 — Drive smoke** (UI phases) | `fake-shed-up.sh` (or a real test shed) → `launch-and-connect.sh macos|linux` → drive new flow by `--key`, verify via `MSTATE/MRESULT` + screenshot → cleanup. M3/M4 add the manual terminal checklist. |
| **2 — `/simplify`** | run on the phase diff; re-run Gate 1. |
| **3 — `/codex:rescue`** | review the diff (esp. transport security: pin verification, fail-closed, POSIX quoting, no token leakage); apply fixes; re-run Gates 1–2. |
| **4 — Commit** | Conventional Commit (`feat(transport):`…) on a branch if a large/risky slice; append the required `Co-Authored-By` / `Claude-Session` trailers. No PR. |

**End-of-milestone gate:** Acceptance Criteria + validation pass before the next milestone. **Release-time (tier d):** GitHub pubkey-paste onboarding + real-infra E2E; `flutter build … --release` confirms the `kDebugMode` marionette/instrumentation tree-shakes out.

---

## 10. Risk Register (v2)

| # | Risk | Sev | Mitigation |
|---|---|---|---|
| 1 | ed25519 keygen + serialization | **Low** (was High) | dartssh2's `OpenSSHEd25519KeyPair.toPem()` + pinenacl; round-trip test in M0. |
| 2 | `flutter_secure_storage` backends | Med | macOS entitlement (Debug+Release); Android `allowBackup=false` + catch-and-reset on undecryptable; Linux libsecret → passphrase-encrypted-file fallback if absent. |
| 3 | `dart:io` pinning correctness | Low | Integration test vs real self-signed shed (M0); constant-time compare + explicit expiry recheck. |
| 4 | Host-key TOFU MITM at add-time | Med | Seed pin from pinned-TLS `/api/ssh-host-key` before bootstrap connect; show fingerprint; mismatch = hard fail. |
| 5 | Android background kill of PTY | Med (M4) | `specialUse` FGS hosting the SSH isolate; battery-opt whitelist; SSH keepalive + auto-reconnect + `tmux` re-attach. OEM killers can't be fully defeated — document. |
| 6 | Token leakage via SSH stdout/stderr | High | Never surface mint output on failure (`mintViaSSH`); tokens in-memory + secure storage only, never logs. |
| 7 | chacha20-poly1305-only sshd | Med | Verify shed offers AES-GCM/CTR (M0); surface mismatch as config error. Pin dartssh2 2.18.0. |
| 8 | `clientKind=shed-mobile` not a recognized server constant | Low | Mint still succeeds (kind recorded empty, like `shed-remote-agent`). Optional: add `ClientMobile` to shed `authtoken` later. |
| 9 | `flutter_secure_storage` Linux headless | Low | Desktop dev runs in a normal session; document passphrase fallback for headless. |
| 10 | GitHub key propagation latency (~1h) | Med | Explain in UI; "Test connection" retry; actionable "key not authorized / enforce required". |
| 11 | Encrypted legacy EC `~/.ssh` key | Low | `isEncryptedPem` + passphrase prompt; typed "unsupported (EC), generate in-app". |
| 12 | SSH isolate contention | Med | Per-stream `ReceivePort`; profile; second isolate for terminal if jank. |
| 13 | shed-ext-rc missing (exit 127) | Low | Typed `ShedExtRcMissing`; `SHED_EXT_RC_BIN` dev override. |
| 14 | MagicDNS `100.x` on Android | Low (M4) | Raw Tailscale IP entry; desktop unaffected. |
| 15 | No embedded SSH test server | Low | Real-sshd-forced-command harness; skip behind `command -v sshd`. |

---

## 11. Open Decisions (remaining)

Resolved: repo name (`shed-mobile`, private) · enrollment (GitHub keys) · Android scope (full incl. terminal+FGS) · toolchain (Flutter 3.44.2) · mint string (`control shed-mobile`) · clientKind (`shed-mobile`). **Remaining:**
1. **Test sheds** — create `shed-mobile-test` (or chosen name) on **mac-mini (localhost)** + **mini3** at build-start once the in-flight 0.7.x update settles (`shed list` currently `[]`).
2. **Android device** — assume **google-pixel-8** (online on tailnet) for M4.
3. **M5 scope** — repo picker (GitHub API/PAT) and `machine:` targets: defer past v1 (default) or include?
4. **iOS** — confirm out of scope for this build (scaffold only at most).

---

## 12. Reference Map (capability → port source)

| Capability | Go | TS (orchestrator) | Other |
|---|---|---|---|
| Bootstrap mint | `sdk/bootstrap.go`; `internal/sshd/bootstrap.go` (`mintBootstrap`) | `controlToken.ts` (`mintViaSSH`) | — |
| Add-server flow | `cmd/shed/server.go` (`runServerAdd`,`confirmHostKey`) | — | — |
| Token bundle parse | `bootstrap.go` (shape) | `controlToken.ts` (`parseTokenBundle`) | `controlToken.test.ts` |
| Token provider FSM | — | `controlToken.ts` (`ControlTokenProvider`,`nameJitter`) | `controlToken.test.ts` |
| Pinned-TLS | — | `secureTransport.ts` | `secureTransport.test.ts` |
| shed HTTP + SSE create | — | `shedClient.ts` | `shedClient.test.ts` |
| SSE parser | — | `packages/shared/src/sse.ts` | tapper `sse_client_test.dart` |
| SSH key allowlist (GitHub) | `internal/sshd/keyauth.go` | — | — |
| SSH routing (`_bootstrap`/`<shed>`) | `internal/sshd/session.go` | — | — |
| RC convention + DTO | `shed-extensions/internal/rc/rc.go`; `cmd/shed-ext-rc` | `rc.ts`,`shedRc.ts` | `rc.test.ts`,`shedRc.test.ts` |
| RC classifier | — | `rc.ts` (`classifyPane`,`extractUrl`,`probeUntilReady`) | `rc.test.ts` |
| Terminal PTY | — | `rcAttach.ts` (`openAttach`,`MAX_TERM_DIM`) | `rcAttach.test.ts` |
| POSIX quoting | — | `shell.ts` | `exec.test.ts` |
| SSH error classify | (≈`ErrHostKeyMismatch`) | `ssh.ts` (`classifySSHError`) | — |
| ed25519 keygen/serialize | (`ssh-keygen -y/-l` golden) | — | dartssh2 `OpenSSHEd25519KeyPair`; pinenacl |
| Local-test skill + driving | — | — | `tapper/.claude/skills/drive-tapper-app/*`, `tapper/.../marionette/*`, CI `flutter-check` |

---

## 13. v3 — Panel-incorporated corrections (Codex + CodeRabbit; these SUPERSEDE earlier sections on conflict)

### Security / transport
- **S1 — TLS pin always-checked (fixes a fail-open).** Build the pinned `HttpClient` from `SecurityContext(withTrustedRoots: false)` so EVERY server cert fails default validation and `badCertificateCallback` always runs the pin check — including a CA-valid-but-wrong cert. Never accept on the default path. Test with self-signed AND a CA-valid wrong cert.
- **S2 — Add-server flow (REPLACES §4).** (1) Dial `https://host:httpsPort` accepting any cert in the callback for THIS first contact only; capture leaf DER → `sha256`; **show + require explicit user confirmation** of the TLS fingerprint (this is TLS TOFU; security rests on Tailscale peer auth + out-of-band confirmation). (2) Build the pinned client from that fingerprint. (3) `GET /api/info` over the pinned client; **branch on `auth_mode == 'secure'`** — do NOT look for `enforce` (separate SSH-allowlist axis, not in `/api/info`); reject `open`. (4) `GET /api/ssh-host-key` → `SHA256:<b64>`, show + confirm, store. (5) Bootstrap mint over SSH (host key verified vs the confirmed pin). (6) **Require** bundle `tls_cert_fingerprint` present + well-formed + == the confirmed TLS pin (reject missing/empty/mismatch; do NOT inherit TS's skip-when-absent). (7) Persist.
- **S3 — Host-key trust.** The verify handler accepts ONLY a pre-confirmed expected pin. Blind TOFU is a `kDebugMode`+test-host shortcut only, never the release default (mirrors Go `confirmHostKey` refusing silent trust non-interactively). On mismatch/re-pin, **evict pooled SSH clients** for that host immediately.
- **S4 — No secret leakage.** `MSTATE/MRESULT`, logs, and errors NEVER emit token or private-key bytes. `DEV_SEED_KEY` loads a throwaway test key only. (Extends Risk #6 to the device's debug surfaces.)
- **S5 — Token persistence.** In-memory token authoritative; a fresh device has **no seed token** → drop/guard the `seedToken` branch. If persisted, bind to `host|sshPort|apiUrl|tlsFp|keyIdentityId`; clear on any change; never log.

### Port fidelity (do NOT bill these as "verbatim")
- **P1 — PTY resize REJECTS** out-of-range/non-integer dims (return null / no-resize), matching `rcAttach.ts parseControlMessage` (NOT clamp).
- **P2 — shed-ext-rc contract (M2):** port `shedRc.ts` fully — `create/list/probe/prompt/kill`; exit 2 `RcBadRequest`/3 `RcSlugTaken`/4 `RcNotFound`/127 missing; flags `--prompt-stdin`, `--session-id`, `--permission-mode`, `--skip`. **SSH RPC must support stdin** (write then close) for `--prompt-stdin`/`prompt`; empty-stdin→exit 2 test.
- **P3 — Autonomy controls:** expose/default `--permission-mode`/`--skip` for unattended sessions.
- **P4 — Bounded memory:** cap collected stdout/stderr from `runWithResult`; cap SSE line/event buffer (TS has no cap — don't inherit the DoS surface).
- **P5 — Labels:** `classifySSHError`'s `hostKeyMismatch` + pinned host keys are a deliberate **security upgrade** over `ssh.ts` (`accept-new`), not a port; `constantTimeEquals` is an addition (harmless on a public fingerprint).
- **P6 — DTO/validation:** `/api/info` is `open`|`secure` only; include `backend` (always) + `http_port` (open mode). In `parseTokenBundle`, when a pin is already configured, **require** the bundle field present (don't silently skip).
- **P7 — `shellQuote` empty-string `'' → ''`** edge reproduced + tested.

### Tests / harness
- **T1 — No fake sshd.** The forced-command sshd harness is infeasible (`_bootstrap`/`<shed>` aren't OS users). SSH-path tests (mint, shed-ext-rc, PTY) run against the **real test sheds** (tier c). Keep the pure-Dart **fake HTTPS** server for pinning/HTTP/SSE (tier b).
- **T2 — Fresh tests, no golden assumed.** No `sse.test.ts` / `classifySSHError` test exist; `exec.test.ts` is the local path. Author **fresh Dart tests** from behavior for the SSE parser + SSH-error classifier; port `controlToken.test.ts` (11 cases) + `rc.test.ts` which DO exist.
- **T3 — Time-dependent criteria** verified by fake-401-once + injected clock (`fake_async`/`Now`), never "run for hours".

### Autonomous execution
- **A1 — Acceptance tiering (REQUIRED).** Tag every criterion: **(a) loop**=unit · **(b) loop**=fake-HTTPS · **(c) real shed** · **(d) human/hardware**. The `/loop` self-certifies only (a)/(b); at any (c)/(d) gate it **records a BLOCKED item in `PROGRESS.md` and stops-and-asks** rather than self-ticking. Desktop M0–M3 (c) gates run against the real `shed-mobile-test` sheds — the loop CAN drive those from this machine via the already-trusted `~/.ssh/id_ed25519`. M4 (d) gates (GitHub key paste + pixel-8) are the genuine human stops.
- **A2 — Gates are concrete.** "/simplify" = run the `/simplify` skill on the phase diff, re-run `make check`. "/codex:rescue" = run the `codex:rescue` skill on the diff, apply fixes, re-run checks. Record a one-line gate result in the commit body; tick `PROGRESS.md` with the commit SHA.
- **A3 — M0 task 1 = real API smoke** against `shed-mobile-test@localhost:2222`: generate→toPem→fromPem→`authenticated`; one `runWithResult` (assert exitCode/stdout/stderr split); one PTY attach; assert `onVerifyHostKey(type, fingerprint)` shape. Catches any dartssh2/pinenacl signature drift in task 1, before §5b is built on it.
- **A4 — M0 = full token FSM** (not "minimal"): complete `ControlTokenProvider` + ported tests.
- **A5 — Pins verified at M-init** via `pub get` (targets, not facts): `flutter_secure_storage` (tapper uses ^9.2.4; current ^10.3.1), `dartssh2 2.18.0`, `flutter_foreground_task ^9.2.2`, `xterm ^4.x`.
- **A6 — CI is an adaptation, not a tapper clone.** tapper CI has no `dart format` step, plain `flutter_lints` (+`experimental_member_use: ignore`), a Makefile gate, AAB→Play release. shed-mobile deliberately differs (private/sideload): keep stricter lints + format gate, use a **Makefile** (`make check`) for tapper-like ergonomics, **pin Flutter `3.44.2` exactly** in CI (don't trust `channel: stable`), add `flutter build linux` smoke from M0 + a macOS job once entitlements land. `DEV_SEED_KEY` has no tapper analog — document it.

### Test targets (resolves Open Decision #1 — DONE)
`shed-mobile-test@localhost:2222` (mac-mini, TLS pin `sha256:8c52…86e6`) · `shed-mobile-test@mini3:2222` (mini3, pin `sha256:c009…8119`) · mini2 pin `sha256:1aa0…5d85`. Desktop reuses the already-trusted `~/.ssh/id_ed25519` (no GitHub-propagation delay). `clientKind=shed-mobile` → empty audit kind (fine); optional `ClientMobile` in shed later.

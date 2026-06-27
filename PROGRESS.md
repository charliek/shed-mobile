# shed-mobile — build progress

Live status for the autonomous build. **Source of truth** — each phase resumes from here.

**Per-phase loop:** implement → unit tests → `make check` (format + analyze + test) → `/simplify` → `/codex:rescue` → commit (Conventional Commit, no PR).

**Acceptance tiers:** (a) unit · (b) fake-HTTPS server · (c) real test shed · (d) human/hardware. The loop self-certifies (a)/(b)/(c). It **STOPS** at (d) gates and records them under "Human-gated items".

**Test targets:** `shed-mobile-test@localhost:2222` (mac-mini, TLS pin `sha256:8c52…86e6`) · `shed-mobile-test@mini3:2222` (mini3, TLS pin `sha256:c009…8119`). Desktop reuses `~/.ssh/id_ed25519` (already GitHub-trusted; no propagation wait).

---

## ⛔ Human-gated items (need Charlie)
- [ ] **(M4)** Paste the app-generated ed25519 **public key** into GitHub → Settings → SSH and GPG keys (trusts the pixel-8 key via `auth.ssh.github_users`; ~1h propagation).
- [ ] **(M4)** Have **google-pixel-8** awake + connected (USB or wireless adb) for the on-device pass.

---

## M-init — repo + scaffold + CI
- [x] gh repo create charliek/shed-mobile (private)
- [x] flutter create (macos, linux)
- [x] pubspec deps + strict analysis_options + Makefile + PROGRESS + README + docs/PLAN
- [x] .github/workflows/ci.yml (Flutter 3.44.2 pinned; format/analyze/test + linux build)
- [x] `make check` green (deps resolve, analyze clean, test pass); commit + push to main
- [x] CI green on main (after adding libsecret-1-dev/libjsoncpp-dev for the Linux build)

## M0 — transport spike (desktop)  [critical path]
- [x] T1: real dartssh2/pinenacl API smoke vs shed-mobile-test@localhost (c) — SMOKE PASS
- [x] core ports: shell_quote, sse_parser (capped), fingerprint, app_error + 19 unit tests (a)
- [x] key import (~/.ssh/id_ed25519; passphrase guard) — KeyManager (a/c)
- [x] host_key_store TOFU/seeded pins + tests (a)
- [x] pinned HttpClient (SecurityContext withTrustedRoots:false, always-checked) (b/c)
- [x] parseTokenBundle (fail-closed) + ServerTarget model + tests (a)
- [x] bootstrap mint over SSH (`control shed-mobile`) + parseControlBundle (c)
- [x] full ControlTokenProvider FSM + ported controlToken.test.ts cases (a) — 43 tests
- [x] listSheds over pinned TLS + 401-retry (c) — full interactive AddServerFlow UI is M1
- [x] ACCEPT: e2e PASS vs real shed — TOFU host key → mint → pinned `GET /api/sheds` lists `shed-mobile-test=running`; pin/token validated

## M1 — server mgmt + shed CRUD + create-SSE (desktop)
- [x] server registry: SecretStore + ServerStore + ServerRecord (add/remove/persist; multi-host) + tests (a)
- [x] AddServerFlow (SSH-mint preview -> confirm fingerprints -> persist) (a)
- [x] full ShedClient port (get/start/stop/delete/sessions/killSession/images) (b)
- [x] createShed SSE (postSse over pinned client) + DTOs (sealed ShedCreateEvent) (a/b)
- [x] marionette drive infra + .claude/skills/drive-shed-mobile (cloned tapper patterns)
- [x] desktop UI: server list / add-server (mint+confirm) / shed list (start/stop/delete) / create (SSE)
- [x] FileSecretStore for desktop (0600 atomic); macOS app-sandbox removed (personal tool)
- [x] ACCEPT: drive-verified on macOS — add server localhost (mint+TOFU+persist) → list → start/stop. (Create UI built; not yet drive-run against a real VM-provision.)

## M2 — RC sessions via shed-ext-rc (desktop)
- [x] rc_models (RcKind/RcState/RcSession DTO) + golden-DTO cross-check (byte-identical to shed-extensions fixture) + tests (a). **`rc_classify` intentionally NOT ported**: shed-ext-rc classifies panes server-side and returns `state`/`url` in the DTO, so a client classifier would be dead code (the machine/inline-tmux path that needs it is deferred). Documented in the commit.
- [x] ssh_runner (reusable `<shed>@host` exec) + ssh_connection (shared connect/teardown primitive + `classifySshException`); BootstrapService.mint refactored onto it (no more duplicated connection) (a/c)
- [x] rc_service: create/list/kill/prompt; exit 2/3/4/127 → AppError (domain codes before missing-binary check); --prompt-stdin (stdin) / --permission-mode / --session-id; DTO shape-failure → RC_FAILED 502 (a/c)
- [x] genSlug (unambiguous alphabet) + tests (a); UI shed-detail (list w/ derived-state chip / create kind-picker+workdir+prompt+skip / kill / copy+open claude.ai URL)
- [x] ACCEPT: drive-verified on macOS (create claude-rc → state=ready + real claude.ai URL → list count=1 → copy → kill → count=0) + raw `tool/e2e_rc.dart` (shell+claude-rc create/list/kill/idempotent-kill PASS vs real shed); provenance `SHED_RC_CREATED_BY=shed-mobile/<ver>`. /simplify: extracted shared SSH connection primitive (collapsed BootstrapService dup), classifySshException, named-record provider key, dedup kickoff, no-refresh-on-cancel/failed-kill. /codex:rescue: 7/8 clean (host-key pin enforced, no token leak, injection-safe, stdin-EOF ok); fixed DTO shape-failure → typed 502 (+4 tests). **M2 COMPLETE.**

## M3 — in-app terminal (desktop)  [L]
- [x] PtySession: long-lived dartssh2 PTY (`tmux attach -t rc-<slug>`) built on the shared `withSshClient` primitive; clampPtyDim [1,1000]; rcAttachCommand (POSIX-quoted); write/resize tolerate teardown races; detach ≠ kill (a)
- [x] xterm.dart TerminalScreen: onOutput→stdin, onResize→PTY resize, chunked Utf8Decoder→terminal.write; reconnect; keyed detach; terminal button on every RC tile (a)
- [x] buildPtySession factory + pinnedHostKeysFor (dedup across mint/RC/PTY); terminal screen owns the live session (no autoDispose-Ref-mid-connect bug)
- [x] ACCEPT: raw `tool/e2e_pty.dart` (attach → `echo` round-trips → resize 120x40 → detach → session survives → kill) PASS vs real shed; macOS drive (attach shell → live shell+tmux render → detach survives → reattach → kill) PASS. /simplify: dropped per-chunk log flood, extracted buildPtySession, assign-before-start teardown, killed dead branches. /codex:rescue: 6/8 clean (host-key pin enforced, injection-safe, dims clamped); fixed dispose-during-connect leak + write/resize teardown-race. **Multi-minute-across-rekey is the remaining manual (tier d) check** (dartssh2 2.18.0 pinned for the AES-GCM rekey fix). **M3 COMPLETE (desktop; manual rekey-soak pending).**

## M4 — Android port + keygen + FGS  [L, human-gated]
- [x] **M4a:** flutter create --platforms=android (org com.charliek.shed); manifest hardened (INTERNET, allowBackup=false, fullBackupContent=false)
- [x] **M4a:** in-app ed25519 keygen (KeyManager.generateEd25519 + GeneratedKey/PublicIdentity; verified byte-identical to `ssh-keygen -y`/`-l`) + IdentityStore (secure-storage; both-or-nothing write w/ rollback; undecryptable-read reset) + GitHub-paste onboarding screen + needsOnboardingProvider gate (mobile-only) + platform-aware identitiesProvider. 95 unit tests; **`flutter build apk --debug` green**; desktop drive still reaches the server list through the gate.
- [x] **M4b:** specialUse foreground service (flutter_foreground_task 9.2.2) keeping the SSH/terminal session alive when backgrounded — `ShedForegroundService` (Android-only, best-effort, start-on-attach/stop-on-detach with race-safe `_wantRunning` intent, battery-opt + notification-permission requests, generic lock-screen text); manifest service (specialUse + subtype property) + permissions. Soft-keyboard handled by `windowSoftInputMode=adjustResize` + Scaffold; MagicDNS via the add-server host field (accepts `100.x`). 95 tests; **apk builds** (KGP-deprecation warning only). /simplify + /codex:rescue (fixed start/stop orphan race + lock-screen leak + unused-permission) applied. **M4 CODE COMPLETE.**
- [ ] ⛔ **ACCEPT (d) — human-gated:** fresh install → generate key → paste pubkey into GitHub → connect to a `github_users`-trusting host → full M0–M3 flow on **google-pixel-8**; terminal usable with soft keyboard; PTY survives backgrounding

## M5 — polish + packaging
- [x] Release builds verified: `flutter build apk --release` + `flutter build macos --release` green; **Marionette/debug instrumentation tree-shaken out** of the release AOT binary (case-sensitive MSTATE/MRESULT/marionette/logDrive = 0; real app strings present). Full matrix green (macOS+Android local, Linux via CI; analyze/format/test).
- [x] Android release-signing scaffold: `build.gradle.kts` reads `android/key.properties` if present (keystore + key.properties gitignored), else falls back to debug signing for local sideload. README documents the setup.
- [x] README: status table, build/release commands, drive/e2e tooling, Android signing, and the explicit human gates (on-device accept, macOS notarization, FGS background-survival) + deferred seams.
- [ ] ⛔ **Human-gated:** macOS signing/notarization (Apple Developer cert); a real release keystore for Android distribution.
- [ ] (deferred seams) repo picker (OAuth/public) + `machine:` targets + iOS — architecture leaves seams; not pulled into scope. (Nice-to-have noted by /simplify: a shared error/async-action widget across the 4 form screens.)

## M6 — UI polish & feature gaps  (panel-reviewed; see docs/PLAN-ui-polish.md)
- [x] **Phase 0a:** fixed the create-shed Create button (never enabled — no rebuild on name input; added controller listeners). New `lib/shed/shed_name.dart` (`validateShedName` mirroring the server regex, `suggestShedName` repo→name) + `CreateShedRequest.fromForm`. Inline validation + auto-suggest (won't clobber a typed name). 108 tests; drive-verified on Pixel 8 emulator (button enables, repo auto-suggests a valid name, create end-to-end `shed-create ok`, delete ok).
- [x] **Phase 0b:** SSH identity screen (view/copy public key + fingerprint; mobile-only guarded regenerate). Shared `fingerprintOfBlob` (DRY with keygen) + `PublicIdentity.fromBlob`/`fromAuthorizedKeyLine` (validates embedded type); `publicIdentityProvider` (public-only) + `canRegenerateKeyProvider`; settings/key entry on the server list. 116 tests; drive-verified on the emulator (shows the stored key + `SHA256:` fp, copy ok, regenerate confirm→cancel keeps the key). /codex:rescue fixed a lax parser + a disposed-ref-on-regenerate (invalidate via the container).
- [ ] **Phase 1:** terminal mobile key toolbar + font size + paste.
- [ ] **Phase 2:** create-shed Image picker + Advanced (cpus/memory/no_provision).
- [ ] **Phase 3:** create-RC session name + permission-mode picker.

---

## Log
- 2026-06-27: M6 Phase 0b — SSH identity screen (view/copy/regenerate). Shared `fingerprintOfBlob` (one fingerprint source for keygen + parser), `PublicIdentity.fromBlob`/`fromAuthorizedKeyLine` (rejects a blob whose embedded type ≠ the token), `publicIdentityProvider` (PublicIdentity, public-only — never the PEM/load()) + `canRegenerateKeyProvider` (keeps Platform out of the widget), AppBar key entry on the server list. Guarded regenerate (container-based invalidation survives a mid-generate dispose; warns GitHub+servers). 116 tests (parser round-trip/options/comment/malformed/type-mismatch + provider public-only); emulator drive (shows stored key + SHA256 fp, copy ok, regen confirm→cancel). /simplify (DRY keygen via fromBlob) + /codex:rescue (lax-parser + disposed-ref fixes).
- 2026-06-27: M6 Phase 0a — fixed the create-shed Create button (added `_name`/`_repo` controller listeners so the button + validation rebuild on input; it never enabled before). New pure `lib/shed/shed_name.dart` (`validateShedName` = server regex `^[a-z][a-z0-9-]*[a-z0-9]$`, ≤63; `suggestShedName` repo→sanitized name) + `CreateShedRequest.fromForm`; inline errorText; auto-suggest that won't overwrite a typed name. 108 tests; drive-verified on the Pixel 8 emulator (disabled-when-empty → repo auto-suggests `my-test-repo` from `charliek/My_Test.Repo.git` → enabled → base shed create end-to-end → delete). /simplify (moved builder to `fromForm`, hoisted nameError) + /codex:rescue (no bugs). Plan panel-reviewed (Codex+CodeRabbit) in docs/PLAN-ui-polish.md (9679430).
- 2026-06-26: M-init started; repo + Flutter scaffold (macos, linux) created.
- 2026-06-26: M-init complete — deps resolve (no conflicts), `make check` green, pushed initial commit. Review gates (`/simplify` + `/codex:rescue`) begin at M0 where real logic lands; M-init is scaffold/config only.
- 2026-06-26: Pre-M0 validation — ~/.ssh/id_ed25519 unencrypted; shed-mobile-test routing OK (shed-ext-rc/tmux/claude present); `_bootstrap 'control shed-mobile'` mint confirmed (bundle pin matches mac-mini).
- 2026-06-26: M0 phase-1 — API smoke (PASS) + core ports (shell_quote/fingerprint/sse_parser/app_error), 19 tests. /simplify: cursor line-scan, dropped constant-time ceremony, renamed caps. /codex:rescue: per-line cap (DoS), AppError status→502 (errors.ts fidelity). Committed 87c24f8.
- 2026-06-26: M0 phase-2 — credential FSM (ServerTarget, parseTokenBundle, ControlTokenProvider), +18 tests (37 total). /codex:rescue: closed an in-flight-mint identity race the TS source leaves open (bound _inflight to identity + regression test). Committed 83f294c.
- 2026-06-26: CI green — added libsecret-1-dev/libjsoncpp-dev for the Linux desktop build (58c8d30).
- 2026-06-26: M0 phase-3 — pinned-TLS client + SSH mint + host-key store + KeyManager + listSheds; tool/e2e_list.dart E2E PASS vs real shed (mint→pin→pinned GET /api/sheds → shed-mobile-test=running). 43 tests. /codex:rescue: fixed 401-retry token reuse + final-401 class, out-of-range https_port, raw-socket leak on construct failure. **M0 COMPLETE.**
- 2026-06-26: M1 data — server store + add-server flow + full ShedClient CRUD + create-SSE (46 tests). Committed 4b1f4e4.
- 2026-06-26: M1 UI — riverpod providers + screens (server list / add-server / shed list / create) + drive-shed-mobile skill (cloned tapper). FileSecretStore (desktop) + macOS sandbox removed + network entitlements. Drive-verified on macOS: add localhost → list → start/stop. /codex:rescue: create-SSE 401-retry, postSse error mapping, pinned-client autoDispose leak, atomic 0600 secret writes, setState-after-dispose guard. Mint hardened (trust stdout, not null exit code). **M1 COMPLETE.**
- 2026-06-26: M2 — RC sessions via shed-ext-rc over SSH. New: ssh_runner + ssh_connection (shared connect/teardown primitive + transport classifier), rc_models (DTO + golden cross-check), rc_service (create/list/kill/prompt, exit-code mapping, genSlug), url_launcher dep, shed-detail + create-rc UI, rcServiceProvider/rcSessionsProvider. BootstrapService.mint refactored onto SshRunner. 83 unit tests; raw `tool/e2e_rc.dart` PASS; macOS drive-verified (claude-rc → ready + URL → kill). /simplify (4 agents) + /codex:rescue applied. `rc_classify` skipped by design (server-side classification). **M2 COMPLETE.** commit 049b81d.
- 2026-06-27: M5 — polish + packaging. Verified release builds (apk + macOS) green and that the kDebugMode Marionette instrumentation tree-shakes out of the release AOT (0 MSTATE/MRESULT/marionette symbols). Android release-signing scaffold (key.properties-driven, debug fallback). Comprehensive README (status, build/release, drive/e2e, signing, human gates, deferred). Full matrix green. Signing/notarization + repo-picker/machines/iOS remain human-gated/deferred. **PLAN COMPLETE** to the limit of available credentials/hardware; on-device pixel-8 acceptance is the standing human gate.
- 2026-06-27: M4b — Android specialUse foreground service (flutter_foreground_task) keeping the SSH/terminal session alive when backgrounded; ShedForegroundService (Android-only, best-effort, race-safe start/stop), manifest service + FGS permissions, battery-opt request. soft-keyboard via adjustResize; MagicDNS via host text. 95 tests; apk builds. /simplify + /codex:rescue (fixed orphan-service race, lock-screen notification leak, unused battery permission). **M4 CODE COMPLETE** — on-device pixel-8 acceptance (key→GitHub→full flow, background survival) remains the human gate.
- 2026-06-27: M4a — Android platform + in-app ed25519 keygen. `flutter create --platforms=android` (org com.charliek.shed); KeyManager.generateEd25519 (pinenacl→dartssh2 OpenSSH; spike-verified vs `ssh-keygen`), IdentityStore (secure storage, rollback + undecryptable-reset), onboarding screen, needsOnboardingProvider gate, manifest hardening. 95 tests; apk builds; desktop drive unaffected. /simplify (dropped dead keyPair field, public-only generateAndStore, fixed desktop-onboarding-loop via needsOnboardingProvider, hoisted _isMobile) + /codex:rescue (fixed partial-write durability + Keystore-invalidation crash-loop) applied. FGS/soft-keyboard/MagicDNS = M4b; on-device accept = human gate.
- 2026-06-27: M3 — in-app terminal. New: ssh/pty_session (long-lived PTY on withSshClient; clamp/attach-command/write-resize teardown-tolerance), features/terminal/terminal_screen (xterm), buildPtySession factory + pinnedHostKeysFor dedup, terminal button on RC tiles, tool/e2e_pty. 86 unit tests; raw e2e_pty PASS; macOS drive-verified (attach→render→detach-survives→reattach→kill). /simplify (4 agents) + /codex:rescue (fixed dispose-during-connect leak + write/resize race) applied. Found+fixed an autoDispose-Ref-mid-connect bug via the drive. **M3 COMPLETE** (desktop; manual rekey-soak is the remaining tier-d check).

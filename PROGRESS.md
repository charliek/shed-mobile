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
- [ ] xterm.dart ↔ dartssh2 PTY (`tmux attach`); reject out-of-range dims; reconnect/resize
- [ ] ACCEPT: interactive multi-minute session stable across rekey; clean teardown (c + manual)

## M4 — Android port + keygen + FGS  [L, human-gated]
- [ ] flutter create --platforms=android
- [ ] in-app ed25519 keygen + GitHub-paste onboarding + "Test connection"
- [ ] specialUse foreground service hosting SSH isolate; soft-keyboard; MagicDNS 100.x fallback
- [ ] ACCEPT (d): fresh install → key→GitHub → connect → full flow on pixel-8

## M5 — polish + packaging
- [ ] macOS signing/notarize; Linux packaging; Android signing; a11y/empty/error states
- [ ] (deferred seams) repo picker (OAuth/public) + machines targets — only if pulled into scope

---

## Log
- 2026-06-26: M-init started; repo + Flutter scaffold (macos, linux) created.
- 2026-06-26: M-init complete — deps resolve (no conflicts), `make check` green, pushed initial commit. Review gates (`/simplify` + `/codex:rescue`) begin at M0 where real logic lands; M-init is scaffold/config only.
- 2026-06-26: Pre-M0 validation — ~/.ssh/id_ed25519 unencrypted; shed-mobile-test routing OK (shed-ext-rc/tmux/claude present); `_bootstrap 'control shed-mobile'` mint confirmed (bundle pin matches mac-mini).
- 2026-06-26: M0 phase-1 — API smoke (PASS) + core ports (shell_quote/fingerprint/sse_parser/app_error), 19 tests. /simplify: cursor line-scan, dropped constant-time ceremony, renamed caps. /codex:rescue: per-line cap (DoS), AppError status→502 (errors.ts fidelity). Committed 87c24f8.
- 2026-06-26: M0 phase-2 — credential FSM (ServerTarget, parseTokenBundle, ControlTokenProvider), +18 tests (37 total). /codex:rescue: closed an in-flight-mint identity race the TS source leaves open (bound _inflight to identity + regression test). Committed 83f294c.
- 2026-06-26: CI green — added libsecret-1-dev/libjsoncpp-dev for the Linux desktop build (58c8d30).
- 2026-06-26: M0 phase-3 — pinned-TLS client + SSH mint + host-key store + KeyManager + listSheds; tool/e2e_list.dart E2E PASS vs real shed (mint→pin→pinned GET /api/sheds → shed-mobile-test=running). 43 tests. /codex:rescue: fixed 401-retry token reuse + final-401 class, out-of-range https_port, raw-socket leak on construct failure. **M0 COMPLETE.**
- 2026-06-26: M1 data — server store + add-server flow + full ShedClient CRUD + create-SSE (46 tests). Committed 4b1f4e4.
- 2026-06-26: M1 UI — riverpod providers + screens (server list / add-server / shed list / create) + drive-shed-mobile skill (cloned tapper). FileSecretStore (desktop) + macOS sandbox removed + network entitlements. Drive-verified on macOS: add localhost → list → start/stop. /codex:rescue: create-SSE 401-retry, postSse error mapping, pinned-client autoDispose leak, atomic 0600 secret writes, setState-after-dispose guard. Mint hardened (trust stdout, not null exit code). **M1 COMPLETE.**
- 2026-06-26: M2 — RC sessions via shed-ext-rc over SSH. New: ssh_runner + ssh_connection (shared connect/teardown primitive + transport classifier), rc_models (DTO + golden cross-check), rc_service (create/list/kill/prompt, exit-code mapping, genSlug), url_launcher dep, shed-detail + create-rc UI, rcServiceProvider/rcSessionsProvider. BootstrapService.mint refactored onto SshRunner. 83 unit tests; raw `tool/e2e_rc.dart` PASS; macOS drive-verified (claude-rc → ready + URL → kill). /simplify (4 agents) + /codex:rescue applied. `rc_classify` skipped by design (server-side classification). **M2 COMPLETE.**

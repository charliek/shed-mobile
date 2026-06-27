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
- [x] `make check` green (deps resolve, analyze clean, test pass); first commit + push to main

## M0 — transport spike (desktop)  [critical path]
- [x] T1: real dartssh2/pinenacl API smoke vs shed-mobile-test@localhost (c) — SMOKE PASS
- [x] core ports: shell_quote, sse_parser (capped), fingerprint, app_error + 19 unit tests (a)
- [ ] key import (~/.ssh/id_ed25519; passphrase guard) (a/c)
- [ ] host_key_store TOFU + confirm-before-persist (a)
- [ ] pinned HttpClient (SecurityContext withTrustedRoots:false) + fake-HTTPS pin tests (b)
- [ ] bootstrap mint (`control shed-mobile`) + parseControlBundle (require pin) (a/c)
- [ ] full ControlTokenProvider FSM + ported controlToken.test.ts cases (a)
- [ ] add-server flow per PLAN §S2; listSheds over pinned TLS (c)
- [ ] ACCEPT: TOFU host key → mint → pinned `GET /api/sheds` lists; mismatches abort (c)

## M1 — server mgmt + shed CRUD + create-SSE (desktop)
- [ ] server registry (add/remove/persist; multi-host) (a/b)
- [ ] full ShedClient port (CRUD/sessions/images) + tests (b)
- [ ] createShedSSE (capped buffers) + SSE parser tests (a/b)
- [ ] desktop UI: list/detail/create (repo as `owner/repo` text behind RepoSource seam)
- [ ] ACCEPT: add server; create→SSE→complete; start/stop/delete; sessions/images (c)

## M2 — RC sessions via shed-ext-rc (desktop)
- [ ] rc_models + rc_classify (verbatim regexes) + tests (a)
- [ ] rc_service: create/list/probe/prompt/kill; exit 2/3/4/127; --prompt-stdin/--session-id/--permission-mode/--skip; SSH stdin (b/c)
- [ ] genSlug; UI list/create/kill/copy-open URL/prompt
- [ ] ACCEPT: each kind; derived states; URL when ready; byte-compatible with shed CLI (c)

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
- 2026-06-26: M0 phase-1 — API smoke (PASS) + core ports (shell_quote/fingerprint/sse_parser/app_error), 19 tests. /simplify: cursor line-scan, dropped constant-time ceremony, renamed caps. /codex:rescue: per-line cap (DoS), AppError status→502 (errors.ts fidelity). Committed.

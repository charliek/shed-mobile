# Epic: Roost Pivot — shed-mobile's part

> Not a docs page; deliberately outside `docs/`. A pointer plus the rules
> that apply in this repo — never a copy of the roadmap.

**Why this exists — read first:**
https://claude.ai/code/artifact/add27f67-3d15-4541-bd3f-eda3f34fcc48
(Private — opens with the owner's claude.ai login. A 404 from anywhere
else is expected, not a broken link.)
Sections that matter here: §02 (the handoff matrix), §03 (the layering
rule), §04 Q2 (the terminal stays, demoted), Q12 (where a session lives),
§06 Track S.

**Tracking:** https://github.com/users/charliek/projects/4 —
`Epic: Roost Pivot`. Your PR body must contain
`Closes charliek/shed-mobile#<n>`. Status moves by itself when that
merges. Never edit board status by hand.

## This repo's items

| ID | issue | phase | one line |
|---|---|---|---|
| S3m | [#15](https://github.com/charliek/shed-mobile/issues/15) | RP/M1 | the phone reads inventory + status from a `roost-session` over the SSH forward — **the priority client** |
| S4m | [#19](https://github.com/charliek/shed-mobile/issues/19) | RP/M3 | the phone reads and drives a machine's agent lane — transcript, approvals, questions, composer — over shed_core::lane's Rust-owned bridge (plan 018) |

S3m proved M1 on the device that matters; S4m delivers M3's content
(transcript, prompt, approve), mirroring shed's A4 lane DTOs and consuming
gx's A3 approvals over the same bridge. Live push follows roost's R1;
terminal attach follows roost's R3.

## Rules that apply in this repo

- **No Dart reimplementation of the wire.** Roost's IPC is consumed
  through `shed-core`'s Rust client over the FRB bridge, exactly as the hub
  client is today. One Rust implementation serves every shed client; that
  is what ends the three-way transport drift.
- **Polling is acceptable until roost R1.** `tab.list` on an interval;
  `events.subscribe` when the lease re-cut lands. The reconnect/backoff
  invariants from plan 012 (reset on the common path, stable local port)
  must survive the swap.
- **The terminal stays, demoted.** Read-only peek via `tab.dump` now;
  interactive attach waits on roost's `vt` payload kind (R3). Do not
  invest in the in-app xterm beyond that.
- **Both `tmux_session` fields go.** `BridgeRcSessionDto.tmux_session`
  (the pre-enrichment Rust DTO FRB ignores) and
  `BridgeRcSession.tmux_session` (FRB-exported) — only the exported one
  reaches Dart, and it is that one's render sites that change.
  `kind_features.attach == native-remote` drives the attach affordance —
  every client already handles that value.
- **Card layout from plan 012 is the spec.** Name + badges, kind chip +
  workdir, `open → copy → launch` actions, bare trash. Re-source the data;
  do not redesign the cards.
- **Status is read, never derived.** Lifecycle and attention come from
  roost's four axes. No regexes in `lib/`.
- **Mobile leads.** Where shed and shed-mobile both change, this repo
  goes first.

## Cross-repo edges

- **S3m ← shed S1.** The roost client in `shed-core` must exist first;
  the FRB surface is regenerated from it.
- **S3m ← roost R1** for live push (not for M1 — polling is fine).
- **A4 (shed) → this repo — closed.** A4 landed in shed and merged at
  `e745d03`; the opencode lane crate it added is FRB-exposed here (S4m,
  plan 018) for the native transcript view.
- **A3 (gx) → this repo.** The gx remote API is what the phone's gx
  transcript and approvals consume; it is shaped for a client that
  reconnects (`Last-Event-ID` resume).
- The R4 acceptance path — phone → Tailscale SSH → mini3 — is the
  transport; nothing here changes it.

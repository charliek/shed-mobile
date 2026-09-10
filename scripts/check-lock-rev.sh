#!/usr/bin/env bash
# Lock-rev-equality guard (plan §3.1).
#
# The shed client core is pulled as a git+rev dependency. Local sibling-checkout
# dev uses a gitignored rust/.cargo/config.toml [patch] that swaps the git source
# for a local path — if that ever leaks into the committed Cargo.lock, CI would
# build a different (unpinned) core than the one the rev names. This asserts that
# ALL FOUR shed crates (shed-core, shed-app, shed-opencode, shed-gx) in
# rust/Cargo.lock resolve to the exact `rev = "…"` declared in rust/Cargo.toml —
# one rev shared by all four — with the canonical git source (never a local path).
#
# It ALSO checks `roost-ipc`, whose lock entry must match mobile's own manifest
# rev. What it deliberately does NOT check is that mobile's roost rev equals the
# one shed's `crates/Cargo.toml` pins: cargo enforces that itself, and far more
# loudly. Git deps unify on `(url, rev)`, so a mobile roost rev that differs from
# shed-core's puts TWO `roost-ipc` crates in one graph and `TabOpenParams` /
# `ssh::remote_command()` stop type-checking against the shed-core that consumes
# them. This script is belt-and-braces for that; the compile failure is the gate.
#
# Run from the repo root.
#
# Usage:
#   scripts/check-lock-rev.sh                 # the guard (CI + `make check-lock`)
#   scripts/check-lock-rev.sh --print-shed-rev  # print the pinned shed rev, exit 0
set -euo pipefail

TOML="rust/Cargo.toml"
LOCK="rust/Cargo.lock"

# Extract the pinned rev(s) for a single crate from Cargo.toml. Supports BOTH:
#   - inline table:   shed-core = { git = "…", rev = "…" }
#   - section form:   [dependencies.shed-core]  (or [<target>.dependencies.<crate>])
#                        git = "…"
#                        rev = "…"
# Prints one rev per match found (so the caller can require exactly one).
extract_rev() {
  local crate="$1"
  awk -v c="$crate" '
    function emit_rev(line,   tmp) {
      if (match(line, /rev[ \t]*=[ \t]*"[^"]+"/)) {
        tmp = substr(line, RSTART, RLENGTH)
        sub(/^rev[ \t]*=[ \t]*"/, "", tmp)
        sub(/".*$/, "", tmp)
        print tmp
      }
    }
    # Any section header: are we entering the [<…>dependencies.<crate>] table?
    /^\[/ {
      insec = ($0 ~ ("^\\[([^]]*\\.)?dependencies\\." c "\\]"))
      next
    }
    insec { emit_rev($0); next }
    # inline table form: "<crate> = { … }" (under a [dependencies] section)
    $0 ~ ("^" c "[ \t]*=") { emit_rev($0) }
  ' "$TOML"
}

# Look up the `source = …` line(s) for a crate in Cargo.lock, BOUNDED to that
# crate's own [[package]] block. A path/dev dependency has no source line;
# without the bound a source-less matching block would leak the NEXT package's
# source line.
#
# **EVERY matching block is printed, not just the first.** A lock can legally
# hold two [[package]] blocks with the same name at different sources — which is
# exactly what a rev disagreement PRODUCES — and a guard that read only the
# first would pass while a second, wrong-rev copy sat in the graph. Cargo does
# break loudly on that, but this script is the belt to cargo's braces and a belt
# that checks one notch is not one.
lock_source() {
  local crate="$1"
  awk -v c="$crate" '
    $0 == "[[package]]" { inblock = 0; next }
    $0 == "name = \"" c "\"" { inblock = 1; next }
    inblock && /^source = / { print; inblock = 0 }
  ' "$LOCK"
}

# Does every source line for `crate` contain `want`, and is there at least one?
# Prints what it found on failure. `$1` crate, `$2` expected substring.
lock_source_is_only() {
  local crate="$1" want="$2" srcs n bad
  srcs=$(lock_source "$crate")
  if [ -z "$srcs" ]; then
    echo "  found:                      <no source line>" >&2
    return 1
  fi
  n=$(printf '%s\n' "$srcs" | wc -l | tr -d ' ')
  bad=$(printf '%s\n' "$srcs" | grep -cvF -- "$want" || true)
  if [ "$bad" != "0" ]; then
    echo "  found $n source line(s), $bad of them wrong:" >&2
    printf '%s\n' "$srcs" | sed 's/^/    /' >&2
    return 1
  fi
  if [ "$n" != "1" ]; then
    echo "  note: $n blocks for $crate, all at the expected rev" >&2
  fi
  return 0
}

# The four shed crates, all pinned to ONE rev. shed-opencode/shed-gx joined in
# plan 018 (the agent-lane adapters); a manifest that let them drift from
# shed-core would silently link two shed trees.
SHED_CRATES="shed-core shed-app shed-opencode shed-gx"

REV=""
for crate in $SHED_CRATES; do
  revs=$(extract_rev "$crate")
  if [ -z "$revs" ]; then
    echo "check-lock-rev: could not find a 'rev = \"…\"' for $crate in $TOML" >&2
    exit 1
  fi
  n=$(printf '%s\n' "$revs" | sort -u | wc -l | tr -d ' ')
  if [ "$n" != "1" ]; then
    echo "check-lock-rev: $crate declares MULTIPLE distinct revs in $TOML:" >&2
    printf '%s\n' "$revs" >&2
    exit 1
  fi
  crate_rev=$(printf '%s\n' "$revs" | sort -u)
  if [ -z "$REV" ]; then
    REV="$crate_rev"
  elif [ "$REV" != "$crate_rev" ]; then
    echo "check-lock-rev: the shed crates pin DIFFERENT revs in $TOML:" >&2
    echo "  $crate pins '$crate_rev'; an earlier one of ($SHED_CRATES) pins '$REV'" >&2
    echo "  All four must name ONE rev — they are one tree." >&2
    exit 1
  fi
done

# `--print-shed-rev`: the agreed shed rev on stdout, for CI (the android-build
# job resolves the same rev the lock names). Nothing else is printed.
if [ "${1:-}" = "--print-shed-rev" ]; then
  printf '%s\n' "$REV"
  exit 0
fi

EXPECTED="git+https://github.com/charliek/shed?rev=${REV}#"
fail=0
for crate in $SHED_CRATES; do
  if lock_source_is_only "$crate" "$EXPECTED"; then
    echo "check-lock-rev: OK  $crate -> ${EXPECTED}"
  else
    echo "check-lock-rev: FAIL $crate in $LOCK does not resolve to rev=$REV" >&2
    echo "  expected every source line to contain: $EXPECTED" >&2
    fail=1
  fi
done

# roost-ipc: a different repo, its own rev, same rule — the lock must name what
# the manifest pins. (Whether that rev EQUALS shed's is cargo's job; see the
# header.)
roost_revs=$(extract_rev roost-ipc)
if [ -z "$roost_revs" ]; then
  echo "check-lock-rev: could not find a 'rev = \"…\"' for roost-ipc in $TOML" >&2
  exit 1
fi
n=$(printf '%s\n' "$roost_revs" | sort -u | wc -l | tr -d ' ')
if [ "$n" != "1" ]; then
  echo "check-lock-rev: roost-ipc declares MULTIPLE distinct revs in $TOML:" >&2
  printf '%s\n' "$roost_revs" >&2
  exit 1
fi
ROOST_REV=$(printf '%s\n' "$roost_revs" | sort -u)
ROOST_EXPECTED="git+https://github.com/charliek/roost?rev=${ROOST_REV}#"
if lock_source_is_only roost-ipc "$ROOST_EXPECTED"; then
  echo "check-lock-rev: OK  roost-ipc -> ${ROOST_EXPECTED}"
else
  echo "check-lock-rev: FAIL roost-ipc in $LOCK does not resolve to rev=$ROOST_REV" >&2
  echo "  expected every source line to contain: $ROOST_EXPECTED" >&2
  echo "  NOTE: if this rev also differs from the one shed's crates/Cargo.toml" >&2
  echo "  pins, the build breaks LOUDLY first — two roost-ipc crates in one" >&2
  echo "  graph, and TabOpenParams/remote_command stop type-checking. Two blocks" >&2
  echo "  for roost-ipc in the lock is that situation, already written down." >&2
  fail=1
fi

if [ "$fail" != "0" ]; then
  cat >&2 <<EOF

The committed Cargo.lock does not match the pinned rev in $TOML.
This usually means the gitignored rust/.cargo/config.toml [patch] leaked a local
path into the lock. Regenerate the lock canonically (with NO local [patch] active):

  ( cd rust && mv .cargo/config.toml /tmp/shed-mobile-cargo-patch.bak 2>/dev/null || true; \\
    cargo update -p shed-core -p shed-app -p shed-opencode -p shed-gx -p roost-ipc; \\
    mv /tmp/shed-mobile-cargo-patch.bak .cargo/config.toml 2>/dev/null || true )

then commit rust/Cargo.lock.
EOF
  exit 1
fi

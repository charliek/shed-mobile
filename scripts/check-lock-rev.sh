#!/usr/bin/env bash
# Lock-rev-equality guard (plan §3.1).
#
# The shed client core is pulled as a git+rev dependency. Local sibling-checkout
# dev uses a gitignored rust/.cargo/config.toml [patch] that swaps the git source
# for a local path — if that ever leaks into the committed Cargo.lock, CI would
# build a different (unpinned) core than the one the rev names. This asserts that
# BOTH shed-core and shed-app in rust/Cargo.lock resolve to the exact `rev = "…"`
# declared in rust/Cargo.toml, with the canonical git source (never a local path).
#
# Run from the repo root.
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

# Look up the `source = …` line for a crate in Cargo.lock, BOUNDED to that crate's
# own [[package]] block. A path/dev dependency has no source line; without the
# bound a source-less matching block would leak the NEXT package's source line.
lock_source() {
  local crate="$1"
  awk -v c="$crate" '
    $0 == "[[package]]" {
      if (matched) exit    # left the matching block without a source line
      matched = 0
      next
    }
    $0 == "name = \"" c "\"" { matched = 1; next }
    matched && /^source = / { print; exit }
  ' "$LOCK"
}

REV=""
for crate in shed-core shed-app; do
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
    echo "check-lock-rev: shed-core and shed-app pin DIFFERENT revs in $TOML:" >&2
    echo "  shed-core/shed-app disagree: '$REV' vs '$crate_rev'" >&2
    exit 1
  fi
done

EXPECTED="git+https://github.com/charliek/shed?rev=${REV}#"
fail=0
for crate in shed-core shed-app; do
  src=$(lock_source "$crate")
  case "$src" in
    *"$EXPECTED"*)
      echo "check-lock-rev: OK  $crate -> ${EXPECTED}"
      ;;
    *)
      echo "check-lock-rev: FAIL $crate in $LOCK does not resolve to rev=$REV" >&2
      echo "  expected source containing: $EXPECTED" >&2
      echo "  found:                      ${src:-<no source line>}" >&2
      fail=1
      ;;
  esac
done

if [ "$fail" != "0" ]; then
  cat >&2 <<EOF

The committed Cargo.lock does not match the pinned rev in $TOML.
This usually means the gitignored rust/.cargo/config.toml [patch] leaked a local
path into the lock. Regenerate the lock canonically (with NO local [patch] active):

  ( cd rust && mv .cargo/config.toml /tmp/shed-mobile-cargo-patch.bak 2>/dev/null || true; \\
    cargo update -p shed-core -p shed-app --precise <rev>; \\
    mv /tmp/shed-mobile-cargo-patch.bak .cargo/config.toml 2>/dev/null || true )

then commit rust/Cargo.lock.
EOF
  exit 1
fi

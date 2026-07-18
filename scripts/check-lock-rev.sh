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

# The single rev the shed git deps pin to (both crates must agree).
REV=$(grep -E '^shed-(core|app)\b' "$TOML" \
  | grep -oE 'rev = "[^"]+"' \
  | sed -E 's/rev = "([^"]+)"/\1/' \
  | sort -u)

if [ -z "$REV" ]; then
  echo "check-lock-rev: could not find a shed git rev in $TOML" >&2
  exit 1
fi
if [ "$(printf '%s\n' "$REV" | wc -l | tr -d ' ')" != "1" ]; then
  echo "check-lock-rev: shed-core and shed-app pin DIFFERENT revs in $TOML:" >&2
  printf '%s\n' "$REV" >&2
  exit 1
fi

EXPECTED="git+https://github.com/charliek/shed?rev=${REV}#"
fail=0
for crate in shed-core shed-app; do
  src=$(awk -v c="$crate" '
    $0 == "name = \"" c "\"" { found = 1; next }
    found && /^source = / { print; exit }
  ' "$LOCK")
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

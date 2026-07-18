#!/usr/bin/env bash
# 16 KB page-size gate (Google Play requirement for 64-bit ABIs) + native-lib
# size record. Shared by ci.yml (debug APK) and release-android.yml (AAB).
#
# Usage: check-16kb-alignment.sh <lib-root> <required-abi-csv>
#   <lib-root>          directory holding the <abi>/ subdirs
#                       (APK: <unzipped>/lib, AAB: <unzipped>/base/lib)
#   <required-abi-csv>  ABIs that MUST be present, comma-separated
#                       (a missing one = packaging regression = FAIL)
#
# Rules:
#   - EVERY *.so in a 64-bit ABI dir (arm64-v8a, x86_64) must have all ELF LOAD
#     segments aligned >= 0x4000. Not just our Rust lib — libflutter.so /
#     libapp.so / a plugin's lib would fail Play's validation just the same.
#   - 32-bit dirs (armeabi-v7a, x86) are size-recorded only: 16 KB pages exist
#     only on 64-bit devices and the NDK has no plans to align 32-bit output.
#   - An unrecognized ABI dir name FAILS (fail-closed: a future ABI must be
#     classified here deliberately, not silently skipped).
set -euo pipefail

LIB_ROOT=${1:?usage: check-16kb-alignment.sh <lib-root> <required-abi-csv>}
REQUIRED_CSV=${2:?usage: check-16kb-alignment.sh <lib-root> <required-abi-csv>}

test -d "$LIB_ROOT" || { echo "FAIL: lib root not found: $LIB_ROOT" >&2; exit 1; }

# llvm-readelf when present; GNU readelf -W is column-compatible for our use
# (one line per LOAD segment, Align last).
if command -v llvm-readelf >/dev/null 2>&1; then
  RE="llvm-readelf -l"
else
  RE="readelf -l -W"
fi

# Presence check (fail-closed on a missing required ABI).
IFS=',' read -r -a REQUIRED <<<"$REQUIRED_CSV"
for abi in "${REQUIRED[@]}"; do
  if [ ! -d "$LIB_ROOT/$abi" ]; then
    echo "FAIL: required ABI dir missing: $LIB_ROOT/$abi" >&2
    exit 1
  fi
done

bad=0
shopt -s nullglob
found_any=0
for abidir in "$LIB_ROOT"/*/; do
  abi=$(basename "$abidir")
  case "$abi" in
    arm64-v8a | x86_64) enforce=1 ;;
    armeabi-v7a | x86) enforce=0 ;;
    *)
      echo "FAIL: unrecognized ABI dir '$abi' — classify it in check-16kb-alignment.sh" >&2
      exit 1
      ;;
  esac
  sos=("$abidir"*.so)
  if [ "${#sos[@]}" -eq 0 ]; then
    echo "FAIL: no .so files under $abidir" >&2
    exit 1
  fi
  found_any=1
  echo "== [$abi] native libs (enforce 16 KB: $enforce) =="
  for so in "${sos[@]}"; do
    ls -l "$so"
    aligns=$($RE "$so" | awk '$1 == "LOAD" { print $NF }')
    if [ -z "$aligns" ]; then
      echo "FAIL: [$abi] no LOAD segments found in $so" >&2
      exit 1
    fi
    while read -r a; do
      [ -z "$a" ] && continue
      dec=$((a)) # bash parses the 0x-prefixed hex
      printf '[%s] %s LOAD align = %s (%d)\n' "$abi" "$(basename "$so")" "$a" "$dec"
      if [ "$enforce" -eq 1 ] && [ "$dec" -lt 16384 ]; then bad=1; fi
    done <<<"$aligns"
  done
done

if [ "$found_any" -eq 0 ]; then
  echo "FAIL: no ABI dirs under $LIB_ROOT" >&2
  exit 1
fi
if [ "$bad" -ne 0 ]; then
  echo "FAIL: a 64-bit ABI LOAD segment is aligned < 16 KB (0x4000)" >&2
  exit 1
fi
echo "OK: every .so in every 64-bit ABI dir is 16 KB-aligned"

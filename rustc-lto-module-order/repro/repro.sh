#!/usr/bin/env bash
# Links two crates that are both named `dup` into one binary, twice, swapping
# their `-C extra-filename`s, and compares the two binaries. See README.md.
#
# usage: ./repro.sh   (RUSTC=... to use another rustc)
#
# Exits 1 if A and B differ in any case.
set -euo pipefail

rustc="${RUSTC:-rustc}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cd "$dir"

# Two different crates, both named `dup`, and a binary that uses both.
cat > dup_v1.rs <<'EOF'
#[inline(never)]
pub fn v1(x: u64) -> u64 { x.wrapping_mul(0x9e3779b97f4a7c15).rotate_left(5) }
EOF
cat > dup_v2.rs <<'EOF'
#[inline(never)]
pub fn v2(x: u64) -> u64 { (x ^ 0xdead_beef).wrapping_add(x << 7) }
EOF
cat > main.rs <<'EOF'
fn main() {
    let n = std::env::args().count() as u64;
    println!("{}", dup1::v1(n) ^ dup2::v2(n));
}
EOF

# Prints a command, then runs it.
run() {
  local cmd
  printf -v cmd '%q ' "$@"
  echo "  ${cmd% }"
  "$@"
}

# build <dir> <naming> <v1 suffix> <v2 suffix> [rustc flags...]
#
# naming: `extra-filename` (`--out-dir` + `-C extra-filename`, like cargo) or
# `o` (`-o lib<name>-<suffix>.rlib`).
build() {
  local out=$1 naming=$2 s1=$3 s2=$4
  shift 4
  mkdir "$out"
  local v=1 s
  for s in "$s1" "$s2"; do
    local name=(-C extra-filename="-$s" --out-dir "$out")
    [[ $naming == o ]] && name=(-o "$out/libdup-$s.rlib")
    run $rustc "$@" --crate-type rlib --crate-name dup -C metadata="v$v" \
      "${name[@]}" "dup_v$v.rs"
    v=2
  done
  run $rustc "$@" --crate-type bin --crate-name main \
    --extern dup1="$out/libdup-$s1.rlib" --extern dup2="$out/libdup-$s2.rlib" \
    -o "$out/main" main.rs
}

sha256() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-16; }

# The order of `dup::v1` and `dup::v2` in the binary's `.text`.
fn_order() {
  nm -n "$1" | grep -oE '3dup2v[12]' | sed 's/3dup2//' | tr '\n' ' '
}

# The sources, as markdown.
for f in dup_v1.rs dup_v2.rs main.rs; do
  # shellcheck disable=SC2016 # literal backticks
  printf '`%s`:\n\n```rust\n' "$f"
  cat "$f"
  printf '```\n\n'
done

$rustc -V
echo
echo "A: v1 is libdup-aaaa.rlib, v2 is libdup-zzzz.rlib"
echo "B: v1 is libdup-zzzz.rlib, v2 is libdup-aaaa.rlib"

row='%-21s %-17s %-17s %-7s %s\n'
# shellcheck disable=SC2059
rows=("$(printf "$row" case 'A sha256' 'B sha256' 'A == B' 'fn order (A | B)')")
i=0
failed=0
for case in \
  "extra-filename -C lto=thin" \
  "extra-filename -C lto=fat" \
  "o -C lto=thin" \
  "extra-filename -C lto=off"; do
  read -r naming flags <<<"$case"
  label="$flags"
  [[ $naming == o ]] && label="$flags, -o"

  echo
  echo "== $label: A"
  # shellcheck disable=SC2086
  build "a$i" "$naming" aaaa zzzz -C opt-level=3 $flags
  echo "== $label: B"
  # shellcheck disable=SC2086
  build "b$i" "$naming" zzzz aaaa -C opt-level=3 $flags

  a="$(sha256 "a$i/main")"
  b="$(sha256 "b$i/main")"
  same=yes
  [[ $a == "$b" ]] || { same=NO; failed=$((failed + 1)); }
  # shellcheck disable=SC2059
  rows+=("$(printf "$row" "$label" "$a" "$b" "$same" \
    "$(fn_order "a$i/main")| $(fn_order "b$i/main")")")
  i=$((i + 1))
done

echo
echo "rlib members in A:"
for rlib in a0/*.rlib; do
  ar t "$rlib" | sed "s|^|  $(basename "$rlib"): |"
done

echo
echo "Expected: A == B in every case, since only the rlibs' file names differ."
echo
printf '%s\n' "${rows[@]}"
echo
if ((failed)); then
  echo "FAIL: A != B in $failed of $i cases"
  exit 1
fi
echo "OK: A == B in all $i cases"

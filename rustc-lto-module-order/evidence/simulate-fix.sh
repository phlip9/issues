#!/usr/bin/env bash
# Simulates the suggested rustc fix on stable rustc: re-archives each rlib with
# the `<crate><extra-filename>.` prefix dropped from its object member names.
set -euo pipefail
rustc=${RUSTC:-rustc}
cat > dup_v1.rs <<'R'
#[inline(never)]
pub fn v1(x: u64) -> u64 { x.wrapping_mul(0x9e3779b97f4a7c15).rotate_left(5) }
R
cat > dup_v2.rs <<'R'
#[inline(never)]
pub fn v2(x: u64) -> u64 { (x ^ 0xdead_beef).wrapping_add(x << 7) }
R
cat > main.rs <<'R'
fn main() {
    let n = std::env::args().count() as u64;
    println!("{}", dup1::v1(n) ^ dup2::v2(n));
}
R
rename_members() {
  local rlib=$1 x m
  x=$(mktemp -d)
  (cd "$x" && ar x "$rlib")
  for m in "$x"/*.rcgu.o; do mv "$m" "$x/$(basename "$m" | cut -d. -f2-)"; done
  rm "$rlib"
  (cd "$x" && ar rcs "$rlib" lib.rmeta ./*.rcgu.o)
  rm -rf "$x"
}
build() {
  local out=$1 s1=$2 s2=$3; shift 3
  rm -rf "$out"; mkdir "$out"
  "$rustc" "$@" --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename="-$s1" --out-dir "$out" dup_v1.rs
  "$rustc" "$@" --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename="-$s2" --out-dir "$out" dup_v2.rs
  if [[ ${RENAME:-0} == 1 ]]; then
    rename_members "$PWD/$out/libdup-$s1.rlib"; rename_members "$PWD/$out/libdup-$s2.rlib"
  fi
  "$rustc" "$@" --crate-type bin --crate-name main --extern dup1="$out/libdup-$s1.rlib" --extern dup2="$out/libdup-$s2.rlib" -o "$out/main" main.rs
}
for lto in thin fat; do
  build a aaaa zzzz -C opt-level=3 -C lto=$lto
  build b zzzz aaaa -C opt-level=3 -C lto=$lto
  echo "lto=$lto RENAME=${RENAME:-0}: A $(sha256sum a/main | cut -c1-16) B $(sha256sum b/main | cut -c1-16); members: $(ar t a/libdup-aaaa.rlib | tr '\n' ' '); run: $(./a/main) $(./b/main)"
done

#!/usr/bin/env bash
# Builds a small wasm workspace, then prints each unit's `-C metadata`, some
# mangled symbols, and the `.wasm`'s hash. See README.md.
#
# usage: ./repro.sh [path/to/cargo]
set -euo pipefail

cargo="${1:-cargo}"
dir="./"

# Build for wasm32-unknown-unknown, which needs no external linker.
"$cargo" -V
rustc -V
echo "build host: $(rustc -vV | sed -n 's/^host: //p')"
"$cargo" build -v --release --target wasm32-unknown-unknown -p app 2>build.log \
  || { cat build.log; exit 1; }

# The `-C metadata` of every rustc invocation. `kind=host` units are built
# for the build host, `kind=target` units for wasm32.
echo
echo "crate                kind    -C metadata"
grep -oE 'rustc --crate-name [^`]*' build.log | while read -r line; do
  name="$(sed -E 's/.*--crate-name ([^ ]+).*/\1/' <<<"$line")"
  meta="$(sed -E 's/.*-C metadata=([^ ]+).*/\1/' <<<"$line")"
  kind=host
  [[ $line == *"--target wasm32-unknown-unknown"* ]] && kind=target
  printf '%-20s %-7s %s\n' "$name" "$kind" "$meta"
done | sort

# Mangled symbol names in the output embed each crate's metadata hash: in
# legacy mangling as the `17h<hash>E` suffix, in v0 mangling as the crate's
# `Cs<hash>_` disambiguator.
wasm=target/wasm32-unknown-unknown/release/app.wasm
echo
echo "mangled symbols of leaf::leaf, bs::bs, app::app in app.wasm:"
{
  LC_ALL=C grep -aoE '_ZN[0-9]+(leaf|bs|app)[0-9A-Za-z_]*17h[0-9a-f]{16}E' "$wasm" || true
  LC_ALL=C grep -aoE '_RNvCs[0-9A-Za-z]+_(4leaf4leaf|2bs2bs|3app3app)' "$wasm" || true
} | sort -u | sed 's/^/  /'
echo
echo "app.wasm sha256: $({ sha256sum "$wasm" 2>/dev/null || shasum -a 256 "$wasm"; } | cut -d' ' -f1)"

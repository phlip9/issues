#!/usr/bin/env bash
# AOT-compiles a program that uses intl, as published and with
# `nan() => double.nan`, on x64 and arm64 hosts. See README.md.
#
# usage: ./repro.sh
set -euo pipefail

intl_version="${INTL_VERSION:-0.20.3}"
sdk="$(dirname "$(dirname "$(readlink -f "$(command -v dart)")")")"
version="$(cat "$sdk/version")"
case "$(uname -m)" in
  x86_64) other=arm64 qemu=qemu-aarch64 ;;
  aarch64) other=x64 qemu=qemu-x86_64 ;;
  *) echo "unsupported host: $(uname -m)" >&2; exit 1 ;;
esac
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cd "$dir"

# The SDK's release channel, for its archive URL.
case "$version" in
  *.dev) channel=dev ;;
  *.beta) channel=beta ;;
  *) channel=stable ;;
esac
base="https://storage.googleapis.com/dart-archive/channels/$channel/release/$version/sdk"

# The cross-compilers to linux-riscv64, for both host CPUs.
for host in x64 arm64; do
  curl -sSfo "gen_snapshot_$host" "$base/gen_snapshot_linux_${host}_linux_riscv64"
  chmod +x "gen_snapshot_$host"
done

# usage: kernel <name> [pubspec lines...]
# Compiles `main.dart` to `<name>.dill`, with intl from pub.dev, plus any
# extra pubspec lines.
kernel() {
  local name="$1"
  shift
  mkdir "$name"
  cat > "$name/pubspec.yaml" <<YAML
name: repro
environment:
  sdk: ^3.8.0
dependencies:
  intl: $intl_version
$(printf '%s\n' "$@")
YAML
  cat > "$name/main.dart" <<'DART'
import 'package:intl/intl.dart';

void main(List<String> args) =>
    print(NumberFormat.decimalPattern('en_US').parse(args.first));
DART
  (cd "$name" && dart pub get >/dev/null) || return 1
  "$sdk/bin/dartaotruntime" "$sdk/bin/snapshots/gen_kernel_aot.dart.snapshot" \
    --platform="$sdk/lib/_internal/vm_platform_product.dill" \
    --packages="$name/.dart_tool/package_config.json" \
    --target-os=linux --aot -Ddart.vm.product=true \
    --output="$name.dill" "$name/main.dart" || return 1
}

# usage: aot <kernel> <host>
# AOT-compiles the kernel for linux-riscv64 with the cross-compiler for
# `<host>`, and prints the output's sha256.
aot() {
  local out="out-$1-$2"
  local run=()
  [[ $2 == "$other" ]] && run=("$qemu")
  mkdir "$out"
  (cd "$out" && "${run[@]}" "../gen_snapshot_$2" \
    --snapshot-kind=app-aot-elf --elf=main.aot "../$1.dill") || return 1
  sha256sum "$out/main.aot" | cut -d' ' -f1
}

kernel published

# The same intl, with `nan() => double.nan`.
intl_src="$(sed -nE 's|.*"rootUri": "file://(.*/intl-[^"]*)".*|\1|p' \
  published/.dart_tool/package_config.json)"
cp -R "$intl_src" intl-patched
chmod -R u+w intl-patched
sed -i 's|num nan() => 0.0 / 0.0;|num nan() => double.nan;|' \
  intl-patched/lib/src/intl/number_parser.dart
grep -q 'num nan() => double.nan;' intl-patched/lib/src/intl/number_parser.dart
kernel patched "dependency_overrides:" "  intl:" "    path: ../intl-patched"

echo "Dart SDK $version, intl $intl_version, AOT for linux-riscv64"
for k in published patched; do
  x64="$(aot "$k" x64)"
  arm64="$(aot "$k" arm64)"
  echo
  echo "intl $k:"
  echo "  linux-x64 host:    $x64"
  echo "  linux-arm64 host:  $arm64"
done

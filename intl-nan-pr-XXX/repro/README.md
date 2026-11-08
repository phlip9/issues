# intl: `NumberParser.nan()` depends on the build host's CPU

intl's `NumberParser.nan()` returns `0.0 / 0.0`, which the AOT compiler folds
on the build host's CPU, so the NaN's sign differs between x64 and arm64 hosts.
Any AOT-compiled app that uses `NumberFormat.parse` then depends on the host
that built it. Returning `double.nan` instead fixes that for builds that share
a platform `.dill`, as Flutter builds do, since `double.nan` comes from there.

TODO(phlip9): upstream

`repro.sh` compiles a program that calls
`NumberFormat.decimalPattern('en_US').parse(...)` to a kernel twice: with intl
from pub.dev, and with a copy patched to `nan() => double.nan`. Then it
AOT-compiles each kernel for linux-riscv64 with the SDK's linux-x64 and
linux-arm64 hosted cross-compilers, and prints the output hashes. It runs the
cross-compiler for the other CPU under qemu-user.

## Run

On x64 or arm64 Linux, with curl, qemu-user with the other CPU's libc, and a
Dart SDK release (stable, beta, or dev) on `PATH`, since `repro.sh` downloads
that release's cross-compilers:

```bash
# ex: on Debian/Ubuntu x64
sudo apt install qemu-user libc6-arm64-cross
export QEMU_LD_PREFIX=/usr/aarch64-linux-gnu
./repro.sh
```

The published intl's two hashes differ, and the patched intl's match. The
kernels embed the temp dir's path, so the hashes themselves change from run to
run, but which of them match doesn't.

To confirm the fix once released, run it with
`INTL_VERSION=<the new version> ./repro.sh`. The two `published` hashes should
then match too.

## Results

Dart SDK 3.13.7 and intl 0.20.3 on x86_64 Linux, with arm64 under qemu-user:

```
Dart SDK 3.13.7, intl 0.20.3, AOT for linux-riscv64

intl published:
  linux-x64 host:    a799584ba35ceb07da135261aa6d7cfab674d18222dd7c1f7c67145408d68eb5
  linux-arm64 host:  83813b32d1bbc2b8c63b274be92b5191c3d9b0d5a005695e2cdaa2430c7d12c1

intl patched:
  linux-x64 host:    ec8204808fdd736a886254ee9b542a49d6c7e23a2506e2873927fa521e1f76ac
  linux-arm64 host:  ec8204808fdd736a886254ee9b542a49d6c7e23a2506e2873927fa521e1f76ac
```

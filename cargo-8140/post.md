<!--
Where: comment on https://github.com/rust-lang/cargo/issues/8140
Repro: repro/cargo-host-metadata
Evidence: evidence/ (1.99.1 stock and with #17522 on both hosts; 1.96.1 patched)
Verified 2026-11-07 with Rust 1.99.1 on both hosts; master's
hash_rustc_version unchanged. #17522 tested: its src/ changes at 3658d3e
applied to the rustc-1.99.1 source tarball's cargo
(evidence/pr17522-applied-to-rustc-1.99.1-src.patch).
Optional: a one-line pointer on #17522 to this comment.
-->

This still reproduces with cargo 1.99.1. Here's a minimal reproducer with no
dependencies: a 4-crate workspace whose `wasm32-unknown-unknown` build differs
between x86_64 Linux and aarch64 macOS hosts, in every crate downstream of a
build script or proc-macro.

We hit this making our Android app's Rust library reproducible across those two
hosts. As data points for the design discussion, we ran the reproducer on both
hosts with two fixes:

- The draft #17522, applied to cargo 1.99.1's source: the target units' `-C
  metadata`, their symbols and the `.wasm` match, while the host units still
  differ, as intended.
- Our stopgap, which skips the `host:` line in `hash_rustc_version` for all
  units (on cargo 1.96): everything matches, and so does our app's library.
  Unlike #17522, it also drops the host triple from the host units' file names.

| cargo 1.99.1 | x86_64 Linux | aarch64 macOS |
| --- | --- | --- |
| `leaf` metadata (no build script or proc-macro) | `fb9fb77cd47e1512` | `fb9fb77cd47e1512` |
| `bs` metadata (has a build script) | `255095b9c0a38f08` | `03030842a7d0c941` |
| `app` metadata (uses a proc-macro) | `c5ff48f3a3b25169` | `71db9166c9cdba99` |
| `app.wasm` sha256 | `219f9af5…` | `bde2b3ac…` |
| `app.wasm` sha256, with #17522 | `1b7e65d3…` | `1b7e65d3…` |

Reproducer, with full outputs, our patch, and steps to confirm a fix:
<REPO_URL>/tree/main/cargo-host-metadata

# cargo: target crates depend on the build host's triple

Cargo hashes the `host:` line of `rustc -vV` into the `-C metadata` of build
scripts and proc-macros. Every target crate that depends on one inherits that
hash, so its symbols, and the final artifact, depend on the build host.
Upstream: [rust-lang/cargo#8140](https://github.com/rust-lang/cargo/issues/8140).

`repro.sh` builds a small workspace:

- `leaf`: no build script, no proc-macro
- `bs`: an empty build script
- `pm`: a proc-macro
- `app`: a `cdylib` that uses all three

It builds `app` for `wasm32-unknown-unknown`, which needs no external linker,
then prints each unit's `-C metadata`, the mangled symbols of `leaf::leaf`,
`bs::bs` and `app::app`, and the `.wasm`'s hash.

## Run

On two hosts with different triples, ex: x86_64 Linux and aarch64 macOS, with
the same Rust release:

```bash
rustup target add wasm32-unknown-unknown
./repro.sh > "out-$(rustc -vV | sed -n 's/^host: //p').txt"
# then, with both outputs on one machine:
diff out-x86_64-unknown-linux-gnu.txt out-aarch64-apple-darwin.txt
```

The `target` lines for `bs` and `app`, their symbols, and the `.wasm` hash
differ, while `leaf` matches.

To confirm a fix, pass the patched cargo on both hosts
(`./repro.sh /absolute/path/to/cargo`) and diff again. The `target` lines, the symbols
and the `.wasm` hash should match. The `host` lines may still differ.

## Results

Stock cargo 1.99.1 on x86_64 Linux:

```
cargo 1.99.1 (5f94df478 2026-08-27)
rustc 1.99.1 (58cf8f9c3 2026-10-13)
build host: x86_64-unknown-linux-gnu

crate                kind    -C metadata
app                  target  c5ff48f3a3b25169
bs                   target  255095b9c0a38f08
build_script_build   host    1b546270667530c2
leaf                 target  fb9fb77cd47e1512
pm                   host    0d5910a6becad355

mangled symbols of leaf::leaf, bs::bs, app::app in app.wasm:
  _RNvCs1UnguzFhWgX_4leaf4leaf
  _RNvCs60IKeJ98H5Z_2bs2bs
  _RNvCscjIrHDmqp31_3app3app

app.wasm sha256: 219f9af515049e3168df547f3e7898244deddd31d5e08715c6c178da548d2091
```

Stock cargo 1.99.1 on aarch64 macOS:

```
cargo 1.99.1 (5f94df478 2026-08-27)
rustc 1.99.1 (58cf8f9c3 2026-10-13)
build host: aarch64-apple-darwin

crate                kind    -C metadata
app                  target  71db9166c9cdba99
bs                   target  03030842a7d0c941
build_script_build   host    47fd0c9bed8b9a3c
leaf                 target  fb9fb77cd47e1512
pm                   host    c98692b9e25784c7

mangled symbols of leaf::leaf, bs::bs, app::app in app.wasm:
  _RNvCs1UnguzFhWgX_4leaf4leaf
  _RNvCs48hX0W1jsC5_3app3app
  _RNvCs5AaESgog97B_2bs2bs

app.wasm sha256: bde2b3ac427f41ef4abdd71607fff97d4d54b423d241a1671f0c7a6a54faa3dc
```

cargo 1.99.1's source (`5f94df478`) with the `src/` changes of
[#17522](https://github.com/rust-lang/cargo/pull/17522) at `3658d3e`, on
x86_64 Linux. Built outside rustc's build system, it reports itself as
cargo 1.99.0. aarch64 macOS prints the same, except for its `build host:` line
and its host units' metadata, which are the same as with stock cargo
(`build_script_build 47fd0c9bed8b9a3c`, `pm c98692b9e25784c7`):

```
crate                kind    -C metadata
app                  target  3cd54b173896421e
bs                   target  beec6c324ee4a2c3
build_script_build   host    1b546270667530c2
leaf                 target  fb9fb77cd47e1512
pm                   host    0d5910a6becad355

mangled symbols of leaf::leaf, bs::bs, app::app in app.wasm:
  _RNvCs1UnguzFhWgX_4leaf4leaf
  _RNvCs94udlu9mXaP_3app3app
  _RNvCsgArEOi7rdLm_2bs2bs

app.wasm sha256: 1b7e65d34996a39933bfc30ce6873bd4d50eedc0a1f74a035d95b2420d8b94a7
```

cargo 1.96 (`356927216`, with rustc 1.96.1) with the patch below prints the
same on both hosts, except for the `build host:` line:

```diff
--- a/src/cargo/core/compiler/build_runner/compilation_files.rs
+++ b/src/cargo/core/compiler/build_runner/compilation_files.rs
@@ -871,7 +871,7 @@
         // omitted since rustc should produce the same output for each target
         // regardless of the host.
         for line in bcx.rustc().verbose_version.lines() {
-            if unit.kind.is_host() || !line.starts_with("host: ") {
+            if !line.starts_with("host: ") {
                 line.hash(hasher);
             }
         }
```

```
crate                kind    -C metadata
app                  target  61b1e52df777de27
bs                   target  d2dbf1fc8b693ad2
build_script_build   host    c2aa26698252b29d
leaf                 target  6c2ff8061f5be50c
pm                   host    11aa71813d083d6f

mangled symbols of leaf::leaf, bs::bs, app::app in app.wasm:
  _ZN2bs2bs17h120d79141ff3a63bE
  _ZN3app3app17h99ddcbcdff087889E
  _ZN4leaf4leaf17hf7d20f18f45d5ef5E

app.wasm sha256: 4aa0372bf0c4d2582a1de72b474bfac910dc0bc1eeace29b3f09c10052d805c0
```

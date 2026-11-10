# rustc: LTO link order depends on `-C extra-filename`

A minimal reproducer demonstrating how `-C extra-filename` affects the
link order of CGUs of duplicate crate deps when LTO is enabled.

````bash
$ RUSTC="rustc +nightly" ./repro.sh

`dup_v1.rs`:

```rust
#[inline(never)]
pub fn v1(x: u64) -> u64 { x.wrapping_mul(0x9e3779b97f4a7c15).rotate_left(5) }
```

`dup_v2.rs`:

```rust
#[inline(never)]
pub fn v2(x: u64) -> u64 { (x ^ 0xdead_beef).wrapping_add(x << 7) }
```

`main.rs`:

```rust
fn main() {
    let n = std::env::args().count() as u64;
    println!("{}", dup1::v1(n) ^ dup2::v2(n));
}
```

rustc 1.102.0-nightly (ac8310ba6 2026-11-09)

A: v1 is libdup-aaaa.rlib, v2 is libdup-zzzz.rlib
B: v1 is libdup-zzzz.rlib, v2 is libdup-aaaa.rlib

== -C lto=thin: A
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename=-aaaa --out-dir a0 dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename=-zzzz --out-dir a0 dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type bin --crate-name main --extern dup1=a0/libdup-aaaa.rlib --extern dup2=a0/libdup-zzzz.rlib -o a0/main main.rs
== -C lto=thin: B
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename=-zzzz --out-dir b0 dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename=-aaaa --out-dir b0 dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type bin --crate-name main --extern dup1=b0/libdup-zzzz.rlib --extern dup2=b0/libdup-aaaa.rlib -o b0/main main.rs

== -C lto=fat: A
  rustc +nightly -C opt-level=3 -C lto=fat --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename=-aaaa --out-dir a1 dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=fat --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename=-zzzz --out-dir a1 dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=fat --crate-type bin --crate-name main --extern dup1=a1/libdup-aaaa.rlib --extern dup2=a1/libdup-zzzz.rlib -o a1/main main.rs
== -C lto=fat: B
  rustc +nightly -C opt-level=3 -C lto=fat --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename=-zzzz --out-dir b1 dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=fat --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename=-aaaa --out-dir b1 dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=fat --crate-type bin --crate-name main --extern dup1=b1/libdup-zzzz.rlib --extern dup2=b1/libdup-aaaa.rlib -o b1/main main.rs

== -C lto=thin, -o: A
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v1 -o a2/libdup-aaaa.rlib dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v2 -o a2/libdup-zzzz.rlib dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type bin --crate-name main --extern dup1=a2/libdup-aaaa.rlib --extern dup2=a2/libdup-zzzz.rlib -o a2/main main.rs
== -C lto=thin, -o: B
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v1 -o b2/libdup-zzzz.rlib dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type rlib --crate-name dup -C metadata=v2 -o b2/libdup-aaaa.rlib dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=thin --crate-type bin --crate-name main --extern dup1=b2/libdup-zzzz.rlib --extern dup2=b2/libdup-aaaa.rlib -o b2/main main.rs

== -C lto=off: A
  rustc +nightly -C opt-level=3 -C lto=off --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename=-aaaa --out-dir a3 dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=off --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename=-zzzz --out-dir a3 dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=off --crate-type bin --crate-name main --extern dup1=a3/libdup-aaaa.rlib --extern dup2=a3/libdup-zzzz.rlib -o a3/main main.rs
== -C lto=off: B
  rustc +nightly -C opt-level=3 -C lto=off --crate-type rlib --crate-name dup -C metadata=v1 -C extra-filename=-zzzz --out-dir b3 dup_v1.rs
  rustc +nightly -C opt-level=3 -C lto=off --crate-type rlib --crate-name dup -C metadata=v2 -C extra-filename=-aaaa --out-dir b3 dup_v2.rs
  rustc +nightly -C opt-level=3 -C lto=off --crate-type bin --crate-name main --extern dup1=b3/libdup-zzzz.rlib --extern dup2=b3/libdup-aaaa.rlib -o b3/main main.rs

rlib members in A:
  libdup-aaaa.rlib: lib.rmeta
  libdup-aaaa.rlib: lib.rmeta-link
  libdup-aaaa.rlib: dup-aaaa.dup.716087c5d84f7a82-cgu.0.rcgu.o
  libdup-zzzz.rlib: lib.rmeta
  libdup-zzzz.rlib: lib.rmeta-link
  libdup-zzzz.rlib: dup-zzzz.dup.1adcd6e01ff6a76a-cgu.0.rcgu.o

Expected: A == B in every case, since only the rlibs' file names differ.

case                  A sha256          B sha256          A == B  fn order (A | B)
-C lto=thin           b8bafb9b10f57924  f07a2ae733f25bad  NO      v1 v2 | v2 v1
-C lto=fat            76ae7877d56d0179  ddc6151b94fdc98a  NO      v1 v2 | v2 v1
-C lto=thin, -o       6bcea5bec12bf3f5  bb008b77cf45aeec  NO      v1 v2 | v2 v1
-C lto=off            0f2c0194a7d99a6d  0f2c0194a7d99a6d  yes     v2 v1 | v2 v1

FAIL: A != B in 3 of 4 cases
````

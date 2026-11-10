# rustc: LTO link order depends on `-C extra-filename` w/ dupe crate deps

<!-- labels: A-LTO, A-reproducibility, T-compiler -->

### Problem

With `-C lto=thin` or `-C lto=fat`, the link order depends on the `-C extra-filename` (or `-o` filename) used to build an `.rlib`. This issue happens specifically when 2+ linked crates have the same crate name _and_ (at least with cargo) you cross-compile to a different `--target`, from two different build hosts. The difference in link order then breaks build reproducibility.

I hit this while making our Android app's release build reproducible across x86_64-linux and aarch64-darwin build hosts.

### More context

I'll quote my `cargo` review comment here: ([rust-lang/cargo#17522](https://github.com/rust-lang/cargo/pull/17522#discussion_r4519720406))

> so AFAICT, this PR changes _only_ the target crate `-C metadata` hashing so that host deps are mixed in without host-specific data (just the host dep package-id in `host_independent_c_metadata` below), right?
> 
> after some testing, this does appear to prevent host-dependent data from leaking into the target and breaking reproducibility... but only _without LTO enabled_ 😭
> 
> turning on `lto="thin"` in our release build then broke reproducibility again (when built across x86_64-linux and aarch64-darwin build hosts). `lto="fat"` also causes the same issue.
> 
> with some more digging, this only appears to trigger when there are duplicate _target_ deps (`socket2-v0.5.10` and `socket2-v0.6.3` in our case)
> 
> roughly, the object files contain `extra_filename` and get linked in a host-dependent order with LTO:
> 
> - the `unit_id` hash is still picking up host-dependent data
> - which infects the `-C extra-filename`
> - which then leaks into the object files in the `.rlib`s (`socket2-<extra_filename>-<cgu_name>-rcgu.o`)
> 
> **without LTO:** `rustc` passes the `.rlib`s to the linker in a deterministic order from the crate graph, so no problem
> 
> **with LTO:**
> - `rustc` extracts the object files from all the `.rlib`s for LTO
> - it produces one module per object, the module name includes `extra_filename`
> - all the compiled modules from all the target `.rlib`s get _sorted together_:
>   ```rust
>   // Regardless of what order these modules completed in, report them to
>   // the backend in the same order every time to ensure that we're handing
>   // out deterministic results.
>   compiled_modules.modules.sort_by(|a, b| a.name.cmp(&b.name));
>   ```
>   see: [rustc_codegen_ssa/src/back/write.rs](https://github.com/rust-lang/rust/blob/ac8310ba643a3796cbe77d2e06944d7c8513999f/compiler/rustc_codegen_ssa/src/back/write.rs#L2207-L2210)
> - if you don't have duplicate deps, there's no issue, since unique crate name --> deterministic sort order. in our case, the modules from the two `socket2` deps happened to get different `extra_filename`s that ordered differently on linux and macOS.
> - the `socket2-v0.5.10` and `socket2-v0.6.3` object files linked in a different order
> - the code in the `.text` section was reordered
> - the binary was no longer reproducible

### Potential fixes

After some more thinking, I don't believe `cargo` is the right place to fix this. Extending rust-lang/cargo#17522 to `unit_id` (and so `-C extra-filename`) would harm normal `cargo` build caching too much.

Instead, I think the right approach is to fix `rustc` so that LTO modules are linked in a not-`extra_filename`-dependent order.

As I understand it `extra_filename` is marked `[UNTRACKED]`, so it should not not be affecting incremental compilation output: [rustc_session/src/options.rs#L2284](https://github.com/rust-lang/rust/blob/ac8310ba643a3796cbe77d2e06944d7c8513999f/compiler/rustc_session/src/options.rs#L2284)

If LTO modules used the CGU name again (ex: `<crate>.<StableCrateId>-cgu.N` in non-incremental builds), either by:

1. renaming `.rlib` object files to `<cgu-name>.rcgu.o` (so e.g. strip off the `<crate><extra_filename>.` prefix)
   - I believe object files in build tempdirs should continue to include the prefix to avoid collisions during parallel compilation.
2. or recording the original object CGU name in the new `lib.rmeta-link` somehow and using that as the LTO module name
   - Would probably extend #154861
3. or have LTO `sort_by` parse and trim off the bad prefix before comparing

then that would probably solve the issue.

The linking should still be correct with the shortened CGU names, as they're supposed to be unique within a crate graph.

### Minimal reproducer

I had an AI cook up a minimal reproducer that succinctly demonstrates the issue with just `rustc`:

<https://github.com/phlip9/issues/tree/master/rustc-lto-module-order/repro>

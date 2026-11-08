<!--
Where: PR to https://github.com/dart-lang/i18n (pkgs/intl), from a fork.
Diff: pr.diff, against dart-lang/i18n@<pr-base.txt> (git apply in a checkout,
  commit, push to a fork, open the PR). Needs the Google CLA.
Checked: `dart test test/number_format_vm_test.dart test/number_closure_test.dart
  test/number_format_compact_test.dart` (883 passed), `dart analyze`,
  `dart format` on the changed file.
Repro: repro/intl-nan
Evidence: evidence.txt
Verified 2026-11-07: intl 0.20.3 (latest on pub.dev) and i18n main still have
  `nan() => 0.0 / 0.0`; repro run with Dart 3.13.7.
<DART_NAN_ISSUE>: from 06-dart-nan-folding once filed (or drop that sentence).

Title: [intl] Return `double.nan` from `NumberParser.nan()`
-->

`NumberParser.nan()` returns `0.0 / 0.0`, which the AOT compiler folds on the build host's CPU, and the folded NaN's sign differs between x64 and arm64 hosts. So any AOT-compiled app that uses `NumberFormat.parse` depends on the CPU that built it. This returns `double.nan` instead, which is still a NaN, so there's no behavior change.

`double.nan` comes from the SDK's platform `.dill` rather than being folded on the build host, and Flutter uses the same platform `.dill` on every host, so Flutter builds no longer depend on the host's CPU here. The underlying compiler issue is <DART_NAN_ISSUE>. `positiveInfinity()` and `negativeInfinity()` stay as they are, since infinities have a single encoding.

We found this while making our Flutter app's release build byte-identical across x64 Linux and arm64 macOS hosts, and with this change it is. The reproducer AOT-compiles a program that uses intl with the SDK's x64 and arm64 hosted cross-compilers:

| AOT output sha256 | x64 host | arm64 host |
| --- | --- | --- |
| intl 0.20.3 | `a799584b…` | `83813b32…` |
| with this PR | `ec820480…` | `ec820480…` |

Reproducer, with full output and steps to confirm the fix: <REPO_URL>/tree/main/intl-nan

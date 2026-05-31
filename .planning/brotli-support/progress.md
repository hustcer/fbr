# Progress Log: Brotli Support

## 2026-06-01 — decode tree lookup validation check removed

- Accepted one decode performance strategy after comparing it against a
  same-time baseline and the existing negative-cache list.
- Changed private `BrotliHuffmanTreeGroup::tree` to rely on validated indexes
  and the underlying array access instead of doing an additional explicit
  `FbrError` bounds check on every hot lookup.
- Added white-box coverage for invalid mapped context-map tree indexes so the
  validation invariant remains tested.
- Screening evidence, current candidate versus same-time baseline, q0/q5/q9/q11
  Google 1 MiB streams with `wasm-gc,native`, repeats=5, samples=3:
  - aggregate eight-row min time: 382.314 -> 372.795 ms/op, +2.49%.
  - q0 wasm/native: 42.907 -> 41.954 ms/op and 70.498 -> 68.741 ms/op.
  - q5 wasm/native: 34.574 -> 34.040 ms/op and 58.943 -> 57.120 ms/op.
  - q9 wasm/native: 33.567 -> 32.884 ms/op and 56.045 -> 55.010 ms/op.
  - q11 wasm/native: 31.122 -> 30.270 ms/op and 54.658 -> 52.778 ms/op.
- Full benchmark evidence:
  - `just bench` passed and regenerated `docs/current-bench/decode.jsonl`,
    `docs/current-bench/encode.jsonl`, and `docs/brotli_release_report.md`.
  - Encode output sizes in `docs/current-bench/encode.jsonl` are unchanged
    versus HEAD, so encoder behavior did not obviously regress.
- MoonBit review/validation evidence:
  - `moon check --target native` passed.
  - `moon test src/decode --target native` passed, 53/53.
  - `moon fmt && moon info && moon check --target all && moon test --target all
    && git diff --check` passed; all four targets report 122/122 tests.
- Follow-up storage decision: benchmark artifacts from this run were moved out
  of git history and saved under
  `target/brotli-perf-notes/2026-06-01-tree-lookup/` for local comparison.
- Rejected follow-up trial: direct distance context-map access in the
  explicit-distance path. It passed native check and decode tests but failed
  q0/q5/q9/q11 same-time screening because q5 wasm-gc regressed from 33.412 to
  33.785 ms/op. Source was reverted and the failure was added to findings.
- Rejected follow-up trial: removing the per-symbol single-symbol Huffman
  table check. It passed native check and decode tests but failed screening
  because q0 wasm-gc regressed from 42.017 to 44.907 ms/op. Source was
  reverted and the failure was added to findings.

## 2026-05-30 — P3 5% ratio release gate enforced

- Committed as `911db1e test(brotli): enforce p3 ratio release gate`.
- Updated `tools/brotli/release/validate.nu` so the q2..q9 ratio step now
  parses `tools/brotli/bench/ratio.nu --json` output and fails if any measured
  quality exceeds the default `--p3-max-overhead 0.05` threshold.
- Documented the gate in `tools/brotli/README.md`; `--p3-max-overhead` is now
  the explicit release-policy override.
- Validation evidence:
  - `nu --ide-check 0 0 tools/brotli/release/validate.nu` passed.
  - `nu tools/brotli/release/validate.nu --skip-moon --skip-conformance
--skip-fuzz --skip-package --silesia-2m
target/brotli-bench/silesia-64k.bin --silesia-1m
target/brotli-bench/silesia-64k.bin` passed the quick ratio/decode path:
    q0 external decode 1.641s, q1 external decode 0.316s, q2..q9 ratio/decode
    36.748s, q10/q11 ratio-exception decode 7.121s.
- This does not change codec output or target-perf baselines; it makes the
  revised P3 5% target an executable release gate rather than a documented
  observation.

## 2026-05-30 — q10/q11 chunked mixed-candidate duplicate build removed

- Committed as `91e78db perf(brotli): avoid duplicate q10 chunked mixed
parse`.
- Removed duplicate mixed static-dictionary LZ77 construction from the chunked
  q10/q11 path. The encoder now builds the real carried-distance-cache
  `BrotliCommandCandidate` once instead of first building a default-cache
  command list only to decide whether to rebuild the candidate.
- Size evidence:
  - `silesia-128k.bin` q10 stays 38,713 bytes vs Google 35,624 (+8.67%).
  - `silesia-128k.bin` q11 stays 38,713 bytes vs Google 35,164 (+10.09%).
- Encode target-perf, same harness before -> after:
  - q10 wasm-gc: 217.776 -> 172.439 ms/op.
  - q10 native `cc-o0`: 456.867 -> 295.990 ms/op.
  - q11 wasm-gc: 225.682 -> 169.021 ms/op.
  - q11 native `cc-o0`: 454.461 -> 314.528 ms/op.
- Representative decode target-perf on Google q11 128 KiB stream after the
  encoder-only change: wasm-gc 70.856 ms/op, native `cc-o0` 79.969 ms/op,
  Google 44.710 ms/op.
- Validation evidence:
  - `moon check --target native` passed.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin
--qualities 10,11 --json` passed with unchanged output sizes.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities
10,11 --target native` passed 8/8 cases.
  - `moon fmt && moon check --target all && moon test --target all &&
moon info && git diff --check` passed; all four targets report 469/469
    tests passed.
- This improves q10/q11 chunked encode performance but does not reduce the
  remaining P4 size gap, so P4 remains open.

## 2026-05-30 — q10/q11 2 MiB chunk trial rejected

- Refreshed current q10/q11 2 MiB ratio after the chunked duplicate-build
  performance commit:
  - q10: 527,008 bytes vs Google 470,219 (+12.08%).
  - q11: 527,008 bytes vs Google 464,049 (+13.57%).
- Trial: let q10/q11 use the 2 MiB standard chunk and raise the high-quality
  hash max input length to 2 MiB, matching the q9 large-chunk path.
- Size result improved but remained far above the revised 5% target:
  - q10: 515,944 bytes vs Google 470,219 (+9.72%).
  - q11: 515,944 bytes vs Google 464,049 (+11.18%).
  - Savings were 11,064 bytes on both q10 and q11.
- Performance result was not acceptable:
  - native `cc-o0` q10 2 MiB encode regressed 4,892.558 -> 6,651.981 ms/op.
  - native `cc-o0` q11 2 MiB encode regressed 4,904.176 -> 5,749.368 ms/op.
  - wasm-gc 2 MiB encode target-perf failed to report `MBT_PERF_SIZE`, so it
    cannot support accepting this trial.
  - Legacy JS verifier time did improve from roughly 248/252s to 147/149s
    because the input became one chunk instead of two, but native target-perf
    is the higher-priority signal.
- Decision: rejected and reverted. A larger q10/q11 chunk is a real size lever,
  but by itself it does not reach 5% and it regresses native encode too much.
- Follow-up 1.5 MiB q10/q11 chunk trial was also rejected before target-perf:
  it only improved `silesia-2m.bin` q10/q11 from 527,008 to 525,291 bytes,
  leaving q10/q11 at +11.71%/+13.20%. The size win is too small to justify
  keeping or further performance-testing that chunk size.

## 2026-05-30 — large single-copy periodic fast path

- Committed as `75cc99f perf(brotli): use single-copy path for large periodic
inputs`.
- Broader P3 corpus screening found two important caveats:
  - tiny 84-byte dictionary text is not suitable for a strict percentage
    gate because a few bytes of header difference becomes a 20%+ ratio swing;
  - `periodic-allbytes-200k.bin` exposed a real gap for highly periodic
    256-byte-cycle data: q2..q9 were 350 bytes versus Google 293..259 bytes.
- Added a >64 KiB single-copy fast path for inputs up to 256 KiB. The encoder
  now tries the existing periodic detector before chunking, then exact-costs
  the single compressed block against a split form: stored prefix meta-block
  plus copy-only compressed meta-block.
- Size evidence on `periodic-allbytes-200k.bin`:
  - q2: 350 -> 301 bytes vs Google 293, overhead +19.45% -> +2.73%.
  - q3: 350 -> 272 bytes vs Google 281, overhead +24.56% -> -3.20%.
  - q4..q8: 350 -> 272 bytes vs Google 260, overhead +34.62% -> +4.62%.
  - q9: 350 -> 272 bytes vs Google 259, overhead +35.14% -> +5.02%.
- Encode target-perf before -> after on `periodic-allbytes-200k.bin`:
  - q2 wasm-gc: 121.193 -> 113.285 ms/op; native `cc-o0`: 91.339 ->
    73.513 ms/op.
  - q9 wasm-gc: 212.056 -> 116.976 ms/op; native `cc-o0`: 666.810 ->
    72.173 ms/op.
- Representative decode target-perf on Google q9 periodic stream after the
  encoder-only change: wasm-gc 57.084 ms/op, native `cc-o0` 86.281 ms/op,
  Google 40.694 ms/op.
- Silesia 128 KiB q2/q5/q9 ratio spot checks are unchanged; q2 remains
  46,509 vs Google 44,794 (+3.83%), q5 40,328 vs Google 40,515 (-0.46%),
  q9 39,081 vs Google 39,695 (-1.55%).
- Validation so far:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*large 256-byte periodic*'` passed.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities
2,9 --target native` passed 8/8 cases.
- P3 broad-corpus task remains open for agreed text/binary samples and because
  q9 is fractionally above 5% on this synthetic periodic sample, but q2..q8
  now fit the revised 5% window and the q9 encode-performance cliff is gone.

## 2026-05-30 — target-perf harness commit landed and q11 no-op trial rejected

- Committed the target-perf main-package harness as
  `9180398 bench(brotli): restore native target-perf harness`.
- Final commit evidence uses the new harness with explicit native
  `native_cc: "cc-o0"` rows:
  - q10 encode on `silesia-64k.bin`, repeats=1/samples=1:
    wasm-gc 21,415 bytes vs Google 19,566 (+9.45%), 123.059 ms/op vs Google
    67.021 ms/op.
  - q10 encode on `silesia-64k.bin`, repeats=1/samples=1:
    native `cc-o0` 21,415 bytes vs Google 19,566 (+9.45%), 287.526 ms/op vs
    Google 67.021 ms/op.
  - q10 Google-stream decode on `silesia-64k.bin.google.q10.br`:
    wasm-gc 19,566 input bytes to 65,536 decoded bytes, 63.987 ms/op vs
    Google 71.855 ms/op.
  - q10 Google-stream decode on `silesia-64k.bin.google.q10.br`:
    native `cc-o0` 19,566 input bytes to 65,536 decoded bytes,
    101.989 ms/op vs Google 71.855 ms/op.
- Rejected and reverted a q11-only exact-cost trial that compared pure 4-byte
  high-quality LZ77 against the mixed dictionary candidate:
  - `silesia-64k.bin` q11 target-perf encode stayed at 21,415 bytes vs Google
    19,258 (+11.20%), wasm-gc 141.818 ms/op, native `cc-o0`
    271.251 ms/op.
  - `silesia-128k.bin` q11 target-perf encode stayed at 38,713 bytes vs
    Google 35,164 (+10.09%), wasm-gc 408.710 ms/op, native `cc-o0`
    652.674 ms/op.
- Source files were restored after the rejected trial; `moon check --target
native` passed.

## 2026-05-30 — remaining work replanned under 5% target

- Updated `.planning/brotli-support/task_plan.md` with an ordered remaining
  development plan under the revised q2..q11 ~5% encoded-size target.
- The planned order is now:
  1. land the target-perf main-package harness and native `native_cc: "cc-o0"`
     measurement convention;
  2. refresh the q2..q11 ratio and wasm-gc/native target-perf baseline matrix;
  3. close P3 through broader q2..q9 corpus validation and regression gates
     rather than defaulting to more C-reference algorithm work;
  4. focus P4 on q10/q11 size reduction from roughly +9%/+10% to <=5% using
     bounded parser, dictionary, distance-cache, and block-layout candidates;
  5. escalate to broader bounded shortest-path/Zopfli-style work only if
     lower-cost q10/q11 candidates stall;
  6. rerun decode, roundtrip, fuzz, MoonBit all-target, and target-perf gates
     before declaring P4/release readiness.
- No codec source changes were made for this planning update.

## 2026-05-30 — target-perf native measurement path restored

- Reworked `tools/brotli/bench/target-perf.nu` away from full-package
  generated white-box tests and into an ignored temporary MoonBit main package
  under `src/brotli_target_perf_main/`.
- Native generated benchmark mains now read input bytes from disk through
  MoonBit native C FFI, avoiding 64 KiB+ byte literals in generated MoonBit
  source. wasm-gc/js targets still use embedded byte literals.
- Default native release `clang -O2` remains impractical for the Brotli package
  C output, even after moving from white-box tests to a main package: a 9.1 MiB
  generated C file stayed in `clang -O2` for more than five minutes.
- Added `tools/brotli/bench/native-cc-o0.nu`, a Nushell `MOON_CC` wrapper used
  only by native release target-perf runs. It rewrites Moon's C compiler
  `-O2` flag to `-O0` and target-perf rows report this explicitly as
  `native_cc: "cc-o0"`.
- Validation evidence:
  - `nu --ide-check 0 0 tools/brotli/bench/target-perf.nu` passed.
  - `nu --ide-check 0 0 tools/brotli/bench/native-cc-o0.nu` passed.
  - `moon check --target native` passed.
  - `moon check --target all` passed.
  - q10 encode smoke:
    - native `cc-o0`: 21,415 bytes vs Google 19,566 (+9.45%),
      185.730 ms/op, Google 62.757 ms/op.
    - wasm-gc: 21,415 bytes vs Google 19,566 (+9.45%),
      114.424 ms/op, Google 63.964 ms/op.
  - q10 Google-stream decode smoke:
    - native `cc-o0`: 19,566 input bytes to 65,536 decoded bytes,
      93.656 ms/op, Google 39.480 ms/op.
    - wasm-gc: 19,566 input bytes to 65,536 decoded bytes,
      62.548 ms/op, Google 39.087 ms/op.

## 2026-05-30 — q10/q11 5% target baseline and rejected low-risk trials

- Restored `.planning/brotli-support` under the revised q2..q11 5% acceptance
  policy and checked the current worktree.
- Confirmed `brotli --version` reports `brotli 1.2.0`.
- Re-ran q10/q11 ratio baselines with `tools/brotli/bench/ratio.nu`:
  - `silesia-64k.bin`: q10 21,415 vs Google 19,566 (+9.45%);
    q11 21,415 vs Google 19,258 (+11.20%).
  - `silesia-128k.bin`: q10 38,713 vs Google 35,624 (+8.67%);
    q11 38,713 vs Google 35,164 (+10.09%).
  - `silesia-512k.bin`: q10 135,268 vs Google 124,480 (+8.67%);
    q11 135,268 vs Google 122,869 (+10.09%).
  - `silesia-1m.bin`: q10 264,422 vs Google 242,485 (+9.05%);
    q11 264,422 vs Google 239,314 (+10.49%).
- Re-ran wasm-gc q10/q11 encode target-perf on `silesia-64k.bin` with
  repeats=2/samples=2:
  - q10: 21,415 bytes vs Google 19,566 (+9.45%), wasm-gc min 83.705 ms/op.
  - q11: 21,415 bytes vs Google 19,258 (+11.20%), wasm-gc min 83.822 ms/op.
- Native release target-perf currently cannot be trusted after `moon clean`:
  `moon test --target native --release` hangs in the generated native test's
  `clang -O2` step for the target-perf generated white-box test. Native debug
  target-perf still runs, but is not accepted as release-quality evidence.
  This needs a tooling fix before final native release data can be refreshed.
- Rejected low-risk q10/q11 size trials:
  - lowering mixed-dictionary minimum output length from 8 to 6 produced no
    `silesia-64k.bin` q10/q11 size change and increased legacy verify time;
  - lowering block split prefilter savings from 384 to 128 produced no
    `silesia-64k.bin` q10/q11 size change and increased candidate cost;
  - exact-costing q10/q11 pure 4-byte high-quality LZ77 against mixed
    dictionary produced no `silesia-64k.bin` q10/q11 size change and increased
    candidate cost.
  - raising q10/q11 max match length from 16 KiB to 32 KiB produced no
    `silesia-64k.bin` or `silesia-128k.bin` q10/q11 size change.
  - extending the bounded shortest-path seed to 64 KiB and wiring it into the
    single-metablock q10/q11 path produced no `silesia-64k.bin` size change
    while raising legacy verify time to roughly 35-36s, so the current seed is
    not useful for the 5% gap.
- All rejected source trials were reverted; `git diff` is clean for source
  files and `moon check --target native` passed.

## 2026-05-30 — revise Brotli encoder acceptance target to 5%

- Replanned the remaining Brotli work after maintainer guidance that P4's
  original 2% q10/q11 ratio target is too strict for the current pure-MoonBit
  implementation goals.
- Updated `.planning/brotli-support/task_plan.md` so q2..q11 target roughly
  5% encoded-size overhead versus Google Brotli on agreed validation corpora.
- Kept q0/q1 as valid stored-fast modes outside the q2..q11 ratio target,
  unless the product decision explicitly reopens P2 ratio work.
- Reframed P4 completion around measured q10/q11 outcomes rather than mandatory
  C-reference Zopfli parity:
  - current q10/q11 remain incomplete under the new target because recorded
    Silesia 1 MiB overhead is +9.05%/+10.49%;
  - the next development priority is to reduce q10/q11 to <=5% while
    preserving acceptable wasm-gc/native encode performance;
  - full Zopfli/shortest-path work remains optional and should be used only if
    cheaper high-quality parser, dictionary, block-layout, or bounded
    shortest-path extensions cannot close the gap.
- No source code changed and no validation commands were run for this planning
  update.

## 2026-05-30 — q4+ combined literal/distance block split

- Added the remaining pairwise q4+ block-layout candidate: combined
  literal-block plus explicit-distance-block splitting.
- The candidate keeps independent event boundaries:
  - literal block lengths count inserted literal events;
  - distance block lengths count only explicit distance symbols;
  - command blocks remain single-tree.
- Together with the accepted literal+command and command+distance candidates,
  this completes pairwise literal/command/distance block-layout coverage while
  still avoiding the rejected three-stream joint split.
- Final selection remains exact-costed by emitted bit count.
- Validation evidence:
  - `moon fmt` passed.
  - `moon check --target native` passed.
  - `moon test --target native --filter '*literal and distance blocks together*'`
    passed 1/1 after fixing the synthetic fixture to make the second-half
    distance-64 copies match the expected decoded bytes.
  - `moon test --target native --filter '*splits LZ77*blocks*'` passed 6/6.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`
    passed 12/12 cases.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`
    kept q5 at 40,328 bytes versus Google 40,515 and q9 at 39,081 bytes
    versus Google 39,695.
  - Final pre-commit validation:
    - `moon check --target all` passed.
    - `moon test --target all` passed: 469/469 on wasm, wasm-gc, js, and
      native.
    - `moon info` passed.
    - `git diff --check` passed.
- `target-perf.nu` was not rerun for this structural block-layout increment
  per latest maintainer instruction.

## 2026-05-30 — q4+ combined literal/command block split

- Added a guarded combined literal-block plus command-block split candidate to
  the q4+ LZ77 meta-block writer.
- The candidate reuses the accepted literal and command histogram estimators,
  but keeps independent boundaries:
  - literal block lengths count inserted literal events;
  - command block lengths count command events.
- Distance blocks remain single-tree, so this does not reintroduce the
  rejected binary literal/command/distance joint split or rejected
  three-literal-block trial.
- Final selection remains exact-costed by emitted bit count, so the candidate
  can only win when it beats weighted, literal-only split, command-only split,
  context, and other multi-stream candidates.
- Validation evidence:
  - `moon fmt` passed.
  - `moon check --target native` passed.
  - `moon test --target native --filter '*literal and command blocks together*'`
    passed 1/1.
  - `moon test --target native --filter '*splits LZ77*blocks*'` passed 5/5.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`
    passed 12/12 cases.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`
    kept q5 at 40,328 bytes versus Google 40,515 and q9 at 39,081 bytes
    versus Google 39,695.
  - Final pre-commit validation:
    - `moon check --target all` passed.
    - `moon test --target all` passed: 468/468 on wasm, wasm-gc, js, and
      native.
    - `moon info` passed.
    - `git diff --check` passed.
- `target-perf.nu` was not rerun for this structural block-layout increment
  per latest maintainer instruction.

## 2026-05-30 — q4+ combined command/distance block split

- Added a guarded combined command-block plus distance-block split candidate to
  the q4+ LZ77 meta-block writer.
- The candidate reuses the accepted command and explicit-distance histogram
  estimators, but lets each stream keep its own split boundary rather than
  forcing a single joint boundary.
- The literal tree remains single-tree; this avoids reopening the rejected
  three-literal-block and binary literal/command/distance joint split trials.
- Final selection remains exact-costed by emitted bit count, so the candidate
  can only win when it beats weighted, literal-split, context, command-only
  split, and distance-only split writers.
- Validation evidence:
  - `moon fmt` passed.
  - `moon check --target native` passed.
  - `moon test --target native --filter '*command and distance blocks together*'`
    passed 1/1.
  - `moon test --target native --filter '*splits LZ77*blocks*'` passed 4/4.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`
    passed 12/12 cases.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`
    kept q5 at 40,328 bytes versus Google 40,515 and q9 at 39,081 bytes
    versus Google 39,695.
- `target-perf.nu` was not rerun for this structural block-layout increment
  per latest maintainer instruction.

## 2026-05-30 — q10/q11 bounded match transition cleanup

- Refactored the q10/q11 bounded shortest-path seed so hash-chain matches and
  bounded suffix-tree matches use one shared bounded-copy transition helper.
- Behavior is intended to be unchanged:
  - both providers still offer minimum, half-length, and full-length copy
    candidates;
  - copy costs still use the greedy-seeded cost model;
  - transition cache updates still use the same Brotli recent-distance helper;
  - final candidate selection still exact-costs the written meta-block.
- This cleanup removes duplicated transition logic before any future broader
  Zopfli/suffix-tree parser work.
- Validation evidence:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*bounded*'` passed 6/6.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json`
    kept q10/q11 at 38,713 bytes versus Google 35,624/35,164 bytes.
  - Final pre-commit validation after docs updates:
    - `moon fmt` passed.
    - `moon check --target all` passed.
    - `moon test --target all` passed: 466/466 on wasm, wasm-gc, js, and
      native.
    - `moon info` passed.
    - `git diff --check` passed.
- `target-perf.nu` was not rerun for this behavior-preserving cleanup per
  latest maintainer instruction.

## 2026-05-30 — complete Brotli harness stale-lock recovery

- Extended owner-PID stale-lock recovery from the fuzz runners to:
  - `tools/brotli/conformance/run.nu`,
  - `tools/brotli/bench/target-perf.nu`.
- Changed target-perf to use the stable ignored
  `src/brotli_target_perf_wbtest.mbt` placeholder instead of creating a new
  timestamped generated-test file per run.
- Added the target-perf placeholder path to `.gitignore`.
- Validation evidence:
  - Created `tools/brotli/.harness-lock/pid` with dead PID `999999`, then ran
    `just brotli-conformance-fixture ukkonooa`; stale lock was recovered and
    the fixture passed 1/1.
  - Created the same stale lock, then ran
    `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 2 --targets native --repeats 1 --samples 1 --json`;
    stale lock was recovered and the run reported q2 MoonBit 25,245 bytes
    versus Google 24,364 bytes.
- This target-perf run validated the harness path only; it is not an
  optimization decision run.

## 2026-05-30 — generated-test placeholder cleanup

- Investigated a stale `_build` failure after a fuzz harness run:
  - `tools/brotli/fuzz/roundtrip.nu` removed
    `src/brotli_roundtrip_fuzz_wbtest.mbt`;
  - the following ratio verifier invoked `moon test` through the legacy JS
    path;
  - MoonBit's incremental graph still referenced the removed generated test
    input and failed before rebuilding.
- Rejected a fresh three-literal-block P3 split attempt after checking the
  existing benchmark log: that direction was already measured and rejected on
  2026-05-28 because it did not improve size and regressed native target-perf.
- Updated conformance, decoder fuzz, and encoder roundtrip fuzz harnesses to
  restore ignored placeholder white-box test files instead of deleting the
  generated source path at the end of a successful run.
- Added the three generated white-box placeholder paths to `.gitignore`.
- Validation evidence:
  - `just brotli-roundtrip native 1 8 2 1` passed 1/1.
  - Without `moon clean`, `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 4 --json`
    passed and reported q4 MoonBit 41,176 bytes versus Google 42,666 bytes.
  - `just brotli-fuzz native 2 1` passed 2/2.
  - `just brotli-conformance-fixture ukkonooa` passed 1/1.
- `target-perf.nu` was not rerun for this tooling-only increment per latest
  maintainer instruction.

## 2026-05-30 — release tooling Justfile and Nushell generate cleanup

- Added direct Justfile recipes for:
  - upstream conformance corpus and single-fixture runs,
  - checked-in decoder fuzz,
  - deterministic encoder roundtrip fuzz,
  - ratio plus external decode checks,
  - wasm-gc/native decode and encode target-perf.
- Simplified generated white-box test batch runners with Nushell `generate`:
  - conformance fixture execution,
  - decoder fuzz batch execution,
  - encoder roundtrip fuzz batch execution.
- Kept execution sequential because those scripts share one temporary generated
  MoonBit white-box test file per runner.
- Updated `tools/brotli/README.md`, `CHANGELOG.md`, and
  `docs/brotli_release_report.md` so the new tooling surface is documented.
- Validation evidence:
  - `just --list` parsed the new recipes.
  - `just brotli-roundtrip native 1 8 2 1` passed 1/1.
  - `just brotli-fuzz native 2 1` passed 2/2.
  - `just brotli-conformance-fixture ukkonooa` passed 1/1.
- `target-perf.nu` was not rerun for this tooling-only increment per latest
  maintainer instruction.

## Session — 2026-05-24

- Loaded `moonbit-agent-guide` and `planning-with-files`.
- Inspected `docs/brotli.md`, current source layout, and existing public API
  files.
- Confirmed no Brotli implementation files exist yet under `src/`.
- Confirmed `brotli --version` reports `brotli 1.2.0`.
- Created scoped planning files under `.planning/brotli-support/` and set that
  plan active.

Next: implement the P1 public API foundation and tests, then validate before
moving into the full decoder core.

## P1 Foundation Increment

- Added Brotli-specific `FzipErrorCode` variants, messages, and stable integer
  mappings.
- Added `UnbrotliOptions::default`, `unbrotli_sync`, `UnbrotliStream`, Brotli
  constants, and a 32-bit LSB-first `BrotliBitReader` scaffold.
- Current decoder behavior: accepts the legal empty Brotli stream `[0xa1, 0x01]`
  and rejects unsupported meta-block paths with `BrotliInvalidMetablock`.
- Added white-box tests for error names, bit-reader basics, empty stream decode,
  max input enforcement, padding rejection, and stream buffering.
- Validation completed:
  - `moon check --target all` passed with 3 expected unused-helper warnings.
  - `moon test --target native --filter '*brotli*'` passed, 7/7.
  - `moon test --target wasm-gc --filter '*brotli*'` passed, 7/7.
  - `moon test --target js --filter '*brotli*'` passed, 7/7.
  - `moon test --target native` passed, 375/375.
  - `moon test --target wasm-gc` passed, 375/375.
  - `moon test --target js` passed, 375/375.
  - `moon fmt` completed.
  - `moon info` regenerated `src/pkg.generated.mbti` with the new public API.

Next: commit this foundation increment, then implement enough RFC meta-block
header and uncompressed meta-block handling to start cross-checking generated
streams against the installed Google Brotli CLI.

## P1 Uncompressed Meta-Block Increment

- Implemented meta-block header decoding from the C reference flow:
  `ISLAST`, optional `ISLASTEMPTY`, `MNIBBLES`, length nibbles, metadata header,
  and `ISUNCOMPRESSED` for non-final blocks.
- Added byte-aligned raw byte copying to `BrotliBitReader`.
- Added output builder growth/fixed-buffer handling for uncompressed blocks.
- `unbrotli_sync` now decodes the q=0 Brotli CLI stream for `"hello world"`:
  bytes `03 05 80 ... 03`.
- Compressed Huffman meta-blocks still intentionally raise
  `BrotliInvalidMetablock` with an offset-bearing message.
- Validation completed:
  - `moon check --target all` passed with no warnings.
  - First full test matrix exposed an incorrect test expectation for aligned
    byte copy; fixed expected bytes from `65/66` to `64/65`.
  - `moon test --target native` passed, 377/377.
  - `moon test --target wasm-gc` passed, 377/377.
  - `moon test --target js` passed, 377/377.
  - `moon fmt` completed.
  - `moon info` completed with no public API changes beyond the prior commit.

Next: commit this increment, then start the compressed meta-block foundation:
Huffman table structures, simple/complex Huffman readers, and the first small
reference compressed fixture.

## P1 Huffman Foundation Increment

- Added Brotli Huffman constants and a private `BrotliHuffmanCode` table entry.
- Added canonical length-set validation for empty, over-subscribed, and
  under-subscribed trees.
- Added root-table construction for code lengths up to the current root width
  and `brotli_read_symbol` for table lookup.
- Added white-box coverage for canonical decode, single-symbol trees, and
  malformed length sets.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 11/11.
  - `moon check --target all` passed with 3 expected unused-helper warnings
    because the Huffman foundation is not wired into compressed meta-block
    decoding yet.
  - `moon test --target native` passed, 380/380.
  - `moon test --target wasm-gc` passed, 380/380.
  - `moon test --target js` passed, 380/380.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-helper warnings and no
    public API additions.

Next: wire this foundation into simple Huffman code reading so compressed
meta-block parsing can begin consuming actual RFC Huffman headers.

## P1 Simple Huffman Increment

- Extended `brotli_build_huffman_table` from root-only entries to two-level
  lookup tables with sub-table allocation bounded by
  `brotli_huffman_max_table_size`.
- Added simple Huffman table construction for the reference cases:
  one symbol, two symbols, three symbols, four `[2,2,2,2]` symbols, and four
  `[1,2,3,3]` symbols.
- Added `brotli_read_huffman_code` with the simple-code path. The complex path
  still raises `BrotliInvalidHuffman` until the code-length-code reader lands.
- Added tests for two-level decode, simple three-symbol decode, duplicate
  simple symbols, and symbols outside the alphabet limit.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 14/14.
  - `moon check --target all` passed with 3 expected unused-helper warnings
    because Huffman decode is still not wired into the main compressed
    meta-block state machine.
  - `moon test --target native` passed, 383/383.
  - `moon test --target wasm-gc` passed, 383/383.
  - `moon test --target js` passed, 383/383.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-helper warnings and no
    public API additions.

Next: implement complex Huffman code-length-code reading and RLE decoding of
symbol code lengths, then use that to start parsing real compressed Brotli
meta-block headers.

## P1 Complex Huffman Increment

- Added `brotli_tables.mbt` with code-length-code order and the static
  prefix-code length/value tables from the C reference.
- Added code-length-code reader, target-symbol code-length RLE decoder, and
  complex Huffman table construction.
- Replaced the temporary complex-Huffman error in `brotli_read_huffman_code`
  with the actual complex path.
- Added tests for a minimal complex two-symbol table and a malformed repeat-zero
  sequence that overflows the target alphabet.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 16/16.
  - `moon check --target all` passed with 1 expected unused-helper warning
    because `brotli_read_huffman_code` is not yet wired into the main compressed
    meta-block state machine.
  - `moon test --target native` passed, 385/385.
  - `moon test --target wasm-gc` passed, 385/385.
  - `moon test --target js` passed, 385/385.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-helper warning and no
    public API additions.

Next: start compressed meta-block header parsing: block type/count decoding,
block length tables, context map decoding, and tree group construction.

## P1 Block Metadata Increment

- Added `brotli_block.mbt` with:
  - `brotli_decode_var_len_uint8`
  - `brotli_read_block_type_count`
  - `brotli_read_block_length`
  - `BrotliBlockTracker` and block type ring resolution
- Added block-length base and extra-bit tables from the reference constants.
- Added tests for varlen uint8, block type count, block length base+extra
  decoding, and block type ring behavior.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 19/19.
  - `moon check --target all` passed with 7 expected unused-helper warnings
    because these helpers are not yet wired into the main compressed meta-block
    state machine.
  - `moon test --target native` passed, 389/389.
  - `moon test --target wasm-gc` passed, 389/389.
  - `moon test --target js` passed, 389/389.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-helper warnings and no
    public API additions.

Next: implement context map decoding and tree group containers, then start
using the Huffman/block helpers from `brotli_decode_scaffold`'s compressed
meta-block branch.

## P1 Context Map Increment

- Added `brotli_context.mbt` with:
  - `BrotliContextMap`
  - `brotli_read_context_map`
  - `brotli_inverse_move_to_front`
- Implemented Brotli context-map parsing for `NTREES`, optional zero-run RLE
  prefix, Huffman-coded map entries, repeat overflow validation, and optional
  inverse move-to-front transform.
- Added white-box coverage for implicit zero maps, direct map values, IMTF
  transformation, and malformed RLE overflow.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 23/23.
  - `moon check --target all` passed with 9 expected unused-helper warnings
    because block/context helpers are not yet wired into the compressed
    meta-block state machine.
  - `moon test --target native` passed, 393/393.
  - `moon test --target wasm-gc` passed, 393/393.
  - `moon test --target js` passed, 393/393.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-helper warnings and no
    public API additions.

Next: add a tree group container/reader, then wire block metadata, context maps,
and Huffman tree groups into the compressed meta-block header path.

## P1 Final Acceptance Bookkeeping

- Focused timing:
  - `/usr/bin/time -p moon test --target native --filter 'brotli*'`
  - Passed 32/32.
  - Runtime: real 1.69s, user 1.49s, sys 0.10s.
- Cross-reference fixture evidence:
  - `nu tools/brotli/silesia/verify.nu /Users/hustcer/iWork/refs/rust-brotli/testdata/alice29.txt.compressed /Users/hustcer/iWork/refs/rust-brotli/testdata/alice29.txt`
  - Decoded size 152089 and SHA-256
    `7467306ee0feed4971260f3c87421154a05be571d944e9cb021a5713700c38f0`.
  - `brotli -d -c` also compared the same rust-brotli fixture successfully.
- Dictionary-transform fixture evidence:
  - `nu tools/brotli/conformance/run.nu --fixture ukkonooa` passed.
  - `brotli -d -c /Users/hustcer/iWork/refs/brotli/tests/testdata/ukkonooa.compressed`
    compared successfully with the expected file.

P1 is functionally complete for the documented decoder acceptance gates. The
24-hour fuzz gate remains a P3-entry gate per the fuzz strategy.

## P2 q=0/q=1 Encoder Increment

- Added `BrotliOptions` with `quality` and `window_bits`; default is quality 1,
  window bits 22.
- Added `brotli_sync` and `BrotliStream`.
- Added `src/brotli_encode.mbt` with a small LSB-first bit writer and an
  uncompressed-meta-block encoder backend for q=0/q=1.
- Added round-trip tests for empty input, small q=0 input, and input spanning
  multiple 16 MiB Brotli meta-blocks.
- Added coverage for every standard `window_bits` value from 10 through 24,
  including the special RFC encoding for 17.
- Added `tools/brotli/encode/verify.nu`, which encodes through MoonBit JS and
  validates the generated stream with the external `brotli` CLI.
- Validation completed so far:
  - `moon fmt` passed.
  - `moon check --target all` passed.
  - `moon test --target native --filter 'brotli*'` passed, 36/36.
  - `moon test --target all` passed, 430/430 on wasm, wasm-gc, js, native.
  - `nu tools/brotli/encode/verify.nu src/tests/brotli_fixtures/quickfox.expected --quality 0`
    passed with Google CLI decode SHA-256 matching input SHA-256.
  - `nu tools/brotli/encode/verify.nu src/tests/brotli_fixtures/quickfox.expected --quality 0 --window-bits 17`
    passed with Google CLI decode SHA-256 matching input SHA-256.
  - `nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 0`
    passed; encoded size 104857629, encoded SHA-256
    `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25`,
    decoded SHA-256
    `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
  - `nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 1`
    passed with the same encoded/decode SHA-256 values.

Next: run final `moon info`, full conformance and Silesia decoder scripts, then
commit the P2 increment.

## P3 q=2..9 Dispatch Increment

- Ran decoder fuzz smoke before changing encoder dispatch:
  - `nu tools/brotli/fuzz/gen-corpus.nu --count 50`
  - `nu tools/brotli/fuzz/run.nu --limit 50`
  - Passed 50/50 generated/seed inputs.
- Enabled `brotli_sync` qualities 2 through 9 through the current
  uncompressed-meta-block backend.
- Moved `BrotliOptions::default()` from quality 1 to quality 9.
- Added q=0..9 and default-quality round-trip tests.
- Added `docs/brotli_benchmarks.md` with Silesia q=2/q=9 external-decoder
  validation and an explicit note that ratio targets are not met by this
  backend.
- Validation completed:
  - `moon fmt` passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 2`
    passed; encoded size 104857629, encoded SHA-256
    `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25`,
    decoded SHA-256
    `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
  - `nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 9`
    passed with the same encoded/decode SHA-256 values.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 432/432 on wasm, wasm-gc, js, native.
  - `moon info` passed.

Next: commit the q=2..9 dispatch increment, then wire q=10/q=11 dispatch.

## P4 q=10/q=11 Dispatch Increment

- Enabled `brotli_sync` qualities 10 and 11 through the current
  uncompressed-meta-block backend.
- Moved `BrotliOptions::default()` from quality 9 to quality 11.
- Expanded quality round-trip coverage from q=0..9 to q=0..11.
- Updated `docs/brotli_benchmarks.md` with q=10/q=11 Silesia external-decoder
  validation and the explicit ratio gap note.
- Validation completed:
  - `moon fmt` passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 10`
    passed; encoded size 104857629, encoded SHA-256
    `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25`,
    decoded SHA-256
    `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
  - `nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 11`
    passed with the same encoded/decode SHA-256 values.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 432/432 on wasm, wasm-gc, js, native.
  - `moon info` passed.
  - `nu tools/brotli/conformance/run.nu` passed all 22 upstream fixtures.
  - `nu tools/brotli/silesia/verify.nu` passed with decoded size 104857600 and
    SHA-256
    `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.

Next: commit the q=10/q=11 dispatch increment. The remaining known gap is
compression ratio, not stream validity or API coverage.

## Completion Audit Correction

- Re-read `docs/brotli.md` P2/P3/P4 acceptance criteria after resuming the
  active goal.
- Corrected the phase checklist: q2..q11 dispatch commits are useful verified
  increments, but they do not complete P3/P4 because the encoder still emits
  uncompressed meta-blocks for all qualities.
- Active gap:
  - P3: implement real standard back-reference encoder, Huffman/meta-block
    construction, and ratio benchmark within 5% of C reference.
  - P4: implement q10/q11 high-quality/Zopfli search path and ratio benchmark
    within 2% of C reference.

Next: inspect the decoder command/Huffman tables and build the first compressed
meta-block encoder path that emits literal/copy commands instead of raw stored
meta-blocks.

## P3 Compressed Repeated-Run Increment

- Inspected existing decoder internals:
  - `brotli_command_info` gives the command prefix table needed by the encoder.
  - simple one-symbol Huffman trees decode without payload bits, which is ideal
    for a repeated-byte compressed meta-block.
  - distance code 16 with one extra bit set to zero resolves to explicit
    distance 1 when `NPOSTFIX = 0` and `NDIRECT = 0`.
- Added a q2+ compressed path for single-byte runs:
  - final compressed meta-block;
  - one literal/command/distance block type;
  - one literal context tree and one distance context tree;
  - one inserted literal followed by an explicit distance-1 copy.
- q0/q1 remain on the uncompressed fast path.
- Added a white-box round-trip/size test proving q2 compresses 1024 repeated
  `A` bytes smaller than q1.
- External validation:
  - created `target/brotli-encode/repeated-a-1k.bin` with 1024 `A` bytes;
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/repeated-a-1k.bin --quality 2`
    passed;
  - encoded size 11 bytes;
  - encoded SHA-256
    `11374c099faa11902a4c6dc08f14a34f0e7b46892d705492c9cd83dff75b9473`;
  - decoded/input SHA-256
    `6ab72eeb9e77b07540897e0c8d6d23ec8eef0f8c3a47e1b3f4e93443d9536bed`.
- Validation completed:
  - `moon fmt` passed.
  - `moon test --target native --filter '*repeated byte*'` passed, 1/1.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 433/433 on wasm, wasm-gc, js, native.
  - `moon info` passed.

Next: commit this compressed-run increment, then generalize q2+ matching to
non-trivial repeated substrings and multi-command meta-blocks.

## P3 Short-Period Compressed Increment

- Generalized the first q2+ compressed path from single-byte runs to whole-input
  periods of length 1 through 4 when the period has unique symbols.
- Added simple-Huffman literal payload emission by deriving bit payloads from
  the same simple table layout used by the decoder.
- Added explicit distance prefix selection for distances 1 through 4.
- Added white-box coverage for a 1024-byte repeated `ABCD` input.
- External validation:
  - created `target/brotli-encode/periodic-abcd-1k.bin`;
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcd-1k.bin --quality 2`
    passed;
  - encoded size 15 bytes;
  - encoded SHA-256
    `b93fc934c730cff0147930ef7572a745f2c8fd28153e836d3f103d6026ab2aeb`;
  - decoded/input SHA-256
    `c2bc376eb7cee7a17331cb38d1637fe08c710b3d8167764f7ec92fd865814d8e`.
- Validation completed:
  - `moon fmt` passed.
  - `moon test --target native --filter '*compresses * with LZ77 copy*'`
    passed, 2/2.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 434/434 on wasm, wasm-gc, js, native.
  - `moon info` passed.

Next: commit the short-period increment, then move from whole-input periodic
matches to a greedy multi-command LZ77 stream.

## P3 Single-Copy Prefix Increment

- Replaced the special-case whole-period detector with a more general
  single-copy matcher:
  - inserts a prefix of up to 256 bytes;
  - requires the inserted prefix to have at most four distinct literal values;
  - copies the rest of the input from any prior distance whose suffix matches.
- The previous repeated-byte and short-period cases now fall out of the same
  single-copy path.
- Added white-box coverage for `X` followed by repeated `ABC`.
- External validation:
  - created `target/brotli-encode/prefix-x-abc-1k.bin`;
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/prefix-x-abc-1k.bin --quality 2`
    passed;
  - encoded size 15 bytes;
  - encoded SHA-256
    `c4b785c5553afc3e367bb3db0cb9a487292d4cc127eb107ff502043aab815993`;
  - decoded/input SHA-256
    `b0ac63f256924c623429f859f6106c51afb4b2e2da1623ba19ec644765f48914`.
- Validation completed:
  - `moon fmt` passed.
  - `moon test --target native --filter '*LZ77 copy*'` passed, 2/2.
  - `moon test --target native --filter '*copied suffix*'` passed, 1/1.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 435/435 on wasm, wasm-gc, js, native.
  - `moon info` passed.

Next: commit this increment, then implement multi-command output with small
literal alphabets before moving to complex Huffman trees.

## P3 Multi-Command Simple-Huffman Increment

- Added a greedy multi-command encoder path for q2+ inputs that:
  - are at most 64 KiB;
  - contain at most four distinct literal bytes;
  - produce at most four command symbols and four distance symbols;
  - use simple Huffman trees for literals, commands, and distances.
- The matcher scans previous distances up to 256 bytes and currently caps each
  match at 6 bytes to keep command-symbol variety bounded while complex
  Huffman output is not implemented.
- Added white-box coverage for `ABCABCX` followed by repeated `ABCABC`.
- External validation:
  - created `target/brotli-encode/small-alpha-multicopy-1207.bin`;
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multicopy-1207.bin --quality 2`
    passed;
  - encoded size 17 bytes;
  - encoded SHA-256
    `e3004449f7c34d354c3e42c25c80af9eb20fa9a316a7e2266ee9de23161e178e`;
  - decoded/input SHA-256
    `5cda1187aab97e0d2172c16e206ea42c02a568ccb804f9d0e316520da2f677a7`.
- Error/learning:
  - an earlier 1400-byte small-alphabet pattern did not use the compressed path
    because the generated command alphabet exceeded simple Huffman's four-symbol
    limit; this motivates complex Huffman tree emission next.
- Validation completed:
  - `moon fmt` passed.
  - `moon test --target native --filter '*multiple small alphabet copies*'`
    passed, 1/1.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 436/436 on wasm, wasm-gc, js, native.
  - `moon info` passed.

Next: commit this increment, then implement complex Huffman code emission so
the encoder can handle realistic literal/command/distance alphabets.

## P3 Complex Huffman Increment

- Added encoder-side complex Huffman tree emission:
  - builds a deterministic fixed-length canonical tree for the active alphabet;
  - pads the active symbol set to a power of two with dummy symbols;
  - writes the code-length-code lengths using Brotli's fixed prefix table;
  - emits target alphabet code lengths without RLE;
  - reuses canonical payload calculation for encoded symbols.
- Lifted the previous four-symbol cap from q2+ literal, command, and distance
  alphabets. Simple Huffman is still used for alphabets of up to four symbols.
- Added regression coverage for:
  - five-symbol literal alphabets (`ABCDE...`);
  - command alphabets that previously exceeded simple-Huffman limits.
- External validation:
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-1025.bin --quality 2`
    passed; encoded size 22 bytes, encoded SHA-256
    `7cc14af91a972848744c19fec74d38a850ef059aaffaa490e566a0886fceefb0`.
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multi-1400.bin --quality 2`
    passed; encoded size 306 bytes, encoded SHA-256
    `385baf3fcd2396020985a9736ad9517ad1b4eaf45644043495fa9d04912a89cc`.
- Validation completed:
  - `moon fmt` passed.
  - `moon test --target native --filter '*complex * Huffman*'` passed, 2/2.
  - `moon check --target all` passed.
  - `moon test --target all` passed, 438/438 on wasm, wasm-gc, js, native.
  - `moon info` passed.

Next: commit this increment, then add frequency-weighted code lengths and a
less artificial match finder so Silesia ratio can start moving materially.

## P3 Ratio Harness Increment

- Added `tools/brotli/bench/ratio.nu`.
- The script compares MoonBit `brotli_sync` output against Google `brotli` for
  selected qualities and delegates MoonBit validation to
  `tools/brotli/encode/verify.nu`.
- Updated `tools/brotli/README.md` with benchmark usage.
- Baseline runs:
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2`
    passed; MoonBit q2 size 306, Google q2 size 169.
  - `nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2`
    passed; MoonBit q2 size 104857629, Google q2 size 35495150.
- The Silesia result confirms the remaining P3 blocker is broad match/block
  coverage on realistic mixed data, not malformed stream output.

Next: commit the ratio harness, then implement block-local compressed encoding
for large inputs so Silesia can move off the uncompressed fallback.

## P1 Huffman Tree Group Increment

- Added compressed-header constants for literal alphabet size, command alphabet
  size, context-bit widths, distance short codes, and standard distance
  alphabet sizing.
- Added `brotli_tree_group.mbt` with `BrotliHuffmanTreeGroup`,
  `num_trees`, `tree(index)`, and `brotli_read_huffman_tree_group`.
- Added white-box coverage for reading two consecutive simple Huffman trees
  from one bitstream and rejecting invalid tree-group parameters.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 25/25.
  - `moon check --target all` passed with 21 expected unused-helper warnings
    because compressed-header helpers are still not wired into the main
    decoder path.
  - `moon test --target all` passed, 395/395 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-helper warnings and no
    public API additions.

Next: build a compressed meta-block header reader that consumes block type
counts, block type/length trees, distance parameters, context modes, context
maps, and the literal/command/distance tree groups.

## P1 Compressed Header Increment

- Added `brotli_compressed_header.mbt` with:
  - `BrotliBlockSwitchHeader`
  - `BrotliCompressedMetablockHeader`
  - block switch header decoding
  - context-mode reading
  - compressed meta-block header decoding through the three Huffman tree groups
- Wired `brotli_decode_scaffold` to parse compressed meta-block headers before
  raising the current body-not-implemented `BrotliInvalidMetablock`.
- Added white-box coverage for a trivial compressed header with one literal,
  command, and distance block type.
- Updated the unsupported compressed-path test fixture so it now contains a
  complete compressed header and fails at the intended body boundary rather than
  with `UnexpectedEOF`.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 26/26.
  - `moon check --target all` passed with 24 expected unused-field warnings;
    these fields are parsed and stored for the upcoming command/body loop.
  - `moon test --target all` passed, 396/396 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-field warnings and no
    public API additions.

Next: implement the command prefix decoding tables and the first compressed
body loop path for literal-only commands.

## P1 Command Prefix Increment

- Added `brotli_command.mbt` with:
  - `BrotliCommandInfo`
  - `BrotliCommand`
  - generated-equivalent command prefix lookup logic
  - command decoding with insert/copy extra bits
- Wired the compressed scaffold path to read the first command from the command
  tree after parsing the compressed header.
- Added white-box coverage for command lookup cases matching the C reference
  table and for command extra-bit application.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 28/28.
  - `moon check --target all` passed with 26 expected unused-field warnings;
    parsed command/header fields will be consumed by the upcoming body loop.
  - `moon test --target all` passed, 398/398 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-field warnings and no
    public API additions.

Next: implement literal insertion for trivial literal-context blocks, then
advance to distance/back-reference handling.

## P1 Literal-Only Compressed Body Increment

- Added `brotli_decode_compressed_metablock_body` for the first narrow body
  path: read one command, insert literals from the first literal tree, and
  finish successfully when the insert length exactly consumes the meta-block.
- Replaced the scaffold's unconditional compressed-body error with the new body
  helper; unsupported copy/distance cases still raise `BrotliInvalidMetablock`.
- Added reusable white-box fixture writers for a standard 10-bit window final
  compressed meta-block and trivial compressed headers.
- Added a synthetic compressed `unbrotli_sync` fixture that decodes to `AA`.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 29/29.
  - `moon check --target all` passed with 25 expected unused-field warnings;
    these cover block switching, copy/distance fields, context maps, and
    distance tree state that the next body increments will consume.
  - `moon test --target all` passed, 399/399 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with the same expected unused-field warnings and no
    public API additions.

Next: implement copy/back-reference handling for short backward distances, then
wire block-length decrement and block switching.

## P1 Implicit Distance Copy Increment

- Added `brotli_distance.mbt` with the RFC/reference recent-distance ring
  initial values `[16, 15, 11, 4]`, negative-safe ring slot normalization, short
  code resolution, and ring update.
- Added `BrotliOutputBuilder::copy_from_distance` for bounded LZ77 copy from
  already-emitted output, including overlapping copies.
- Extended `brotli_decode_compressed_metablock_body` into a command loop:
  inserts literals, resolves implicit short-distance commands, copies from
  previous output, records successful distances, and rejects unsupported
  explicit-distance commands.
- Replaced the previous unsupported-body fixture expectation with a malformed
  no-history back-reference that now raises `BrotliInvalidDistance`.
- Added a synthetic compressed fixture that decodes to `AAAAAA` via insert 4 +
  implicit distance 4 copy 2.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 30/30.
  - `moon test --target all` passed, 401/401 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary unused-field/helper warnings
    and no public API additions.
  - `moon check --target all` passed with the same expected warnings.

Next: implement explicit distance symbol decoding, including direct/postfix
distance formulas and distance tree/context selection.

## P1 Explicit Distance Increment

- Added RFC §4 distance helpers:
  `brotli_distance_extra_bits`, `brotli_distance_offset`, and
  `brotli_read_distance`.
- Wired `brotli_decode_compressed_metablock_body` to read explicit distance
  symbols from the distance tree when the command prefix requires them.
- Extended the compressed-header fixture writer to choose the distance-tree
  one-symbol value.
- Added white-box checks for direct/postfix distance formulas and a synthetic
  compressed fixture using command symbol 160 plus distance symbol 17 with extra
  bit 1 to copy from distance 4.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 32/32.
  - `moon check --target all` passed with expected temporary warnings.
  - `moon test --target all` passed, 403/403 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary warnings and no public API
    additions.

Next: add block-length decrement and block switching for literal, command, and
distance block groups so multi-block compressed meta-blocks can select the
right Huffman trees.

## P1 Block Switching Increment

- Added `BrotliBlockTracker::new_with_length` and `ensure_ready`, using parsed
  first block lengths and reading block type/length trees whenever a block is
  exhausted.
- Added `brotli_context_map_tree_index` to validate block/context-to-tree
  lookups.
- Wired compressed body decoding to:
  - switch command blocks before reading each command,
  - switch literal blocks before reading each inserted literal,
  - switch distance blocks before reading explicit distance symbols,
  - choose literal and distance trees through the parsed context maps.
- Added a white-box compressed body test that uses two literal block types and
  two literal trees to decode `AB` after the first literal block expires.
- Validation completed:
  - `moon test --target native --filter '*brotli*'` passed, 32/32.
  - `moon test --target native --filter 'compressed body switches literal blocks'`
    passed, 1/1.
  - `moon check --target all` passed with expected temporary warnings.
  - `moon test --target all` passed, 404/404 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary warnings and no public API
    additions.

Next: implement literal context mode computation from previous literals and
then move distance-ring persistence out of the per-meta-block body helper.

## P1 Literal Context Increment

- Added literal context-id helpers for all four RFC modes:
  LSB6, MSB6, UTF8, and SIGNED.
- Updated compressed body decoding to compute literal context from the previous
  two output bytes before each inserted literal and to choose literal trees via
  the parsed context mode and literal context map.
- Added tests for reference context categories and a compressed body fixture
  that maps LSB context 1 to a second literal tree, decoding `AB`.
- Validation completed:
  - `moon test --target native --filter '*context*'` passed, 5/5.
  - `moon test --target native --filter 'compressed body selects literal tree by LSB context'`
    passed, 1/1.
  - `moon check --target all` passed with expected temporary warnings.
  - `moon test --target all` passed, 406/406 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary warnings and no public API
    additions.

Next: introduce a decoder state object so the recent-distance ring persists
across compressed meta-blocks, then start handling dictionary distances.

## P1 Decoder State Increment

- Added `BrotliDecoderState` with a persistent `BrotliDistanceRing`.
- Created one decoder state in `brotli_decode_scaffold` and passed it into each
  compressed meta-block body.
- Removed the per-body distance ring allocation so recorded distances survive
  across body calls.
- Added a white-box test that records explicit distance 2 in one body and then
  reuses it through an implicit short-distance command in a later body.
- Validation completed:
  - `moon test --target native --filter 'compressed body preserves distance ring in decoder state'`
    passed, 1/1.
  - `moon check --target all` passed with expected temporary warnings.
  - `moon test --target all` passed, 407/407 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary warnings and no public API
    additions.

Next: implement static dictionary data/transforms or add a bounded placeholder
path that distinguishes dictionary distance handling from invalid backward
references.

## P1 Static Dictionary Identity Increment

- Generated `src/brotli_dictionary_data.mbt` from
  `/Users/hustcer/iWork/refs/brotli/c/common/dictionary.bin`.
- Added `brotli_dictionary.mbt` with static dictionary size-bit and offset
  metadata by word length.
- Added `BrotliOutputBuilder::copy_from_dictionary` for dictionary addresses
  that resolve to transform index 0 (identity).
- Routed copy commands with distance greater than the current output length to
  dictionary address resolution instead of treating them as ordinary invalid
  backward distances.
- Added tests for direct identity dictionary copy and a compressed-body command
  that decodes dictionary word `time`.
- Validation completed:
  - `moon test --target native --filter '*dictionary*'` passed, 5/5.
  - `moon check --target all` passed with expected temporary warnings.
  - `moon test --target all` passed, 409/409 on native, js, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary warnings and no public API
    additions.

Next: port dictionary transform metadata and implement non-identity transform
application.

## P1 Static Dictionary Transform Increment

- Generated `src/brotli_transform_data.mbt` from
  `/Users/hustcer/iWork/refs/brotli/c/common/transform.c`.
- Added dictionary transform application for standard prefixes, suffixes,
  omit-last 1..9, omit-first 1..9, uppercase-first, and uppercase-all.
- Routed dictionary references through the transform table instead of accepting
  only transform index 0.
- Added a white-box test for an uppercase/suffix dictionary transform.
- Validation completed:
  - `moon test --target native --filter '*dictionary*'` passed, 6/6.
  - `moon check --target all` passed with expected temporary warnings.
  - `moon test --target all` passed, 410/410 on native, js, wasm, and wasm-gc.
  - `moon fmt` completed.
  - `moon info` completed with expected temporary warnings and no public API
    additions.

Next: build the corpus/conformance path for real Brotli fixtures, tighten
window-distance limits, and remove temporary warnings as remaining helpers are
wired.

## P1 Fixture and Conformance Increment

- Generated the embedded fixture set with `tools/brotli/gen-fixtures.nu`.
  `quickfox_repeated` now computes its expected output from the short
  `quickfox` phrase to avoid a generated source file large enough to overflow
  `moon fmt`.
- Added `src/brotli_fixture_wbtest.mbt` plus fixture files under
  `src/tests/brotli_fixtures/` for `empty`, `10x10y`, `64x`, `quickfox`,
  `quickfox_repeated`, `ukkonooa`, `monkey`, and `random_org_10k_bin`.
- Added `tools/brotli/conformance/run.nu` to generate a temporary
  `src/brotli_conformance_wbtest.mbt` per upstream fixture and run native
  `moon test` against it.
- Added `tools/brotli/README.md` with generator and conformance commands.
- Fixed corpus-exposed decoder bugs:
  - single-symbol/zero-bit Huffman tables now decode without consuming bits;
  - root-table lookup at physical EOF can select from already buffered bits
    while still raising `UnexpectedEOF` if the selected symbol needs more bits;
  - code-length-code length reading stops when the code space is complete;
  - dictionary copies no longer record static-dictionary distances in the
    recent-distance ring;
  - compressed meta-block remaining length is decremented by actual emitted
    bytes so dictionary transforms with prefixes/suffixes are handled.
- Validation completed on 2026-05-24 06:28 CST:
  - `moon fmt` passed.
  - `moon check --target all` passed with 6 known temporary unused warnings.
  - `moon test --target all` passed: 418/418 on wasm, wasm-gc, js, and native.
  - `moon test --target native --filter '*fixture*'` passed: 9/9.
  - `moon info` passed with the same 6 known temporary unused warnings.
  - `nu tools/brotli/conformance/run.nu` passed all 22 upstream fixtures.
  - Google `brotli -d -c` matched every embedded `.br` fixture against its
    `.expected` file.
  - `src/brotli_conformance_wbtest.mbt` was removed after the conformance run.

Next: commit this verified fixture/conformance increment, then continue P1
hardening: window-distance limits, explicit malformed/truncation/bomb tests,
fuzz harness scaffolding, and Silesia q=11 acceptance evidence.

## P1 Window, Negative-Test, and Fuzz-Harness Increment

- Added Brotli window-gap constant and decoder-state maximum backward distance:
  `min(output_position, (1 << window_bits) - 16)`.
- Changed compressed-body distance handling to route only distances within that
  capped maximum to LZ77 output copies; larger distances now resolve through the
  static dictionary path.
- Changed static dictionary address calculation to use
  `distance - max_distance - 1`, matching the Google C reference.
- Added recent-distance compensation when a short-code distance resolves to the
  static dictionary, avoiding incorrect ring movement for dictionary copies.
- Added negative tests for:
  - large-window header path (`BrotliLargeWindowNotSupported`);
  - trailing nonzero bytes after final meta-block (`BrotliInvalidPadding`);
  - uncompressed output bomb rejection through `max_output_size`;
  - truncated prefixes for embedded small fixtures.
- Verified Google `brotli 1.2.0` rejects a valid `quickfox` payload followed
  by nonzero trailing data and by a second Brotli stream; fzip matches by
  rejecting trailing nonzero data.
- Added `tools/brotli/fuzz/gen-corpus.nu` and `tools/brotli/fuzz/run.nu`.
  The harness generates fixture-seeded truncation/append/delete mutations,
  runs native temporary white-box tests, and treats any non-`FzipError` panic as
  a failed run.
- Added a shared `tools/brotli/.harness-lock` in conformance and fuzz runners
  after a parallel smoke attempt exposed that Moon test discovery can race with
  temporary file cleanup.
- Validation completed on 2026-05-24 06:40 CST:
  - `moon fmt` passed.
  - `moon check --target all` passed with the same 6 known temporary unused
    warnings.
  - `moon test --target all` passed: 424/424 on wasm, wasm-gc, js, and native.
  - `moon info` passed with the same 6 known temporary unused warnings.
  - `nu tools/brotli/conformance/run.nu` passed all 22 upstream fixtures.
  - `nu tools/brotli/fuzz/gen-corpus.nu --count 5` followed by
    `nu tools/brotli/fuzz/run.nu --limit 5` passed; generated corpus artifacts
    and temporary test files were removed afterward.

Next: commit this verified hardening increment, then locate or generate the
100 MB Silesia q=11 acceptance artifact and clean up or explicitly justify the
remaining temporary warnings before declaring P1 complete.

## P1 Silesia q=11 Acceptance Increment

- Downloaded the standard Silesia corpus to ignored `target/brotli-silesia/`
  and built a deterministic 100 MiB slice from:
  `webster mozilla mr dickens x-ray ooffice xml samba nci sao reymont osdb`.
- Recorded Silesia slice SHA-256:
  `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
- Compressed the slice with Google `brotli 1.2.0` at q=11 and verified
  `brotli -t` accepts it. Compressed SHA-256:
  `535c6bfaaf077ee30ef88a54ade88e08e3f0b91204efac10731c35b25961fd1e`.
- Found a smaller long-stream reproducer (`webster` plus `mozilla` prefix)
  that initially failed after crossing the corpus boundary.
- Compared fzip's JavaScript backend against an instrumented local copy of the
  Google C decoder and fixed two UTF8 literal-context edge cases:
  - second-last bytes `208..223` contribute `0`, not `2`;
  - byte `127` is treated as control in both UTF8 context tables.
- Added white-box tests for the context boundaries.
- Added `tools/brotli/silesia/verify.nu`, a Nushell wrapper that rebuilds the
  MoonBit JavaScript test bundle, invokes `unbrotli_sync`, and checks decoded
  size plus SHA-256 against an expected file.
- Validation so far:
  - `moon fmt` passed.
  - `moon test --target native --filter '*literal context*'` passed: 1/1.
  - `nu tools/brotli/silesia/verify.nu target/brotli-silesia/webster-mozilla4k.bin.br target/brotli-silesia/webster-mozilla4k.bin` passed.
  - direct JS verification passed for `webster + 64 KiB mozilla`, decoded size
    `41524239`, SHA-256
    `6a9d1c2101a80b35cc60801e30143c108093a4930a6b2499b7f67c19e939437c`.
  - direct JS verification passed for the 100 MiB Silesia q=11 artifact,
    decoded size `104857600`, SHA-256
    `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
  - Full final validation passed:
    - `moon fmt`
    - `moon check --target all` with the same 6 known temporary warnings
    - `moon test --target all`: 424/424 on wasm, wasm-gc, js, and native
    - `moon info` with the same 6 known temporary warnings
    - `nu tools/brotli/conformance/run.nu`: 22/22 upstream fixtures
    - `nu tools/brotli/silesia/verify.nu`: decoded size `104857600`,
      SHA-256
      `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`

Next: commit this acceptance increment, then clean up or explicitly justify the
remaining temporary warnings before marking P1 complete.

## P1 Warning Cleanup Increment

- Removed private Brotli helpers and tree-group metadata that were only kept for
  earlier white-box tests:
  - `BrotliBitReader::bits_consumed`
  - `BrotliBlockTracker::new`
  - stored `alphabet_size_max`, `alphabet_size_limit`, `root_bits`, and
    `num_trees()` on `BrotliHuffmanTreeGroup`
- Updated white-box tests to inspect private state directly where needed.
- Validation completed:
  - `moon fmt` passed.
  - `moon check --target all` passed with no warnings.
  - `moon test --target all` passed: 424/424 on wasm, wasm-gc, js, and native.
  - `moon info` passed with no warnings.
  - `nu tools/brotli/conformance/run.nu` passed all 22 upstream fixtures.
  - `nu tools/brotli/silesia/verify.nu` passed with decoded size
    `104857600` and SHA-256
    `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.

Next: commit warning cleanup, then run longer fuzzing/final P1 bookkeeping.

## P3 q2 Chunked Hash-Match Increment

- Added q2 large-input chunking around the existing simple LZ77 meta-block
  writer, using 65,535-byte chunks and a final empty meta-block.
- Replaced the per-position local distance scan with a bounded hash-chain match
  table. Matches must prove four bytes before extension and are capped at 64
  bytes for this increment.
- Added a conservative low-alphabet gate for the q2 compressed chunk path. Chunks
  with more than 16 unique literal bytes fall back to stored blocks until the
  encoder has stronger entropy coding and block splitting.
- Fixed a chunk-splicing bug: independently encoded uncompressed chunks were
  invalid because their padding was aligned from bit offset zero, not the active
  stream bit offset. Stored chunks are now written directly to the main writer.
- Added white-box coverage for a 200 KiB periodic q2 input that must compress
  below q1 and round-trip through `unbrotli_sync`.
- External validation:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-128k.bin --quality 2` passed after the stored-chunk fix.
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2` passed: encoded size 2,820 bytes, encoded SHA-256 `39f3ef856d8b1099306bd1c3272c176cd237c4f5ae8395c5562b2483c6d17327`.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2` passed: MoonBit 1,048,628 bytes vs Google 320,418 bytes.
  - `nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2` passed: MoonBit 104,862,404 bytes vs Google 35,495,150 bytes.
- Validation completed:
  - `moon fmt`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*complex * Huffman*'`
  - `moon test --target native --filter '*LZ77 copy*'`
  - `moon check --target all`
  - `moon test --target all`: 439/439 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit this chunked q2 increment, then continue P3 with frequency-weighted
Huffman lengths and broader natural-data block splitting.

## P3 q2 Weighted Huffman Increment

- Extended complex Huffman emission so the code-length-code alphabet is itself
  generated as a complete prefix tree. The encoder can now write arbitrary
  target code lengths instead of only `0` and a single fixed length.
- Added a small frequency-weighted Huffman tree builder for q2 compressed
  chunks with up to 16 symbols. Literal, command, and distance trees now use
  measured frequencies when that beats the fixed-length alternative in the
  simple LZ77 meta-block path.
- External validation:
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multi-1400.bin --quality 2` passed: 231 bytes, SHA-256 `9f089e3ac9defbfbd82c19370b93e716d3f35ae2b500d4dd4e2655531423ad8b`.
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-1025.bin --quality 2` passed: unchanged at 22 bytes.
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2` passed: 2,820 bytes, SHA-256 `39f3ef856d8b1099306bd1c3272c176cd237c4f5ae8395c5562b2483c6d17327`.
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2` passed: MoonBit 231 bytes vs Google 169 bytes.
  - `nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2` passed: unchanged at MoonBit 104,862,404 bytes vs Google 35,495,150 bytes.
- Validation completed:
  - `moon fmt`
  - `moon test --target native --filter '*complex * Huffman*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*LZ77 copy*'`
  - `moon check --target all`
  - `moon test --target all`: 439/439 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit this weighted-Huffman increment, then work on removing the
low-alphabet gate with natural-data block splitting and compressed/stored
costing.

## P3 q2 Sampled Match-Density Gate Increment

- Replaced the strict `<=16` literal-symbol q2 compressed-chunk gate with a
  sampled match-density gate. Low-alphabet chunks still pass immediately; high-
  alphabet chunks must show dense repeated 4-byte sequences at sampled positions.
- Added a 1,200-command cap in simple LZ77 command construction to keep broad
  natural-data candidates bounded in the JavaScript verification harness.
- Added white-box coverage for a high-alphabet repetitive chunk stream. The test
  cycles all 256 byte values, proves the input exceeds the old 16-literal gate,
  requires q2 to beat q1, and round-trips through `unbrotli_sync`.
- External validation:
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2` passed: encoded size 5,878 bytes, SHA-256 `e4f96c81a833bc5e8052c8af716c3095120504681924ea9470821d622121b5a7`.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2` passed: MoonBit 1,048,628 bytes vs Google 320,418 bytes.
  - `nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2` passed: unchanged at MoonBit 104,862,404 bytes vs Google 35,495,150 bytes.
- Validation completed:
  - `moon fmt`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*complex command Huffman*'`
  - `moon test --target native --filter '*repeated byte*'`
  - `moon test --target native --filter '*short periodic*'`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit this bounded gate-widening increment, then continue with real
natural-data block splitting / command partitioning because Silesia remains far
outside the P3 ratio target.

## P3 q2 Longer Match Increment

- Increased the bounded q2 hash-match extension cap from 64 bytes to 4,096
  bytes. Command prefix encoding already handles the longer copies, so this
  reduces command count without changing the meta-block format.
- External validation:
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2` passed: encoded size 249 bytes, SHA-256 `59992ec9753734496469262136d5063839da2dacc00434c4f43a185a897d5c8c`.
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2` passed: encoded size 1,399 bytes, SHA-256 `75a268e3beae7baff6fb8ca4eedf07306b7a8155f8854ccadf5275fb4fb19c3e`.
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2` passed: unchanged at MoonBit 231 bytes vs Google 169 bytes.
  - `nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2` passed: unchanged at MoonBit 104,862,404 bytes vs Google 35,495,150 bytes.
- Validation completed:
  - `moon fmt`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit this longer-match increment. P3 still needs natural-data block
splitting and broader candidate admission to move Silesia ratio.

## P3 Timed Ratio Harness Increment

- Extended `tools/brotli/bench/ratio.nu` to measure MoonBit and Google encode
  durations in milliseconds.
- Added `--json` output so wide benchmark records are not truncated by Nushell's
  table renderer.
- Updated `tools/brotli/README.md` and `docs/brotli_benchmarks.md` with timed
  q2 examples and measurements.
- Validation completed:
  - `nu --ide-check 100 tools/brotli/bench/ratio.nu`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`: MoonBit 836.648 ms vs Google 44.078 ms.
  - `nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2 --json`: MoonBit 76,009.389 ms vs Google 817.288 ms.

Next: commit this benchmark harness increment, then continue encoder-side P3
work using the timed harness to track both ratio and runtime regressions.

## P3 Chunk Match Diagnostic Increment

- Added `tools/brotli/bench/chunk-match.nu` to report per-chunk unique literal
  counts, sampled 4-byte match density, and bounded greedy-copy estimates
  across candidate minimum match lengths.
- The diagnostic mirrors the current q2 chunk size and command cap, so it can
  explain why a chunk would remain stored before changing encoder admission
  heuristics.
- Validation completed:
  - `nu --ide-check 100 tools/brotli/bench/chunk-match.nu`
  - `nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16 --min-lengths 4,8,16,24,32 --json`
  - `nu tools/brotli/bench/chunk-match.nu target/brotli-encode/periodic-allbytes-200k.bin --max-chunks 1 --min-lengths 4,16,32 --json`
- Findings:
  - First 16 Silesia chunks cap at 1,201 commands for minimum match lengths
    4 and 8, so naive short-match admission would exceed the current command
    budget.
  - Minimum match length 16 avoids the cap and averages 35.02% copied bytes,
    but earlier ratio experiments showed it is not enough by itself and is too
    slow without stronger block/cost decisions.
  - A high-alphabet periodic chunk has 99.61% sampled 4-byte density and 99.61%
    copied bytes with only 16 commands, matching the case the current gate is
    designed to admit.

Next: use this diagnostic to design the first natural-data block splitter or
cost gate instead of broadening the current sampled-density heuristic blindly.

## P3 Hash Helper Split Increment

- Moved the active q2 hash-chain helpers from `src/brotli_encode.mbt` into the
  new `src/brotli_encode_hash.mbt` file named by the P3 plan.
- Kept behavior unchanged: the same 3-byte hash, sampled-density gate,
  previous-position table, 4-candidate search, and 4,096-byte match cap remain
  in use.
- Validation completed:
  - `moon fmt`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: expand `brotli_encode_hash.mbt` toward the quality-aware hash-chain
variants from the C reference, then wire a costed natural-data admission path.

## P3 Quality Hash Config Increment

- Added `BrotliHashConfig` and `brotli_hash_config_for_quality` in
  `src/brotli_encode_hash.mbt`.
- Threaded the config through q2+ standard encoding, chunked compression,
  sampled-density admission, previous-position table construction, and
  longest-match search.
- This preserves current behavior for all quality levels, but removes
  hardcoded table/search constants from `src/brotli_encode.mbt` so q5/q9
  variants can be introduced locally in the hash subsystem.
- Validation completed:
  - `moon fmt`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: give `brotli_hash_config_for_quality` real quality tiers once the
natural-data cost model can reject slow or low-value candidates safely.

## P3 Hash Admission Plumbing Increment

- Added `BrotliHashConfig` fields for minimum match length, scan step,
  maximum command count, minimum copy ratio, and dense-match gate control.
- Added `copy_length` to `BrotliEncodeCommand`, plus command copy-byte
  accounting for future pre-cost decisions.
- Changed LZ77 literal alphabet/frequency collection to use inserted command
  literals rather than every byte in the source chunk. Current validated
  benchmark outputs stayed unchanged, but this is the correct accounting for
  future natural-data chunks where copied bytes should not train the literal
  tree.
- Measured and rejected an experimental q9 sparse-match configuration:
  - `silesia-1m.bin` q9 stayed at 1,048,628 bytes versus Google 263,791 bytes
    and took 12,158.154 ms in the end-to-end harness.
  - `small-alpha-multi-1400.bin` q9 regressed to 1,404 bytes versus the
    existing 231-byte path.
  - The slow q9 admission remains disabled; all qualities currently keep the
    previous dense-match behavior.
- Validation completed:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: implement a real chunk-level cost model or block splitter before
relaxing dense-match gating again.

## P3 Complex Huffman RLE Increment

- Added repeat-zero RLE for complex Huffman code-length streams in
  `brotli_write_complex_huffman`.
- Captured an important decoder rule: consecutive repeat-zero symbols
  accumulate repeat state, so long zero runs are broken with a literal zero
  length between repeat-zero codes.
- Size results:
  - `small-alpha-multi-1400.bin` q2 improved from 231 to 195 bytes versus
    Google 169 bytes.
  - `periodic-abcde-200k.bin` q2 improved from 249 to 240 bytes.
  - `periodic-allbytes-200k.bin` stayed at 1,399 bytes.
  - `silesia-1m.bin` q2/q9 stayed stored at 1,048,628 bytes.
- Validation completed:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native --filter '*complex command Huffman*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: add repeat-previous RLE or a compressed-size estimator for candidate
chunks; natural-data ratio still requires block splitting or safer admission.

## P3 Complex Huffman Repeat-Previous Increment

- Added repeat-previous RLE for complex Huffman code-length streams using
  symbol 16.
- Preserved the repeat-state rule discovered in the repeat-zero increment:
  consecutive repeat codes accumulate, so long nonzero runs are split by
  inserting a literal code length between repeat-previous codes.
- Size results:
  - `periodic-allbytes-200k.bin` q2 improved from 1,399 to 1,382 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 stayed at 195 bytes.
  - `periodic-abcde-200k.bin` q2 stayed at 240 bytes.
  - `silesia-1m.bin` q2/q9 stayed stored at 1,048,628 bytes.
- Validation completed:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native --filter '*complex command Huffman*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
  - `moon check --target all`
  - `moon test --target all`: 440/440 on wasm, wasm-gc, js, and native
  - `moon info`

Next: move from tree-header reductions back to candidate admission/block
splitting; Silesia remains unchanged while natural chunks are stored.

## P3 Literal-Only Candidate Increment

- Added a literal-only compressed meta-block candidate for q2+ chunks with at
  most 64 distinct literal bytes.
- Added an insert-only command-prefix search that can use any command cell
  because the decoder exits before consuming a distance when the insert fills
  the meta-block.
- Kept the candidate costed: chunked output only splices it when rounded-up
  candidate bytes beat stored bytes, and single-block output compares against
  the uncompressed stream before returning compressed output.
- Added a white-box regression test for low-alphabet literal chunks.
- Validation completed:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native --filter '*literal chunks*'`
  - `moon test --target native --filter '*complex command Huffman*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*q0 through q11*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/alpha64-xorshift-16000.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2`
  - `moon check --target all`
  - `moon test --target all`: 441/441 on wasm, wasm-gc, js, and native
  - `moon info`
- Results:
  - `alpha64-xorshift-16000.bin` q2 improved from 16,004 to 12,022 bytes,
    slightly smaller than Google q2's 12,029 bytes for this artificial corpus.
  - `silesia-1m.bin` q2/q9 stayed at the stored fallback size of 1,048,628
    bytes after tightening the low-alphabet gate and stored-size comparison.

Next: literal-only improves a narrow low-alphabet case. The Silesia target
still requires block splitting and broader back-reference admission.

## P3 High-Alphabet Literal Entropy Increment

- Extended q2+ literal-only compressed chunks beyond the 64-symbol gate by
  adding an entropy precheck and length-limited weighted literal Huffman trees.
- Reused the package `h_tree` length limiter for Brotli literal alphabets up
  to 256 symbols, and precomputed Huffman payload tables so chunk-scale
  literal writing does not recompute canonical codes per byte.
- Fixed a shared Huffman sentinel bug: `h_tree` used `25001` as the sentinel
  frequency, which is too small for 65 KiB Brotli chunks and could panic in JS
  when a symbol frequency exceeded that value.
- Added a white-box regression test for skewed high-alphabet literal chunks.
- Results:
  - `silesia-128k.bin` q2 now encodes to 82,602 bytes and decodes through
    Google Brotli.
  - `silesia-1m.bin` q2 improved from stored 1,048,628 bytes to 657,233 bytes
    versus Google q2's 320,418 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 stayed at 195 bytes.
  - `periodic-allbytes-200k.bin` q2 stayed at 1,382 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*high alphabet literal*'`
  - `moon test --target native --filter '*literal chunks*'`
  - `moon test --target native --filter '*complex command Huffman*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*q0 through q11*'`
  - `moon test --target native --filter '*huffman*'`
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-128k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 442/442 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit this entropy-only natural-data increment, then continue with real
block splitting and back-reference admission.

## P3 q9 Sparse-Match Recheck

- Rechecked the previously rejected q9 sparse natural-data config after
  high-alphabet literal entropy coding landed.
- Trial settings: minimum match length 16, one candidate check, scan step 8,
  1,200-command cap, 20% copied-byte precheck, dense-density gate disabled.
- Result:
  - `silesia-1m.bin` q9 stayed at 657,233 bytes, matching the entropy-only
    q2/q9 output, but slowed to 21,058.137 ms in the ratio harness.
  - `small-alpha-multi-1400.bin` q9 regressed from 195 bytes to 364 bytes.
- Decision: rejected again and restored the dense-match config. Sparse natural
  matching needs either a better command/tree cost model or block splitting
  before it should be enabled.

## P3 Smaller Meta-Block Split Trial

- Tried lowering the chunk/meta-block size from 65,535 bytes to 16,384 bytes
  to see whether local literal entropy trees would improve Silesia before a
  proper block splitter exists.
- Result:
  - `silesia-1m.bin` q2 worsened slightly from 657,233 to 658,175 bytes.
  - `periodic-allbytes-200k.bin` q2 regressed from 1,382 to 4,050 bytes.
  - `periodic-abcde-200k.bin` q2 regressed from 240 to 407 bytes.
- Decision: rejected and restored the 65,535-byte chunk boundary. Smaller
  meta-blocks alone are not a substitute for a real Brotli block splitter.

## P3 Identity Static-Dictionary Candidate Increment

- Added `src/brotli_encode_dict.mbt` with a small hash index over identity
  words in the RFC static dictionary.
- Added a costed q2+ candidate that emits insert/copy commands referencing
  dictionary words for small single-block inputs.
- Kept the broad chunked path disabled after measurement:
  - Ungated dictionary probing changed `silesia-1m.bin` q2 from 657,233 to
    657,243 bytes and slowed the q2/q9 ratio harness to ~22s/~20s.
  - Restricting the candidate to `base_offset == 0` restores the Silesia q2
    baseline at 657,233 bytes.
- Added a white-box test for identity static dictionary words.
- Results:
  - `dictionary-words.txt` q2 encodes to 76 bytes versus Google q2's 78 bytes
    and decodes through Google Brotli.
  - `periodic-allbytes-200k.bin` q2 remains unchanged at 1,382 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains unchanged at 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*static dictionary words*'`
  - `moon test --target native --filter '*literal chunks*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/dictionary-words.txt --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-words.txt --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 443/443 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit the static-dictionary increment, then continue with block
splitting or broader dictionary/back-reference cost modeling.

## P3 Two-Literal-Block Split Candidate Increment

- Added a midpoint two-literal-block candidate for literal-only q2+ compressed
  meta-blocks.
- The writer now emits:
  - two literal block types with a block-type tree and block-length tree,
  - two LSB6 context modes,
  - a compact trivial context map that maps block type to tree,
  - one command block and one distance block,
  - separate weighted literal trees for each half.
- A first three-split trial improved `silesia-1m.bin` q2 from 657,233 to
  656,639 bytes but took 37,346.020 ms in the ratio harness. Kept only the
  midpoint split, which improves Silesia to 656,982 bytes and runs in
  20,574.832 ms.
- Added a white-box test proving the split literal candidate beats the
  single-tree literal candidate on a distribution-shift fixture.
- Results:
  - `split-literals-8k.bin` q2 encodes to 4,464 bytes versus Google q2's
    3,455 bytes and decodes externally.
  - `silesia-1m.bin` q2 improves from 657,233 to 656,982 bytes.
  - `periodic-allbytes-200k.bin` q2 remains unchanged at 1,382 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains unchanged at 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*splits literal*'`
  - `moon test --target native --filter '*literal chunks*'`
  - `moon test --target native --filter '*static dictionary words*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`

Next: commit this first block-splitting increment, then continue with cheaper
split heuristics and broader back-reference modeling.

## P3 Split-Candidate Admission Heuristic Increment

- Added `brotli_split_literal_may_beat_single`, a cheap Huffman-length
  estimator that compares one-tree literal cost against two midpoint literal
  trees before writing the expensive split meta-block candidate.
- The estimator requires a 384-bit predicted saving to cover block-switch,
  context-map, and second-tree overhead.
- Extended the split white-box test to assert that distribution-shift input
  passes the estimator and flat input is rejected.
- Results:
  - `silesia-1m.bin` q2 remains 656,982 bytes, preserving the split gain.
  - Silesia q2 ratio harness time improved from 20,574.832 ms to
    14,736.167 ms.
  - `split-literals-8k.bin` q2 remains 4,464 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
  - `periodic-allbytes-200k.bin` q2 remains 1,382 bytes.
- Validation completed so far:
  - `moon test --target native --filter '*splits literal*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`

Committed as `c254dd9 perf: gate Brotli split candidates`.

Next: continue with broader P3 back-reference and block-split cost modeling.

## P3 Three-Point Literal Split Selector Increment

- Reworked the literal split estimator to score quarter, midpoint, and
  three-quarter split positions from a shared single-tree literal cost.
- The encoder still writes at most one expensive two-block meta-block candidate
  per chunk, but now chooses the best estimated split instead of hard-coding
  the midpoint.
- Extended the split white-box test to assert that the distribution-shift
  fixture chooses the midpoint and that a flat input rejects splitting.
- Results:
  - `silesia-1m.bin` q2 improves from 656,982 to 656,614 bytes.
  - Silesia q2 ratio harness time is 16,404.430 ms after scoring three split
    points, still below the earlier ungated three-write trial's 37,346.020 ms.
  - `split-literals-8k.bin` q2 remains 4,464 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
  - `periodic-allbytes-200k.bin` q2 remains 1,382 bytes and decodes through
    Google Brotli.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*splits literal*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `7b668aa perf: choose Brotli literal split points`.

Next: continue with P3 back-reference and block-split cost modeling.

## P3 Large-Input Long-Match Candidate Increment

- Added `brotli_natural_hash_config_for_quality`, a separate q2+ natural-data
  search configuration with 32-byte minimum copies, dense-match gating disabled,
  and a 12% copied-byte floor.
- The dense baseline remains unchanged. The encoder tries the long-match
  candidate only for inputs/chunks of at least 8 KiB, then exact-costs it
  against existing LZ77, literal-only, split-literal, dictionary, and stored
  candidates.
- Extended the split white-box test to assert that the natural long-match
  candidate finds meaningful copy bytes on the distribution-shift fixture.
- Results:
  - `silesia-1m.bin` q2 improves from 656,614 to 579,879 bytes.
  - Silesia q2 ratio improves from 1.596x after literal splitting to 1.808x.
  - `split-literals-8k.bin` q2 improves from 4,464 to 3,434 bytes, now
    slightly smaller than Google q2's 3,455 bytes on that synthetic fixture.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes because the long-match
    candidate is gated to larger inputs.
  - `periodic-allbytes-200k.bin` q2 remains 1,382 bytes and decodes through
    Google Brotli.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*literal chunks*'`
  - `moon test --target native --filter '*splits literal*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `51b57a9 feat: add Brotli long-match candidates`.

Next: continue toward a real token/block splitter.

## P3 Long-Match Threshold Tuning Increment

- Tuned the large-input natural long-match candidate from a 32-byte minimum
  copy length to 16 bytes.
- Trial results:
  - 24-byte minimum: `silesia-1m.bin` q2 improved to 524,560 bytes.
  - 16-byte minimum: `silesia-1m.bin` q2 improved to 471,230 bytes.
  - 12-byte minimum: rejected; Silesia worsened to 646,930 bytes, indicating
    command/tree overhead dominated shorter copies.
- Regression fixtures stayed stable at the selected 16-byte threshold:
  - `split-literals-8k.bin` q2 remains 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
  - `periodic-allbytes-200k.bin` q2 remains 1,382 bytes and decodes through
    Google Brotli.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*splits literal*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `0ef553e perf: tune Brotli long-match threshold`.

Next: continue toward token/block splitting.

## P3 High-Quality Candidate Test Coverage

- Added a white-box fixture with repeated 12-byte runs separated by unique
  bytes.
- The q2 natural candidate rejects the fixture because its minimum copy length
  is 16 bytes, while the q9 high-quality candidate accepts it and finds more
  than 2,000 copied bytes.
- Validation:
  - `moon check --target native`
  - `moon test --target native --filter '*shorter high-quality*'`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 445/445 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `e648c7d test: cover Brotli q9 match admission`.

Next: continue toward token/block splitting.

## P3 Q9 Candidate Runtime Increment

- Changed q9+ candidate selection to skip the q2 natural long-match candidate
  and run only the q9 high-quality long-match candidate after the shared
  dense/literal/split/dictionary candidates.
- Results:
  - `silesia-1m.bin` q9 remains 422,673 bytes.
  - Silesia q9 ratio-harness time drops from 45,860.218 ms to 23,732.480 ms.
  - `silesia-1m.bin` q2 remains 455,386 bytes.
  - `split-literals-8k.bin` q9 remains 3,434 bytes.
  - `periodic-allbytes-200k.bin` q9 remains 350 bytes and decodes through
    Google Brotli.
- Validation completed so far:
  - `moon check --target native`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `f68b047 perf: skip duplicate Brotli q9 candidate`.

Next: continue toward token/block splitting.

## P3 High-Quality Long-Match Candidate Increment

- Added `brotli_high_quality_hash_config_for_quality` for q9+.
- The q9+ candidate keeps the natural search settings but lowers the minimum
  copy length from 16 bytes to 12 bytes and raises the command cap to 25,600.
- The candidate is exact-costed after the q2 natural candidate, so q9 only uses
  it when the encoded meta-block is smaller.
- A 10-byte minimum trial was rejected because it fell back to the q2-sized
  stream on Silesia, indicating shorter commands overpaid.
- Results:
  - `silesia-1m.bin` q2 remains 455,386 bytes.
  - `silesia-1m.bin` q9 improves from 455,386 to 422,673 bytes.
  - Silesia q9 ratio improves to 2.481x, 60.23% larger than Google q9.
  - `split-literals-8k.bin` q2/q9 remains 3,434 bytes; Google q9 is 3,418.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 remains 350 bytes and decodes through
    Google Brotli.
- Validation completed so far:
  - `moon check --target native`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `8ad1ae3 feat: add Brotli q9 long-match candidate`.

Next: continue toward token/block splitting.

## Current P3 Gap Snapshot

- `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json`
- Results after `e9241ff`:
  - q2: MoonBit 455,386 bytes versus Google 320,418 bytes, 42.12% overhead.
  - q9: MoonBit 455,386 bytes versus Google 263,791 bytes, 72.63% overhead.
- q2 and q9 still produce identical streams, so P3 remains open for
  quality-aware token/block modeling. P4 remains open for real q10/q11 Zopfli
  search.

## P3 Longer Natural Copy Increment

- Raised the natural long-match candidate's maximum copy length from 4 KiB to
  16 KiB.
- Results:
  - `periodic-allbytes-200k.bin` q2 improves from 494 to 350 bytes and decodes
    through Google Brotli.
  - `silesia-1m.bin` q2 remains 455,386 bytes.
  - `split-literals-8k.bin` q2 remains 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `e9241ff perf: lengthen Brotli natural copies`.

Next: continue toward token/block splitting.

## P3 Natural Lazy-Match Increment

- Added a one-byte lazy-match check for long-match natural candidates. If the
  next position has a match more than four bytes longer, the encoder emits one
  more literal before copying.
- Gated the heuristic to `min_match_length >= 16` so the dense small-input path
  keeps its previous behavior.
- Results:
  - `silesia-1m.bin` q2 improves from 457,776 to 455,386 bytes.
  - Silesia q2 ratio improves to 2.303x, 42.12% larger than Google q2.
  - `periodic-allbytes-200k.bin` q2 remains 494 bytes and decodes through
    Google Brotli.
  - `split-literals-8k.bin` q2 remains 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*splits literal*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*literal chunks*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `92a258b perf: add Brotli lazy matching`.

Next: continue toward token/block splitting.

## P3 Weighted Command/Distance Huffman Increment

- Extended `brotli_make_weighted_huffman_spec` to use length-limited weighted
  Huffman lengths for command and distance alphabets, not only literals.
- This removes the previous `count > 16` fallback to uniform code lengths for
  non-literal trees.
- Results:
  - `silesia-1m.bin` q2 improves from 460,961 to 457,776 bytes.
  - Silesia q2 ratio improves to 2.291x, 42.87% larger than Google q2.
  - `periodic-allbytes-200k.bin` q2 remains 494 bytes and decodes through
    Google Brotli.
  - `split-literals-8k.bin` q2 remains 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*splits literal*'`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*literal chunks*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Next: commit the weighted command/distance tree increment, then continue toward
token/block splitting.

## P3 One-MiB Standard Chunk Increment

- Raised the q2+ chunked standard meta-block size from 262,143 bytes to
  1,048,575 bytes.
- Raised the natural long-match command cap from 4,800 to 19,200 to keep the
  cap proportional to the larger chunk.
- Results:
  - `silesia-1m.bin` q2 improves from 462,172 to 460,961 bytes.
  - Silesia q2 ratio improves to 2.275x, 43.86% larger than Google q2.
  - `periodic-allbytes-200k.bin` q2 remains 494 bytes and decodes through
    Google Brotli.
  - `split-literals-8k.bin` q2 remains 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Next: commit the 1 MiB chunk increment, then continue toward token/block
splitting.

## P3 Larger Standard Chunk Increment

- Raised the q2+ chunked standard meta-block size from 65,535 bytes to 262,143
  bytes.
- Raised the natural long-match candidate's command cap from 1,200 to 4,800 to
  keep the cap proportional to the larger chunk.
- Kept the dense baseline command cap unchanged at 1,200.
- Results:
  - `silesia-1m.bin` q2 improves from 471,230 to 462,172 bytes.
  - Silesia q2 ratio improves to 2.269x, 44.24% larger than Google q2.
  - `periodic-allbytes-200k.bin` q2 improves from 1,382 to 494 bytes and
    decodes through Google Brotli.
  - `split-literals-8k.bin` q2 remains 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 remains 195 bytes.
- Validation completed so far:
  - `moon check --target native`
  - `moon test --target native --filter '*chunked large input*'`
  - `moon test --target native --filter '*high alphabet repetitive*'`
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json`
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json`
  - `nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 444/444 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`

Committed as `7d98b84 perf: enlarge Brotli standard chunks`.

Next: continue toward token/block splitting.

## Latest Continuation State

- Latest tracked commits:
  - `e648c7d test: cover Brotli q9 match admission`
  - `f68b047 perf: skip duplicate Brotli q9 candidate`
  - `8ad1ae3 feat: add Brotli q9 long-match candidate`
  - `e9241ff perf: lengthen Brotli natural copies`
- Current 1 MiB Silesia slice evidence:
  - q2: 455,386 bytes versus Google q2 320,418 bytes.
  - q9: 422,673 bytes versus Google q9 263,791 bytes.
- Current regression fixture evidence:
  - `split-literals-8k.bin` q9: 3,434 bytes versus Google q9 3,418 bytes.
  - `periodic-allbytes-200k.bin` q2/q9: 350 bytes, external decode verified.
  - `small-alpha-multi-1400.bin` q2/q9: 195 bytes.
- Latest full validation:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 445/445 on wasm, wasm-gc, js, and native
  - `moon info`
  - `git diff --check`
- P3 remains open: Silesia q2/q9 ratios are still outside the documented 5%
  target and need real token/block splitting.
- P4 remains open: q10/q11 still do not have a real Zopfli/suffix-tree search.

## 2026-05-24 17:11 +0800 — P3 four-tree UTF-8 context increment

- Current clean-base commits before this increment:
  - `630824b perf: add Brotli literal context candidate`
  - `7019f36 perf: improve Brotli LZ77 coding`
- Implemented a complex-Huffman writer fix so code-length-code alphabets with
  17/18 symbols use bounded Huffman lengths instead of failing the old
  power-of-two padding check.
- Added an exact-costed four-tree UTF-8 literal-context LZ77 candidate on top
  of the existing two-tree candidate.
- Measured fixture results:
  - `silesia-1m.bin` q2: 438,806 -> 424,532 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 408,875 -> 396,969 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native`: 448/448
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`, then commit if
  clean.

## 2026-05-24 17:31 +0800 — P3 four-byte natural hash candidate

- Added a `hash_bytes` field to `BrotliHashConfig`; existing configs retain
  three-byte hash behavior.
- Added `brotli_four_byte_hash_config` and try it as an additional exact-costed
  natural/high-quality candidate for q2+ chunks >= 8192 bytes.
- A global four-byte replacement was rejected because it regressed
  `small-alpha-multi-1400.bin` from 195 to 197 bytes. The exact-costed
  dual-candidate version restores the 195-byte output.
- Measured fixture results:
  - `silesia-1m.bin` q2: 424,532 -> 419,583 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 396,969 -> 390,314 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Tradeoff: Silesia 1 MiB benchmark time rises to ~66-68 seconds because both
  hash-chain candidates are built and exact-costed. Future P3 work should add
  cheaper candidate admission rather than trying every parser unconditionally.
- Targeted validation so far:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native`: 449/449

## 2026-05-24 17:46 +0800 — P4 max-input-size safety groundwork

- Added `max_input_size` to public `BrotliOptions`, matching the option shape
  required by `docs/brotli.md`.
- `brotli_sync` now rejects inputs larger than `opts.max_input_size` before
  encoder allocation.
- q10/q11 now apply the documented 256 MiB safety cap for the future
  suffix-tree/Zopfli backend.
- Updated Brotli white-box tests and the Nushell JS verifier to construct the
  expanded `BrotliOptions`.
- Validation so far:
  - `moon fmt`
  - `moon check --target native`
  - `moon test --target native`: 450/450
  - `nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multi-1400.bin --quality 2`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 19:25 +0800 — Current P3 parser follow-up notes

- Accepted and committed distance-cache short codes and aggressive lazy-match
  tuning; current measured Silesia 1 MiB sizes are q2 317,081 bytes and q9
  301,268 bytes.
- Rejected after those commits:
  - q9 5-byte minimum matches: Silesia q9 regressed to 307,807 bytes.
  - q9 6-check high-quality chain: identical q9 bytes.
  - q9 5-byte alternate hash candidate: identical q9 bytes.
  - q9 hybrid LZ77 + identity dictionary candidate: identical q9 bytes and
    123,941 ms runtime.
  - two-command-block + 16-tree literal-context candidate: identical q9 bytes.
- Rejected a q9 exact-costed hybrid LZ77 + identity static-dictionary
  candidate: focused tests passed, but Silesia q9 stayed at 301,268 bytes and
  runtime increased to 123,941 ms, so the prototype was reverted.
- Rejected a two-command-block plus 16-tree literal-context candidate:
  focused tests passed, but Silesia q9 stayed at 301,268 bytes and the
  prototype was reverted.

## 2026-05-24 19:25 +0800 — P3 three-byte lazy lookahead

- Extended short-match lazy lookahead to inspect up to three following byte
  positions before taking the current match.
- Measured lookahead trials:
  - two-byte lookahead: Silesia q9 298,889 bytes.
  - three-byte lookahead: Silesia q9 298,536 bytes, accepted.
  - four-byte lookahead: Silesia q9 299,595 bytes, rejected.
- Measured fixture results at the accepted three-byte setting:
  - `silesia-1m.bin` q2: 317,081 -> 314,410 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 301,268 -> 298,536 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 193 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*q9 admits shorter high-quality matches*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 19:25 +0800 — P3 aggressive lazy-match margin

- Tuned the lazy-match lookahead margin after the short-match lazy increment:
  - `next > current + 2`: Silesia q9 302,076 bytes.
  - `next > current + 1`: Silesia q9 301,599 bytes.
  - `next > current`: Silesia q9 301,268 bytes, accepted.
- Measured fixture results at the accepted margin:
  - `silesia-1m.bin` q2: 318,026 -> 317,081 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 303,384 -> 301,268 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 193 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*q9 admits shorter high-quality matches*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 19:25 +0800 — P3 short-match lazy lookahead

- Lowered the existing lazy-match lookahead gate from 16-byte minimum matches
  to 6-byte minimum matches so the q2 natural and q9 high-quality parsers can
  skip short copies when the next byte starts a substantially longer match.
- Measured fixture results:
  - `silesia-1m.bin` q2: 320,612 -> 318,026 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 306,645 -> 303,384 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 193 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*q9 admits shorter high-quality matches*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.
- Rejected a 64K q9 high-quality hash table trial after the 6-byte threshold
  landed: it produced identical Silesia q9 bytes (`307,056`) and was reverted.
- Rejected a q9-only 512 KiB chunk-size trial: the first Silesia q9 output
  was worse (`309,550` bytes) and the ratio harness exited nonzero, so the
  prototype was reverted.

## 2026-05-24 19:25 +0800 — P3 distance-cache short codes

- Added encoder-side distance-code computation against the four-entry Brotli
  distance cache, matching the reference `ComputeDistanceCode` behavior.
- Distance code 0 still uses the compact implicit command form; nonzero short
  codes are emitted as distance-tree symbols.
- Added a white-box test covering code 0/1/2/3 computation, explicit cached
  distance emission, and cache update order.
- Measured fixture results:
  - `silesia-1m.bin` q2: 320,899 -> 320,612 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 307,056 -> 306,645 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 improved from 195 to 193 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*distance-cache short codes*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.
- Rejected a q9 8-check high-quality chain trial after the 10-byte threshold
  landed: it produced identical Silesia q9 bytes (`332,140`) and was reverted.

## 2026-05-24 18:48 +0800 — P3 six-byte q9 high-quality matches

- Lowered the q9 high-quality hash parser further to 6-byte minimum matches
  with a 150,000-command cap.
- Measured threshold trials:
  - 8-byte q9: 319,715 bytes.
  - 6-byte q9: 307,056 bytes.
  - 4-byte q9: 313,641 bytes, rejected as command-entropy overpayment.
- Measured fixture results at the accepted 6-byte setting:
  - `silesia-1m.bin` q9: 332,140 -> 307,056 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*q9 admits shorter high-quality matches*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 18:48 +0800 — P3 shorter q9 high-quality matches

- Lowered the q9 high-quality hash parser from 12-byte minimum matches to
  10-byte minimum matches and raised its command cap to 52,000.
- The shorter-match stream is exact-costed; previous low-cap q9 trials had
  rejected too early.
- Measured fixture results:
  - `silesia-1m.bin` q9: 352,245 -> 332,140 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*q9 admits shorter high-quality matches*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 19:09 +0800 — P3 deeper q2 natural match chains

- Tested natural/high-quality `max_match_checks: 8`; it improved q2 but
  regressed q9, so only the q2 natural parser keeps 8 checks.
- Measured fixture results:
  - `silesia-1m.bin` q2: 407,942 -> 396,543 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: unchanged at 376,154 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native`: 450/450 before adding the config assertion
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 18:42 +0800 — P3 wider natural hash table

- Rejected an exact-costed command-block split candidate: it decoded correctly
  and improved a synthetic stream, but did not improve Silesia q2/q9 and added
  large-corpus runtime.
- Rejected a 256 KiB chunk-size experiment: Silesia q2 regressed from 419,583
  to 421,681 bytes.
- Increased baseline, natural, and high-quality LZ77 hash tables from 4K to
  32K entries.
- Measured fixture results:
  - `silesia-1m.bin` q2: 419,583 -> 407,942 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 390,314 -> 376,154 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native`: 450/450 before adding the config assertion
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 19:36 +0800 — P3 eight-tree UTF-8 context candidate

- Added an exact-costed eight-tree UTF-8 literal-context LZ77 candidate.
- The candidate is tried after the two-tree and four-tree context candidates
  and can only win by final encoded bit count.
- Measured fixture results:
  - `silesia-1m.bin` q2: 396,543 -> 379,211 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 376,154 -> 361,642 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native`: 450/450 before adding the focused test update
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 20:03 +0800 — P3 sixteen-tree UTF-8 context candidate

- Added an exact-costed sixteen-tree UTF-8 literal-context LZ77 candidate.
- The candidate is tried after the 2/4/8-tree context candidates and can only
  win by final encoded bit count.
- Measured fixture results:
  - `silesia-1m.bin` q2: 379,211 -> 367,920 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 361,642 -> 352,245 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*UTF-8 context literal trees*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 20:24 +0800 — Rejected P3 entropy/chunk experiments

- Rejected a 32-tree UTF-8 literal-context candidate:
  - Focused context test passed and guardrails were stable.
  - `silesia-1m.bin` q2/q9 produced identical bytes to the 16-tree candidate
    (`367,920` / `352,245`) while increasing runtime.
  - Reverted to the committed 16-tree candidate.
- Rejected a 512 KiB chunk-size split:
  - Native tests passed, but the first Silesia output was worse
    (`376,544` bytes versus the committed q2 `367,920`), and the ratio harness
    exited nonzero.
  - Reverted to the committed 1,048,575-byte chunk size.
- Validation after reverting:
  - `moon fmt`
  - `moon test --target native`: 450/450

## 2026-05-24 18:48 +0800 — Rejected P3 split-context candidate

- Rejected a two-literal-block plus sixteen-tree UTF-8 context LZ77 candidate:
  - The focused split/context white-box test passed and decoded internally.
  - `silesia-1m.bin` q2/q9 produced identical bytes to the committed
    16-tree candidate (`367,920` / `352,245`).
  - Runtime increased to 124,503 ms for q2 and 110,099 ms for q9 in the
    ratio harness.
  - Reverted the prototype because it added an exact-costed candidate with no
    ratio gain.

## 2026-05-24 18:48 +0800 — P3 shorter q2 natural matches

- Lowered the q2 natural hash parser from 16-byte minimum matches to 10-byte
  minimum matches and raised its command cap to 52,000.
- The shorter-match stream is still exact-costed against the existing LZ77,
  context, literal-only, dictionary, and stored candidates.
- Measured fixture results:
  - `silesia-1m.bin` q2: 367,920 -> 320,899 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9 remains 352,245 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 195 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*alternate hash candidates exact-costed*'`: 1/1
  - `moon test --target native`: 450/450
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 21:05 +0800 — P3 recent-distance match probes

- Added a cache-aware LZ77 match finder that probes all 16 Brotli
  recent-distance short-code candidates before the hash chain.
- The parser keeps recent-distance matches on equal length, giving the existing
  command builder more opportunities to emit cheap distance symbols.
- Rejected nearby parser experiments before accepting this:
  - Shortened-copy shaping: q9 stayed 298,536 bytes and runtime rose to
    129,817 ms.
  - Relaxed lazy threshold: q9 regressed to 303,496 bytes.
  - q9 8 hash-chain checks after three-byte lazy lookahead: byte-identical at
    298,536 bytes.
- Measured fixture results:
  - `silesia-1m.bin` q2: 314,410 -> 313,585 bytes, Google q2 320,418.
  - `silesia-1m.bin` q9: 298,536 -> 296,784 bytes, Google q9 263,791.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 improves from 193 to 179 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Targeted validation so far:
  - `moon fmt`
  - `moon test --target native --filter '*matcher probes distance-cache candidates*'`: 1/1
  - Fixture ratio/verify commands listed in `docs/brotli_benchmarks.md`
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 21:32 +0800 — P4 baseline after recent-distance probes

- Measured current q10/q11 dispatch on `target/brotli-bench/silesia-1m.bin`.
- q10 and q11 still share the q9 backend, so they produce the same 296,784-byte
  stream.
- Google reference sizes on the same slice:
  - q10: 242,485 bytes; current overhead 22.39%.
  - q11: 239,314 bytes; current overhead 24.01%.
- This confirms P4 still requires a real Zopfli/shortest-path backend rather
  than further dispatch wiring.
- Also rejected expanding identity-only dictionary matching to the 1 MiB
  chunk: q9 stayed byte-identical at 296,784 bytes.

## 2026-05-24 21:58 +0800 — Rejected P3 parser/block-split trials

- Rejected a two-command-block LZ77 candidate with quarter/midpoint/three-quarter
  splits:
  - Native check passed.
  - `silesia-1m.bin` q9 stayed byte-identical at 296,784 bytes.
  - Runtime increased to 99,173 ms, so the prototype was reverted.
- Rejected cached-distance bias thresholds:
  - Requiring hash-chain matches to beat cached-distance matches by more than
    2 bytes regressed q9 to 296,789 bytes.
  - A 1-byte margin stayed size-neutral at 296,784 bytes but changed the output
    hash, so it added alternate tokenization without ratio gain.
  - Restored the committed strict longer-match policy.

## 2026-05-24 22:16 +0800 — P3 encoder dictionary uppercase transforms

- Extended `BrotliDictionaryEncodeIndex` to store Brotli transform indices in
  addition to word length and word index.
- Indexed only same-length transforms with empty prefix/suffix and identity,
  uppercase-first, or uppercase-all transform types. This keeps the command copy
  length equal to the transformed output length.
- Fixed an initial prototype error: dictionary distances must encode the
  transform index into `brotli_transform_triplets`, not the transform type enum.
- Added a white-box test proving an uppercase input can resolve to a transformed
  static-dictionary match and round-trip through `brotli_sync`/`unbrotli_sync`.
- Measured fixture results:
  - `dictionary-words.txt` q2/q9 unchanged at 76 bytes.
  - Generated `dictionary-title-words.txt`: q2/q9 78 bytes, versus Google q2
    89 bytes and q9 73 bytes.
  - `silesia-1m.bin` q9 unchanged at 296,784 bytes.
  - split/small-alpha/periodic guardrails unchanged, periodic q2/q9 externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 22:48 +0800 — P3 encoder dictionary suffix transforms

- Extended encoder static-dictionary matching so selected Brotli transforms can
  emit a different output length from the dictionary word length.
- Added `BrotliEncodeCommand.output_length` so the meta-block length and copy
  ratio calculations count decoded bytes, while command prefix copy length
  remains the dictionary word length required by the Brotli spec.
- Fixed the dictionary word-boundary heuristic for transforms that include a
  trailing non-word byte such as a space.
- Added white-box coverage for suffix static-dictionary commands and verified
  small transform-heavy streams with Google Brotli.
- Measured fixture results:
  - `dictionary-words.txt` q2/q9 unchanged at 76 bytes.
  - `dictionary-title-words.txt` q2/q9 unchanged at 78 bytes.
  - Generated `dictionary-words-spaced.txt`: q2/q9 76 bytes, versus Google q2
    79 bytes and q9 62 bytes.
  - `silesia-1m.bin` q9 unchanged at 296,784 bytes.
  - split/small-alpha/periodic guardrails unchanged, periodic q2/q9 externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 23:18 +0800 — P4 q10/q11 high-quality parser tuning

- Added a q10/q11-specific high-quality hash config instead of sharing q9's
  parser limits.
- q10/q11 now use 16 hash-chain checks, 5-byte minimum matches, and a
  250,000-command cap. q9 remains at 4 checks, 6-byte minimum matches, and
  150,000 commands.
- Measured fixture results:
  - `silesia-1m.bin` q9 unchanged at 296,784 bytes.
  - `silesia-1m.bin` q10 improves from 296,784 to 288,988 bytes, versus Google
    q10 242,485 bytes.
  - `silesia-1m.bin` q11 improves from 296,784 to 288,988 bytes, versus Google
    q11 239,314 bytes.
  - `split-literals-8k.bin` q9/q10/q11 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q9/q10/q11 unchanged at 179 bytes.
  - `periodic-allbytes-200k.bin` q11 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-24 23:39 +0800 — P4 q11 deeper parser tuning

- Split q11 from q10 by raising q11 to 32 hash-chain checks and a
  300,000-command cap while keeping the q10 settings from the prior increment.
- Measured fixture results:
  - `silesia-1m.bin` q10 unchanged at 288,988 bytes.
  - `silesia-1m.bin` q11 improves from 288,988 to 283,133 bytes, versus Google
    q11 239,314 bytes.
  - `split-literals-8k.bin` q10/q11 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q10/q11 unchanged at 179 bytes.
  - `periodic-allbytes-200k.bin` q11 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 00:22 +0800 — P3 q2 fast large-chunk profile

- Added quality-aware LZ77 meta-block writing so q2 large chunks do not run
  the full q9/q11 exact-cost matrix.
- For q2 chunks at least 8 KiB, the chunk selector now tries the natural LZ77
  parser directly instead of first building literal-only, split-literal,
  dictionary, baseline hash, and four-byte hash candidates.
- For q2 LZ77 writers, chunks at least 512 KiB try the 16-tree UTF-8 context
  writer directly; smaller chunks keep the weighted fallback to preserve the
  200 KiB periodic guardrail.
- Rejected a q2 4-check natural-chain trial: Silesia encoded to 338,135 bytes
  but failed external Google Brotli decode as corrupt input.
- Measured fixture results:
  - `silesia-1m.bin` q2 changes from 313,585 bytes / ~82,818 ms to 325,896
    bytes / ~42,558 ms, versus Google q2 320,418 bytes.
  - `split-literals-8k.bin` q2/q9 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9 unchanged at 179 bytes.
  - `silesia-1m.bin` q9 unchanged at 296,784 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 00:48 +0800 — P3/P4 deeper q9/q10 parser tuning

- Promoted q9 and q10 to q11's deeper high-quality parser settings: 32
  hash-chain checks, 5-byte minimum matches, and a 300,000-command cap.
- A q9 intermediate trial with q10's older 16-check/250,000-command settings
  improved Silesia q9 to 288,988 bytes; the retained 32-check setting improved
  it further to 283,133 bytes with similar measured runtime.
- Measured fixture results:
  - `silesia-1m.bin` q9 improves from 296,784 to 283,133 bytes, versus Google
    q9 263,791 bytes.
  - `silesia-1m.bin` q10 improves from 288,988 to 283,133 bytes, versus Google
    q10 242,485 bytes.
  - `silesia-1m.bin` q11 stays at 283,133 bytes, versus Google q11 239,314.
  - `split-literals-8k.bin` q9/q10/q11 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q9/q10/q11 unchanged at 179 bytes.
  - `periodic-allbytes-200k.bin` q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 01:10 +0800 — P3 q2 chunk distance-cache state

- Investigated a 512 KiB high-quality chunk-size trial. It generated a smaller
  287,762-byte Silesia stream but external Google Brotli rejected the stream,
  exposing that compressed chunk command building restarted the recent-distance
  cache for each meta-block.
- Added a distance-cache-aware LZ77 command builder and threaded q2 chunked
  compression through a persistent cache.
- The chunked writer snapshots and restores the cache when a compressed
  candidate is rejected in favor of a stored meta-block, matching decoder
  semantics where stored blocks do not update recent distances.
- Measured fixture results:
  - `silesia-1m.bin` q2 remains valid at 325,896 bytes, versus Google q2
    320,418 bytes, with measured runtime ~40,867 ms.
  - `periodic-allbytes-200k.bin` q2 remains 350 bytes and externally decodes
    with Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 01:36 +0800 — P3/P4 five-byte lazy lookahead

- Extended lazy lookahead to high-quality configs that admit 5-byte matches.
  The parser now checks the next three positions for a longer match at q9+,
  instead of only doing that for 6-byte-minimum configs.
- Measured fixture results:
  - `silesia-1m.bin` q9 improves from 283,133 to 273,641 bytes, versus Google
    q9 263,791 bytes. This is 3.73% overhead and enters the P3 5% target
    window on the 1 MiB validation slice.
  - `silesia-1m.bin` q10 improves from 283,133 to 273,641 bytes, versus Google
    q10 242,485 bytes.
  - `silesia-1m.bin` q11 improves from 283,133 to 273,641 bytes, versus Google
    q11 239,314 bytes.
  - `split-literals-8k.bin` q9/q10/q11 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q9/q10/q11 unchanged at 179 bytes.
  - `periodic-allbytes-200k.bin` q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 02:30 +0800 — P3/P4 chunked final-block boundary

- Rejected two P4 parser trials:
  - q10 `min_match_length=4` regressed Silesia q10 to 285,760 bytes versus
    the committed 273,641-byte baseline.
  - deeper q10/q11 lazy lookahead regressed Silesia q10 to 291,763 bytes and
    q11 to 320,823 bytes, with much higher runtime.
- Kept a lower-risk chunked boundary fix instead:
  - compressed final chunks now pass `is_last=true` into candidate writers;
  - chunked standard encoding only appends an empty final meta-block when the
    final chunk was stored or no chunk was written;
  - standard chunk size is now 1,048,576 bytes, avoiding a 1-byte tail chunk
    for exactly 1 MiB inputs.
- Measured fixture results:
  - `silesia-1m.bin` q2 improves from 325,896 to 325,887 bytes, versus Google
    q2 320,418 bytes.
  - `silesia-1m.bin` q9 improves from 273,641 to 273,633 bytes, versus Google
    q9 263,791 bytes.
  - `silesia-1m.bin` q10/q11 improve from 273,641 to 273,633 bytes, versus
    Google q10 242,485 and q11 239,314 bytes.
  - `split-literals-8k.bin` q2/q9/q10/q11 unchanged at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2/q9/q10/q11 unchanged at 179 bytes.
  - `periodic-allbytes-200k.bin` q2/q9 unchanged at 350 bytes and externally
    decoded by Google Brotli.
- Remaining before commit: run full `moon fmt`, `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 03:20 +0800 — q2 fast profile scan reduction

- Investigated the q2 speed complaint. The current q2 fast profile is close
  to Google q2 on ratio but still much slower because it still performs heavy
  MoonBit-side LZ77 search and repeated literal-context scans.
- Optimized the 16-tree UTF-8 context writer to gather all literal sets and
  frequency tables in one pass instead of 32 command-literal scans.
- Added hash-config controls for recent-distance probe count and lazy
  lookahead:
  - q2 natural parsing now uses 0 recent-distance short-code probes and a
    one-position lazy lookahead;
  - q9+ keeps all 16 recent-distance probes and three-position lazy lookahead.
- Rejected q2 natural `max_match_checks=4`: Silesia encoded to 339,926 bytes
  but Google Brotli rejected the stream as corrupt.
- Measured fixture results:
  - `silesia-1m.bin` q2 changes from 325,887 bytes / ~40,862 ms to 329,512
    bytes / ~28,054 ms, versus Google q2 320,418 bytes / ~45 ms.
  - `split-literals-8k.bin` q2 stays at 3,434 bytes.
  - `small-alpha-multi-1400.bin` q2 improves from 179 to 162 bytes.
  - `periodic-allbytes-200k.bin` q2 stays at 350 bytes and externally decodes
    with Google Brotli.
- Remaining before commit: run full `moon fmt`, `moon check --target all`,
  `moon test --target all`, `moon info`, `git diff --check`.

## 2026-05-25 06:25 +0800 — wasm-gc/native performance harness

- Added `tools/brotli/bench/target-perf.nu` so Brotli performance work can use
  wasm-gc/native target data instead of the older JS file-verification harness.
- The harness generates a temporary white-box test from the benchmark input,
  warms the selected target, then reports per-operation target time against
  Google Brotli. Decode mode requires an expected output file; encode mode also
  reports MoonBit and Google encoded sizes plus size overhead.
- Verified decode mode on `silesia-1m.bin.google.q11.br`:
  - wasm-gc: ~48.7 ms/decode versus Google ~14.5 ms, about 3.36x slower.
  - native: ~131.6 ms/decode versus Google ~14.5 ms, about 9.06x slower.
- Verified encode mode on `silesia-128k.bin` q2:
  - wasm-gc: 51,928 bytes versus Google 44,794 bytes, ~182.6 ms versus
    Google ~38.7 ms.
  - native: same bytes, ~503.8 ms versus Google ~38.7 ms.
- This supports treating performance as a first-class Brotli requirement:
  ratio-only improvements are not enough for future P3/P4 increments.

## 2026-05-25 07:25 +0800 — literal-set collector speedup

- Reproduced a target-perf harness race: concurrent benchmark runs can fail
  because Moon scans all temporary `src/*_wbtest.mbt` files while another run
  removes its generated file.
- Added `tools/brotli/.harness-lock` serialization to
  `tools/brotli/bench/target-perf.nu`, matching the conformance/fuzz harness
  model.
- Replaced linear unique-symbol scans in literal collectors with 256-entry
  `seen` tables while preserving first-seen symbol order.
- Target-perf q2 encode on `silesia-128k.bin`:
  - wasm-gc improved from ~178.97 ms avg to ~163.79 ms avg, size unchanged at
    51,928 bytes versus Google 44,794.
  - native improved from ~521.30 ms avg to ~470.19 ms avg, size unchanged.
- Additional measurements:
  - Silesia 1 MiB q2 ratio remains 329,512 bytes versus Google 320,418.
  - q9 `silesia-128k.bin` target-perf remains valid at 40,013 bytes versus
    Google 39,695; wasm-gc ~339 ms, native ~2,769 ms.
- Validation completed:
  - `moon check --target all`
  - `moon test --target all` passed 454/454 on wasm, wasm-gc, js, native.
  - `moon info`

## 2026-05-25 19:51 +0800 — current-code audit and staged fast path

- Used `moonbit-agent-guide` for this audit and treated MoonBit package
  boundaries accordingly: Brotli code is in the root `src/` package, with
  public API reflected by `src/pkg.generated.mbti`.
- Current implementation status from code:
  - `unbrotli_sync`, `UnbrotliStream`, fixtures, dictionary decode, transforms,
    compressed meta-block decode, and defensive size limits are present.
  - `brotli_sync` and `BrotliStream` are present; `BrotliOptions` accepts
    quality `0..11` and defaults to `11`.
  - `brotli_sync q0 through q11 round-trip` white-box coverage exists, so all
    quality levels currently produce streams the in-tree decoder can read.
  - q2 has a fast large-chunk path, chunked compression, distance-cache
    threading, weighted Huffman, literal-context candidates, limited static
    dictionary encoding, and natural/high-quality LZ77 candidates.
  - q9/q10/q11 use high-quality hash configs. Current code has moved beyond
    the last recorded q11 numbers: q11 now uses a 131,072-entry hash table,
    128 match checks, 5-byte minimum matches, and a 600,000-command cap; q9
    and q10 still use 32 checks, a 32,768-entry table, and a 300,000-command
    cap.
- Staged but not committed source change:
  - `src/brotli_encode.mbt` changes `brotli_command_uses_distance_symbol`
    from a raising helper that calls `brotli_command_info(...)` to a direct
    `command.has_copy && command.command.symbol >= 128` predicate.
  - This is behavior-preserving for command symbols because Brotli command
    cells with `symbol >> 6 >= 2` are exactly the cells that consume an
    explicit distance symbol.
  - The change removes repeated prefix-table work in command emission and does
    not alter public APIs.
- Validation run during this audit:
  - `moon check --target all`: passed.
  - `moon test --target native --filter '*brotli*'`: 75/75 passed.
- Functions still not complete relative to `docs/brotli.md`:
  - P3 is not complete as a phase. q2..q9 are implemented and can round-trip,
    but the documented P3 requirements for general block splitting, histogram
    clustering, broad natural-data entropy decisions, full ratio validation,
    and release-grade benchmark evidence remain open.
  - The q2 natural-data path is still deliberately conservative. Large q2
    chunks take a fast natural LZ77 path, but the plan item to remove the
    low-alphabet/dense-match style gate via general natural-data block
    splitting and entropy decisions is still open.
  - P4 is not complete as a phase. q10/q11 have deeper high-quality parser
    settings and safety caps, but there is still no real Zopfli/shortest-path
    or suffix-tree backend, and the documented q10/q11 2% ratio target has not
    been demonstrated.
  - The latest q11 parser settings in code need fresh ratio and external
    Google Brotli decode measurements; the progress log currently records
    older q10/q11 benchmark numbers.
  - The full long-running fuzz/conformance gate remains unrecorded, so Brotli
    support should not be treated as release-ready solely from unit tests.

## 2026-05-25 20:10 +0800 — P0 distance-symbol fast-path validation

- Prioritized release-directed Brotli work into P0/P1/P2:
  - P0: target-perf evidence, q11 validation, full MoonBit validation, and
    commit hygiene.
  - P1: bounded performance improvements selected by target-perf data.
  - P2: larger P3/P4 algorithm completion such as histogram clustering and
    Zopfli/suffix-tree search.
- Validated the staged `brotli_command_uses_distance_symbol` fast path.
- Initial q2 8 KiB target-perf did not show a reliable improvement:
  - current wasm-gc release: 40.143 ms/op versus HEAD baseline 39.888 ms/op.
  - current native debug: 136.675 ms/op versus HEAD baseline 136.085 ms/op.
  - Conclusion: q2/split-literal input is not a useful signal for this change.
- q9 Silesia target-perf did show improvement on the distance-heavy path:
  - wasm-gc release, `silesia-128k.bin` q9 encode:
    current 228.405 ms/op versus HEAD baseline 231.168 ms/op; size unchanged
    at 40,013 bytes versus Google 39,695 bytes.
  - native debug, `silesia-64k.bin` q9 encode:
    current 642.933 ms/op versus HEAD baseline 657.714 ms/op; size unchanged
    at 22,261 bytes versus Google 22,063 bytes.
- Decode sanity target-perf, current code:
  - wasm-gc release, `silesia-64k.bin.google.q11.br`: 28.099 ms/op versus
    Google 14.602 ms/op.
  - native debug, same input: 75.986 ms/op versus Google 14.219 ms/op.
- Tooling finding: `target-perf.nu` native release can spend minutes compiling
  generated white-box tests that embed 64 KiB+ byte arrays. For quick per-commit
  evidence, use wasm-gc release plus native debug or smaller inputs; a future
  P0 tooling task should make native release baselines practical.
- Validation completed after formatting:
  - `moon fmt`
  - `git diff --check --cached`
  - `moon check --target all`
  - `moon test --target all`: 455/455 passed on wasm, wasm-gc, js, native.
  - `moon info`

## 2026-05-25 20:11 +0800 — P0 target-perf baseline and q11 validation

- Established practical per-commit target-perf baselines after the distance
  fast-path commit:
  - q2 encode, `split-literals-8k.bin`, wasm-gc release:
    40.143 ms/op, 3,434 bytes versus Google 3,455 bytes.
  - q2 encode, `split-literals-8k.bin`, native debug:
    136.675 ms/op, 3,434 bytes versus Google 3,455 bytes.
  - q9 encode, `silesia-128k.bin`, wasm-gc release:
    228.405 ms/op, 40,013 bytes versus Google 39,695 bytes.
  - q9 encode, `silesia-64k.bin`, native debug:
    642.933 ms/op, 22,261 bytes versus Google 22,063 bytes.
  - q11 encode, `silesia-64k.bin`, wasm-gc release:
    155.733 ms/op, 22,155 bytes versus Google 19,258 bytes; 15.04%
    size overhead.
  - q11 encode, `silesia-64k.bin`, native debug:
    664.039 ms/op, 22,155 bytes versus Google 19,258 bytes; 15.04%
    size overhead.
  - q11 decode, `silesia-64k.bin.google.q11.br`, wasm-gc release:
    28.099 ms/op versus Google 14.602 ms/op.
  - q11 decode, `silesia-64k.bin.google.q11.br`, native debug:
    75.986 ms/op versus Google 14.219 ms/op.
- Validated q11 external decode with the installed Google Brotli CLI:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 11`
  - encoded size: 22,155 bytes.
  - encoded SHA-256:
    `92b6b1b2103eec3ac0217ec074c21e3ad0966a45a02f46498c41209c1239a542`.
  - decoded SHA-256 matched input:
    `262258811321382f9e4f44d2184b6b7fed0336cf831446d8336c47d6ccc2b32e`.
- Release interpretation:
  - q11 is correct on this external-decode slice, but still far from the P4
    2% ratio goal on `silesia-64k.bin` because it is 15.04% larger than
    Google q11.
  - Native release target-perf remains a tooling problem for 64 KiB+ embedded
    input tests; do not mistake native debug numbers for final release
    performance.

## 2026-05-25 20:22 +0800 — P1 Brotli copy-from-distance decode fast path

- Optimized `BrotliOutputBuilder::copy_from_distance`:
  - distance=1 now fills the repeated byte without recomputing the source
    offset on every byte.
  - non-overlapping copies (`distance >= length`) use `FixedArray::blit_to`.
  - overlapping copies keep the previous forward byte-by-byte semantics
    required by Brotli back-references.
- Added white-box coverage for non-overlap, distance=1, and overlapping copy
  semantics in `brotli_wbtest.mbt`.
- target-perf q11 decode on `silesia-64k.bin.google.q11.br`:
  - wasm-gc release: improved from 23.077 ms/op to 19.023 ms/op.
  - native debug: improved from 28.675 ms/op to 28.553 ms/op after a higher
    repeat-count rerun; the smaller 5-repeat run was noisy.
  - Decoded size unchanged at 65,536 bytes; input compressed size 19,258
    bytes.
- Validation completed:
  - `moon test --target native --filter '*copy_from_distance*'`: 1/1 passed.
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 20:25 +0800 — P1 Brotli command-info lookup table

- Replaced repeated `brotli_command_info` prefix-offset computation with a
  704-entry precomputed `brotli_command_info_table`.
- This benefits both decode (`brotli_read_command`) and encode command-prefix
  search paths while preserving the same public API and invalid-symbol error.
- target-perf results against HEAD baseline:
  - q11 decode, `silesia-64k.bin.google.q11.br`, wasm-gc release:
    10.515 ms/op versus baseline 10.650 ms/op.
  - q11 decode, same input, native debug:
    29.498 ms/op versus baseline 29.625 ms/op.
  - q9 encode, `silesia-64k.bin`, wasm-gc release:
    149.446 ms/op versus baseline 150.459 ms/op; size unchanged at
    22,261 bytes versus Google 22,063 bytes.
  - q9 encode, `silesia-64k.bin`, native debug:
    432.617 ms/op versus baseline 652.482 ms/op; size unchanged at
    22,261 bytes versus Google 22,063 bytes.
- Validation completed:
  - `moon test --target native --filter '*brotli_command_info*'`: 1/1 passed.
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 20:29 +0800 — P1 fuzz and conformance evidence

- Generated a local short fuzz corpus with:
  - `nu tools/brotli/fuzz/gen-corpus.nu --count 25`
- Ran the short fuzz gate:
  - `nu tools/brotli/fuzz/run.nu --limit 25`
  - Result: 25/25 inputs passed without native panic or unchecked bounds
    failure. Inputs included embedded fixture seeds plus truncation, append,
    and delete-middle mutations.
- Ran the full available upstream Google Brotli conformance corpus:
  - `nu tools/brotli/conformance/run.nu`
  - Result: 22/22 fixtures passed:
    `10x10y`, `64x`, `alice29.txt`, `asyoulik.txt`, `backward65536`,
    `compressed_file`, `compressed_repeated`, `cp1251-utf16le`, `cp852-utf8`,
    `empty`, `lcet10.txt`, `mapsdatazrh`, `monkey`, `plrabn12.txt`,
    `quickfox`, `quickfox_repeated`, `random_org_10k.bin`, `ukkonooa`, `x`,
    `xyzzy`, `zeros`, `zerosukkanooa`.
- Cleaned the generated random fuzz corpus after the run and kept only the
  checked-in `.gitkeep`; the corpus generator remains the reproducible entry
  point for local fuzz samples.
- Release interpretation:
  - This satisfies the practical P1 short gate for this session.
  - It does not replace the final documented 24-hour fuzz gate required before
    declaring Brotli release-ready.

## 2026-05-25 20:34 +0800 — P2 q2 medium-input split/context candidate

- Measured current ratio baseline on `silesia-64k.bin`:
  - q2: 27,968 bytes versus Google q2 24,364 bytes; 14.79% overhead.
  - q9: 22,261 bytes versus Google q9 22,063 bytes; 0.90% overhead.
  - q11: 22,155 bytes versus Google q11 19,258 bytes; 15.04% overhead.
- q2 was the best P2 first target because q9 is already inside the 5% P3
  window and q11 needs the larger P4 backend.
- Changed q2 LZ77 meta-block selection for medium inputs:
  - Keep the fast weighted-only return for inputs at least 128 KiB.
  - For 8 KiB..128 KiB q2 chunks, exact-cost only two bounded candidates:
    literal split and 16-tree UTF-8 context.
  - This preserves most of the ratio win from the full candidate matrix while
    avoiding the highest candidate-write overhead.
- Ratio and external decode evidence on `silesia-64k.bin` q2:
  - MoonBit output improved from 27,968 to 25,245 bytes.
  - Google q2 output is 24,364 bytes.
  - Size overhead improved from 14.79% to 3.62%, entering the 5% target window
    on this slice.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 2`
    passed external `brotli` decode; decoded SHA-256 matched input
    `262258811321382f9e4f44d2184b6b7fed0336cf831446d8336c47d6ccc2b32e`.
- target-perf tradeoff versus HEAD baseline:
  - wasm-gc release q2 encode: 115.819 ms/op versus 109.058 ms/op baseline;
    size 25,245 bytes versus 27,968 baseline.
  - native debug q2 encode: 329.200 ms/op versus 300.358 ms/op baseline;
    size 25,245 bytes versus 27,968 baseline.
  - Full candidate-matrix trial was rejected as too expensive: same 25,245-byte
    output but 128.853 ms/op wasm-gc and 382.848 ms/op native debug.
- Validation completed:
  - `moon test --target native --filter '*brotli_sync q2*'`: 18/18 passed.
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 20:39 +0800 — P2 q2 128 KiB split/context extension

- Extended the bounded q2 split/context exact-cost path from `<128 KiB` to
  `<256 KiB` chunks by raising the fast weighted-only cutoff from 131,072 to
  262,144 bytes.
- Ratio and external decode evidence on `silesia-128k.bin` q2:
  - MoonBit output improved from 51,928 to 46,509 bytes.
  - Google q2 output is 44,794 bytes.
  - Size overhead improved from 15.93% to 3.83%, entering the 5% target window
    on this slice.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-128k.bin --quality 2`
    passed external `brotli` decode; decoded SHA-256 matched input
    `c069c1fdca99bc5c44f06d134cd0cda60315dd631aa6564733b2ce0e6d59305c`.
- target-perf tradeoff versus HEAD baseline:
  - wasm-gc release q2 encode: 132.088 ms/op versus 124.937 ms/op baseline;
    size 46,509 bytes versus 51,928 baseline.
  - native debug q2 encode: 333.868 ms/op versus 308.044 ms/op baseline;
    size 46,509 bytes versus 51,928 baseline.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 21:34 +0800 — P2 q11 parser depth and distance-cache tradeoff

- Rejected a combined split + UTF-8-16-context meta-block experiment for q11:
  it compiled and produced valid streams, but `silesia-64k.bin` q11 stayed at
  22,155 bytes, so the extra 32-tree context-map/header cost did not beat the
  existing exact-costed candidates.
- Tuned the high-quality q11 parser:
  - q11 hash-chain checks increased from 128 to 256.
  - Recent-distance cache matches are preserved unless a q11 hash-chain
    candidate is at least two bytes longer. The margin is gated to the q11
    256-check configuration so q9 keeps its previous behavior.
  - Rejected a 512-check q11 trial: `silesia-1m.bin` improved further to
    264,938 bytes, but legacy verification encode time rose to ~199.8s versus
    ~137.8s for 256 checks and ~96.7s at HEAD.
- Ratio evidence:
  - `silesia-64k.bin` q11 improved from 22,155 to 22,139 bytes versus Google
    q11's 19,258 bytes; overhead improved from 15.04% to 14.96%.
  - `silesia-1m.bin` q11 improved from 267,620 to 266,056 bytes versus Google
    q11's 239,314 bytes; overhead improved from 11.83% to 11.17%.
  - q9 `silesia-64k.bin` stayed at the prior 22,261-byte output after scoping
    the distance-cache preference to q11.
- target-perf evidence versus HEAD baseline on `silesia-64k.bin` q11:
  - wasm-gc release encode: 53.254 ms/op versus 50.086 ms/op baseline; size
    22,139 bytes versus 22,155 baseline.
  - native debug encode: 266.152 ms/op versus 246.360 ms/op baseline; size
    22,139 bytes versus 22,155 baseline.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 11`
    passed; encoded size 22,139 bytes and decoded SHA-256 matched input
    `262258811321382f9e4f44d2184b6b7fed0336cf831446d8336c47d6ccc2b32e`.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 11`
    passed; encoded size 266,056 bytes and decoded SHA-256 matched input
    `2e22bff2997b86befa1165366bd320c9535882009e4d5cd7c838542edf13baf2`.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 22:11 +0800 — P2 residual low-alphabet gate cleanup

- Audited the remaining "conservative low-alphabet q2 gate" plan item against
  current code:
  - q2 large-input chunks now enter `brotli_natural_hash_config_for_quality(2)`,
    whose `require_dense_match_density` is `false`.
  - `brotli_collect_unique_literals(data, data.length())` always returns
    `Some` because it now uses a 256-entry seen table and no longer enforces a
    symbol cap.
  - The leftover calls in the literal-only and LZ77 command builders were
    therefore dead O(n) scans from the old gate era.
- Removed those two dead scans from `src/brotli_encode.mbt`.
- Ratio evidence on `silesia-64k.bin` stayed byte-for-byte unchanged:
  - q2: 25,245 bytes versus Google q2 24,364 bytes.
  - q9: 22,261 bytes versus Google q9 22,063 bytes.
  - q11: 22,139 bytes versus Google q11 19,258 bytes.
- Current 1 MiB Silesia baseline after `bfa4782`:
  - q2: 329,512 bytes versus Google 320,418; overhead 2.84%.
  - q9: 273,633 bytes versus Google 263,791; overhead 3.73%.
  - q11: 266,056 bytes versus Google 239,314; overhead 11.17%.
- target-perf evidence versus HEAD baseline on `silesia-64k.bin`:
  - q2 wasm-gc encode: 27.985 -> 27.585 ms/op; native debug:
    129.866 -> 129.135 ms/op; size unchanged at 25,245 bytes.
  - q9 wasm-gc encode: 44.887 -> 43.976 ms/op; native debug:
    206.419 -> 205.193 ms/op; size unchanged at 22,261 bytes.
  - q11 wasm-gc encode: 53.479 -> 52.938 ms/op; native debug:
    267.565 -> 266.154 ms/op; size unchanged at 22,139 bytes.
- Rejected q11 two-command-block split as a smaller P4 subproblem:
  even with loose admission, `silesia-64k.bin` q11 stayed at 22,139 bytes.
- Validation completed:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 2`
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 9`
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 11`
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 22:34 +0800 — P2 q10 high-quality search promotion

- Measured q10 as a separate P4 gap instead of assuming q11 was the only
  remaining high-quality target:
  - Before change, q10 used the q9 32-check high-quality configuration and
    produced the same bytes as q9.
  - `silesia-64k.bin` q10 baseline: 22,261 bytes versus Google q10 19,566
    bytes; 13.77% overhead.
  - `silesia-1m.bin` q10 baseline: 273,633 bytes versus Google q10 242,485
    bytes; 12.85% overhead.
- Promoted q10 to the same 131,072-entry / 256-check / 600,000-command
  high-quality parser configuration as q11.
- Ratio evidence:
  - `silesia-64k.bin` q10 improved from 22,261 to 22,139 bytes; overhead
    13.77% -> 13.15%.
  - `silesia-1m.bin` q10 improved from 273,633 to 266,056 bytes; overhead
    12.85% -> 9.72%.
  - q9 stayed at 22,261 bytes on `silesia-64k.bin`; q11 stayed at 22,139
    bytes on `silesia-64k.bin`.
- target-perf evidence versus HEAD baseline on `silesia-64k.bin` q10:
  - wasm-gc release encode: 44.865 -> 53.307 ms/op; size 22,261 -> 22,139
    bytes.
  - native debug encode: 205.104 -> 266.193 ms/op; size 22,261 -> 22,139
    bytes.
  - This is an intentional high-quality tradeoff: q10 moves closer to P4
    ratio while remaining below q11's quality level in Google-reference size.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 10`
    passed; decoded SHA-256 matched input.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 10`
    passed; decoded SHA-256 matched input.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 22:58 +0800 — P2 q10/q11 high-quality candidate pruning

- Investigated whether q10/q11 still need both high-quality hash candidates:
  - Skipping the 4-byte hash candidate made q10/q11 faster but regressed
    `silesia-64k.bin` from 22,139 to 22,145 bytes, so that direction was
    rejected.
  - Keeping only the 4-byte hash candidate preserved q10/q11 size on both
    `silesia-64k.bin` and `silesia-1m.bin`.
- Accepted change:
  - q10/q11 now run only the 4-byte high-quality hash candidate.
  - q9 still runs both 3-byte and 4-byte candidates and remains unchanged.
- Ratio evidence:
  - `silesia-64k.bin` q10/q11 stay at 22,139 bytes.
  - `silesia-1m.bin` q10/q11 stay at 266,056 bytes.
  - Legacy ratio time on `silesia-1m.bin` q10/q11 drops from about 138-139s
    to about 65s with unchanged bytes.
- target-perf evidence versus HEAD baseline on `silesia-64k.bin`:
  - q10 wasm-gc encode: 53.591 -> 31.815 ms/op; native debug:
    266.972 -> 144.376 ms/op; size unchanged at 22,139 bytes.
  - q11 wasm-gc encode: 53.522 -> 30.943 ms/op; native debug:
    267.016 -> 149.348 ms/op; size unchanged at 22,139 bytes.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 10`
    passed; decoded SHA-256 matched input.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 11`
    passed; decoded SHA-256 matched input.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`

## 2026-05-25 21:53 +0800 — P4 q10/q11 local parser probes rejected

- Continued the P4 q10/q11 investigation after `f82896a` with five bounded,
  reversible experiments:
  - Stricter high-quality lazy skipping: rejected because `silesia-64k.bin`
    q10/q11 regressed from 22,139 to 22,212 bytes.
  - Estimated distance-bit hash-candidate scoring: rejected because
    `silesia-64k.bin` q10/q11 regressed to 22,203 bytes.
  - q10/q11 min-match length 5 -> 4: rejected because `silesia-64k.bin`
    q10/q11 regressed to 22,179 bytes.
  - q10/q11 direct context16 writer: preserved 22,139 bytes on 64 KiB and
    266,056 bytes on 1 MiB, but controlled `target-perf.nu` comparisons
    showed it was slower than HEAD.
  - q10/q11 direct high-quality parser without preliminary low-quality,
    literal-only, and dictionary candidates: preserved 22,139 bytes on 64 KiB
    and 266,056 bytes on 1 MiB, but only improved q10 wasm-gc while regressing
    native debug q10/q11 by roughly 1-4%.
- Current worktree was restored to clean code after the rejected probes; no
  performance commit was made because none met both wasm-gc and native
  requirements.
- Updated findings with the rejected probe details and the conclusion that the
  remaining q10/q11 release gap needs a real shortest-path/Zopfli candidate or
  broader block/histogram clustering rather than another local greedy knob.

## 2026-05-25 22:08 +0800 — P4 bounded shortest-path probe rejected

- Implemented and tested a temporary q10/q11-only bounded shortest-path probe:
  - The probe retained the current greedy command stream as the baseline.
  - It added a second exact-costed candidate that could shorten long copies by
    up to 16 bytes when the shorter boundary exposed a longer following match.
- Ratio evidence:
  - `silesia-64k.bin` q10/q11 stayed at 22,139 bytes, with no size gain.
  - `silesia-1m.bin` q11 stayed at 266,056 bytes, with no size gain.
- Performance evidence:
  - The extra candidate made the legacy verification path much slower
    (`silesia-1m.bin` q11 around 173s), so it is not acceptable for release.
- Reverted the temporary implementation and kept the worktree clean.
- Conclusion: the remaining q10/q11 P4 gap needs a real Zopfli-style node
  array, cost model, and traceback rather than local copy-boundary trimming.

## 2026-05-25 22:35 +0800 — P4 shortest-path DP work in progress

- Added a work-in-progress q10/q11 DP traceback candidate locally:
  - hash-chain candidate enumeration now exposes multiple match candidates per
    position for the DP parser.
  - the DP path uses a bounded integer cost model and exact-costs the resulting
    command stream against the existing greedy q10/q11 stream.
  - DP output currently uses explicit distances only; attempts to use
    recent-distance short codes without carrying distance-ring state caused
    corrupt 1 MiB streams (`brotli` reported `FORMAT_TRANSFORM`), so short-code
    use must wait for a DP state model that includes the distance ring.
- Current evidence from the WIP implementation:
  - `silesia-1m.bin` q11 improves from 266,056 to 262,969 bytes and validates
    with external Google Brotli when DP uses explicit distances.
  - `silesia-1m.bin` q10 also improves to 262,969 bytes.
  - The legacy verification encode time is much higher (~212-213s on 1 MiB),
    so this is not yet a commit-ready release increment under the native/wasm
    encode-performance constraint.
  - DP does not materially help 128 KiB, so the local WIP now raises the DP
    trigger threshold to 512 KiB to reduce wasted medium-input cost.
- Next step: either optimize the DP parser enough to make the 1 MiB ratio gain
  acceptable, or replace the explicit-distance DP with a Zopfli-style state
  that carries recent-distance cache state and can safely use short codes.

## 2026-05-25 23:45 +0800 — P4 shortest-path DP bounded to 1 MiB chunks

- Refined and then rejected the q10/q11 shortest-path DP candidate after
  target-perf exposed excessive native encode cost:
  - Inlined candidate relaxation into the DP loop to remove per-position
    candidate Array allocation.
  - Limited DP to full 1 MiB chunks; 512 KiB and smaller inputs keep the
    previous direct greedy q10/q11 path.
  - Kept explicit distances in the DP traceback because short-code experiments
    without distance-ring state produced corrupt 1 MiB streams.
  - Used 32 emitted candidates with a 128 hash-chain check cap as the current
    ratio/time tradeoff.
- Ratio evidence:
  - `silesia-512k.bin` q11 remains at 136,638 bytes, matching the pre-DP
    greedy output.
  - `silesia-1m.bin` q10 improves from 266,056 to 263,496 bytes; overhead
    versus Google q10 moves from 9.72% to 8.66%.
  - `silesia-1m.bin` q11 improves from 266,056 to 263,496 bytes; overhead
    versus Google q11 moves from 11.17% to 10.10%.
- target-perf evidence:
  - `silesia-512k.bin` q11 wasm-gc min is 517.230 ms versus HEAD 510.658 ms;
    native debug min is 1953.553 ms versus HEAD 1965.578 ms; size unchanged.
  - `silesia-512k.bin` q10 wasm-gc min is 507.755 ms versus HEAD 510.581 ms;
    native debug min is 1975.432 ms versus HEAD 1959.534 ms; size unchanged.
  - `silesia-1m.bin` wasm-gc target-perf cannot currently run because the
    generated embedded-input white-box test exceeds the WasmGC function-size
    limit; use ratio harness time and 512 KiB target-perf as local evidence
    until the harness supports file-backed inputs.
  - `silesia-1m.bin` q11 native debug target-perf regressed from 4275.087 ms
    at HEAD to 18179.669 ms with the 128-check DP, and still took 17075.047
    ms at 64 checks. A 32-check / 16-candidate trial removed the size gain but
    still took 12191.136 ms. This violates the encode-performance constraint.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 10`
    passed; decoded SHA-256 matched input.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 11`
    passed; decoded SHA-256 matched input.
- Validation completed before rejection:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`
- Final decision: do not commit this DP implementation. The worktree was
  restored to the previous code state. The next P4 attempt should either carry
  recent-distance state in the shortest-path model and reduce search cost
  substantially, or prioritize block/histogram clustering where exact-cost
  writer work is more bounded.

## 2026-05-25 23:59 +0800 — Joint block clustering probe rejected

- Implemented a local q10/q11 literal/command/distance two-block candidate:
  - split points were command-stream 1/4, 1/2, and 3/4;
  - literal, command, and distance block headers were all split together;
  - literal and distance context maps selected tree 0 for block 0 and tree 1
    for block 1;
  - all candidates were exact-costed against the existing best meta-block.
- Validation and measurements:
  - `moon check --target all` passed.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-64k.bin --qualities 10,11 --json`
    showed q10/q11 unchanged at 22,139 bytes.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json`
    showed q10/q11 unchanged at 266,056 bytes.
- Decision: reject and restore the worktree. The bounded binary joint split
  adds writer cost without ratio gain, so it is not a release-useful
  block/histogram clustering increment.

## 2026-05-26 00:18 +0800 — q10/q11 mixed dictionary parser increment

- Implemented a bounded q10/q11 mixed static-dictionary + high-quality LZ77
  parser candidate:
  - large q10/q11 chunks now try a 4-byte high-quality parser that can emit
    8+ byte identity static-dictionary commands at word boundaries;
  - the mixed parser is used as the high-quality q10/q11 candidate when it
    finds dictionary matches, avoiding the previous double writer cost of
    exact-costing both plain hq and mixed hq streams;
  - if no dictionary match is found, q10/q11 fall back to the existing 4-byte
    high-quality hash parser.
- Rejected intermediate variants:
  - full same-length plus selected extra transforms improved `silesia-1m.bin`
    to 264,024 bytes but raised legacy verify time to ~138-140s;
  - exact-costing mixed after plain hq doubled target-perf native debug time;
  - 12+ byte identity-only matches kept performance but improved 1 MiB by
    only 343 bytes.
- Accepted ratio evidence:
  - `silesia-64k.bin` q10/q11: 22,139 -> 21,681 bytes.
  - `silesia-1m.bin` q10/q11: 266,056 -> 265,056 bytes.
  - q10 1 MiB overhead vs Google q10: 9.72% -> 9.31%.
  - q11 1 MiB overhead vs Google q11: 11.17% -> 10.76%.
- target-perf evidence on `silesia-64k.bin`:
  - q10 wasm-gc encode min: 31.815 -> 33.620 ms/op; size 22,139 -> 21,681.
  - q10 native debug encode min: 144.376 -> 155.233 ms/op; size 22,139 ->
    21,681.
  - q11 wasm-gc encode min: 30.943 -> 33.636 ms/op; size 22,139 -> 21,681.
  - q11 native debug encode min: 149.348 -> 154.935 ms/op; size 22,139 ->
    21,681.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 10`
    passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-64k.bin --quality 11`
    passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 10`
    passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 11`
    passed.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`
  - `git diff --cached --check`

## 2026-05-26 00:34 +0800 — q10/q11 same-length dictionary transforms

- Extended the q10/q11 mixed dictionary index from identity-only transform 0
  to the three same-length transforms `[0, 9, 44]`.
- This preserves the optimized mixed-main-candidate structure from commit
  `3f90716` while avoiding the earlier expensive all-transform scan.
- Accepted ratio evidence:
  - `silesia-64k.bin` q10/q11: 21,681 -> 21,595 bytes.
  - `silesia-1m.bin` q10/q11: 265,056 -> 264,840 bytes.
  - q10 1 MiB overhead vs Google q10: 9.31% -> 9.22%.
  - q11 1 MiB overhead vs Google q11: 10.76% -> 10.67%.
- target-perf evidence on `silesia-64k.bin`:
  - q10 wasm-gc encode min: 33.620 -> 35.151 ms/op; size 21,681 -> 21,595.
  - q10 native debug encode min: 155.233 -> 162.467 ms/op; size 21,681 ->
    21,595.
  - q11 wasm-gc encode min: 33.636 -> 34.509 ms/op; size 21,681 -> 21,595.
  - q11 native debug encode min: 154.935 -> 162.666 ms/op; size 21,681 ->
    21,595.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 10`
    passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 11`
    passed.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`
  - `git diff --cached --check`
- Follow-up rejected: adding the selected extra transform list reduced
  `silesia-64k.bin` q10/q11 to 21,332 bytes, but q11 native debug target-perf
  regressed from 162.666 to 241.425 ms/op, so the experiment was reverted.
- Follow-up rejected: raising q10/q11 hash-chain checks from 256 to 512 after
  the same-length dictionary commit reduced `silesia-1m.bin` q10/q11 from
  264,840 to 263,738 bytes, but q11 1 MiB native debug target-perf was
  5,954.132 ms/op and the legacy verify path rose to ~85.5s. The performance
  cost is too high for the remaining ratio gap.

## 2026-05-26 00:55 +0800 — q10/q11 trailing-space dictionary transforms

- Added the two selected extra transforms `[1, 4]` to the q10/q11 mixed
  dictionary index. These cover identity/uppercase-first words followed by a
  trailing space and avoid the rejected full selected-extra transform scan.
- Accepted ratio evidence:
  - `silesia-64k.bin` q10/q11: 21,595 -> 21,415 bytes.
  - `silesia-1m.bin` q10/q11: 264,840 -> 264,422 bytes.
  - q10 1 MiB overhead vs Google q10: 9.22% -> 9.05%.
  - q11 1 MiB overhead vs Google q11: 10.67% -> 10.49%.
- target-perf evidence on `silesia-64k.bin`:
  - q10 wasm-gc encode min: 35.151 -> 37.226 ms/op; size 21,595 -> 21,415.
  - q10 native debug encode min: 162.467 -> 170.846 ms/op; size 21,595 ->
    21,415.
  - q11 wasm-gc encode min: 34.509 -> 37.329 ms/op; size 21,595 -> 21,415.
  - q11 native debug encode min: 162.666 -> 170.831 ms/op; size 21,595 ->
    21,415.
- External decode evidence:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 10`
    passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 11`
    passed.
- Validation completed:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`: 456/456 passed on wasm, wasm-gc, js, native.
  - `moon info`
  - `git diff --check`
  - `git diff --cached --check`
- Follow-up rejected: expanding the subset to `[1, 4, 16, 28, 47]` only
  reduced `silesia-64k.bin` q10/q11 from 21,415 to 21,396 bytes, while q11
  native debug target-perf regressed from 170.831 to 191.219 ms/op.

## 2026-05-26 02:30 +0800 — P4 baseline confirmation and Zopfli-lite design

- Validation pass on commit `7afd657`:
  - `moon check --target all`: passed
  - `moon test --target all`: 456/456 on wasm/wasm-gc/js/native
  - `nu tools/brotli/conformance/run.nu`: 22/22 upstream fixtures pass
  - `nu tools/brotli/fuzz/gen-corpus.nu --count 25` + `nu tools/brotli/fuzz/run.nu --limit 25`: 25/25 inputs pass
- target-perf baselines on the current code:
  - `silesia-64k.bin` q11 encode: wasm-gc 36.15 ms / native 24.18 ms;
    MoonBit 21,415 bytes vs Google 19,258 (11.20% overhead).
  - `silesia-64k.bin` q10 encode: wasm-gc 36.30 ms / native 23.93 ms;
    MoonBit 21,415 bytes vs Google 19,566 (9.45% overhead).
  - `silesia-128k.bin` q11 encode: wasm-gc 62.96 ms / native 43.78 ms;
    MoonBit 38,713 bytes vs Google 35,164 (10.09% overhead).
  - `silesia-256k.bin` q11 encode: wasm-gc 139.60 ms / native 96.47 ms;
    MoonBit 71,928 bytes vs Google 65,448 (9.90% overhead).
  - `silesia-64k.bin` q11 decode: wasm-gc 5.20 ms / native 2.22 ms vs Google
    4.23 ms (wasm-gc 1.23x slower, native 0.53x faster).
  - `silesia-512k.bin` q11 decode: wasm-gc 17.28 ms / native 6.86 ms vs Google
    8.31 ms (wasm-gc 2.08x slower, native 0.82x).
- Decode literal hot-loop optimization tested and rejected:
  - Maintained `prev_byte_1`/`prev_byte_2` in registers across the inner loop
    instead of recomputing from `output.buf` each step.
  - target-perf min times stayed within noise (silesia-64k.bin q11 wasm-gc:
    5.20 -> 5.20 ms; native: 2.22 -> 2.23 ms).
  - MoonBit compiler likely already does this optimization. Rolled back.
- Conclusion: bias next work toward the Zopfli-lite DP candidate. Local
  greedy/parser knobs and bounded clustering have hit diminishing returns.

### Zopfli-lite Design Outline

- Integer cost model (no `Double` carry issues): cost units are 1/1024 bits
  to keep arithmetic in `Int` while preserving relative ordering.
- Per-position node array:
  - `cost`: cumulative cost reaching the node
  - `length`: 0 = literal, >0 = match length
  - `distance`: 0 = literal, >0 = explicit backward distance
  - `short_code`: -1 = explicit, 0..15 = recent-distance short code
  - `insert_length`: number of literals from the previous decision
  - `prev_pos`: pointer back to the predecessor
- Traceback rebuilds the four-entry distance cache by replaying decisions,
  so cache state does not have to be stored in every node.
- Candidate generation reuses `brotli_longest_previous_hash_match_with_cache`
  but bounded to 1 longest match per position. Future increments may add
  multi-length expansions if ratio results justify the cost.
- Cost model:
  - Literal byte: 8 << 10 (=8 bits) plus optional frequency-weighted boost.
  - Command symbol: ~5 bits (5 << 10) as a starting approximation.
  - Distance: short code 4 << 10, explicit code 6..12 bits depending on
    extra bits.
- Gated to q10/q11 chunks with `data.length() >= 65536` (≈ 64 KiB). Smaller
  inputs continue to use the existing high-quality hash candidate.
- Exact-costed against the existing best candidate; never replaces a smaller
  stream and never adds candidate writer work to lower qualities.

## 2026-05-26 03:20 +0800 — Zopfli-lite v1 prototype rejected

- Implemented a minimal Zopfli-lite parser (`src/brotli_encode_zopfli.mbt`,
  ~300 lines) with an integer cost model, frequency-weighted literal costs,
  and single longest-match per position with 3 expanded copy lengths.
- Wired it as an additional q11 candidate after the mixed-dictionary path.
- Measurement on `silesia-64k.bin` q11:
  - encoded size: 21,415 bytes (unchanged versus mixed-dictionary)
  - wasm-gc encode: 36.15 ms -> 71.21 ms (2x slower)
  - native encode: 24.18 ms -> 53.35 ms (2.2x slower)
- Root cause of zero ratio gain: cost model is too coarse to make different
  decisions than greedy. With only one longest match per position and no
  per-node distance-cache state, the DP effectively duplicates the existing
  mixed-dictionary parser's command stream. The exact-cost gate then rejects
  it (same byte count), wasting all DP work.
- Conclusion: a useful Zopfli candidate requires
  - per-node distance-cache state (so DP can prefer short-code transitions
    paths the greedy parser cannot see),
  - multiple match candidates per position (length range, not just the
    longest),
  - command/distance symbol costs derived from observed frequencies
    (Google Brotli iterates 4 rounds for this).
  - Total work is ≈ 1000-1500 LOC plus a faster inner loop, beyond what fits
    in this session's release-readiness scope.
- Removed the prototype and white-box test file. Recorded the design in this
  progress entry so future P4 work can resume from this point.
- Decision: ship Brotli with the current ratio gap documented in
  `docs/brotli_benchmarks.md` rather than ship a regressing Zopfli candidate.
- Action items remaining for release: update `CHANGELOG.md`, refresh
  `docs/brotli_benchmarks.md` with current q10/q11 numbers, refresh
  `README.md` for the new public Brotli APIs.

## 2026-05-26 03:50 +0800 — Zopfli-lite v2 (multi-candidate) also rejected

- Implemented Zopfli v2 with:
  - Frequency-weighted literal cost from `h_tree`.
  - Integer log2 cost table (1/1024 bit units) for command/distance symbols.
  - `brotli_zopfli_estimate_command_cost` mapping (insert_length, copy_length,
    distance, short_code) to an estimated Brotli command symbol cost via
    `log2(11 + symbol)` and `log2(20 + distance_code)`.
  - Length expansion `[length, length-1, length-2, length-4]` per candidate.
  - Multi-candidate hash chain enumeration via the new
    `brotli_collect_hash_match_candidates` helper (up to 8 candidates per
    position).
- Measurement on `silesia-64k.bin` q11 with Zopfli wired as an additional
  exact-costed q11 candidate:
  - encoded size: 21,415 bytes (unchanged from mixed-dictionary).
  - wasm-gc encode: 36.15 ms -> 59.36 ms (1.64x slower).
  - native encode: 24.18 ms -> 54.50 ms (2.25x slower).
- Measurement on `silesia-512k.bin` q11:
  - encoded size: 135,268 bytes (unchanged from mixed-dictionary).
  - wasm-gc encode: 354 ms -> 436 ms (1.23x slower).
  - native encode: 230 ms -> 285 ms (1.24x slower).
- Root cause of zero ratio improvement:
  - Mixed-dictionary parser already uses static dictionary matches; Zopfli
    candidate emits LZ77-only commands so its byte count is always >= the
    dictionary stream on natural text.
  - log2 cost model still picks longest-match decisions identical to greedy
    in the absence of dictionary candidates; DP cannot beat what greedy
    already finds.
- Conclusion: a useful q11 Zopfli candidate must integrate static dictionary
  matches into its candidate set and use exact Brotli command symbol costs
  (not log2 approximations). Total work is ~1500 LOC of MoonBit plus
  performance tuning, beyond this session's release scope.
- Reverted the prototype (`src/brotli_encode_zopfli.mbt`,
  `brotli_collect_hash_match_candidates` in
  `src/brotli_encode_hash.mbt`, and the `brotli_try_compressed_chunk` /
  `brotli_encode_standard` wiring).
- Action: ship Brotli with the current q10/q11 ratio gap documented; record
  the Zopfli design and failure modes here for the next P4 attempt.

## 2026-05-27 — q9 mixed dictionary candidate enabled

- Added `brotli_build_mixed_dictionary_lz77_commands` attempt at q9 with the
  4-byte high-quality hash config in both `brotli_encode_standard` and
  `brotli_try_compressed_chunk`, mirroring the q10/q11 path.
- Accepted ratio evidence:
  - silesia-64k.bin q9: 22,261 -> 21,514 bytes; now -2.49% vs Google 22,063
    (was +0.90%).
  - silesia-128k.bin q9: 40,013 -> 39,081 bytes; now -1.55% vs Google 39,695
    (was +0.80%).
  - silesia-1m.bin q9: 273,633 -> 271,776 bytes; overhead 3.73% -> 3.03%.
- target-perf evidence:
  - silesia-64k.bin q9 wasm-gc encode min: 140.583 -> 161.436 ms/op (+14.8%).
  - silesia-64k.bin q9 native encode min: 60.651 -> 77.168 ms/op (+27.2%).
  - silesia-128k.bin q9 wasm-gc encode min: 187.508 -> 223.941 ms/op (+19.4%).
  - silesia-128k.bin q9 native encode min: 89.278 -> 116.025 ms/op (+30.0%).
- q11 64k unchanged at 21,415 bytes.
- Validation completed: moon fmt; moon check --target all; moon test
  --target all 456/456 wasm/wasm-gc/js/native; moon info; external decode
  through Google Brotli for silesia-1m q9.

## 2026-05-28 10:40 +0800 — Planning files aligned with current Brotli code

- Updated `task_plan.md` to distinguish current implementation facts from
  remaining phase acceptance:
  - q0/q1 are RFC-valid stored-meta-block encoders, but do not satisfy the
    original q0/q1 Silesia ratio target unless that target is explicitly
    waived.
  - q2 and q9 have meaningful P3 ratio evidence, while q3..q8 still need a
    per-quality ratio and `target-perf.nu` acceptance matrix.
  - q10/q11 currently use deeper high-quality hash parsing plus mixed
    static-dictionary matches, not the planned P4 Zopfli/suffix-tree backend.
- Recorded HEAD implementation details that were missing from planning state:
  - `9075033` gates q9 mixed-dictionary work behind
    `brotli_mixed_dictionary_may_pay`, preserving q9 ratio wins while avoiding
    unconditional dictionary search.
  - `b910f87` trims mixed dictionary index allocation to the same transform
    subset used by the mixed path.
- No source changes and no test run in this update; this was a planning-state
  synchronization pass only.

## 2026-05-28 — q3..q8 baseline matrix recorded

- Ran the missing intermediate-quality P3 baseline:
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 3,4,5,6,7,8 --json`
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality <q> --targets wasm-gc,native --repeats 1 --samples 1 --json` for q3..q8.
- Key result: q3..q8 currently emit the same MoonBit stream on measured
  Silesia slices.
  - 1 MiB output: 313,577 bytes for q3..q8.
  - 64 KiB output: 25,127 bytes for q3..q8.
- Acceptance impact:
  - q3 is inside the P3 5% ratio window: 1 MiB is -0.05% versus Google q3,
    and 64 KiB is +4.44%.
  - q4..q8 are outside the 5% target because Google output improves with
    quality while MoonBit output is unchanged. 1 MiB overhead ranges from
    7.26% at q4 to 18.41% at q8.
- Updated `docs/brotli_benchmarks.md` with the ratio and target-perf table.
- Updated `task_plan.md`: the q3..q8 measurement task is complete; the next
  P3 implementation task is quality-aware q4..q8 differentiation, followed by
  richer histogram/block clustering.

## 2026-05-28 — q4..q8 intermediate search implemented

- Added `brotli_intermediate_hash_config_for_quality`:
  - q4: 8 hash-chain checks, 100,000-command cap, 6-byte minimum match.
  - q5/q6: 16 checks, 180,000-command cap, 5-byte minimum match.
  - q7/q8: 32 checks, 240,000-command cap, 5-byte minimum match.
- Wired q4..q8 to exact-cost the intermediate 3-byte and 4-byte hash
  candidates after the existing natural candidates. q3 remains on the prior
  faster baseline path.
- Added white-box coverage for the new intermediate config values.
- Ratio result on `silesia-1m.bin`:
  - q3 unchanged at 313,577 bytes, -0.05% versus Google q3.
  - q4: 313,577 -> 287,092 bytes, 7.26% overhead -> -1.80%.
  - q5: 313,577 -> 278,961 bytes, 14.41% overhead -> 1.78%.
  - q6: 313,577 -> 278,961 bytes, 16.30% overhead -> 3.46%.
  - q7: 313,577 -> 273,633 bytes, 17.40% overhead -> 2.45%.
  - q8: 313,577 -> 273,633 bytes, 18.41% overhead -> 3.33%.
- target-perf sampled on `silesia-64k.bin`:
  - q4 size 25,127 -> 22,785; wasm-gc 510.333 -> 559.701 ms/op; native
    120.076 -> 148.200 ms/op.
  - q5 size 25,127 -> 22,336; wasm-gc 529.914 -> 559.509 ms/op; native
    84.142 -> 110.135 ms/op.
  - q8 size 25,127 -> 22,261; wasm-gc 567.508 -> 556.979 ms/op; native
    125.608 -> 105.232 ms/op.
- Updated `docs/brotli_benchmarks.md` with the new ratio and target-perf
  tables.
- Remaining P3 work after this increment: full validation, broader
  histogram/block clustering, and release-scale q2..q9 ratio/perf matrix.

## 2026-05-28 — q2..q9 P3 matrix recorded

- Ran the current q2..q9 ratio matrix:
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,3,4,5,6,7,8,9 --json`
- Ran the current q2..q9 target-perf matrix:
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality <q> --targets wasm-gc,native --repeats 1 --samples 1 --json` for q2..q9.
- 1 MiB ratio result: every q2..q9 quality is inside the measured 5% Silesia
  ratio window:
  - q2 2.84%, q3 -0.05%, q4 -1.80%, q5 1.78%, q6 3.46%, q7 2.45%, q8 3.33%,
    q9 3.03%.
- 64 KiB target-perf result: every q2..q9 quality is inside the measured 5%
  Silesia ratio window, but sampled native runtime is high for q5..q7:
  - q5 native 142.394 ms vs Google 42.415 ms (3.36x).
  - q6 native 143.404 ms vs Google 39.738 ms (3.61x).
  - q7 native 153.878 ms vs Google 41.474 ms (3.71x).
  - q8 and q9 are lower at 2.56x and 2.65x, respectively.
- Updated `docs/brotli_benchmarks.md` and `task_plan.md` with this matrix.
- Next P3 implementation priority: tune q5..q7 runtime without losing the
  measured 5% ratio window, then decide whether broader histogram/block
  clustering is still needed before P3 release acceptance.

## 2026-05-28 — q6/q7 small-input runtime tuning

- Tested removing the intermediate 4-byte hash candidate for q5..q7:
  - q5 64 KiB size stayed inside 5% but native runtime regressed to
    194.418 ms, so q5 keeps the 4-byte candidate.
  - q6 1 MiB regressed to 288,629 bytes, 7.04% over Google q6.
  - q7 1 MiB regressed to 281,225 bytes, 5.29% over Google q7.
- Accepted a conditional version:
  - q6/q7 skip the intermediate 4-byte candidate only when `data.length() <=
65536`.
  - Larger q6/q7 chunks keep the 4-byte candidate, preserving 1 MiB ratio.
- Evidence:
  - q6 1 MiB remains 278,961 bytes, 3.46% over Google q6.
  - q7 1 MiB remains 273,633 bytes, 2.45% over Google q7.
  - q6 64 KiB native target-perf improves from 143.404 to 126.045 ms/op;
    wasm-gc improves from 556.699 to 514.744 ms/op; size moves from 22,336
    to 22,542 bytes but stays 1.90% over Google.
  - q7 64 KiB native target-perf improves from 153.878 to 139.976 ms/op;
    wasm-gc improves from 550.708 to 524.353 ms/op; size moves from 22,261
    to 22,373 bytes but stays 1.23% over Google.
- Added white-box assertions for `brotli_use_intermediate_four_byte_candidate`.
- Updated `docs/brotli_benchmarks.md`, `CHANGELOG.md`, and `task_plan.md`.
- Follow-up decode microtrial: skipping `take_bits(0)` for command and
  distance extras improved wasm-gc slightly in one same-day sample
  (62.105 to 59.815 ms/op) but regressed native from 21.694 to 26.296 ms/op
  against the `47dd8cb` worktree baseline, so it was reverted.

## 2026-05-28 — distance ring slot simplification accepted

- Simplified `brotli_distance_ring_slot` from `% 4` plus negative correction
  to `index & 3`, with an English comment documenting why the mask is valid
  for the four-slot ring and negative short-code indices.
- Added white-box coverage for `-1`, `-2`, and `4` slot wraparound before the
  existing implicit-distance assertions.
- Target-perf on Google q11 `silesia-1m.bin` stream:
  - wasm-gc decode: 242.629 to 245.813 ms/op in the sampled run.
  - native decode: 27.770 to 27.139 ms/op in the sampled run.
- Decision: retained as an equivalent hot-path simplification per maintainer
  preference; wasm-gc movement is small and within same-day sample noise, and
  native moved slightly faster.
- Follow-up decode microtrial: replacing `take_short_code` branch arithmetic
  with short-code lookup tables improved sampled native decode from 27.139 to
  20.994 ms/op, but regressed sampled wasm-gc decode from 245.813 to
  277.682 ms/op on the q11 1 MiB stream, so it was reverted.
- Remaining P3 runtime concern: q5 sampled native runtime.

## 2026-05-28 — Planning sync for current q5 worktree experiment

- Re-read `planning-with-files` and `moonbit-agent-guide`, then checked the
  active plan, git status, current Brotli diff, recent benchmark docs, and the
  q6/q7 small-input tuning commit at `9322d68`.
- Current dirty worktree state:
  - `src/brotli_encode_hash.mbt` changes q5 to the lighter q4-style
    intermediate hash config: 8 checks, 100,000-command cap, and 6-byte
    minimum match. Tracked HEAD still has q5 at 16 checks, 180,000-command cap,
    and 5-byte minimum match.
  - `src/brotli_wbtest.mbt` updates the white-box expectations for that q5
    trial.
  - `src/brotli_target_perf_1779955563258957000-279810685_wbtest.mbt` was a
    generated target-perf scratch test file during the active run; the harness
    removed it after completion, so it is not source.
- q5 ratio evidence already observed for the trial:
  - `silesia-1m.bin` q5: MoonBit 287,092 bytes versus Google 274,088 bytes,
    or 4.74% overhead.
  - Previous accepted q5 config was 278,961 bytes, or 1.78% overhead, so the
    trial spends most of the remaining 5% ratio margin.
- Completed the pending q5 target-perf run:
  - `silesia-64k.bin` q5 worktree trial output: 22,785 bytes versus Google
    22,271 bytes, or 2.31% overhead.
  - wasm-gc encode: 535.757 ms/op versus Google 41.049 ms/op, 13.05x.
  - native encode: 145.131 ms/op versus Google 41.049 ms/op, 3.54x.
- Decision recorded in `task_plan.md`: reject and revert this q5 trial. The
  wasm-gc improvement versus the accepted q5 baseline is too small to justify
  worse native runtime, worse 64 KiB size, and the 1 MiB ratio moving from
  +1.78% to +4.74%.
- Reverted the q5 trial code path back to the accepted 16-check,
  180,000-command, 5-byte-minimum intermediate config. The tracked source diff
  for `src/brotli_encode_hash.mbt` and `src/brotli_wbtest.mbt` is now clean.
- Added the rejected q5 trial data to `docs/brotli_benchmarks.md` so future
  q5 work does not repeat this size/native-runtime tradeoff.

## 2026-05-28 — q5 natural 4-byte candidate skip accepted

- Tested skipping only q5's natural 4-byte hash candidate while keeping the
  intermediate 4-byte candidate. This differs from the rejected broad q5 skip:
  the accepted q5 stream is still available, but one redundant natural
  parser/candidate-writer pass is removed.
- Validation evidence before full final gate:
  - `moon fmt` passed.
  - `moon check --target all` passed.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 5 --json`
    kept q5 output at 278,961 bytes versus Google 274,088 bytes, or +1.78%.
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 5 --targets wasm-gc,native --repeats 1 --samples 1 --json`
    kept output at 22,336 bytes versus Google 22,271 bytes; wasm-gc improved
    from 541.752 to 524.160 ms/op and native improved from 142.394 to 94.185
    ms/op.
- Updated `src/brotli_encode.mbt`, `src/brotli_wbtest.mbt`,
  `docs/brotli_benchmarks.md`, `CHANGELOG.md`, and `task_plan.md`.

## 2026-05-28 — three-literal-block LZ77 split rejected

- Tried a bounded three-literal-block LZ77 candidate as the next P3
  block/histogram step. The estimator considered split pairs at `(1/4, 1/2)`,
  `(1/4, 3/4)`, and `(1/2, 3/4)` over inserted literals and wrote a
  three-literal-block candidate only when estimated literal entropy savings
  exceeded a metadata threshold.
- Validation:
  - `moon fmt` passed.
  - `moon check --target all` passed.
  - `moon test --target native --filter '*splits LZ77 command literal blocks*'`
    passed 1/1.
  - `target-perf.nu` on `silesia-64k.bin` q9 kept size at 21,514 bytes;
    wasm-gc measured 504.737 ms/op versus prior 530.562, but native measured
    130.972 ms/op versus prior 128.080.
  - `ratio.nu` on `silesia-1m.bin` q9 kept size at 271,776 bytes versus
    Google 263,791, while legacy JS verifier time moved from 48,703.919 to
    52,258.807 ms.
- Decision: rejected and reverted. The candidate did not improve size and did
  not produce a defensible native performance win. Recorded in
  `docs/brotli_benchmarks.md`.

## 2026-05-28 — q10/q11 P4 baseline refreshed

- Re-ran current q10/q11 P4 ratio and target-perf baselines after the q5 and
  P3 exploration commits.
- Ratio on `silesia-1m.bin`:
  - q10: 264,422 bytes versus Google 242,485, or +9.05%.
  - q11: 264,422 bytes versus Google 239,314, or +10.49%.
- `target-perf.nu` on `silesia-64k.bin`:
  - q10 wasm-gc: 21,415 bytes, 510.253 ms/op versus Google 19,566 bytes and
    62.649 ms/op.
  - q10 native: 21,415 bytes, 121.332 ms/op versus Google 19,566 bytes and
    62.649 ms/op.
  - q11 wasm-gc: 21,415 bytes, 547.539 ms/op versus Google 19,258 bytes and
    115.586 ms/op.
  - q11 native: 21,415 bytes, 75.297 ms/op versus Google 19,258 bytes and
    115.586 ms/op.
- Updated `docs/brotli_benchmarks.md` with this baseline. P4 remains
  ratio-bound: q10/q11 still share the same MoonBit stream and are far outside
  the 2% target.

## 2026-05-28 — q10-only wider mixed dictionary transforms rejected

- Tested widening only q10's mixed static-dictionary extra transforms from
  `[1, 4]` to `[1, 4, 16, 28, 47]`. q11 kept `[1, 4]` after a shared-transform
  trial showed an unacceptable q11 native runtime regression.
- Validation evidence:
  - `moon fmt` passed.
  - `moon check --target all` passed.
  - q10 `silesia-64k.bin` improved from 21,415 to 21,396 bytes; sampled
    wasm-gc improved from 510.253 to 495.301 ms/op and sampled native from
    121.332 to 118.007 ms/op.
  - q10 `silesia-1m.bin` improved only from 264,422 to 264,315 bytes versus
    Google 242,485, while legacy JS verifier time moved from 63,742.891 to
    73,885.551 ms.
  - q10 `silesia-128k.bin` improved only from 38,713 to 38,681 bytes versus
    Google 35,624, while sampled native moved from 91.262 to 97.858 ms/op and
    sampled wasm-gc was unstable at 703.386 ms/op versus a 172.893 ms/op
    baseline sample.
- Decision: rejected and reverted. The trial is too small a ratio win for the
  observed medium-input runtime risk. Recorded in `docs/brotli_benchmarks.md`.

- Follow-up microtrial: lowering only q11 high-quality minimum match length
  from 5 to 4 bytes regressed `silesia-1m.bin` q11 from 264,422 to 265,441
  bytes versus Google 239,314, so it was reverted without a target-perf run.
- Follow-up microtrial: relaxing the mixed dictionary replacement margin from
  `output_length >= match_length + 2` to `output_length > match_length`
  regressed `silesia-1m.bin` q10/q11 from 264,422 to 264,447 bytes, so it was
  reverted before target-perf.
- Follow-up microtrial: tightening the same margin to
  `output_length >= match_length + 3` regressed `silesia-1m.bin` q10/q11 to
  264,493 bytes, so the accepted `+2` margin remains the local optimum on this
  slice.
- Follow-up microtrial: reducing q10/q11 high-quality hash-chain checks from
  256 to 128 improved legacy JS verifier time (about 63s to 45s) but regressed
  `silesia-1m.bin` q10/q11 from 264,422 to 265,960 bytes, so it was reverted.
- Follow-up P4 parser trial: increasing q10/q11 high-quality hash-chain checks
  from 256 to 384 improved `silesia-1m.bin` q10/q11 to 263,700 bytes, but q11
  64 KiB native target-perf regressed from 75.297 to 117.263 ms/op. Narrowing
  to q10 only still regressed `silesia-128k.bin` q10 target-perf from
  91.262/172.893 ms/op native/wasm-gc to 143.997/660.508 ms/op while saving
  only 27 bytes on that slice, so it was reverted and recorded in
  `docs/brotli_benchmarks.md`.

## 2026-05-28 — overlapping decode copy fast path accepted

- Added a general overlapping back-reference fast path in
  `BrotliOutputBuilder::copy_from_distance`: after validating/growing output,
  it copies the first distance-sized period once, then doubles the copied range
  with non-overlapping `blit_to` calls.
- Target-perf baseline on Google q11 `silesia-1m.bin` stream:
  - wasm-gc decode: 258.079 ms/op.
  - native decode: 40.152 ms/op.
- Target-perf after the change:
  - wasm-gc decode: 242.629 ms/op, a 6.0% improvement.
  - native decode: 27.770 ms/op, a 30.8% improvement.
- Focused tests passed on native and wasm-gc for
  `BrotliOutputBuilder copy_from_distance keeps overlap semantics`.
- Updated `docs/brotli_benchmarks.md`, `CHANGELOG.md`, and `task_plan.md`.

## 2026-05-29 — chunked encoder state carry fix accepted

- Broader 2 MiB validation found q3/q5 chunked streams that were corrupt even
  though the first and second 1 MiB chunks each encoded correctly in isolation.
- Root cause: exact-costed candidates did not carry the selected candidate's
  recent-distance cache across chunks, and UTF-8 literal-context writers used
  zero as the previous two decoded bytes at every meta-block boundary.
- Implemented candidate wrappers that preserve the terminal recent-distance
  cache, committed only the accepted compressed candidate's cache, and passed
  the previous two decoded bytes into context literal frequency and payload
  selection. Mixed dictionary LZ77 candidates now preserve cache state for
  interleaved LZ77 copies while dictionary copies remain cache-neutral.
- Validation evidence before final full gate:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*UTF-8 context literal trees*'`
    passed 1/1.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 3`
    passed: 629,531 bytes, external Google decode SHA-256 matched input.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 5`
    passed: 555,326 bytes, external Google decode SHA-256 matched input.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 9`
    passed: 542,335 bytes, external Google decode SHA-256 matched input.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 2,5,9 --json`
    measured q2 +8.77%, q5 +3.05%, q9 +6.04% versus Google; q2/q9 keep P3
    open.
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 5 --targets wasm-gc,native --repeats 1 --samples 1 --json`
    measured q5 output 22,336 bytes versus Google 22,271, wasm-gc 511.803
    ms/op, native 96.357 ms/op.
- Updated `docs/brotli_benchmarks.md`, `CHANGELOG.md`, `task_plan.md`, and
  `progress.md`.

## 2026-05-29 — q9 2 MiB chunk ratio improvement accepted

- Rejected a q9-only 64K hash-table trial before committing: increasing the
  q9 high-quality table from 32K to 64K produced the same 271,776-byte
  `silesia-1m.bin` output, so the 2 MiB gap was not a simple hash-collision
  issue.
- Implemented a q9-only 2 MiB standard chunk size and raised the high-quality
  LZ77/mixed-dictionary candidate input bound to 2 MiB. q2..q8 and q10/q11 keep
  their existing 1 MiB standard chunk until separate target-perf evidence says
  otherwise.
- Added a white-box test covering the q9 chunk-size and high-quality input
  bound.
- Validation evidence before final full gate:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*two-mebibyte high-quality chunks*'`
    passed 1/1.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 9`
    passed: 535,421 bytes, external Google decode SHA-256 matched input.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 9 --json`
    measured q9 535,421 bytes versus Google 511,433, reducing 2 MiB overhead
    from +6.04% to +4.69%.
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 1 --samples 1 --json`
    measured q9 output 21,514 bytes versus Google 22,063, wasm-gc 523.417
    ms/op, native 89.076 ms/op.
- P3 remains open: q9 is now inside the measured 2 MiB target, but q2 remains
  +8.77% versus Google on `silesia-2m.bin`, and broader block/histogram
  clustering is still incomplete.

## 2026-05-29 — q2 2 MiB chunk ratio improvement accepted

- Applied the same larger-chunk strategy to q2, but only after confirming that
  q2 also needs a proportional command budget. A 2 MiB q2 chunk with the old
  52,000-command cap fell back to a stored block at 2,097,157 bytes; raising
  q2's natural parser budget to 104,000 commands produced a valid compressed
  stream.
- Validation evidence before final full gate:
  - `moon check --target native` passed.
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 2`
    passed: 652,695 bytes, external Google decode SHA-256 matched input.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 2 --json`
    measured q2 652,695 bytes versus Google 637,343, reducing 2 MiB overhead
    from +8.77% to +2.41%.
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 2 --targets wasm-gc,native --repeats 1 --samples 1 --json`
    measured q2 output 25,245 bytes versus Google 24,364, wasm-gc 480.975
    ms/op, native 75.117 ms/op.
  - `moon fmt`, `moon check --target all`, `moon test --target native --filter '*two-mebibyte chunks*'`,
    `moon test --target all`, `moon info`, and `git diff --check` passed.
- P3's known 2 MiB q2/q9 Silesia ratio gaps are now closed on the measured
  slice; remaining P3 work is broader block/histogram clustering and release
  validation.

## 2026-05-29 — q3..q8 2 MiB chunk promotion accepted

- Promoted the 2 MiB standard chunk strategy to q3..q8 after q3/q5/q8 and
  q4/q6/q7 ratio sweeps all stayed inside the 5% Silesia target window.
- Refined the implementation so command budgets scale only for chunks larger
  than 1 MiB. Small inputs keep the historical q3..q8 command budgets.
- Validation evidence before final full gate:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*two-mebibyte chunks*'` passed 1/1.
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 3,5,8 --json`
    measured q3 617,687 bytes versus Google 623,577 (-0.94%), q5 549,625
    versus 538,906 (+1.99%), and q8 537,621 versus 514,598 (+4.47%).
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 4,6,7 --json`
    measured q4 566,718 bytes versus Google 569,163 (-0.43%), q6 549,625
    versus 527,485 (+4.20%), and q7 537,621 versus 520,020 (+3.38%).
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 8 --targets wasm-gc,native --repeats 1 --samples 1 --json`
    measured q8 output 22,261 bytes versus Google 22,077, wasm-gc 524.749
    ms/op, native 112.349 ms/op.
- The measured 2 MiB q2..q9 Silesia matrix is now inside the 5% target window.
  Remaining P3 work is broader block/histogram clustering plus release
  validation, not the previously open 2 MiB ratio gap.

## 2026-05-29 — P4 heuristic optimization stop point accepted

- Recorded the q10/q11 release-validation checkpoint. The current q10/q11
  streams are valid and externally decodable, but they remain high-quality
  greedy/hash-chain streams rather than the documented Zopfli/shortest-path P4
  backend.
- Current baseline kept for release validation:
  - `silesia-1m.bin` q10: 264,422 bytes versus Google 242,485 (+9.05%).
  - `silesia-1m.bin` q11: 264,422 bytes versus Google 239,314 (+10.49%).
  - `silesia-64k.bin` q10 target-perf: 21,415 bytes versus Google 19,566,
    wasm-gc/native 510.253/121.332 ms.
  - `silesia-64k.bin` q11 target-perf: 21,415 bytes versus Google 19,258,
    wasm-gc/native 547.539/75.297 ms.
- Rationale for stopping heuristic optimization:
  - Wider q10 mixed-dictionary transform scans saved only 107 bytes on 1 MiB
    and 32 bytes on 128 KiB while moving medium-input native target-perf
    backward.
  - A 384-check parser saved 722 bytes on 1 MiB but regressed q10 128 KiB
    target-perf to 143.997/660.508 ms native/wasm-gc and q11 64 KiB native to
    117.263 ms.
  - A bounded shortest-path DP prototype had a large native debug regression
    and lacked recent-distance-cache state, so it remains future P4 work rather
    than commit-ready code.
- Decision: stop local q10/q11 heuristic tuning and proceed to release
  validation. Full P4 remains incomplete unless a release exception is
  accepted; the next implementation step is a real bounded Zopfli/shortest-path
  backend with recent-distance-cache state and explicit memory caps.

## 2026-05-29 — Practical Brotli release validation checkpoint passed

- Ran the MoonBit all-target release gate:
  - `moon fmt`
  - `moon check --target all`
  - `moon test --target all`
  - `moon info`
  - `git diff --check`
- Result: passed. `moon test --target all` reported 458 passed / 0 failed on
  each of `wasm`, `wasm-gc`, `js`, and `native`.
- Ran q2..q9 external decode/ratio validation:
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 2,3,4,5,6,7,8,9 --json`
  - Results: q2 652,695 vs Google 637,343 (+2.41%); q3 617,687 vs 623,577
    (-0.94%); q4 566,718 vs 569,163 (-0.43%); q5 549,625 vs 538,906
    (+1.99%); q6 549,625 vs 527,485 (+4.20%); q7 537,621 vs 520,020
    (+3.38%); q8 537,621 vs 514,598 (+4.47%); q9 535,421 vs 511,433
    (+4.69%). All generated streams passed external Google Brotli decode.
- Ran q10/q11 external decode/ratio validation:
  - `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json`
  - Results: q10 264,422 vs Google 242,485 (+9.05%); q11 264,422 vs Google
    239,314 (+10.49%). Both generated streams passed external Google Brotli
    decode and remain the documented P4 ratio-exception baseline.
- Ran q0/q1 external decode validation:
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 0`
  - `nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 1`
  - Both produced 2,097,157-byte stored streams and matched the input SHA-256
    after external Google Brotli decode.
- Ran representative encode target-perf on `silesia-64k.bin`:
  - q2: 25,245 vs Google 24,364; wasm-gc/native 498.394/114.186 ms.
  - q8: 22,261 vs Google 22,077; wasm-gc/native 525.977/110.541 ms.
  - q9: 21,514 vs Google 22,063; wasm-gc/native 513.957/87.947 ms.
  - q10: 21,415 vs Google 19,566; wasm-gc/native 497.344/117.832 ms.
  - q11: 21,415 vs Google 19,258; wasm-gc/native 518.946/122.539 ms.
- Ran representative decode target-perf:
  - `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-1m.bin.google.q11.br --mode decode --expected target/brotli-bench/silesia-1m.bin --targets wasm-gc,native --repeats 1 --samples 1 --json`
  - Result: decoded 1,048,576 bytes from the 239,314-byte Google q11 stream;
    wasm-gc/native 709.926/142.882 ms versus Google 80.475 ms.
- Ran decoder robustness gates:
  - `nu tools/brotli/conformance/run.nu`: all 22 upstream Google Brotli
    fixtures passed.
  - `nu tools/brotli/fuzz/run.nu --limit 25`: all 25 local fuzz inputs passed
    without native panic or unchecked bounds failure.
- Decision: practical release validation passes for the current checkpoint.
  Stop local heuristic optimization here and move remaining release work to
  broader corpus validation, the long fuzz gate, packaging checks, and an
  explicit P4 ratio exception unless a real bounded Zopfli/shortest-path
  backend is implemented.

## 2026-05-29 — Batched fuzz runner accepted

- Identified the next release-readiness blocker: `tools/brotli/fuzz/run.nu`
  generated one temporary white-box test and invoked `moon test` once per input,
  making broader local fuzz sweeps unnecessarily expensive.
- Baseline timing before the change:
  - `/usr/bin/time -p nu tools/brotli/fuzz/run.nu --limit 25`
  - Result: 25/25 passed, `real 54.73`.
- Updated `run.nu` to write multiple generated fuzz tests per temporary file
  and invoke `moon test` once per batch. The default batch size is 25, with a
  `--batch-size` option for larger local runs.
- Validation after the change:
  - `nu tools/brotli/fuzz/run.nu --limit 1 --batch-size 1` passed.
  - `/usr/bin/time -p nu tools/brotli/fuzz/run.nu --limit 25` passed 25/25 in
    `real 2.19`, a 25.0x wall-clock improvement over the baseline.
  - `/usr/bin/time -p nu tools/brotli/fuzz/run.nu` passed the current 58-input
    corpus in `real 7.00`.
- This does not replace the 24-hour fuzz requirement, but it makes the
  checked-in corpus practical as a normal local release gate.

## 2026-05-29 — Cross-target fuzz runner accepted

- Added a `--target` option to `tools/brotli/fuzz/run.nu`, defaulting to
  `native`, and forwarded it to `moon test --target`.
- This keeps fast local native fuzz sweeps unchanged while letting release
  validation reuse the same generated corpus for `wasm-gc`, `js`, or `all`
  backend coverage.
- Validation:
  - `nu tools/brotli/fuzz/run.nu --limit 2 --batch-size 1 --target native`
    passed 2/2.
  - `nu tools/brotli/fuzz/run.nu --limit 5 --target wasm-gc` passed 5/5.
  - `nu tools/brotli/fuzz/run.nu --limit 3 --target all` passed 3/3.
- This is release-readiness tooling only; Brotli encode/decode implementation
  and codec target-perf baselines are unchanged.

## 2026-05-29 — Encoder roundtrip fuzz harness accepted

- Added `tools/brotli/fuzz/roundtrip.nu`, a deterministic encoder-side fuzz
  harness. It generates byte inputs, runs `brotli_sync` with selected quality
  levels, decodes with `unbrotli_sync`, and checks byte-for-byte equality.
- The default quality set is q0/q1/q2/q9/q11, covering stored streams, the
  standard P3 path, the high-quality P3 path, and the current P4
  release-exception path.
- Validation:
  - `nu tools/brotli/fuzz/roundtrip.nu --count 2 --qualities 0,2 --target native --batch-size 2`
    passed 4/4.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --target native`
    passed 20/20.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 3 --max-len 256 --qualities 2,11 --target wasm-gc`
    passed 6/6.
- This is release-readiness tooling only; it does not change Brotli
  encode/decode behavior or target-perf baselines.

## 2026-05-29 — Fuzz harness stale-lock recovery accepted

- Updated `tools/brotli/fuzz/run.nu` and `tools/brotli/fuzz/roundtrip.nu` so
  `.harness-lock` records the owning Nushell PID.
- If a previous interrupted run leaves a lock with a dead or invalid PID, the
  next harness run removes it and reacquires the lock. If the PID is still
  alive, the harness still rejects concurrent execution.
- Validation:
  - Created `.harness-lock/pid` with dead PID `999999`, then ran
    `nu tools/brotli/fuzz/run.nu --limit 1 --target native`; stale lock was
    recovered and 1/1 passed.
  - Created `.harness-lock/pid` from a live `sleep` process, then ran
    `nu tools/brotli/fuzz/run.nu --limit 1 --target native`; command rejected
    with the owner PID, as expected.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 2 --qualities 2,11 --target native --batch-size 2`
    passed 4/4.
- This removes a practical release-validation footgun seen during interrupted
  local runs without changing Brotli encode/decode behavior.

## 2026-05-29 — Release validation runner accepted

- Added `tools/brotli/release/validate.nu` as a single-command practical
  release gate.
- The default gate runs MoonBit all-target checks, upstream conformance,
  q0/q1 external decode validation, q2..q9 2 MiB ratio/external decode
  validation, q10/q11 1 MiB ratio-exception decode validation, decoder fuzz,
  encoder roundtrip fuzz, and `git diff --check`.
- The runner intentionally skips `target-perf.nu` by default. Target-perf
  remains the required decision harness for codec/performance changes, but the
  current task is release-validation tooling only.
- Validation:
  - `nu --ide-check 0 tools/brotli/release/validate.nu` parsed successfully.
  - `nu tools/brotli/release/validate.nu --skip-moon --skip-ratio --decoder-fuzz-limit 2 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2 --roundtrip-target native`
    passed conformance, decoder fuzz, and encoder roundtrip fuzz.

## 2026-05-29 — Full practical release gate and report

- Ran the full practical release gate:
  - `nu tools/brotli/release/validate.nu`
- Result: passed.
- Gate details:
  - `moon fmt`: pass.
  - `moon check --target all`: pass.
  - `moon test --target all`: pass, 458 passed / 0 failed on each of `wasm`,
    `wasm-gc`, `js`, and `native`.
  - `moon info`: pass.
  - `git diff --check`: pass.
  - Upstream Brotli conformance corpus: pass.
  - q0/q1 2 MiB external decode: pass.
  - q2..q9 2 MiB ratio and external decode: pass.
  - q10..q11 1 MiB ratio-exception decode: pass.
  - Decoder fuzz corpus: pass.
  - Encoder roundtrip fuzz: pass.
- Added `docs/brotli_release_report.md`, summarizing the implemented surface,
  measured size/perf evidence, validation results, accepted exceptions, and the
  remaining final-release boundary.

## 2026-05-29 — Packaging gate and Justfile entries accepted

- Added Justfile entries:
  - `just brotli-release`
  - `just brotli-release-smoke`
  - `just brotli-release-package`
- Extended `tools/brotli/release/validate.nu` with optional package validation.
  The default gate now runs `moon package` and publish dry-run package
  verification.
- The current MoonBit toolchain reports `moon package --dry-run` as
  unimplemented, so package validation uses `moon package`.
- `moon publish --dry-run` validates the packaged zip, extracts it, and runs
  `moon check` on the extracted package. It then reports a duplicate-version
  409 for already-published version `0.8.0`; the release runner accepts that
  exact condition only after packaged-zip verification has passed.
- Validation:
  - `just --list` lists all three Brotli release recipes.
  - `nu --ide-check 0 tools/brotli/release/validate.nu` parsed successfully.
  - `just brotli-release-smoke` passed decoder fuzz corpus and encoder
    roundtrip fuzz.
  - `just brotli-release-package` passed `moon package` and publish dry-run
    package verification.

## 2026-05-29 — Long fuzz soak runner accepted

- Added `tools/brotli/fuzz/soak.nu`, a repeatable soak runner for the long
  Brotli fuzz gate.
- Each iteration runs decoder fuzz and encoder roundtrip fuzz, writes JSONL
  progress to `target/brotli-fuzz-soak/soak.jsonl`, and stops by duration or
  iteration count.
- Added Justfile entries:
  - `just brotli-fuzz-soak`
  - `just brotli-fuzz-soak-smoke`
- Validation:
  - `nu --ide-check 0 tools/brotli/fuzz/soak.nu` parsed successfully.
  - `just --list` lists both soak recipes.
  - `just brotli-fuzz-soak-smoke` passed one decoder fuzz iteration and one
    encoder roundtrip fuzz iteration.
- The runner scripts the documented 24-hour fuzz gate, but the 24-hour soak
  itself is still a final-release execution gate.

## 2026-05-29 — Deterministic fuzz corpus generation accepted

- Updated `tools/brotli/fuzz/gen-corpus.nu` to use a seed-driven linear
  congruential generator instead of process-random Nushell commands.
- Added `--seed` and `--corpus-dir` options so generated fuzz corpora can be
  reproduced exactly and written to throwaway `target/` directories.
- Used Nushell `generate` to thread PRNG state through byte generation and
  mutation generation.
- Validation:
  - `nu --ide-check 0 tools/brotli/fuzz/gen-corpus.nu` parsed successfully.
  - Two corpora generated with `--count 12 --seed 12345` in separate target
    directories had identical sorted SHA-256 manifests.
  - `nu tools/brotli/fuzz/run.nu --corpus-dir target/brotli-fuzz-determinism-a --target native --batch-size 10`
    passed 20/20.

## 2026-05-29 — Generated fuzz corpus release gate accepted

- Extended `tools/brotli/release/validate.nu` with generated decoder corpus
  options:
  - `--generated-fuzz-count`
  - `--generated-fuzz-seed`
  - `--generated-fuzz-dir`
- Added `just brotli-release-generated-fuzz`.
- When a generated count is provided, the release runner calls
  `tools/brotli/fuzz/gen-corpus.nu` and then points the decoder fuzz harness at
  that generated corpus.
- Validation:
  - `nu --ide-check 0 tools/brotli/release/validate.nu` parsed successfully.
  - `just --fmt --check` passed.
  - `just --list` lists `brotli-release-generated-fuzz`.
  - `nu tools/brotli/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-package --generated-fuzz-count 12 --generated-fuzz-seed 12345 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2`
    generated 20 decoder fuzz inputs, passed decoder fuzz, and passed encoder
    roundtrip fuzz.
  - `moon fmt`, `moon check --target all`, `moon test --target all`,
    `moon info`, and `git diff --check` passed.

## 2026-05-29 — Broader release fuzz validation accepted

- Ran the broader generated-corpus release gate:
  - `just brotli-release-generated-fuzz`
  - This generated 1,000 deterministic mutations with seed `1`, copied the 8
    checked-in `.br` seed fixtures into `target/brotli-release-fuzz-corpus`,
    passed decoder fuzz, and passed default encoder roundtrip fuzz.
  - Step timings: generate corpus 210.55 ms, decoder fuzz 90,822.64 ms,
    encoder roundtrip fuzz 14,357.89 ms.
- Ran the bounded multi-iteration soak:
  - `nu tools/brotli/fuzz/soak.nu --duration-min 1440 --max-iterations 3`
  - Passed 3 decoder-fuzz iterations and 3 encoder-roundtrip iterations.
  - `target/brotli-fuzz-soak/soak.jsonl` contained 6 successful rows.
- Confirmed no stale `tools/brotli/.harness-lock`,
  `src/brotli_fuzz_wbtest.mbt`, or `src/brotli_roundtrip_fuzz_wbtest.mbt`
  remained afterward.
- This does not claim that the reserved 24-hour fuzz soak has completed.

## 2026-05-29 — Phase completion audit report accepted

- Added a phase-by-phase audit matrix to `docs/brotli_release_report.md`.
- The matrix separates:
  - completed P1 decoder and local fuzz/conformance coverage,
  - q0/q1 stream validity from the original P2 ratio exception,
  - current q2..q9 measured 2 MiB Silesia ratio readiness from remaining P3
    histogram/block clustering,
  - q10/q11 stream validity from incomplete P4 ratio/Zopfli requirements,
  - local release fuzz/package evidence from the unclaimed 24-hour soak.
- No Brotli encode/decode implementation changed.

## 2026-05-29 — Bounded soak Justfile entry accepted

- Added `just brotli-fuzz-soak-bounded`, a full-corpus finite soak entry that
  runs `nu tools/brotli/fuzz/soak.nu --duration-min 1440 --max-iterations N`.
- Updated `tools/brotli/README.md`, `docs/brotli_benchmarks.md`, and
  `CHANGELOG.md` so the finite soak route is discoverable alongside the 24-hour
  soak and tiny smoke checks.
- This is release-validation tooling only; Brotli encode/decode implementation
  did not change.

## 2026-05-29 — q10/q11 release exception accepted

- Updated `docs/brotli_release_report.md` to accept the q10/q11 P4 ratio
  exception for the current Brotli-capable release candidate.
- Kept P4 marked incomplete: q10/q11 still miss the original 2% ratio target,
  and a real bounded Zopfli/suffix-tree backend remains future work.
- Removed the release-report action item asking whether the q10/q11 exception
  is acceptable; the remaining final-release items are long-duration fuzz soak
  if required and any release-specific publishing checks beyond the local dry
  run.
- This is documentation/decision recording only; Brotli encode/decode
  implementation did not change.

## 2026-05-29 — Release-candidate aggregate recipes accepted

- Added `just brotli-release-candidate` to run the full practical release gate,
  generated deterministic decoder fuzz gate, and bounded full-corpus soak.
- Added `just brotli-release-candidate-smoke` to run the corresponding quick
  gate family so the aggregate wiring can be checked without the full ratio
  matrix.
- Updated `tools/brotli/README.md`, `docs/brotli_benchmarks.md`,
  `docs/brotli_release_report.md`, and `CHANGELOG.md`.
- This is release-validation tooling only; Brotli encode/decode implementation
  did not change.

## 2026-05-29 — Full release-candidate aggregate gate passed

- Ran `just brotli-release-candidate`.
- The full practical gate passed:
  - `moon fmt`, `moon check --target all`, `moon test --target all`,
    `moon info`, and `git diff --check`.
  - Brotli conformance corpus.
  - q0/q1 2 MiB external decode.
  - q2..q9 2 MiB ratio and external decode, elapsed 922,378.64 ms.
  - q10..q11 1 MiB ratio-exception decode, elapsed 242,288.91 ms.
  - decoder fuzz corpus and default encoder roundtrip fuzz.
  - `moon package` and `moon publish --dry-run` package verification.
- The generated corpus gate passed with 1,000 mutations and seed `1`:
  - decoder fuzz elapsed 98,481.68 ms.
  - encoder roundtrip fuzz elapsed 13,945.08 ms.
- The bounded full-corpus soak passed 3 decoder-fuzz iterations and 3
  encoder-roundtrip iterations.
- Confirmed `target/brotli-fuzz-soak/soak.jsonl` contained 6 successful rows
  and no temporary harness lock or generated white-box test file remained.
- This does not claim that the reserved 24-hour fuzz soak has completed.

## 2026-05-29 — Soak append-log tooling in progress

- Added `--append-log` to `tools/brotli/fuzz/soak.nu`.
- Default behavior remains a clean log per run.
- Append mode preserves existing JSONL rows, ignores empty or malformed rows
  while scanning previous progress, and continues iteration numbering from the
  largest recorded `iteration`.
- Updated release-validation docs and planning notes so interrupted or
  segmented long soaks are discoverable without claiming that the 24-hour soak
  has completed.
- Validation:
  - `nu --ide-check 0 tools/brotli/fuzz/soak.nu` parsed successfully.
  - Clean one-iteration soak wrote two iteration-1 rows.
  - Append-mode one-iteration soak preserved the existing log and appended two
    iteration-2 rows.
  - No stale harness lock or generated fuzz white-box test files remained.
  - `moon fmt`, `moon check --target all`, `moon test --target all`, `moon
info`, and `git diff --check` passed.

## 2026-05-29 — Command-block histogram split candidate in progress

- Added a guarded q4+ command-block histogram split candidate:
  - snapshots command-symbol frequencies at 1/4, 1/2, and 3/4 command-stream
    boundaries,
  - estimates command payload savings with one-symbol block payloads treated as
    zero-bit payloads,
  - writes a two-command-block meta-block candidate only when the estimated
    saving clears the overhead guard,
  - keeps exact-cost selection by comparing final `bit_pos` with the existing
    weighted, literal-split, and context candidates.
- Added white-box coverage proving a synthetic command-skew stream selects the
  command split candidate, beats the single weighted command tree, and
  round-trips through `unbrotli_sync`.
- Target-perf/ratio evidence gathered so far:
  - q5 Silesia 64 KiB target-perf: 22,336 bytes vs Google 22,271;
    wasm-gc/native min encode 81.122/52.656 ms.
  - q9 Silesia 64 KiB target-perf: 21,514 bytes vs Google 22,063;
    wasm-gc/native min encode 77.966/45.555 ms.
  - q5/q9 Silesia 128 KiB ratio: 40,328/39,081 bytes vs Google
    40,515/39,695.
- Validation:
  - `moon test --target native --filter 'brotli_sync splits LZ77 command blocks by command histograms'`
    passed.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`
    passed 12/12 cases.
  - First `moon check --target all` attempt after fuzz hit stale `_build`
    state referencing removed `src/brotli_roundtrip_fuzz_wbtest.mbt`; no source
    temp files or harness lock remained, and `moon clean` cleared the build
    graph.
  - `moon fmt`, `moon check --target all`, `moon test --target all`, `moon
info`, `git diff --check`, and `git diff --cached --check` passed after
    cleaning `_build`.
  - `moon fmt`, `moon check --target all`, `moon test --target all`, `moon
info`, `git diff --check`, and `git diff --cached --check` passed.

## 2026-05-29 — Distance-block histogram split candidate in progress

- Added a guarded q4+ distance-block histogram split candidate:
  - counts only explicit distance-symbol events, matching Brotli distance block
    semantics,
  - snapshots distance-symbol frequencies at 1/4, 1/2, and 3/4 distance-event
    boundaries,
  - writes a two-distance-block meta-block candidate only when the estimated
    distance payload saving clears the overhead guard,
  - emits a two-tree distance context map and switches distance block type
    immediately before the split distance symbol.
- Added white-box coverage proving a synthetic distance-skew stream selects the
  distance split candidate, beats the single weighted distance tree, and
  round-trips through `unbrotli_sync`.
- Target-perf/ratio evidence gathered so far:
  - q5 Silesia 64 KiB target-perf: 22,336 bytes vs Google 22,271;
    wasm-gc/native min encode 82.182/53.730 ms.
  - q9 Silesia 64 KiB target-perf: 21,514 bytes vs Google 22,063;
    wasm-gc/native min encode 79.780/47.608 ms.
  - q5/q9 Silesia 128 KiB ratio: 40,328/39,081 bytes vs Google
    40,515/39,695.
- Validation:
  - `moon test --target native --filter 'brotli_sync splits LZ77 distance blocks by distance histograms'`
    passed.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`
    passed 12/12 cases.

## 2026-05-29 — q10/q11 bounded shortest-path seed

- Added a bounded q10/q11 shortest-path command candidate for inputs up to
  32 KiB:
  - uses the existing hash-chain matcher with a capped 32-check parser config,
  - keeps one longest match per position and evaluates only minimum, half, and
    full copy lengths to bound CPU/memory,
  - reconstructs commands with correct recent-distance-cache updates,
  - delegates final selection to the existing exact-cost meta-block writer.
- Added white-box coverage proving the bounded candidate can write a decodable
  final meta-block and that the public q10 encoder round-trips the same input.
- Ratio/validation evidence:
  - q10/q11 Silesia 128 KiB remain 38,713 bytes versus Google
    35,624/35,164 bytes, so the documented P4 ratio exception is unchanged.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - `moon check --target all` passed.
  - `moon test --target all` passed: 461 tests on wasm, wasm-gc, js, and native.
- `target-perf.nu` was not rerun for this increment per latest maintainer
  instruction.

## 2026-05-30 — q10/q11 bounded suffix-tree match source

- Added `src/brotli_encode_suffix_tree.mbt` with a bounded suffix binary-tree
  match source for the q10/q11 small-input shortest-path seed.
- The tree is built incrementally over previous positions in the current
  meta-block and caps both search and insertion work with the current bounded
  match-check budget.
- The shortest-path seed now offers suffix-tree matches into the same
  two-state beam as hash-chain matches, with exact-cost final selection still
  deciding whether the candidate wins.
- Added white-box coverage proving suffix-tree match enumeration sees multiple
  prior suffixes at one position.
- Validation evidence:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*bounded*'` passed 6/6.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - q10/q11 Silesia 128 KiB remain 38,713 bytes versus Google
    35,624/35,164 bytes, so the documented P4 ratio exception is unchanged.
- `target-perf.nu` was not rerun for this increment per latest maintainer
  instruction.

## 2026-05-30 — q10/q11 greedy-seeded cost model

- Added a lightweight cost model for the q10/q11 bounded shortest-path seed.
- The model is initialized from the current greedy LZ77 command stream:
  - inserted literals populate literal frequencies,
  - explicit distance symbols populate distance frequencies,
  - frequencies are converted to Huffman code-length estimates with fallback
    fixed costs when no greedy candidate is available.
- DP literal transitions now use the estimated literal bit cost; copy
  transitions use estimated distance-symbol bits plus distance extra bits while
  still treating distance-code 0 as having no explicit distance-symbol cost.
- Added white-box coverage proving the cost model follows literal histograms.
- Validation evidence:
  - `moon check --target native` passed.
  - `moon test --target native --filter '*bounded shortest-path*'` passed 5/5.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - q10/q11 Silesia 128 KiB remain 38,713 bytes versus Google
    35,624/35,164 bytes, so the documented P4 ratio exception is unchanged.
- `target-perf.nu` was not rerun for this increment per latest maintainer
  instruction.

## 2026-05-30 — q10/q11 bounded two-state beam

- Replaced the bounded shortest-path seed's single state per input position
  with a two-state beam.
- Each retained state carries:
  - estimated cost,
  - recent-distance cache,
  - previous position/slot traceback,
  - copy length and distance choice.
- Literal and copy transitions offer successor states into the target
  position's two-slot beam; only the two lowest-cost states are retained.
- Added white-box coverage for beam insertion, including cache and traceback
  movement when a new best state shifts the previous best into the second slot.
- Validation evidence:
  - `moon test --target native --filter '*bounded shortest-path*'` passed 4/4.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - q10/q11 Silesia 128 KiB remain 38,713 bytes versus Google
    35,624/35,164 bytes, so the documented P4 ratio exception is unchanged.
- `target-perf.nu` was not rerun for this increment per latest maintainer
  instruction.

## 2026-05-29 — q10/q11 bounded recent-distance state

- Extended the q10/q11 bounded shortest-path seed so each DP position carries
  the selected path's recent-distance cache.
- Literal transitions inherit the cache unchanged; copy transitions compute the
  distance code from the path cache and update the successor cache with the
  same helper used during command emission.
- Match enumeration now uses the current path cache, allowing the seed to see
  short-code distance matches created by earlier DP choices.
- Added white-box coverage that a cached distance has a lower bounded
  copy-cost estimate than an uncached explicit distance.
- Validation evidence:
  - `moon test --target native --filter '*bounded shortest-path*'` passed 3/3.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - q10/q11 Silesia 128 KiB remain 38,713 bytes versus Google
    35,624/35,164 bytes, so the documented P4 ratio exception is unchanged.
- `target-perf.nu` was not rerun for this increment per latest maintainer
  instruction.

## 2026-05-29 — q10/q11 bounded multi-match seed

- Extended the q10/q11 bounded shortest-path seed to enumerate multiple
  previous hash-chain matches per input position instead of only the single
  longest match.
- Kept the parser bounded:
  - 32 KiB input cap,
  - capped 32 hash-chain checks inherited from the bounded config,
  - minimum/half/full copy-length transitions per match,
  - exact-cost final meta-block selection before any candidate can win.
- Added white-box coverage for multiple previous-match enumeration at one
  position.
- Validation evidence:
  - `moon test --target native --filter '*bounded shortest-path*'` passed 2/2.
  - `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`
    passed 8/8 cases.
  - q10/q11 Silesia 128 KiB remain 38,713 bytes versus Google
    35,624/35,164 bytes, so the documented P4 ratio exception is unchanged.
  - `moon check --target all` passed.
- `target-perf.nu` was not rerun for this increment per latest maintainer
  instruction.

## 2026-05-31 — Logged failed decode optimization trials

- Recorded negative findings from the current decode performance exploration
  in `.planning/brotli-support/findings.md` under
  `2026-05-31 — Rejected decode performance trials`.
- Failed strategies now explicitly listed:
  single distance-tree/block fast path, distance-1 exponential copy fill,
  final meta-block exact-capacity fitting, dedicated root-8 Huffman decoder,
  and two-byte bit-reader refill.
- Important decision rule captured: future decode candidates should improve
  both `wasm-gc` and native `cc-o0` on q0/q5/q9/q11 before running full
  `just bench`; narrow q0-only or wasm-only improvements should be reverted.
- Current local state at time of logging: the first four failed trials had
  already been reverted; the two-byte bit-reader refill trial was still present
  in the worktree and measured as not worth keeping.
- Follow-up: reverted the two-byte bit-reader refill trial after recording it
  as a rejected strategy, leaving only planning-file updates in the worktree.
- Continued decode exploration with a zero-insert command skip in
  `brotli_decode_compressed_metablock_body`; it passed `moon test src/decode
  --target all` and `moon check --target all`, but target-perf comparison
  against `/tmp/fbr-baseline` was mixed and q11 regressed on both targets.
  Reverted the code and test, and added it to the rejected strategy list.
- Tried inlining `BrotliDecoderState::max_distance` in the copy hot path. It
  passed decode tests/check but introduced an unused-function warning and
  regressed native `cc-o0` in q5/q9/q11 screening, so it was reverted and
  recorded as rejected.
- Tried a single command-block fast path to skip per-command block tracker work
  when only one command block type exists. It passed tests/check, but q11
  native `cc-o0` regressed badly despite q0 native improving, so it was
  reverted and recorded as rejected.
- Tried `BrotliBitReader::take_bits_fast` for command, distance, and
  block-length extra bits. It passed tests/check, but same-time baseline showed
  wasm-gc regressions on q5/q9 and no stable q9 native win, so it was reverted
  and recorded as rejected.
- Tried a manual loop for short non-overlapping `copy_from_distance` copies
  (`distance >= length && length <= 8`). It passed tests/check but regressed
  native `cc-o0` broadly, so it was reverted and recorded as rejected.
- Tried inlining the implicit `distance_code == 0` recent-distance lookup in
  the command loop. It passed tests/check but regressed native `cc-o0` on
  q5/q9/q11, so it was reverted and recorded as rejected.
- Tried private packed decode-only command-info tables to avoid record field
  access in `BrotliCommand::read_into`. It passed tests/check and helped some
  high-quality points, but q0 native `cc-o0` regressed sharply, so it was
  reverted and recorded as rejected.
- Tried empty single-tree context maps to avoid allocating zero-filled context
  maps for `num_trees == 1`. It passed tests/check after updating white-box
  expectations, but same-time baseline showed native `cc-o0` slower on all
  q0/q5/q9/q11 screening points, so it was reverted and recorded as rejected.
- Tried a prechecked back-reference copy helper to avoid repeated validation
  and capacity checks inside the decode loop. It passed tests/check but made
  the original helper unused and screened slower on native `cc-o0`, so it was
  reverted and recorded as rejected.
- Tried removing the repeated literal byte-range checks from the hot literal
  loops. It passed tests/check but screened slower across the q0/q5/q9/q11 set,
  so it was reverted and recorded as rejected.
- Tried an early return from `BrotliOutputBuilder::ensure(0)` to reduce
  zero-insert command overhead. It passed tests/check but same-time baseline
  showed native `cc-o0` slower across q0/q5/q9/q11, so it was reverted and
  recorded as rejected.
- Reinforced the plan-level decode performance guardrail in
  `.planning/brotli-support/task_plan.md`: future agents must treat the full
  `findings.md` rejected-trials section as a negative cache, including the
  later failed literal range-check, `ensure(0)`, checked-copy, context-map, and
  command/distance shortcut trials.
- Tried lowering `brotli_initial_output_capacity` from a 5.0x compressed-size
  hint to 4.5x. After updating the white-box test, `moon test src/decode
  --target all` and `moon check --target all` passed, but q0/q5/q9/q11
  targeted decode screening against `/tmp/fbr-baseline` was mixed to worse:
  q5 was slower on both wasm-gc and native `cc-o0`, and native regressed on
  q0/q9/q11. Reverted the source/test change and recorded it as rejected.
- Tried splitting normal-copy `remaining` bookkeeping so non-dictionary
  back-references subtract `command.copy_length` directly instead of measuring
  `output.len - output_before_copy`. It passed `moon test src/decode --target
  all` and `moon check --target all`, but q0 same-time screening regressed
  from baseline 42.389/67.837 ms to 46.289/69.586 ms on wasm-gc/native
  `cc-o0`. Reverted and recorded it as rejected without spending time on q5+.
- Tried removing the redundant `bits_avail < n` condition from the 24-bit
  refill branch in `BrotliBitReader::refill_to`. It passed `moon test
  src/decode --target all` and `moon check --target all`, but q0 same-time
  screening was not better: wasm-gc tied baseline and native `cc-o0` regressed
  from 67.572 ms to 69.396 ms. Reverted and recorded it as rejected.
- Tried combining command insert/copy extra-bit reads when their total width is
  <=24, with a fallback to the old two-read path for wider commands. It passed
  `moon test src/decode --target all` and `moon check --target all`; q0
  wasm-gc improved only marginally, but native `cc-o0` regressed to 69.194 ms
  versus the recent baseline around 67.572 ms. Reverted and recorded it as
  rejected.
- Tried skipping `take_bits(0)` in block-length and distance extra-bit readers.
  It passed `moon test src/decode --target all` and `moon check --target all`,
  but q0 same-time screening regressed versus `/tmp/fbr-baseline`: wasm-gc
  42.635 vs 42.219 ms and native `cc-o0` 69.682 vs 67.800 ms. Reverted and
  recorded it as rejected.
- Tried replacing the hottest single literal tree + single literal block
  `for _ in 0..<command.insert_length` loop with a `while pos < end` loop. It
  passed `moon test src/decode --target all` and `moon check --target all`, but
  q0 native `cc-o0` regressed to 69.838 ms, so it was reverted and recorded as
  rejected.
- Tried inlining `BrotliCommand::read_into` into the compressed-body loop as
  local command variables. It passed `moon test src/decode --target all` and
  `moon check --target all` (with temporary unused-command warnings before
  cleanup). Same-time screening showed q0 improved slightly, but q5 regressed
  on wasm-gc/native and q9/q11 native regressed, so it was reverted and
  recorded as rejected.

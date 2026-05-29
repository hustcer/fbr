# Brotli Release Readiness Report

Date: 2026-05-29

This report summarizes the current Brotli implementation state after the P3
2 MiB promotion, the P4 heuristic stop point, and the practical release
validation gate.

## Executive Summary

The current codebase implements Brotli decode and encode entry points for
quality levels q0 through q11, plus stream-compatible wrappers. The decoder is
RFC-valid on the checked upstream conformance corpus. The encoder emits
externally decodable Brotli streams for every quality level.

The q2 through q9 encoder path is inside the measured P3 5% size window on the
current 2 MiB Silesia validation slice. The q10 and q11 paths are valid and
externally decodable, but they are not the planned P4 Zopfli/shortest-path
backend and remain outside the documented 2% P4 ratio target. Release
readiness therefore depends on accepting the recorded P4 ratio exception.

The latest full practical release gate passed:

```nu
nu tools/brotli/release/validate.nu
```

This gate intentionally does not run `tools/brotli/bench/target-perf.nu`.
Target-perf remains the required decision harness for codec or performance
changes; the latest release-validation work is tooling and documentation only.

## Implemented Surface

- `unbrotli_sync` and `UnbrotliStream`.
- `brotli_sync` and `BrotliStream`.
- Brotli options and error codes integrated with the existing fzip API model.
- Static dictionary decode support, including transform handling.
- Encoder support for q0 through q11.
- Upstream conformance harness.
- External Google Brotli decode verification harness.
- Ratio benchmark harness.
- wasm-gc/native target performance harness.
- Decoder fuzz harness with batching and target selection.
- Encoder roundtrip fuzz harness.
- Shared Brotli harness locking with stale-lock recovery.
- Practical release validation runner.
- Justfile entry points for full, smoke, and package-only Brotli release
  validation.

## Current Encoder Behavior

| Quality range | Current behavior                                                | Release status                                   |
| ------------- | --------------------------------------------------------------- | ------------------------------------------------ |
| q0..q1        | Standard uncompressed meta-block output                         | Valid and externally decodable                   |
| q2..q3        | Fast standard compressed candidate path                         | Inside measured P3 2 MiB size window             |
| q4..q8        | Intermediate hash-chain search path                             | Inside measured P3 2 MiB size window             |
| q9            | High-quality parser plus gated mixed static-dictionary search   | Inside measured P3 2 MiB size window             |
| q10..q11      | Deeper high-quality parser plus mixed static-dictionary matches | Valid, but accepted only with P4 ratio exception |

## Size Evidence

Latest recorded external Google Brotli decode and size comparison:

| Corpus     | Quality | MoonBit bytes | Google bytes | Size overhead | Google decode |
| ---------- | ------- | ------------- | ------------ | ------------- | ------------- |
| silesia-2m | q0      | 2,097,157     | n/a          | n/a           | pass          |
| silesia-2m | q1      | 2,097,157     | n/a          | n/a           | pass          |
| silesia-2m | q2      | 652,695       | 637,343      | +2.41%        | pass          |
| silesia-2m | q3      | 617,687       | 623,577      | -0.94%        | pass          |
| silesia-2m | q4      | 566,718       | 569,163      | -0.43%        | pass          |
| silesia-2m | q5      | 549,625       | 538,906      | +1.99%        | pass          |
| silesia-2m | q6      | 549,625       | 527,485      | +4.20%        | pass          |
| silesia-2m | q7      | 537,621       | 520,020      | +3.38%        | pass          |
| silesia-2m | q8      | 537,621       | 514,598      | +4.47%        | pass          |
| silesia-2m | q9      | 535,421       | 511,433      | +4.69%        | pass          |
| silesia-1m | q10     | 264,422       | 242,485      | +9.05%        | pass          |
| silesia-1m | q11     | 264,422       | 239,314      | +10.49%       | pass          |

Interpretation:

- q2..q9 satisfy the measured P3 5% size window on the current 2 MiB slice.
- q10/q11 do not satisfy the documented P4 2% size target.
- q10/q11 are acceptable for release only if the project accepts the explicit
  P4 ratio exception recorded in `docs/brotli_benchmarks.md`.

## Performance Evidence

Representative target-perf data was recorded before the latest tooling-only
changes. The latest report commit does not change Brotli encode/decode code.

64 KiB encode target-perf:

| Quality | Target  | MoonBit bytes | Google bytes | Size overhead | MoonBit ms | Google ms | Slowdown |
| ------- | ------- | ------------- | ------------ | ------------- | ---------- | --------- | -------- |
| q2      | wasm-gc | 25,245        | 24,364       | +3.62%        | 498.394    | 39.787    | 12.53x   |
| q2      | native  | 25,245        | 24,364       | +3.62%        | 114.186    | 39.787    | 2.87x    |
| q8      | wasm-gc | 22,261        | 22,077       | +0.83%        | 525.977    | 42.859    | 12.27x   |
| q8      | native  | 22,261        | 22,077       | +0.83%        | 110.541    | 42.859    | 2.58x    |
| q9      | wasm-gc | 21,514        | 22,063       | -2.49%        | 513.957    | 44.435    | 11.57x   |
| q9      | native  | 21,514        | 22,063       | -2.49%        | 87.947     | 44.435    | 1.98x    |
| q10     | wasm-gc | 21,415        | 19,566       | +9.45%        | 497.344    | 62.929    | 7.90x    |
| q10     | native  | 21,415        | 19,566       | +9.45%        | 117.832    | 62.929    | 1.87x    |
| q11     | wasm-gc | 21,415        | 19,258       | +11.20%       | 518.946    | 107.217   | 4.84x    |
| q11     | native  | 21,415        | 19,258       | +11.20%       | 122.539    | 107.217   | 1.14x    |

Representative decode target-perf:

| Input stream                | Target  | Encoded bytes | Decoded bytes | MoonBit ms | Google ms | Slowdown |
| --------------------------- | ------- | ------------- | ------------- | ---------- | --------- | -------- |
| silesia-1m Google q11 `.br` | wasm-gc | 239,314       | 1,048,576     | 709.926    | 80.475    | 8.82x    |
| silesia-1m Google q11 `.br` | native  | 239,314       | 1,048,576     | 142.882    | 80.475    | 1.78x    |

## Full Practical Release Gate

Command:

```nu
nu tools/brotli/release/validate.nu
```

Result:

| Step                                   | Result | Elapsed ms |
| -------------------------------------- | ------ | ---------- |
| `moon fmt`                             | pass   | 17.70      |
| `moon check --target all`              | pass   | 47.45      |
| `moon test --target all`               | pass   | 17,574.30  |
| `moon info`                            | pass   | 13.63      |
| `git diff --check`                     | pass   | 9.77       |
| Brotli conformance corpus              | pass   | 68,422.60  |
| q0 2 MiB external decode               | pass   | 908.63     |
| q1 2 MiB external decode               | pass   | 878.67     |
| q2..q9 2 MiB ratio and external decode | pass   | 934,269.21 |
| q10..q11 1 MiB ratio-exception decode  | pass   | 242,602.16 |
| decoder fuzz corpus                    | pass   | 6,515.04   |
| encoder roundtrip fuzz                 | pass   | 13,210.20  |

Additional package-only release gate:

```nu
just brotli-release-package
```

| Step | Result | Elapsed ms |
| ---- | ------ | ---------- |
| `moon package` | pass | 131.48 |
| `moon publish --dry-run` package verification | pass | 2,436.83 |

The `moon test --target all` step reported 458 passed and 0 failed on each of
`wasm`, `wasm-gc`, `js`, and `native`.

## Fuzz and Conformance Coverage

Current local release coverage:

- 22 upstream Google Brotli conformance fixtures.
- 58 checked-in decoder fuzz corpus inputs.
- Deterministic seed-based corpus generation via
  `tools/brotli/fuzz/gen-corpus.nu --seed ... --corpus-dir ...`.
- Encoder roundtrip fuzz across the default q0, q1, q2, q9, and q11 quality
  set.
- Configurable fuzz targets: `native`, `wasm-gc`, `js`, or `all`.
- Stale lock recovery for interrupted fuzz runs.
- Scripted long fuzz soak entry points:
  - `nu tools/brotli/fuzz/soak.nu`
  - `just brotli-fuzz-soak`
  - `just brotli-fuzz-soak-smoke`

Reserved final-release work:

- The original 24-hour fuzz gate is now scriptable through
  `tools/brotli/fuzz/soak.nu`, but this report does not claim that a 24-hour
  soak has completed.
- A broader corpus can now be run through `tools/brotli/release/validate.nu`
  and the fuzz scripts before the final release artifact is cut.

## Accepted Exceptions

P2 q0/q1:

- q0/q1 are RFC-valid stored streams and externally decodable.
- They do not attempt to match Google Brotli's compression ratio.

P4 q10/q11:

- q10/q11 are RFC-valid and externally decodable.
- They remain outside the documented P4 2% ratio target.
- Local heuristic tuning was stopped because measured trials either produced
  small size gains or regressed wasm-gc/native encode performance too much.
- Completing P4 as originally specified still requires a real bounded
  shortest-path/Zopfli backend with recent-distance-cache state and explicit
  memory caps.

## Release Recommendation

The implementation is ready for release validation as a Brotli-capable fzip
build with the documented P4 ratio exception. It should not be described as a
complete P4 Zopfli encoder.

Before cutting a final public release artifact, the remaining non-heuristic
release tasks are:

- Decide whether the q10/q11 P4 ratio exception is acceptable for the release.
- Run any required long-duration fuzz soak.
- Run any release-specific packaging/publishing checks beyond local
  `moon package` and `moon publish --dry-run` package verification.

## Key References

- Plan: `.planning/brotli-support/task_plan.md`
- Benchmark log: `docs/brotli_benchmarks.md`
- Implementation plan: `docs/brotli.md`
- Tooling README: `tools/brotli/README.md`
- Practical release gate: `tools/brotli/release/validate.nu`

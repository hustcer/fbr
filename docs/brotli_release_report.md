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

Additional reproducible release-validation coverage has also passed:

- `just brotli-release-generated-fuzz`: generated 1,000 deterministic
  mutations plus the 8 checked-in `.br` fixtures, passed decoder fuzz, then
  passed the default encoder roundtrip fuzz quality set.
- `nu tools/brotli/fuzz/soak.nu --duration-min 1440 --max-iterations 3`:
  passed 3 decoder-fuzz iterations and 3 encoder-roundtrip iterations, with 6
  successful JSONL status rows written to `target/brotli-fuzz-soak/soak.jsonl`.

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
- Stable ignored generated-test placeholders for conformance, fuzz, and
  target-perf harnesses, avoiding stale incremental MoonBit inputs.
- Practical release validation runner.
- Justfile entry points for full, smoke, and package-only Brotli release
  validation.
- Aggregate Justfile release-candidate entry points for the accepted full and
  smoke release-validation gate sets.
- Direct Justfile entry points for conformance, decoder fuzz, encoder
  roundtrip fuzz, ratio, and wasm-gc/native target-perf checks.

## Current Encoder Behavior

| Quality range | Current behavior                                                | Release status                                   |
| ------------- | --------------------------------------------------------------- | ------------------------------------------------ |
| q0..q1        | Standard uncompressed meta-block output                         | Valid and externally decodable                   |
| q2..q3        | Fast standard compressed candidate path                         | Inside measured P3 2 MiB size window             |
| q4..q8        | Intermediate hash-chain search path                             | Inside measured P3 2 MiB size window             |
| q9            | High-quality parser plus gated mixed static-dictionary search   | Inside measured P3 2 MiB size window             |
| q10..q11      | Deeper high-quality parser plus mixed static-dictionary matches | Valid, but accepted only with P4 ratio exception |

## Phase Completion Audit

This matrix audits the current code against the `docs/brotli.md` phase
acceptance criteria. It separates stream-valid release readiness from the
larger P3/P4 algorithm-completion targets.

| Area                      | Requirement                                                                            | Current evidence                                                                                                                                                 | Status                                                                |
| ------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| P1 decoder                | `unbrotli_sync`, `UnbrotliStream`, static dictionary, transforms, conformance fixtures | Public APIs exist; 22 upstream Google Brotli conformance fixtures pass in the release gate                                                                       | Complete                                                              |
| P1 correctness            | Decoder must return output or `FzipError`, not panic, on fuzz inputs                   | Checked-in decoder corpus and generated deterministic corpus pass through `tools/brotli/fuzz/run.nu`                                                             | Release-ready locally                                                 |
| P2 q0/q1 validity         | q0/q1 outputs decode through MoonBit and Google Brotli                                 | `nu tools/brotli/release/validate.nu` verifies q0 and q1 on the 2 MiB Silesia slice with external Google decode                                                  | Complete for stream validity                                          |
| P2 q0/q1 ratio            | Original plan asked for q0 >= 1.6:1 and q1 >= 2.0:1 on `silesia.tar`                   | Current q0/q1 are stored meta-block streams and intentionally do not target Google q0/q1 ratios                                                                  | Accepted exception, not original-ratio complete                       |
| P3 q2..q9 validity        | All q2..q9 outputs decode through MoonBit and Google Brotli                            | q2..q9 are covered by roundtrip tests and 2 MiB external Google decode in the release gate                                                                       | Complete for current validation corpus                                |
| P3 q2..q9 ratio           | Within 5% of Google Brotli per quality on Silesia                                      | Current 2 MiB Silesia window: q2 +2.41%, q3 -0.94%, q4 -0.43%, q5 +1.99%, q6 +4.20%, q7 +3.38%, q8 +4.47%, q9 +4.69%                                             | Complete for measured 2 MiB Silesia slice                             |
| P3 broader algorithm      | Richer literal, command, and distance block/histogram clustering                       | Plan still lists richer histogram/block clustering as remaining work beyond the current single split/context candidates                                          | Incomplete                                                            |
| P3 performance            | q5 encode-time budget and regression tracking                                          | Target-perf evidence is recorded in `docs/brotli_benchmarks.md`; latest codec-changing commits carry wasm-gc/native evidence                                     | Evidence recorded, not rerun for tooling-only updates                 |
| P4 q10/q11 validity       | q10/q11 outputs decode through MoonBit and Google Brotli                               | q10/q11 pass external Google decode in the release gate                                                                                                          | Complete for stream validity                                          |
| P4 q10/q11 ratio          | Within 2% of Google Brotli on Silesia                                                  | Current 1 MiB Silesia window: q10 +9.05%, q11 +10.49%                                                                                                            | Incomplete; exception accepted for the current Brotli-capable release |
| P4 Zopfli backend         | Suffix-tree plus bounded shortest-path/Zopfli parser with recent-distance-cache state  | Local shortest-path probes were rejected as too slow or incomplete; no production Zopfli backend is enabled                                                      | Incomplete                                                            |
| P4 performance and memory | Encode within 5x and memory within 2x of C reference                                   | No accepted production Zopfli backend exists, so these P4 acceptance checks cannot be claimed                                                                    | Incomplete                                                            |
| Fuzz gate                 | Scripted fuzz harness and long-fuzz route                                              | Checked-in corpus, generated deterministic corpus, encoder roundtrip fuzz, and bounded 3-iteration soak passed                                                   | Release-ready locally; 24-hour soak not claimed                       |
| Packaging                 | Package validation before release                                                      | `moon package` and `moon publish --dry-run` package verification pass; duplicate published-version response is accepted only after package verification succeeds | Complete locally                                                      |
| Hand-off checklist        | `moon fmt`, `moon check`, `moon test`, `moon info`, changelog, benchmarks, fixtures    | Latest release-validation commits passed these local gates and updated changelog/benchmark/report docs                                                           | Complete for current checkpoint                                       |

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
- q10/q11 are accepted for this Brotli-capable release candidate under the
  explicit P4 ratio exception recorded in `docs/brotli_benchmarks.md`.

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

| Step                                          | Result | Elapsed ms |
| --------------------------------------------- | ------ | ---------- |
| `moon package`                                | pass   | 131.48     |
| `moon publish --dry-run` package verification | pass   | 2,436.83   |

The `moon test --target all` step reported 458 passed and 0 failed on each of
`wasm`, `wasm-gc`, `js`, and `native`.

## Aggregate Release Candidate Gate

Command:

```nu
just brotli-release-candidate
```

Result:

| Gate                                | Result | Key timing                                                                       |
| ----------------------------------- | ------ | -------------------------------------------------------------------------------- |
| full practical release gate         | pass   | q2..q9 ratio/decode 922,378.64 ms; q10..q11 ratio-exception decode 242,288.91 ms |
| generated deterministic corpus gate | pass   | 1,000 mutations; decoder fuzz 98,481.68 ms; encoder roundtrip 13,945.08 ms       |
| bounded full-corpus soak            | pass   | 3 decoder-fuzz iterations and 3 encoder-roundtrip iterations                     |

The full practical gate also passed `moon package` and `moon publish
--dry-run` package verification. The bounded soak wrote 6 successful JSONL
rows to `target/brotli-fuzz-soak/soak.jsonl`, and no temporary harness lock or
generated white-box test file remained afterward.

## Fuzz and Conformance Coverage

Current local release coverage:

- 22 upstream Google Brotli conformance fixtures.
- 58 checked-in decoder fuzz corpus inputs.
- Deterministic seed-based corpus generation via
  `tools/brotli/fuzz/gen-corpus.nu --seed ... --corpus-dir ...`.
- Generated deterministic corpus release gate via
  `tools/brotli/release/validate.nu --generated-fuzz-count ...`.
- The generated-corpus release gate has passed with 1,000 deterministic
  mutations and seed `1`.
- Encoder roundtrip fuzz across the default q0, q1, q2, q9, and q11 quality
  set.
- Configurable fuzz targets: `native`, `wasm-gc`, `js`, or `all`.
- Stale lock recovery for interrupted fuzz runs.
- Scripted long fuzz soak entry points:
  - `nu tools/brotli/fuzz/soak.nu`
  - `nu tools/brotli/fuzz/soak.nu --append-log`
  - `just brotli-fuzz-soak`
  - `just brotli-fuzz-soak-smoke`
- A bounded soak execution has passed 3 full decoder-fuzz iterations and 3
  default encoder-roundtrip iterations.
- Generated-test batch runners now use Nushell `generate` pipelines for the
  sequential temp-file workflow, reducing mutable accumulator code in the
  conformance, decoder fuzz, and encoder roundtrip harnesses.

Reserved final-release work:

- The original 24-hour fuzz gate is now scriptable through
  `tools/brotli/fuzz/soak.nu`; append mode preserves JSONL evidence and
  iteration numbering for interrupted or segmented runs, but this report does
  not claim that a 24-hour soak has completed.
- Any project-required 24-hour soak should still be run before the final public
  release artifact is cut.

## Accepted Exceptions

P2 q0/q1:

- q0/q1 are RFC-valid stored streams and externally decodable.
- They do not attempt to match Google Brotli's compression ratio.

P4 q10/q11:

- q10/q11 are RFC-valid and externally decodable.
- They remain outside the documented P4 2% ratio target.
- Local heuristic tuning was stopped because measured trials either produced
  small size gains or regressed wasm-gc/native encode performance too much.
- The q10/q11 ratio exception is accepted for the current Brotli-capable
  release candidate because q10/q11 stream validity is proven and completing
  the original P4 target requires a larger Zopfli/suffix-tree backend.
- Completing P4 as originally specified still requires a real bounded
  shortest-path/Zopfli backend with recent-distance-cache state and explicit
  memory caps.

## Release Recommendation

The implementation is ready as a Brotli-capable fzip release candidate with
the accepted P4 ratio exception. It should not be described as a complete P4
Zopfli encoder.

Before cutting a final public release artifact, the remaining non-heuristic
release tasks are:

- Run any required long-duration fuzz soak.
- Run any release-specific packaging/publishing checks beyond local
  `moon package` and `moon publish --dry-run` package verification.

## Key References

- Plan: `.planning/brotli-support/task_plan.md`
- Benchmark log: `docs/brotli_benchmarks.md`
- Implementation plan: `docs/brotli.md`
- Tooling README: `tools/brotli/README.md`
- Practical release gate: `tools/brotli/release/validate.nu`

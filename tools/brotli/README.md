# Brotli Tools

These helpers support the Brotli implementation work. Run them from the
repository root.

## Fixture Generator

```nu
nu tools/brotli/gen-fixtures.nu
```

Regenerates `src/brotli_fixture_wbtest.mbt` and copies the selected upstream
fixtures into `src/tests/brotli_fixtures/`.

## Conformance Harness

```nu
nu tools/brotli/conformance/run.nu
nu tools/brotli/conformance/run.nu --fixture monkey
just brotli-conformance
just brotli-conformance-fixture monkey
```

Runs the upstream corpus at `/Users/hustcer/iWork/refs/brotli/tests/testdata`
through `unbrotli_sync`. The harness writes a temporary
`src/brotli_conformance_wbtest.mbt`, runs one native MoonBit test per fixture,
then restores an ignored placeholder file so later incremental `moon` commands
do not retain a stale generated-test input path.

## Decoder Fuzz Harness

```nu
nu tools/brotli/fuzz/gen-corpus.nu --count 1000
nu tools/brotli/fuzz/gen-corpus.nu --count 1000 --seed 12345
nu tools/brotli/fuzz/gen-corpus.nu --count 100 --corpus-dir target/brotli-fuzz-corpus
nu tools/brotli/fuzz/run.nu
nu tools/brotli/fuzz/run.nu --limit 25
nu tools/brotli/fuzz/run.nu --batch-size 50
nu tools/brotli/fuzz/run.nu --limit 25 --target all
just brotli-fuzz native 25 25
nu tools/brotli/fuzz/roundtrip.nu
nu tools/brotli/fuzz/roundtrip.nu --count 25 --qualities 2,9,11 --target wasm-gc
just brotli-roundtrip native 12 2048 0,1,2,9,11 25
nu tools/brotli/fuzz/soak.nu
nu tools/brotli/fuzz/soak.nu --append-log
just brotli-fuzz-soak
just brotli-fuzz-soak-smoke
```

`gen-corpus.nu` seeds `tools/brotli/fuzz/corpus/` from the embedded fixture set
and adds deterministic seed-based truncation, append, and delete-middle
mutations. Use `--seed` to reproduce a corpus exactly and `--corpus-dir` to
write a throwaway release-validation corpus under `target/`. `run.nu`
generates temporary `src/brotli_fuzz_wbtest.mbt` batches and asserts
`unbrotli_sync` either returns bytes or raises `FzipError`; native panics or
unchecked bounds failures fail the run. The default batch size is 25 inputs to
keep full-corpus local runs fast while still reporting the batch that failed.
The default MoonBit test target is `native`; pass `--target wasm-gc`, `--target
js`, or `--target all` when validating backend-specific release behavior. The
temporary generated test is replaced with an ignored placeholder after the run
so later incremental `moon` commands can rebuild without requiring `moon clean`.

`roundtrip.nu` is the encoder fuzz companion. It generates deterministic byte
inputs, encodes them with selected Brotli quality levels, decodes the result
through `unbrotli_sync`, and asserts byte-for-byte equality. The defaults cover
q0, q1, q2, q9, and q11 on the native backend; use `--qualities` and `--target`
to broaden release validation.

Conformance and fuzz runners use `tools/brotli/.harness-lock` to avoid
overlapping temporary white-box test files. The lock records the owning process
ID and automatically recovers if a previous interrupted run left a stale lock
behind.

`soak.nu` repeats the decoder fuzz corpus and encoder roundtrip fuzz loops for
a duration or iteration limit and writes JSONL progress to
`target/brotli-fuzz-soak/soak.jsonl`. The default duration is 24 hours for the
documented long fuzz gate. Each normal run starts with a clean log; pass
`--append-log` when resuming an interrupted or segmented long soak so existing
JSONL rows are preserved and iteration numbering continues from the largest
recorded iteration. Use `just brotli-fuzz-soak-bounded` for a full-corpus
finite soak and `just brotli-fuzz-soak-smoke` for a one-iteration small-corpus
local smoke check.

## Release Validation

```nu
nu tools/brotli/release/validate.nu
nu tools/brotli/release/validate.nu --skip-ratio --decoder-fuzz-limit 25
nu tools/brotli/release/validate.nu --skip-ratio --generated-fuzz-count 1000 --generated-fuzz-seed 12345
just brotli-release
just brotli-release-smoke
just brotli-release-generated-fuzz
just brotli-release-package
just brotli-release-candidate
just brotli-release-candidate-smoke
just brotli-fuzz-soak-bounded
```

Runs the practical Brotli release gate from one command: MoonBit all-target
checks, upstream conformance, q0/q1 external decode validation, q2..q9 ratio
and external decode validation, q10/q11 ratio-exception decode validation,
decoder fuzz, encoder roundtrip fuzz, packaging, publish dry-run package
verification, and `git diff --check`. The q2..q9 ratio step now fails if any
measured quality exceeds the default 5% overhead gate; use
`--p3-max-overhead` only when intentionally changing that release policy. The
default gate does not run `tools/brotli/bench/target-perf.nu`; run target-perf
separately when changing Brotli codec behavior or making a performance
decision.

The Justfile recipes are thin entry points:

- `just brotli-release`: full practical gate.
- `just brotli-release-smoke`: quick decoder and encoder fuzz smoke.
- `just brotli-release-generated-fuzz`: generated deterministic decoder fuzz
  corpus plus encoder roundtrip fuzz.
- `just brotli-conformance` and `just brotli-conformance-fixture`: upstream
  conformance corpus shortcuts.
- `just brotli-fuzz` and `just brotli-roundtrip`: direct decoder and encoder
  fuzz shortcuts with target/count/batch parameters.
- `just brotli-ratio`: ratio and external-decode shortcut for a selected input
  and quality set.
- `just brotli-target-perf-decode` and `just brotli-target-perf-encode`:
  explicit wasm-gc/native performance harness shortcuts.
- `just brotli-release-package`: packaging and publish dry-run package
  verification only.
- `just brotli-release-candidate`: full practical gate, generated deterministic
  corpus gate, and bounded full-corpus soak.
- `just brotli-release-candidate-smoke`: quick aggregate smoke for the same
  release-candidate gate families.
- `just brotli-fuzz-soak-bounded`: finite full-corpus decoder fuzz and encoder
  roundtrip soak iterations.

## Silesia q=11 Verification

```nu
nu tools/brotli/silesia/verify.nu
nu tools/brotli/silesia/verify.nu target/brotli-silesia/webster-mozilla64k.bin.br target/brotli-silesia/webster-mozilla64k.bin
```

Verifies a Google Brotli q=11 stream against an expected output file through
the JavaScript backend. The default paths are the local 100 MiB Silesia
acceptance artifact under `target/brotli-silesia/`. The script rebuilds the
MoonBit JS test bundle, calls `unbrotli_sync`, and prints decoded and expected
SHA-256 values. This is a legacy file-IO verifier, not the default performance
benchmark.

## Encoder Verification

```nu
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 0
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 1
```

Encodes a file with MoonBit `brotli_sync`, decodes the generated stream with
the external `brotli` CLI, and compares the decoded bytes with the original
input. This legacy JS verifier keeps encoder acceptance independent from
fzip's own decoder; use `bench/target-perf.nu` for wasm-gc/native encode
timings.

## Ratio Benchmark

```nu
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2,9,11
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2 --json
just brotli-ratio target/brotli-bench/silesia-2m.bin 2,3,4,5,6,7,8,9
```

Compares MoonBit `brotli_sync` output size against the Google `brotli` CLI for
the selected qualities. The script also validates MoonBit output through the
external decoder by delegating to the legacy JS file verifier
`tools/brotli/encode/verify.nu`. Treat the timing columns as historical
JS-verifier telemetry only; the JSON output includes backend metadata and points
performance consumers to `tools/brotli/bench/target-perf.nu`.

## Target Performance Benchmark

```nu
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-1m.bin.google.q11.br \
  --mode decode \
  --expected target/brotli-bench/silesia-1m.bin \
  --targets wasm-gc,native \
  --json

nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-128k.bin \
  --mode encode \
  --quality 2 \
  --targets wasm-gc,native \
  --json

just brotli-target-perf-decode \
  target/brotli-bench/silesia-1m.bin.google.q11.br \
  target/brotli-bench/silesia-1m.bin

just brotli-target-perf-encode target/brotli-bench/silesia-128k.bin 2
```

Measures Brotli decode or encode time through a temporary ignored MoonBit main
package on the selected targets. The default targets are `wasm-gc,native`,
because those are the performance targets that matter for Brotli work; the
older JavaScript harness remains useful for file-based verification but is not
a good default performance signal. Encode mode reports both target encode time
and MoonBit-vs-Google output size from the same target run, so ratio work
cannot hide unacceptable runtime regressions.

`target-perf.nu` shares the Brotli harness lock with conformance and fuzz
runners, including owner-PID stale-lock recovery. Its generated main package
uses an ignored stable placeholder path so incremental `moon` commands do not
retain missing generated inputs after a benchmark run. Native release
benchmark rows include `native_cc`; the current harness uses `cc-o0` for native
release because default clang `-O2` does not finish reliably on the generated C
for the Brotli package.

## Chunk Match Diagnostics

```nu
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16 --json
```

Reports per-chunk unique literal counts, sampled 4-byte match density, and
bounded greedy match estimates for selected minimum match lengths. This is a
planning aid for P3 block splitting and match admission work; it does not
encode or verify Brotli streams.

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
```

Runs the upstream corpus at `/Users/hustcer/iWork/refs/brotli/tests/testdata`
through `unbrotli_sync`. The harness writes a temporary
`src/brotli_conformance_wbtest.mbt`, runs one native MoonBit test per fixture,
then removes the temporary file.

## Decoder Fuzz Harness

```nu
nu tools/brotli/fuzz/gen-corpus.nu --count 1000
nu tools/brotli/fuzz/run.nu
nu tools/brotli/fuzz/run.nu --limit 25
nu tools/brotli/fuzz/run.nu --batch-size 50
nu tools/brotli/fuzz/run.nu --limit 25 --target all
nu tools/brotli/fuzz/roundtrip.nu
nu tools/brotli/fuzz/roundtrip.nu --count 25 --qualities 2,9,11 --target wasm-gc
```

`gen-corpus.nu` seeds `tools/brotli/fuzz/corpus/` from the embedded fixture set
and adds random truncation, append, and delete-middle mutations. `run.nu`
generates temporary `src/brotli_fuzz_wbtest.mbt` batches and asserts
`unbrotli_sync` either returns bytes or raises `FzipError`; native panics or
unchecked bounds failures fail the run. The default batch size is 25 inputs to
keep full-corpus local runs fast while still reporting the batch that failed.
The default MoonBit test target is `native`; pass `--target wasm-gc`, `--target
js`, or `--target all` when validating backend-specific release behavior. The
temporary file is removed after the run.

`roundtrip.nu` is the encoder fuzz companion. It generates deterministic byte
inputs, encodes them with selected Brotli quality levels, decodes the result
through `unbrotli_sync`, and asserts byte-for-byte equality. The defaults cover
q0, q1, q2, q9, and q11 on the native backend; use `--qualities` and `--target`
to broaden release validation.

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
```

Measures Brotli decode or encode time through temporary MoonBit white-box tests
on the selected targets. The default targets are `wasm-gc,native`, because
those are the performance targets that matter for Brotli work; the older
JavaScript harness remains useful for file-based verification but is not a good
default performance signal. Encode mode reports both target encode time and
MoonBit-vs-Google output size from the same target run, so ratio work cannot
hide unacceptable runtime regressions.

## Chunk Match Diagnostics

```nu
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16 --json
```

Reports per-chunk unique literal counts, sampled 4-byte match density, and
bounded greedy match estimates for selected minimum match lengths. This is a
planning aid for P3 block splitting and match admission work; it does not
encode or verify Brotli streams.

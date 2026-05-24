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
```

`gen-corpus.nu` seeds `tools/brotli/fuzz/corpus/` from the embedded fixture set
and adds random truncation, append, and delete-middle mutations. `run.nu`
generates a temporary `src/brotli_fuzz_wbtest.mbt` per input and asserts
`unbrotli_sync` either returns bytes or raises `FzipError`; native panics or
unchecked bounds failures fail the run. The temporary file is removed after the
run.

## Silesia q=11 Verification

```nu
nu tools/brotli/silesia/verify.nu
nu tools/brotli/silesia/verify.nu target/brotli-silesia/webster-mozilla64k.bin.br target/brotli-silesia/webster-mozilla64k.bin
```

Verifies a Google Brotli q=11 stream against an expected output file through
the JavaScript backend. The default paths are the local 100 MiB Silesia
acceptance artifact under `target/brotli-silesia/`. The script rebuilds the
MoonBit JS test bundle, calls `unbrotli_sync`, and prints decoded and expected
SHA-256 values.

## Encoder Verification

```nu
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 0
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 1
```

Encodes a file with MoonBit `brotli_sync`, decodes the generated stream with
the external `brotli` CLI, and compares the decoded bytes with the original
input. This keeps encoder acceptance independent from fzip's own decoder.

## Ratio Benchmark

```nu
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2,9,11
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2 --json
```

Compares MoonBit `brotli_sync` output size against the Google `brotli` CLI for
the selected qualities. The script also validates MoonBit output through the
external decoder by delegating to `tools/brotli/encode/verify.nu`. The default
table output includes size and ratio columns; `--json` emits full records with
MoonBit and Google encode timings in milliseconds for regression tracking.

## Chunk Match Diagnostics

```nu
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16 --json
```

Reports per-chunk unique literal counts, sampled 4-byte match density, and
bounded greedy match estimates for selected minimum match lengths. This is a
planning aid for P3 block splitting and match admission work; it does not
encode or verify Brotli streams.

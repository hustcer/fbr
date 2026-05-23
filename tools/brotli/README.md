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

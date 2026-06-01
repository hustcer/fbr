# Tools

Developer tools for validation, benchmarks, fuzzing, fixture generation, and
release checks. Run commands from the repository root unless a script says
otherwise.

Most day-to-day tasks should use the `just` recipes first. The Nushell scripts
under `tools/` are the implementation details behind those recipes and are
useful when you need narrower control over inputs, targets, or output format.

## Quick Commands

```bash
just lint
just test
just release-smoke
just release
just size
just bench
```

Use the lighter commands while iterating and the broader gates before handoff:

- `just lint`: `moon check --target all`.
- `just test`: `moon test --target all`.
- `just release-smoke`: fast practical Brotli release smoke.
- `just release`: full validation gate.
- `just size` or `just size js,wasm-gc`: package split artifact checks.
- `just bench`: regenerate the Brotli release benchmark report.

## Tool Layout

- `bench/`: ratio, size/time reports, target performance, and same-time
  baseline comparisons.
- `conformance/`: upstream Google Brotli corpus validation.
- `encode/`: external decode verification for MoonBit encoder output.
- `fuzz/`: decoder corpus fuzzing, encoder roundtrip fuzzing, and soak runs.
- `release/`: practical release validation gate.
- `silesia/`: large Silesia verification helpers.
- `size/`: package split artifact checks.

## Brotli Tools

Common entry points:

```bash
just conformance
just roundtrip
just fuzz
just ratio
just target-perf-encode target/brotli-bench/silesia-128k.bin 2
just target-perf-decode target/brotli-bench/silesia-1m.bin.google.q11.br target/brotli-bench/silesia-1m.bin
just decode-compare
just encode-compare
```

Use the comparison commands when evaluating performance-sensitive changes:

- `just decode-compare`: same-time decode speed comparison against a baseline
  git ref.
- `just encode-compare`: same-time encode speed and encoded-size comparison
  against a baseline git ref.

Both comparison scripts also support `--json` directly when machine-readable
output is useful:

```bash
nu tools/bench/decode-compare.nu --json --quiet
nu tools/bench/encode-compare.nu --json --quiet
```

For direct script usage:

- `nu tools/gen-fixtures.nu`: regenerate checked-in Brotli fixtures.
- `nu tools/conformance/run.nu`: run upstream conformance fixtures.
- `nu tools/fuzz/run.nu`: run the decoder fuzz corpus.
- `nu tools/fuzz/roundtrip.nu`: run deterministic encoder roundtrip fuzz.
- `nu tools/fuzz/soak.nu`: repeat fuzz and roundtrip loops for a duration or
  iteration limit.
- `nu tools/release/validate.nu`: run the practical release validation gate.
- `nu tools/encode/verify.nu <input> --quality <q>`: encode with MoonBit and
  validate with the external `brotli` CLI.
- `nu tools/bench/target-perf.nu <input> --mode encode|decode`: measure
  wasm-gc/native codec performance.
- `nu tools/bench/ratio.nu <input> --qualities 2,9,11`: compare MoonBit output
  size against Google Brotli.

## Coverage Helper

```bash
nu tools/analyze-coverage.nu
```

Runs `moon coverage analyze` and prints a compact coverage summary. This helper
is intended for local inspection rather than release gating.

## Generated Files And Scratch Data

Many tools create temporary MoonBit test/main packages, benchmark outputs, or
fuzz corpora. Generated build and benchmark data belongs under `target/` or
other ignored scratch paths. Do not commit generated corpora, `_build/`,
`target/`, or local benchmark scratch output unless a documented release
artifact explicitly says it should be checked in.

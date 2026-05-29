# Brotli Package Split Proposal

This document describes how to move fzip's Brotli implementation into a new
MoonBit module named `hustcer/fbr` while preserving the current Brotli runtime
behavior, encoded output, and benchmark profile.

The package name is intentionally short and tied to the standard `.br` file
suffix. Public APIs should still use the Brotli name (`brotli_sync`,
`unbrotli_sync`, `BrotliOptions`, `UnbrotliOptions`) because users search for
the algorithm name, not the package abbreviation.

## Goals

- Publish Brotli as `hustcer/fbr`, separate from `hustcer/fzip`.
- Let decode-only users depend on Brotli decoding without pulling encoder code.
- Let encode-only users depend on Brotli encoding without pulling decoder code.
- Share common Brotli code and tables where that reduces source duplication.
- Preserve the current `brotli_sync` and `unbrotli_sync` behavior.
- Preserve encoded bytes for every quality level and input covered by the
  current verification corpus.
- Preserve decode and encode performance within normal benchmark noise.
- Keep the migration from the current flat `src/brotli*.mbt` layout mechanical
  and reviewable.

## Non-Goals

- Do not change the Brotli bitstream format, encoder heuristics, hash-chain
  limits, dictionary decisions, or chunk sizing as part of the package split.
- Do not add true incremental streaming. The existing stream wrappers buffer
  chunks until `final_=true`; keep that behavior unless changed in a separate
  feature.
- Do not add Brotli auto-detection to fzip's `decompress_sync`; Brotli has no
  reliable magic header.
- Do not keep Brotli error codes inside fzip's `FzipErrorCode` after the split.
  `hustcer/fbr` should own its own error type.
- Do not make `hustcer/fzip` depend on `hustcer/fbr` by default. That would
  defeat the size-boundary goal.

## Recommended Module Layout

Use one MoonBit module, `hustcer/fbr`, with multiple packages. MoonBit package
boundaries are directory boundaries, not file-name prefixes, so decode-only and
encode-only dependency control requires separate package directories.

```text
fbr/
  moon.mod.json
  README.md
  CHANGELOG.md
  LICENSE
  src/
    moon.pkg                  # Optional full API facade.
    fbr.mbt
    common/
      moon.pkg
      constants.mbt
      error.mbt
      bits.mbt
      huffman.mbt
      tables.mbt
      command.mbt
      distance.mbt
      context.mbt
      block.mbt
      compressed_header.mbt
      stream_handler.mbt
    dictionary/
      moon.pkg
      dictionary.mbt
      dictionary_data.mbt
      transform.mbt
      transform_data.mbt
    decode/
      moon.pkg
      types.mbt
      bit_reader.mbt
      tree_group.mbt
      decode.mbt
      stream.mbt
    encode/
      moon.pkg
      types.mbt
      bit_writer.mbt
      encode.mbt
      encode_hash.mbt
      encode_dict.mbt
      stream.mbt
    tests/
      moon.pkg
      fixtures/
  docs/
    brotli.md
    brotli_benchmarks.md
  tools/
    brotli/
```

The root package `hustcer/fbr` is optional but useful. It should be a small
facade that imports both `decode` and `encode` and exposes the familiar full
surface:

- `brotli_sync`
- `unbrotli_sync`
- `BrotliOptions`
- `UnbrotliOptions`
- `BrotliStream`
- `UnbrotliStream`

Users who want the smallest dependency graph should import a subpackage:

- Decode only: `hustcer/fbr/decode`
- Encode only: `hustcer/fbr/encode`
- Full convenience API: `hustcer/fbr`

This gives a clear tradeoff: the root package is convenient, while subpackages
are size-oriented.

## Dependency Graph

The intended package dependency graph is:

```text
          hustcer/fbr
          /        \
         v          v
 hustcer/fbr/decode  hustcer/fbr/encode
         \          /
          v        v
       hustcer/fbr/dictionary
                |
                v
        hustcer/fbr/common
```

`common` must not import `decode` or `encode`. `dictionary` must not import
`decode` or `encode`. That keeps shared code reusable without creating a hidden
dependency from one high-level package to the other.

Decode-only users should compile this graph:

```text
hustcer/fbr/decode
  -> hustcer/fbr/dictionary
  -> hustcer/fbr/common
```

Encode-only users should compile this graph:

```text
hustcer/fbr/encode
  -> hustcer/fbr/dictionary
  -> hustcer/fbr/common
```

Full API users compile both:

```text
hustcer/fbr
  -> hustcer/fbr/decode
  -> hustcer/fbr/encode
```

## What Goes In `common`

`common` should contain Brotli concepts used by both encoder and decoder, as
long as they do not pull in large one-sided implementation details:

- Numeric constants such as window limits, alphabet sizes, max table sizes, and
  distance constants.
- Brotli-specific error type and error codes.
- Small static tables used by both sides.
- Huffman code representations and canonical-code helpers that are genuinely
  shared.
- Insert/copy command prefix tables when both encoder and decoder use the same
  definitions.
- Distance-code helpers shared by both paths.
- Small byte/bit helpers that do not force either a decoder reader or encoder
  writer dependency.
- The stream callback wrapper if both encode and decode stream wrappers should
  keep the same callback shape.

`common` should not contain:

- Decoder state-machine code.
- Encoder match finding, hash-chain parsing, or cost model code.
- Large data that only one side uses.
- Public full-API facade functions.

The practical rule is: if adding an item to `common` makes decode-only users
compile encoder-only logic, it does not belong in `common`.

## What Goes In `dictionary`

The Brotli static dictionary and transform tables are a special case. They are
large, but they are not purely decode-owned:

- The decoder needs them to handle valid Brotli streams that reference the
  static dictionary.
- The encoder needs them if current mixed static-dictionary encoding is kept.
- Removing dictionary access from either side would change behavior or encoded
  size, which is explicitly out of scope.

Therefore the dictionary should be a separate shared package:

- `dictionary_data.mbt`: embedded static dictionary bytes.
- `dictionary.mbt`: word-length buckets, offsets, and lookup helpers.
- `transform_data.mbt`: transform definitions and suffix/prefix data.
- `transform.mbt`: transform application helpers.

This package is intentionally pulled by both `decode` and `encode`. That keeps
the implementation single-sourced while preserving the larger win: decode-only
users avoid encoder code, and encode-only users avoid decoder code.

If future encoder modes allow a no-static-dictionary build, that should be a
separate package such as `hustcer/fbr/encode_lite`, not a conditional behavior
inside the main `encode` package.

## What Goes In `decode`

`decode` owns the public decompression API:

- `unbrotli_sync(data, opts?)`
- `UnbrotliOptions`
- `UnbrotliStream`

It should also own decoder-only internals:

- `BrotliBitReader`
- Meta-block header parsing.
- Decoder state and output builder.
- Huffman tree-group reading.
- Context map decoding.
- Literal, command, and distance decode loops.
- Padding validation.
- Decoder-focused tests and conformance fixtures.

The decoder should import only `common` and `dictionary`. It must not import
`encode`, even for tests. Shared tests that need roundtrips should live outside
the decode package or be written as black-box integration tests that import both
high-level packages.

## What Goes In `encode`

`encode` owns the public compression API:

- `brotli_sync(data, opts?)`
- `BrotliOptions`
- `BrotliStream`

It should also own encoder-only internals:

- Bit writer.
- Quality selection.
- Chunk sizing.
- Hash configuration and hash-chain match finding.
- Command candidate construction.
- Literal-only, LZ77, mixed dictionary, and high-quality paths.
- Huffman payload emission.
- Encoder-focused ratio and external decode validation tests.

The encoder should import only `common` and `dictionary`. It must not import
`decode`. Encoder validation should continue to use the external Google Brotli
CLI where appropriate, because importing the local decoder into encoder tests
can hide bitstream compatibility bugs.

## Error Model

Move Brotli-specific errors out of `FzipErrorCode` and into `hustcer/fbr/common`.
The new module should expose:

```moonbit
pub(all) enum FbrErrorCode {
  UnexpectedEOF
  InvalidWindowBits
  InvalidMetablock
  InvalidHuffman
  InvalidContextMap
  InvalidDistance
  InvalidTransform
  DictionaryNotSupported
  LargeWindowNotSupported
  Reserved
  InvalidPadding
  InvalidInput
}

pub(all) suberror FbrError {
  FbrError(code~ : FbrErrorCode, message~ : String)
}
```

Do not reuse `FzipError` in `hustcer/fbr`. Depending on fzip just for a shared
error type would reintroduce coupling and make `hustcer/fbr` less reusable.

For migration readability, keep messages close to the current ones. If fzip
later offers optional wrappers around `hustcer/fbr`, those wrappers can convert
`FbrError` into `FzipError` at the boundary.

## Public API Shape

Decode package:

```moonbit
let plain = @fbr_decode.unbrotli_sync(compressed)
let plain = @fbr_decode.unbrotli_sync(
  compressed,
  opts={
    out: None,
    max_output_size: 100 * 1024 * 1024,
    max_input_size: 1024 * 1024 * 1024,
  },
)
```

Encode package:

```moonbit
let compressed = @fbr_encode.brotli_sync(data)
let compressed = @fbr_encode.brotli_sync(
  data,
  opts={
    quality: 9,
    window_bits: 22,
    max_input_size: 1024 * 1024 * 1024,
  },
)
```

Full facade package:

```moonbit
let compressed = @fbr.brotli_sync(data)
let plain = @fbr.unbrotli_sync(compressed)
```

The facade package should not contain independent logic. It should delegate to
`decode` and `encode` so there is exactly one implementation of each public
operation.

## fzip Integration After The Split

`hustcer/fzip` should remove Brotli from its default package surface before the
next public release that includes Brotli. The fzip README can point users to
`hustcer/fbr`:

```text
Brotli support lives in hustcer/fbr. Use hustcer/fbr/decode for decode-only,
hustcer/fbr/encode for encode-only, or hustcer/fbr for the full API.
```

Do not make `hustcer/fzip` import `hustcer/fbr` by default.

An optional compatibility package can be added later if there is user demand:

```text
hustcer/fzip/brotli
  -> hustcer/fbr
```

That compatibility package should be explicitly imported by users who want the
old fzip-style grouping. It should not affect the default `hustcer/fzip`
artifact.

## Migration Plan

### Phase 1: Create `hustcer/fbr` Skeleton

- Create a new repository or module with `moon.mod.json` name `hustcer/fbr`.
- Add `src/common`, `src/dictionary`, `src/decode`, and `src/encode` packages.
- Add a root facade package only after subpackages compile independently.
- Copy docs and tools that are Brotli-specific from fzip.

Validation:

```bash
moon check --target all
moon info
```

### Phase 2: Move Common And Dictionary Code

- Move Brotli constants and small shared tables into `common`.
- Move static dictionary and transform code into `dictionary`.
- Keep function bodies unchanged except for package-qualified references.
- Preserve table byte order and static data exactly.

Validation:

```bash
moon check --target all
moon test src/common
moon test src/dictionary
```

### Phase 3: Move Decoder

- Move decoder-only files into `decode`.
- Replace `FzipError` usage with `FbrError`.
- Keep public names `unbrotli_sync`, `UnbrotliOptions`, and `UnbrotliStream`.
- Port decoder fixtures and conformance harness.
- Verify decode-only package does not import `encode`.

Validation:

```bash
moon check --target all
moon test src/decode
nu tools/brotli/conformance/run.nu
nu tools/brotli/silesia/verify.nu
```

### Phase 4: Move Encoder

- Move encoder-only files into `encode`.
- Replace `FzipError` usage with `FbrError`.
- Keep public names `brotli_sync`, `BrotliOptions`, and `BrotliStream`.
- Port encoder verification and ratio tools.
- Verify encode-only package does not import `decode`.

Validation:

```bash
moon check --target all
moon test src/encode
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 9
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 11
```

### Phase 5: Add Facade And Update fzip

- Add root package wrappers in `hustcer/fbr`.
- Remove Brotli public API from `hustcer/fzip` before release, or leave it only
  on an unreleased branch until fzip is rebased on the split.
- Update fzip README and changelog to point to `hustcer/fbr`.

Validation:

```bash
moon check --target all
moon test --target all
moon info
```

## Performance And Encoded-Size Invariants

The package split must be behavior-preserving. Treat any changed encoded byte
sequence as a regression unless the change is explicitly approved in a separate
encoder PR.

Required invariants:

- `brotli_sync(input, opts)` returns byte-for-byte identical output before and
  after the split for the same target backend.
- `unbrotli_sync(input, opts)` returns byte-for-byte identical output before and
  after the split.
- Public defaults are unchanged.
- Quality-to-strategy mapping is unchanged.
- Chunk-size selection is unchanged.
- Hash-chain limits and candidate ordering are unchanged.
- Static dictionary match decisions are unchanged.
- Error categories may be renamed from `FzipErrorCode::Brotli...` to
  `FbrErrorCode::...`, but success behavior must not change.

Benchmark acceptance:

- Decode performance should stay within 3% of the current baseline on native
  and wasm-gc for the Silesia q=11 verification input.
- Encode performance should stay within 3% of the current baseline on native
  and wasm-gc for the existing q2, q9, q10, and q11 benchmark set.
- Encoded size must be exactly unchanged for all recorded ratio harness inputs.

Use the existing `docs/brotli_benchmarks.md` corpus as the baseline source.
Record split validation in a new section of that document rather than rewriting
historical measurements.

Suggested validation commands:

```bash
moon check --target all
moon test --target all
nu tools/brotli/conformance/run.nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9,10,11 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-1m.bin.google.q11.br \
  --mode decode \
  --expected target/brotli-bench/silesia-1m.bin \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 3 \
  --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 9 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 3 \
  --json
```

## Artifact-Size Validation

The reason to split packages is not just source organization; it is to let
callers avoid unused encoder or decoder code. Add an artifact-size check before
publishing `hustcer/fbr`.

Create three tiny downstream fixtures:

```text
target/fbr-size/decode-only/
target/fbr-size/encode-only/
target/fbr-size/full/
```

Each fixture should import one package and perform one operation:

- Decode-only imports `hustcer/fbr/decode` and calls `unbrotli_sync`.
- Encode-only imports `hustcer/fbr/encode` and calls `brotli_sync`.
- Full imports `hustcer/fbr` and calls both.

For each target backend, compare output artifact size:

```bash
moon build --target wasm-gc
moon build --target js
moon build --target native
```

Acceptance criteria:

- Decode-only artifact does not include encoder-only functions such as hash
  configuration, match finding, command candidate construction, or bit writer.
- Encode-only artifact does not include decoder-only functions such as bit
  reader, meta-block parser, output builder, or decode state machine.
- Both decode-only and encode-only may include `dictionary` if required to keep
  behavior and encoded size unchanged.
- Full facade artifact may include both sides.

If the compiler still includes both sides for a subpackage fixture, the split
has failed its main purpose and should not be published until the package graph
is corrected.

## Naming And Documentation

Use `hustcer/fbr` as the module name, but keep Brotli in all user-facing
descriptions:

```json
{
  "name": "hustcer/fbr",
  "description": "Pure MoonBit Brotli (.br) encoder and decoder with split encode/decode packages",
  "keywords": ["brotli", "br", "compression", "decompression", "encoder", "decoder"]
}
```

README positioning:

```text
fbr is a pure MoonBit Brotli implementation for `.br` streams.

- Import hustcer/fbr/decode for decode-only applications.
- Import hustcer/fbr/encode for encode-only applications.
- Import hustcer/fbr for the full convenience API.
```

Do not rename the algorithm-level APIs to `fbr_sync` or `unfbr_sync`. Those
names obscure the standard format and make interop documentation harder to
search.

## Release Recommendation

Publish `hustcer/fbr` first as the canonical Brotli package. Keep the fzip
release that removes unreleased Brotli APIs separate from the fbr release:

1. Publish `hustcer/fbr` with decode, encode, dictionary, common, and facade
   packages.
2. Validate downstream decode-only and encode-only artifact size.
3. Update `hustcer/fzip` docs to reference `hustcer/fbr`.
4. Release fzip without Brotli in the default package.
5. Add an optional fzip compatibility package only if users ask for it.

This path gives users the smallest default fzip package, keeps Brotli available
under the requested `hustcer/fbr` name, and preserves the current implementation
quality without forcing encoder and decoder users to pay for code they do not
call.

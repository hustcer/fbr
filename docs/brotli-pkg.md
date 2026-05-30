# Brotli Package Split Proposal

This document describes how to move fzip's Brotli implementation into a new
MoonBit module named `hustcer/fbr` while preserving the current Brotli runtime
behavior, encoded output, and benchmark profile.

The package name is intentionally short and tied to the standard `.br` file
suffix. Public APIs should still use the Brotli name (`brotli_sync`,
`unbrotli_sync`, `BrotliOptions`, `UnbrotliOptions`) because users search for
the algorithm name, not the package abbreviation.

> **Read this first:** the section
> [MoonBit Compilation Model — What Actually Controls Size](#moonbit-compilation-model--what-actually-controls-size)
> changes the rationale for the split. Artifact size is controlled by MoonBit's
> function-level dead-code elimination (DCE), _not_ by the package boundary.
> The package and module split buys compile-time isolation, a DCE-independent
> guarantee, and download-footprint separation — which is still worth doing, but
> for different reasons than "otherwise decode-only users get the encoder."

## Goals

- Publish Brotli as `hustcer/fbr`, separate from `hustcer/fzip`.
- Let decode-only users depend on Brotli decoding without pulling encoder code
  into their final artifact or their compile graph.
- Let encode-only users depend on Brotli encoding without pulling decoder code.
- Single-source the code that both sides genuinely share, to reduce source size
  and maintenance — _without_ making either side pay for the other in the final
  artifact. Function-level DCE makes this possible (see below); the job of the
  layout is to not defeat it.
- Preserve the current `brotli_sync` and `unbrotli_sync` behavior.
- Preserve encoded bytes for every quality level and input covered by the
  current verification corpus (byte-for-byte).
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

## MoonBit Compilation Model — What Actually Controls Size

This split is about three different "sizes", and MoonBit handles each at a
different level. Getting this right is the difference between a plan that works
and one that ships encoder code to decode-only users anyway.

### The three levels

- **Module** (`moon.mod` / legacy `moon.mod.json`): the dependency, publishing,
  and versioning unit (one mooncake). What a downstream user _downloads_.
- **Package** (one `moon.pkg` per directory): the **compilation unit**. All
  `.mbt` files in a package are concatenated and share one private scope. What a
  downstream user _compiles_.
- **File** (`.mbt`): purely organizational. File names create no boundary; a
  method/function/type can be moved freely between files **in the same package**
  without changing semantics. This matters for the dictionary fix below.

### Function-level dead-code elimination is real (measured)

MoonBit's `release` builds perform **function-level** DCE: an unused `pub fn`,
together with the data it transitively references, is removed from the final
artifact — _even when it lives in the same package as code that is used_.

Verified on `moon 0.1.20260522` with a minimal two-function package (one
function references a 256 KB constant, the other does not; `main` calls exactly
one of them):

| `main` calls      | js artifact | wasm-gc artifact | 256 KB constant in artifact |
| ----------------- | ----------- | ---------------- | --------------------------- |
| only the light fn | **441 B**   | **1.7 KB**       | stripped                    |
| only the heavy fn | **262 KB**  | **526 KB**       | present                     |

Both functions were in the **same package**. The delta is exactly the unused
constant. Conclusion: reachability from the program entry point, not the package
boundary, is what removes code from the artifact.

### What this means for the split

| Concern                                                                        | Controlled by        | Does splitting help?                                                                      |
| ------------------------------------------------------------------------------ | -------------------- | ----------------------------------------------------------------------------------------- |
| Final **artifact** size (decode-only user has no encoder bytes)                | **DCE** (any layout) | Not strictly required — DCE already does it, _if no reachability edge ties the two sides_ |
| **Compile-time** isolation (decode-only user never type-checks encoder source) | **package** boundary | Yes — a package is the compilation unit                                                   |
| **DCE-independent guarantee** (cannot accidentally retain the other side)      | **package** boundary | Yes — a hard structural boundary, not an optimizer best-effort                            |
| **Download** footprint (decode-only user does not fetch encoder source)        | **module** boundary  | Yes — only a separate module removes it from the dependency                               |

So the split is still worth doing, but justify it as **compile-time isolation +
a structural guarantee + download separation**, not as "otherwise the encoder
ends up in a decode-only binary." The latter is handled by DCE — _provided the
layout does not defeat DCE_, which is the subject of the next section.

The corollary is liberating for the reuse goal: **you may freely single-source
shared code in `common` to reduce source size, and DCE still ensures each
consumer only pays for the symbols it actually reaches** — as long as the
shared package stays DCE-safe.

## DCE Hazards and `common` Constraints

Function-level DCE works by reachability. A handful of constructs make the
compiler unable to prove a symbol is unreachable, which silently drags the other
side into a "decode-only" or "encode-only" artifact. The layout must avoid them.

DCE hazards to forbid in shared packages:

- **Cross-side dynamic dispatch.** A trait defined in `common` with one impl on
  a decode type and one on an encode type, consumed through a `common` function
  that dispatches dynamically, makes both impls reachable from either side. Keep
  trait impls on the side that owns the type; do not route encode/decode through
  a shared dynamic dispatch point.
- **Global registries / init tables that list both sides.** Any top-level value
  that references both `brotli_sync` and `unbrotli_sync` (or their internals)
  pins both. Do not build a "format registry" in `common`.
- **The facade as a forced edge.** The root `@fbr` package re-exports both sides.
  Calling only `unbrotli_sync` through the facade should still let DCE strip the
  encoder, but the guarantee is only structural if the user imports the leaf
  package. Document the facade as convenience, and tell size-sensitive users to
  import `@fbr/decode` or `@fbr/encode` directly.

`common` must therefore contain **only**:

- Pure constants and static tables.
- Pure functions (no dependency on a decode reader/output type or an encode
  writer/state type).
- The shared error type.

`common` must **not** contain: decoder state, encoder state, any method on a
decode-only or encode-only type, cross-side trait dispatch, or any global that
forces both sides reachable. See the dictionary fix below for a concrete case
where the original plan violated this.

## Recommended Module Layout

Use one MoonBit module, `hustcer/fbr`, with multiple packages. MoonBit package
boundaries are directory boundaries, not file-name prefixes, so decode-only and
encode-only compile-time control requires separate package directories. Prefer
the current `moon.mod` format for a freshly created module (the toolchain still
reads legacy `moon.mod.json`, but new modules should use `moon.mod`).

```text
fbr/
  moon.mod                    # Module metadata (source = "src").
  README.mbt.md               # Symlinked to README.md; mbt check examples.
  CHANGELOG.md
  LICENSE
  src/
    moon.pkg                  # Root facade package.
    fbr.mbt
    common/
      moon.pkg
      constants.mbt
      error.mbt
      huffman.mbt             # ONLY canonical-code helpers with no reader/writer dep.
      tables.mbt
      command.mbt            # ONLY shared prefix tables (see hot-path note).
      distance.mbt           # ONLY shared distance constants/pure helpers.
      context.mbt
      dictionary_data.mbt     # Raw embedded dictionary bytes.
      dictionary.mbt          # PURE word lookups only — no BrotliOutputBuilder.
      transform_data.mbt      # Transform definition tables.
      transform.mbt           # PURE transform metadata helpers only.
      compressed_header.mbt
    decode/
      moon.pkg
      types.mbt               # BrotliOutputBuilder lives here.
      bit_reader.mbt
      tree_group.mbt
      decode.mbt
      dictionary_copy.mbt     # BrotliOutputBuilder dictionary/transform methods.
      stream.mbt
    encode/
      moon.pkg
      types.mbt
      bit_writer.mbt
      encode.mbt
      encode_hash.mbt
      encode_dict.mbt         # Encoder hash-based dictionary matching.
      stream.mbt
    tests/
      moon.pkg                # Imports BOTH decode and encode for roundtrips.
      fixtures/
  docs/
    brotli.md
    brotli_benchmarks.md
  tools/
    brotli/
```

> **Static dictionary placement:** the current implementation keeps dictionary
> and transform data in `common`. Both leaf packages use that data today, so an
> extra `dictionary` package is not required. If a future no-static-dictionary
> encoder is introduced, this can be split again as a separate package.

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
are size-oriented and give a structural (not DCE-dependent) guarantee.

## Dependency Graph

The intended package dependency graph is:

```text
          hustcer/fbr
          /        \
         v          v
 hustcer/fbr/decode  hustcer/fbr/encode
         \          /
          v        v
        hustcer/fbr/common
```

`common` must not import `decode` or `encode`. That keeps shared code reusable
without creating a hidden dependency from one high-level package to the other,
and it prevents the circular dependency described in the dictionary fix below
(`common` referencing a decode-only type while `decode` imports `common`).

Decode-only users should compile this graph:

```text
hustcer/fbr/decode
  -> hustcer/fbr/common
```

Encode-only users should compile this graph:

```text
hustcer/fbr/encode
  -> hustcer/fbr/common
```

Full API users compile both:

```text
hustcer/fbr
  -> hustcer/fbr/decode
  -> hustcer/fbr/encode
```

## What Goes In `common`

`common` should contain Brotli concepts used by both encoder and decoder, **only
when they are pure** (no dependency on a decode reader/output type or an encode
writer/state type) — see [DCE Hazards](#dce-hazards-and-common-constraints):

- Numeric constants such as window limits, alphabet sizes, max table sizes, and
  distance constants.
- Brotli-specific error type and error codes.
- Small static tables used by both sides.
- Huffman code representations and canonical-code helpers that are genuinely
  shared **and** do not take a reader or writer argument.
- Insert/copy command prefix tables when both encoder and decoder use the same
  definitions.
- Distance-code helpers shared by both paths.
- Small byte helpers that do not force either a decoder reader or encoder writer
  dependency.

`common` should not contain:

- Decoder state-machine code, or any method on a decode-only type.
- Encoder match finding, hash-chain parsing, or cost model code, or any method on
  an encode-only type.
- Large data that only one side uses.
- Cross-side trait dispatch or any global that pins both sides (DCE hazard).
- Public full-API facade functions.
- **Any function on a decode/encode inner loop** (hot-path rule below).

The practical rule is: if adding an item to `common` makes decode-only users
compile encoder-only logic, or makes the compiler unable to strip one side, or
sits on an inner loop, it does not belong in `common`.

## Static Dictionary Data In `common`

The Brotli static dictionary and transform tables are large and are referenced
by both sides — but **only their raw data and pure lookups are shared**. This
section corrects a structural bug in the earlier version of this plan.

**The bug.** In the current flat source, the "dictionary" and "transform" files
contain methods on `BrotliOutputBuilder`:

- `brotli_dictionary.mbt`: `BrotliOutputBuilder::copy_from_dictionary_after_max_distance`
- `brotli_transform.mbt`: `BrotliOutputBuilder::copy_transformed_dictionary_word`

`BrotliOutputBuilder` is a `priv struct` defined in the decoder
(`brotli.mbt`) and is **never referenced by the encoder** — it is decode-only.
If those methods are placed in a shared `dictionary` package, that package must
import `decode` to know the type, while `decode` imports `dictionary` →
**circular package dependency, which MoonBit rejects** (and the type is `priv`,
so it cannot be referenced across packages at all).

**The fix.** Because file names are organizational in MoonBit, split by _type
ownership_, not by file name:

- `common` keeps only:
  - `dictionary_data.mbt`: embedded static dictionary bytes (the large blob).
  - `transform_data.mbt`: transform definitions and suffix/prefix data.
  - `dictionary.mbt`: pure word-length buckets, offsets, and byte lookups.
  - `transform.mbt`: pure transform metadata and byte-case helpers.
- `decode` owns the decode-side access layer that reads the shared data and
  writes into the output builder: the two `BrotliOutputBuilder::*` methods above
  and the uppercase-into-output logic. Put them in `decode/dictionary_copy.mbt`.
- `encode` owns the encode-side access layer: `encode_dict.mbt`
  (`brotli_dictionary_hash_update`, `brotli_dictionary_hash_data`,
  `brotli_dictionary_encode_entry_capacity`, …) — hash-based match finding over
  the same raw bytes.

Net effect: the raw dictionary bytes are single-sourced in `common`, while each
side keeps its own derived access layer. Both `decode` and `encode` depend on
`common`; neither depends on the other.

If a future encoder mode allows a no-static-dictionary build, that can justify
reintroducing a separate package such as `hustcer/fbr/encode_lite` or a
dictionary subpackage. It is not required for the current encoder/decoder split.

## What Goes In `decode`

`decode` owns the public decompression API:

- `unbrotli_sync(data, opts?)`
- `UnbrotliOptions`
- `UnbrotliStream`

It should also own decoder-only internals:

- `BrotliBitReader` (hot path — must stay here; see below).
- `BrotliOutputBuilder` and its methods, **including** the dictionary/transform
  copy methods relocated per the dictionary fix above.
- Meta-block header parsing.
- Decoder state and output builder.
- Huffman tree-group reading.
- Context map decoding.
- Literal, command, and distance decode loops.
- Padding validation.
- Decoder-focused tests and conformance fixtures.

The decoder should import only `common`. It must not import `encode`, even for
tests. Roundtrip tests that need both sides live in the top-level `tests`
package, not in `decode`.

## What Goes In `encode`

`encode` owns the public compression API:

- `brotli_sync(data, opts?)`
- `BrotliOptions`
- `BrotliStream`

It should also own encoder-only internals:

- Bit writer (hot path — must stay here; see below).
- Quality selection.
- Chunk sizing.
- Hash configuration and hash-chain match finding.
- Command candidate construction.
- Literal-only, LZ77, mixed dictionary, and high-quality paths.
- Huffman payload emission.
- Encoder hash-based dictionary matching (`encode_dict.mbt`).
- Encoder-focused ratio and external decode validation tests.

The encoder should import only `common`. It must not import `decode`. The
encoder currently reuses one fzip-core helper, `slc` (a private array-copy in
fzip's `bits.mbt`), plus a couple of bit helpers. `hustcer/fbr` must **carry its
own copy** of these — do not depend on `hustcer/fzip` for a one-line helper.
Encoder validation should continue to use the external Google Brotli CLI where
appropriate, because importing the local decoder into encoder tests can hide
bitstream compatibility bugs.

## Hot-Path and Cross-Package Inlining (Performance Invariant)

The split must not regress decode or encode throughput. The most likely
split-induced regression is **a hot-loop helper moved across a package
boundary**: if MoonBit does not inline that call across packages, every inner
iteration pays a call frame.

Note: function-level DCE was verified empirically (see above), but
**cross-package inlining was not separately verified**. Treat the following as a
conservative invariant, backed by the benchmark gate:

- **No function called from a decode or encode inner loop may live in `common`
  unless benchmark evidence proves the package boundary is harmless.**
- The decode hot primitives — `BrotliBitReader::peek_bits` / `drop_bits` /
  `take_bits` / `refill_to` — stay in `decode`.
- The encode hot primitive — the bit writer — stays in `encode`.
- `common` holds only cold/setup code, pure constant tables, and per-reference
  (not per-symbol) lookups.
- **Borderline shared helpers** that are logically shared _but_ may sit on a hot
  path — distance-code helpers (`distance.mbt`), command-prefix logic
  (`command.mbt`), and some Huffman helpers (`huffman.mbt`) — must be validated
  by the benchmark gate after the move. If any shows a regression beyond the
  threshold, **duplicate the helper into each side** (small source duplication)
  rather than share it. Single-sourcing is a goal, not an absolute; correctness
  and performance invariants win.

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

Provide an `fbr_err(code) -> FbrError` helper mirroring fzip's `fzip_err`, so the
~13 Brotli source files can keep their `raise fbr_err(...)` call shape. During
migration, every `raise FzipError` / `raise fzip_err(...)` in the moved files
becomes `raise FbrError` / `raise fbr_err(...)`, and the function signatures
`... raise FzipError` become `... raise FbrError`. This is a mechanical,
file-by-file change.

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
next public release that includes Brotli. This is a concrete deletion, and parts
of it touch fzip's **public** API — plan accordingly.

Deletion checklist (these are the _only_ core↔Brotli coupling points in the
current tree):

- **`src/stream.mbt`** — remove `BrotliStream` and `UnbrotliStream` (the struct
  defs, `::new`, and `::push`). This is the only place fzip's non-Brotli core
  references Brotli.
- **`src/error.mbt`** — remove the 10 `Brotli*` variants from `FzipErrorCode`
  (and their `to_string` / `to_int` / message-table entries).
  **`FzipErrorCode` is `pub(all)`**, so this is a breaking change to fzip's
  public API _if those variants already shipped_ (e.g. in 0.8.0). Decide:
  - keep the integer slots (currently 17–26) **reserved/unused** to avoid
    renumbering the remaining codes, and bump fzip's minor/major per its semver
    policy; or
  - renumber and treat it as a major bump.
    Verify whether the `Brotli*` variants were released before choosing.
- **`src/brotli*.mbt`** — remove all Brotli source and Brotli tests/fixtures
  (including the large `brotli_fixture_wbtest.mbt`; do **not** carry the stray
  untracked `brotli_target_perf_*_wbtest.mbt` into the new module — clean it up).
- **`slc`** stays in fzip; `hustcer/fbr` carries its own copy (see encode
  section).
- **README / CHANGELOG** — point users to `hustcer/fbr`:

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

That compatibility package depends on an external module, so it must **pin a
version** (`hustcer/fbr@x.y.z`) and document the semver coupling. It should be
explicitly imported by users who want the old fzip-style grouping, and must not
affect the default `hustcer/fzip` artifact.

## Migration Plan

### Phase 1: Create `hustcer/fbr` Skeleton

- Create a new repository or module with `moon.mod` name `hustcer/fbr`.
- Add `src/common`, `src/decode`, `src/encode`, and `src/tests` packages, each
  with a `moon.pkg`.
- Add a root facade package only after subpackages compile independently.
- Copy docs and tools that are Brotli-specific from fzip.

Validation:

```bash
moon check --target all
moon info
```

### Phase 2: Move Common Code

- Move Brotli constants and small shared tables into `common`.
- Move static dictionary and transform data plus pure lookups into `common`
  (no `BrotliOutputBuilder` methods — see the dictionary fix).
- Add `FbrErrorCode` / `FbrError` / `fbr_err` to `common`.
- Keep function bodies unchanged except for package-qualified references and the
  `FzipError` → `FbrError` rename.
- Preserve table byte order and static data exactly.

Validation:

```bash
moon check --target all
moon test src/common
```

### Phase 3: Move Decoder

- Move decoder-only files into `decode`, **including** the relocated
  `BrotliOutputBuilder` dictionary/transform copy methods.
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

- Move encoder-only files into `encode`, including `encode_dict.mbt` and the
  fbr-local copy of `slc` / bit helpers.
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

### Phase 5: Add Facade, Tests, And Update fzip

- Add root package wrappers in `hustcer/fbr`.
- Add the top-level `tests` package importing both `decode` and `encode` for
  roundtrip coverage (decoder/encoder packages stay decoupled).
- Remove Brotli public API from `hustcer/fzip` per the deletion checklist above,
  on a branch until fzip is rebased on the split.
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

### Make the invariants automated gates, not manual steps

The split moves shared tables and helpers between packages; the realistic
failure modes are (a) a reordered/retyped static table changing encoded bytes,
and (b) a hot-path helper crossing a package boundary and regressing speed.
Both must be caught by CI, not by remembering to run a command.

- **Byte-exact golden gate (encoded-size invariant).** Commit a golden corpus
  test: for every `(input, quality)` pair in the ratio corpus, store a hash of
  `brotli_sync` output and assert equality. Any drift fails CI. This is the only
  reliable guard against silent table-ordering changes. Do the same for
  `unbrotli_sync` output on the decode corpus.
- **Benchmark gate (performance invariant).** Run the existing
  `tools/brotli/bench` target-perf harness before the split (baseline) and after
  (candidate) on the same corpus; fail the gate when decode or encode regresses
  beyond the threshold below. This is also the backstop for the unverified
  cross-package inlining assumption.

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

Function-level DCE already keeps the encoder out of a decode-only program and
the decoder out of an encode-only program (see the measured result above). The
purpose of this check is therefore **to confirm no DCE hazard defeats that** —
not to prove the package split is what removes the code.

The checked-in validation entry point creates three temporary main packages
under ignored `src/fbr_size_*_main/` directories:

```text
src/fbr_size_decode_main/   # imports hustcer/fbr/decode, calls unbrotli_sync
src/fbr_size_encode_main/   # imports hustcer/fbr/encode, calls brotli_sync
src/fbr_size_full_main/     # imports hustcer/fbr, calls both
```

Run:

```bash
just size
# or:
nu tools/brotli/size/verify.nu --targets js --json
```

The script builds the fixtures in release mode and records linked artifact
sizes. For the JS target it also scans the linked output for package markers,
which makes the check an automated DCE-hazard gate rather than a manual size
inspection. Additional targets such as `wasm-gc` can be added for size
comparison with `--targets js,wasm-gc`.

Acceptance criteria:

- Decode-only artifact does not include encoder-only functions such as hash
  configuration, match finding, command candidate construction, or bit writer.
- Encode-only artifact does not include decoder-only functions such as bit
  reader, meta-block parser, output builder, or decode state machine.
- Both decode-only and encode-only may include dictionary raw bytes if
  required to keep behavior and encoded size unchanged.
- Full facade artifact may include both sides.

If a decode-only fixture still contains encoder symbols, the cause is a **DCE
hazard** (a cross-side trait dispatch, a shared global pinning both sides, or a
facade edge), not the package boundary — fix the hazard per
[DCE Hazards](#dce-hazards-and-common-constraints). Do not publish until the
decode-only and encode-only fixtures are clean.

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

1. Publish `hustcer/fbr` with decode, encode, common, and facade packages.
2. Validate downstream decode-only and encode-only artifact size (confirm no DCE
   hazard).
3. Update `hustcer/fzip` docs to reference `hustcer/fbr`.
4. Release fzip without Brotli in the default package (handle the
   `FzipErrorCode` change per its semver policy).
5. Add an optional fzip compatibility package only if users ask for it.

This path gives users the smallest default fzip package, keeps Brotli available
under the requested `hustcer/fbr` name, and preserves the current implementation
quality without forcing encoder and decoder users to pay for code they do not
call.

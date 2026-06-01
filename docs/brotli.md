# Brotli Support Implementation Plan

This document specifies how to add Brotli (RFC 7932) compression and
decompression to fzip. It is written so that a developer new to the project can
deliver phases P1 through P4 in order, with each phase shipping standalone
value before the next begins.

Authoritative references:

- RFC 7932 — "Brotli Compressed Data Format". Section numbers throughout this
  document refer to RFC 7932 unless stated otherwise.
- Google reference implementation at `/Users/hustcer/iWork/refs/brotli`.
  - C decoder: `c/dec/` (~3,745 LOC).
  - C encoder: `c/enc/` (~25,000 LOC including SIMD and hash variants).
  - Common tables and static dictionary: `c/common/`.
- Rust port at `/Users/hustcer/iWork/refs/rust-brotli`. The Rust decoder lives
  in a separate `brotli-decompressor` crate; this repository holds only the
  encoder. Treat the Rust source as a portability cheat sheet — it has already
  resolved many of the same `UInt`/`Int` and unaligned-read questions that this
  port faces.
- Existing planning doc `docs/zip64.md` for tone, depth, and validation
  workflow conventions used in this repository.

## Goals

- Ship a correct, RFC 7932-compliant Brotli decoder for fzip that handles every
  conformance file in the official test corpus.
- Ship a Brotli encoder that produces RFC-compliant streams at quality levels
  0 through 11.
- Match fzip's existing format coverage: a synchronous in-memory API
  (`unbrotli_sync` / `brotli_sync`) and a stream-compatible wrapper
  (`UnbrotliStream` / `BrotliStream`) that mirrors the current GZIP and
  DEFLATE surface in `src/stream.mbt`. In P1 the wrapper buffers input chunks
  until `final_=true`, matching the existing `InflateStream` implementation;
  true incremental Brotli decode is an optional follow-up once the one-shot
  decoder is conformant.
- Preserve fzip's `FzipError`/`FzipErrorCode` error model. All Brotli errors
  propagate as `FzipError`; callers can branch on the new error codes added in
  P1.
- Preserve existing security guarantees: a configurable output-size cap,
  bounded ring-buffer growth, and rejection of malformed streams without
  panicking. No raw indexing past validated bounds.
- Keep the package layout flat in `src/`, matching the rest of fzip. New files
  are prefixed `brotli_` so they group naturally in directory listings while
  still living in the same MoonBit package.

## Non-Goals

- Do not implement compound (shared) dictionaries (RFC 7932 §10). The reference
  C decoder supports them through `BrotliDecoderAttachDictionary`, but the
  feature is rare in the wild and adds significant state-machine surface.
  Standard Brotli streams do not self-describe an external dictionary
  requirement; reserve a Brotli error code for future public APIs that accept
  shared-dictionary options, but P1 exposes no such option.
- Do not implement the "large window" extension (custom window bits beyond 24).
  The decoder rejects `large_window` streams with a dedicated error code.
- Do not implement multi-threaded encoding. The reference Rust encoder has a
  worker-pool path; fzip stays single-threaded.
- Do not add SIMD intrinsics. MoonBit lacks a portable SIMD surface today.
- Do not regenerate fzip's public DEFLATE/GZIP/Zlib/ZIP APIs. Brotli is added
  as a peer format; existing callers are untouched.
- Do not auto-detect Brotli from a magic prefix in `decompress_sync`. Brotli
  has no reliable magic header; auto-detection would misclassify short DEFLATE
  streams. Callers select Brotli explicitly via `unbrotli_sync`.

## Phased Delivery Overview

Each phase produces a shippable artifact. A developer should finish one phase
(including tests, formatting, and `pkg.generated.mbti` review) before opening
the next branch.

| Phase | Scope                                       | C reference LOC                                                                                      | Estimated MoonBit LOC           | Estimated effort |
| ----- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------- | ---------------- |
| P1    | Decoder (`unbrotli_sync`, `UnbrotliStream`) | ~3,745 (`c/dec/` + `c/common/`)                                                                      | ~6,500 (incl. static dict data) | 4–6 weeks        |
| P2    | Encoder at q=0 and q=1 (fast path)          | ~2,100 (`compress_fragment*.c`, parts of `brotli_bit_stream.c`)                                      | ~2,500                          | 2–3 weeks        |
| P3    | Encoder at q=2–9 (standard back-references) | ~3,500 (`backward_references.c`, hash chains, `metablock.c`, `block_splitter.c`, `entropy_encode.c`) | ~4,500                          | 4–6 weeks        |
| P4    | Encoder at q=10–11 (Zopfli search)          | ~2,000 (`backward_references_hq.c` plus block-splitter heuristics tuned for q≥10)                    | ~2,500                          | 3–4 weeks        |

P1 unblocks ~90% of consumption use cases (decoding `.br` files,
`Content-Encoding: br` HTTP responses). Each subsequent encoder phase improves
the compression ratio achievable at the matching quality level.

## Repository Integration Points

Files that Brotli code will create, extend, or coexist with:

- `src/brotli_*.mbt` — new files; full list per phase below.
- `src/error.mbt` — extend `FzipErrorCode` with Brotli-specific codes (see
  "Error Model" below). Update `error_messages`, `Show` impl, and
  `fzip_error_code_to_int`.
- `src/stream.mbt` — add `UnbrotliStream` and (later) `BrotliStream`. Follow
  the existing `InflateStream` / `DeflateStream` pattern exactly: a public
  `mut ondata : FbrStreamHandler?`, private buffered chunks, and
  `push(chunk, final_?)`. The shared callback wrapper `FbrStreamHandler`
  and helper `call_handler` are already defined at the top of
  `src/stream.mbt`; reuse them verbatim. `priv` is valid on individual
  fields of a `pub(all) struct` in MoonBit (see existing
  `DeflateStream`/`InflateStream` definitions in the same file); reuse the
  pattern. Do not introduce a separate `set_ondata` API.
- `src/types.mbt` — add `UnbrotliOptions` and (later) `BrotliOptions` with
  `::default()` constructors. Keep field naming consistent with existing option
  structs (snake_case).
- `src/fzip.mbt` — do **not** modify `compress_sync` / `decompress_sync`. The
  Brotli entry points are independent top-level functions.
- `src/pkg.generated.mbti` — regenerated via `moon info` after every phase.
- `src/tests/brotli_fixtures/` — new directory for test corpora (see
  "Testing"). The directory does not exist today; the first Brotli PR creates
  it.
- `tools/` — new top-level directory created by P1 to hold
  generation and conformance helpers. Keep these outside the published
  `src/` package tree unless they must be compiled by `moon`. Add
  `tools/README.md` listing each helper and its exact invocation.
  If a helper is written in MoonBit as a single-file utility, invoke it with
  `moon run - < tools/<name>.mbt`; if it needs package imports or
  command-line parsing, give it its own small module under `tools/<name>/`.
- `tools/conformance/` — manual harness added by P1 to drive the full
  upstream Brotli test corpus. Excluded from `moon test` by default; invoke
  manually from its README instructions.

### Target backends

MoonBit targets **native (Linux/Windows/macOS)**, **JavaScript**, and
**WebAssembly** (wasm-gc). fzip's `moon.mod.json` does not pin
`preferred-target`, so Brotli code must compile and pass tests on all three.

Backend-specific guidance:

- **Integer widths**: `Int` is 64-bit on native and 32-bit on JavaScript and
  wasm-gc. Use `Int` for array indices (safe on all backends), use `UInt` for
  bit-field shifts (always 32-bit), and avoid relying on the upper 32 bits of
  `Int` for portability.
- **`UInt64`**: works on all three backends but is slower on JavaScript (no
  native 64-bit integer; emulated as a pair of 32-bit). The 32-bit bit-reader
  accumulator chosen for `brotli_bit_reader.mbt` avoids this entirely.
- **`Double`**: IEEE 754 binary64 on all backends. Bit-exact entropy
  calculations (P3 clustering) should match across backends; if they do not,
  the divergence is almost certainly in `log2(0)` handling.
- **Endianness**: all three backends are little-endian or backend-managed;
  Brotli is byte-stream with LSB-first bit ordering — no concern.
- **File I/O**: not used by Brotli core. Do not assume a package named `@fs`
  exists in fzip; the first Brotli PR must either discover and use the
  project-approved file API, or embed small fixtures as `FixedArray[Byte]`
  literals so native, JS, and wasm-gc run the same tests. Large upstream
  conformance files stay in the manual harness under `tools/`.

Validation matrix per phase PR:

```
moon check --target all
moon test --target native
moon test --target wasm-gc
moon test --target js
moon fmt
moon info
```

Note: `moon test --target all` runs all three targets sequentially; prefer
that over invoking each target manually unless debugging a single backend.
The performance budgets in "Cross-Phase Concerns" below are quoted for
wasm-gc; native is typically faster, JavaScript typically slower.

## Brotli Format Background

A Brotli stream is a sequence of meta-blocks framed inside a single bit
stream. Logical structure:

1. **Stream header** (§9.1). The `WBITS` field is a variable-length bit
   sequence, not a fixed byte. Port the reference `DecodeWindowBits` logic:
   first read 1 bit; `0` means `window_bits = 16`. Otherwise read 3 bits; a
   nonzero value maps to `window_bits = 17 + n`. If that value is zero, read
   another 3 bits; `0` maps to 17, `2..7` maps to `8 + n`, and `1` is invalid
   unless the large-window extension is explicitly enabled. fzip does not
   support large-window streams, so that path must raise
   `BrotliLargeWindowNotSupported` or `BrotliInvalidWindowBits` before any
   large allocation.
2. **A sequence of meta-blocks** (§9.2). Each meta-block has:
   - `ISLAST` flag (1 bit), `ISLASTEMPTY` flag (1 bit, only if `ISLAST`).
   - `MNIBBLES` (2 bits) plus `MLEN` (variable) — the uncompressed length the
     meta-block contributes.
   - Optional `ISUNCOMPRESSED` flag for non-last meta-blocks (§9.2).
   - For metadata meta-blocks (§9.2), `MLEN` is followed by raw bytes.
   - For compressed meta-blocks, the header continues with `NBLTYPESL`,
     `NBLTYPESI`, `NBLTYPESD` (block-type counts for literals, insert-and-copy,
     and distances), three block-switch Huffman trees, the context-modes array
     (one 2-bit mode per literal block type), `NTREESL` and `NTREESD` (number
     of Huffman trees in the literal/distance groups), two context maps (each
     run-length encoded with IMTF), `NPOSTFIX` and `NDIRECT` distance
     parameters (§4 and §9.2), three Huffman tree groups, and finally a series
     of commands (§9.3).
3. **Commands** (§9.3). Each command consists of an insert-length, a copy-
   length, optionally an explicit distance, then the corresponding literal
   bytes and a back-reference copy.
4. **Distances** (§4). A 4-element ring buffer of recent distances plus
   "direct" distances plus "decoded" distances computed from `NPOSTFIX` and
   `NDIRECT`. Some distance codes index into the static dictionary (§8) and
   apply a transformation (uppercase, suffix `ing`, etc.) defined in
   `common/transform.c`.
5. **Bit stream** is LSB-first within each byte. The bit reader pulls 16- or
   32-bit chunks at a time. RFC §1.4 details the bit-ordering convention.

The decoder should still be structured as a state machine because the format is
stateful and the reference implementation is organized that way. P1 does not
need to expose true incremental decode, though: `unbrotli_sync` owns the full
input buffer, and `UnbrotliStream` buffers chunks until the final push just like
the existing fzip stream wrappers.

## Naming and Style Conventions

These are non-negotiable for the duration of this work — they keep new code
legible alongside existing fzip files and avoid the cryptic three-letter
identifiers used in `dflt`, `wblk`, etc.

- Files are named `brotli_<role>.mbt` (e.g., `brotli_bit_reader.mbt`).
- Public entry points use a `brotli_` or `unbrotli_` prefix: `brotli_sync`,
  `unbrotli_sync`, `BrotliStream`, `UnbrotliStream`, `BrotliOptions`,
  `UnbrotliOptions`.
- Private functions inside Brotli files use descriptive snake_case names
  (`read_huffman_code`, `take_simple_huffman`, `decode_context_map`). Do not
  introduce new two- or three-letter identifiers; this is the rule
  `docs/zip64.md` codifies for new ZIP64 helpers and Brotli follows it from
  day one.
- Top-level items are separated by `///|` per MoonBit convention.
- Use `pub(all) struct` only when external code legitimately needs to
  construct a value (options structs). Otherwise use `priv struct`.
- Mark Brotli-internal enums `priv` unless they appear in public signatures.
- Constants live in `brotli_constants.mbt`. Lookup tables live in
  `brotli_tables.mbt`. Prefer `let NAME : FixedArray[Int] = [...]` over
  `const NAME : Int = ...` for tables; MoonBit's `const` is only allowed for
  primitive scalars.
- All buffer-typed values are `FixedArray[Byte]` to match the rest of fzip.
  Do not introduce `Bytes` in private signatures except as input to ergonomics
  helpers. Public APIs accept `FixedArray[Byte]` for symmetry with
  `deflate_sync` / `inflate_sync`.

## Error Model

Add the following codes to `FzipErrorCode` in `src/error.mbt`. Keep ordering
stable; existing call sites depend on `fzip_error_code_to_int`'s mapping.

```mbt nocheck
  /// Brotli window-bits field is out of range or reserved.
  BrotliInvalidWindowBits
  /// Brotli meta-block header is malformed.
  BrotliInvalidMetablock
  /// Brotli Huffman code tree could not be built from declared lengths.
  BrotliInvalidHuffman
  /// Brotli context map encoding is invalid.
  BrotliInvalidContextMap
  /// Brotli distance code references a position outside the window.
  BrotliInvalidDistance
  /// Brotli transform index is out of range.
  BrotliInvalidTransform
  /// Brotli shared-dictionary APIs are not supported by fzip.
  BrotliDictionaryNotSupported
  /// Brotli stream uses the large-window extension fzip does not support.
  BrotliLargeWindowNotSupported
  /// Brotli stream contains a reserved bit or pattern.
  BrotliReserved
  /// Brotli padding bits at end of stream are non-zero.
  BrotliInvalidPadding
```

Each new code requires:

1. Adding the variant to `FzipErrorCode`.
2. Extending the `Show` implementation.
3. Appending a default human message to `error_messages`.
4. Extending `fzip_error_code_to_int` with a unique index in order.

Decoder code raises via `raise fzip_err(BrotliInvalidMetablock, msg="...")`.
Where the C decoder distinguishes many internal causes under a single error
code, supply a descriptive `msg`. Do not invent further codes for diagnostic
variants; the message field is the right place for that detail.

For P1 internal control flow, do **not** invent a separate `BrotliResult`
enum like `RESULT_NEEDS_MORE_INPUT`. The MoonBit decoder is one-shot over a
complete buffer, so it either reaches `Done` or raises a real `FzipError`.
If a later phase adds true incremental decode, introduce an explicit
`BrotliDecodeStatus` first; do not reuse `UnexpectedEOF` as a soft
"need more input" signal.

## P1 — Decoder

### Goal

Deliver `unbrotli_sync(data, options?)` and `UnbrotliStream` that decode any
RFC 7932-compliant Brotli stream into a `FixedArray[Byte]`. Pass the upstream
test corpus (see Testing). Reject malformed and out-of-scope streams with a
descriptive `FzipError`.

### File Map (P1)

| MoonBit file                 | Approx. LOC   | Mirrors C source                                | Responsibility                                                                                                                                 |
| ---------------------------- | ------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `brotli_constants.mbt`       | ~200          | `common/constants.{c,h}` + new error codes      | All numeric constants: max window bits, code-length alphabets, ring-buffer sizes, distance-postfix limits.                                     |
| `brotli_tables.mbt`          | ~450          | `common/context.c`, `dec/prefix_inc.h`          | Context lookup tables (LUT0/1/2), insert-and-copy code base lengths, distance code postfix tables, code-length code-length permutation order.  |
| `brotli_transform.mbt`       | ~280          | `common/transform.{c,h}`                        | Prefix/suffix string table, 121 transform definitions, `apply_transform(word, transform_id, out_buf, out_pos)`.                                |
| `brotli_dict.mbt`            | ~3,000 (data) | `common/dictionary_inc.h` (5,847 lines of data) | Embedded static dictionary (122,784 bytes) plus the offset/length index arrays. See "Static Dictionary Embedding" below.                       |
| `brotli_bit_reader.mbt`      | ~320          | `dec/bit_reader.{c,h}`                          | `BitReader` struct + accessors. Refill 32 bits at a time. Provide both consuming reads (`take_bits`) and non-consuming peeks (`peek_bits`).    |
| `brotli_huffman.mbt`         | ~380          | `dec/huffman.{c,h}`                             | Build canonical Huffman tables; read complex and simple Huffman codes; fast-table lookup.                                                      |
| `brotli_state.mbt`           | ~480          | `dec/state.{c,h}`                               | `BrotliDecoderState` struct, sub-state enums, ring-buffer container, allocation helpers.                                                       |
| `brotli_decode.mbt`          | ~1,600        | `dec/decode.c` (3,023 LOC condensed)            | The main state machine plus its sub-state pump.                                                                                                |
| `brotli.mbt`                 | ~120          | `include/brotli/decode.h`                       | Public `unbrotli_sync` entry point, options handling, allocation policy.                                                                       |
| `src/*/*_wbtest.mbt`         | n/a           | —                                               | Package-local white-box tests in `common`, `decode`, and `encode` for bit reader, Huffman, transforms, dictionary access, and encoder helpers. |
| `brotli_test.mbt`            | ~500          | —                                               | Black-box roundtrip and conformance tests through `unbrotli_sync`.                                                                             |
| `src/tests/brotli_fixtures/` | n/a           | —                                               | Compressed test inputs and expected outputs.                                                                                                   |

P1 totals roughly 6,500 LOC of MoonBit, with the static dictionary accounting
for the bulk of `brotli_dict.mbt`.

### Concrete Tables and Arena Sizes (`brotli_tables.mbt`, `brotli_constants.mbt`)

The C reference hides several "magic" constants behind macros and `#include`
files. New employees consistently mis-transcribe them. Pin the values here so
they can be copy-pasted into `brotli_tables.mbt` without going back to the
RFC.

```mbt nocheck
///|
/// Order in which the 18 code-length code lengths are read at the start of
/// every complex Huffman header. RFC 7932 §3.5.
let CODE_LENGTH_CODE_ORDER : FixedArray[Int] = [
  1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

///|
/// Number of code-length codes that always have their length read. RFC §3.5
/// requires the first four lengths in `CODE_LENGTH_CODE_ORDER` to be present;
/// remaining lengths follow until the implied count is reached.
const NUM_CODE_LENGTH_CODES : Int = 18

///|
/// Maximum code length in bits for any Brotli Huffman alphabet. RFC §3.4.
const HUFFMAN_MAX_CODE_LENGTH : Int = 15

///|
/// Root table width (in bits) for the two-level Huffman lookup. RFC reference
/// uses 8 for all alphabets; matches the C reference's `HUFFMAN_TABLE_BITS`.
const HUFFMAN_TABLE_BITS : Int = 8

///|
/// Per-tree table capacity. C reference: `BROTLI_HUFFMAN_MAX_TABLE_SIZE = 1080`.
/// Derived from a width-8 root table plus the worst-case sub-tables for a
/// 704-symbol alphabet at max length 15.
const HUFFMAN_MAX_TABLE_SIZE : Int = 1080

///|
/// Alphabet sizes per stream.
const LITERAL_ALPHABET_SIZE : Int = 256
const INSERT_AND_COPY_ALPHABET_SIZE : Int = 704
const BLOCK_LENGTH_ALPHABET_SIZE : Int = 26
const BLOCK_TYPE_ALPHABET_SIZE_MAX : Int = 258  // 256 types + 2 control codes
// Distance alphabet size depends on NPOSTFIX/NDIRECT and window bits; computed
// per meta-block via:
//   16 + NDIRECT + (48 << NPOSTFIX)
// Upper bound at NPOSTFIX=3, NDIRECT=120 is 16 + 120 + (48 << 3) = 520.
const DISTANCE_ALPHABET_SIZE_MAX : Int = 520

///|
/// Maximum number of Huffman trees in each of the three tree groups. RFC §9.2
/// caps tree counts at the encoded block-type count, which itself is bounded
/// by 256. Use 256 as the worst case.
const MAX_HUFFMAN_TREES_PER_GROUP : Int = 256
```

#### Huffman arena sizing

Pre-allocate one flat `FixedArray[HuffmanCode]` per tree group; subdivide
with `(offset, length)` triples (no `ArraySlice` abstraction in fzip). Use
these formulas in `BrotliDecoderState::new`:

```mbt nocheck
///|
fn huffman_arena_size(alphabet_size : Int, num_trees : Int) -> Int {
  // Each tree consumes at most HUFFMAN_MAX_TABLE_SIZE entries. The C
  // reference asserts this bound in `huffman.c::BrotliBuildHuffmanTable`.
  // Use a tighter bound where alphabet_size < 704 to save memory:
  let per_tree = if alphabet_size <= 256 {
    632                  // empirical bound from C ref for 256-symbol alphabets
  } else if alphabet_size <= 272 {
    656
  } else if alphabet_size <= 396 {
    792
  } else {
    HUFFMAN_MAX_TABLE_SIZE
  }
  per_tree * num_trees
}
```

Per-decoder-call peak sizes (when `window_bits=24` and `num_trees=256` on all
three groups):

- Literal arena: `1080 * 256 = 276,480` entries × 4 bytes (UInt16 bits +
  UInt16 value) = ~1.1 MB.
- Insert-and-copy arena: `792 * 256 = 202,752` entries × 4 bytes = ~0.8 MB.
- Distance arena: `656 * 256 = 167,936` entries × 4 bytes = ~0.7 MB.
- Block-switch trees (three): `≤ 632 * 3 * 4 ≈ 7.6 KB`.
- Ring buffer: `1 << 24 = 16 MB`.
- Context maps: up to `256 * 64 = 16,384` bytes each, two of them.
- **Decoder per-call peak: ~19 MB** at the largest legal window. Document
  this in the public API doc-comment of `unbrotli_sync`.

Pessimistic decoders should NOT allocate at this peak unconditionally. Use
`num_trees` actually present in the meta-block (from `NTREESL` / `NTREESD`
/ `NBLTYPES*`) to size each arena. The worst case is rare; typical streams
use 1–4 trees per group and `window_bits` of 22 (4 MB).

#### Insert-and-copy length-code base/extra tables

RFC §5 defines insert-and-copy length codes as a packed `(insert_lcode,
copy_lcode)` pair, with `lcode` 0..23 each. Each `lcode` decodes to a
`(base_length, extra_bits)` tuple. Port these tables verbatim from
`c/common/constants.h`:

```mbt nocheck
let INSERT_LENGTH_BASES : FixedArray[Int] = [
  0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98,
  130, 194, 322, 578, 1090, 2114, 6210, 22594,
]

let INSERT_LENGTH_EXTRA_BITS : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5,
  6, 7, 8, 9, 10, 12, 14, 24,
]

let COPY_LENGTH_BASES : FixedArray[Int] = [
  2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54,
  70, 102, 134, 198, 326, 582, 1094, 2118,
]

let COPY_LENGTH_EXTRA_BITS : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4,
  5, 5, 6, 7, 8, 9, 10, 24,
]
```

#### Block-length codes

RFC §6 defines block-length codes as a 26-symbol alphabet, each symbol
encoding a `(base_length, extra_bits)` tuple in the same style as the
insert/copy tables:

```mbt nocheck
let BLOCK_LENGTH_BASES : FixedArray[Int] = [
  1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209,
  241, 305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625,
]

let BLOCK_LENGTH_EXTRA_BITS : FixedArray[Int] = [
  2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,
  6, 6, 7, 8, 9, 10, 11, 12, 13, 24,
]
```

#### Static-dictionary length tables

Already shown in "Static Dictionary Embedding" below. They live in
`brotli_dict.mbt` next to the dictionary itself because they are conceptually
part of the dictionary, not free-standing tables.

### Block-Length and Block-Switch Decoding (RFC §6)

Every compressed meta-block carries three independent token streams: literals,
insert-and-copy codes, and distances. Each stream is partitioned into "blocks"
that share the same Huffman tree (its block type). At meta-block start, three
counters — `block_len_l`, `block_len_i`, `block_len_d` — hold the number of
tokens remaining before the next block-switch on each stream.

When a counter reaches zero **before** reading the next token of that stream,
the decoder:

1. Reads a new `block_type_code` from the block-type Huffman tree for that
   stream. Block-type codes use a 258-symbol alphabet: 0..255 for explicit
   block types plus two control codes that select the previous-1 and
   previous-2 block types (a tiny ring buffer of size 2 per stream).
2. Resolves `block_type_code` to a concrete block type and updates the
   stream's 2-entry block-type ring.
3. Reads a new `block_length_code` from the block-length Huffman tree for
   that stream using the 26-symbol alphabet. The decoded value plus the
   appropriate extra bits (see `BLOCK_LENGTH_BASES` and
   `BLOCK_LENGTH_EXTRA_BITS`) becomes the new counter value.
4. Continues with the original token read using the now-current Huffman
   tree from the new block type.

The counter is decremented exactly once per token of that stream, regardless
of how many bits the token consumes. Block-switches are completely
independent across the three streams; a single command can trigger 0, 1, 2,
or all 3 of them.

Implementation skeleton:

```mbt nocheck
///|
/// Per-stream block tracking. One instance for literals, one for
/// insert-and-copy, one for distances.
priv struct BlockTracker {
  type_tree_offset : Int     // offset into block-type Huffman arena
  length_tree_offset : Int   // offset into block-length Huffman arena
  mut current_type : Int     // index into the stream's tree group
  mut prev_type_1 : Int      // 1 step back
  mut prev_type_2 : Int      // 2 steps back
  mut remaining : Int        // tokens until next switch
}

///|
fn BlockTracker::take_token(
  self : BlockTracker,
  reader : BitReader,
  tables : FixedArray[HuffmanCode],
) -> Unit raise FzipError {
  if self.remaining == 0 {
    let type_code = read_symbol(reader, tables, self.type_tree_offset)
    let new_type = resolve_block_type_code(self, type_code)
    self.prev_type_2 = self.prev_type_1
    self.prev_type_1 = self.current_type
    self.current_type = new_type
    let len_code = read_symbol(reader, tables, self.length_tree_offset)
    self.remaining = BLOCK_LENGTH_BASES[len_code] +
      reader.take_bits(BLOCK_LENGTH_EXTRA_BITS[len_code]).reinterpret_as_int()
    if self.remaining < 1 {
      raise fzip_err(BrotliInvalidMetablock, msg="block length must be >= 1")
    }
  }
  self.remaining -= 1
}

///|
fn resolve_block_type_code(self : BlockTracker, code : Int) -> Int {
  // RFC §6: code 0 -> prev_type_2, code 1 -> prev_type_1 + 1 mod num_types,
  // code n >= 2 -> n - 2.
  match code {
    0 => self.prev_type_2
    1 => (self.prev_type_1 + 1) % num_block_types_for(self)
    n => n - 2
  }
}
```

For meta-blocks with `NBLTYPESL = 1` (or `NBLTYPESI = 1`, `NBLTYPESD = 1`),
the corresponding block-switch tree is absent. Represent this explicitly
with a `single_block_type : Bool` field on `BlockTracker`, or initialize
`remaining` with the package-local `max_int_val()` helper. Do not write
`Int::max_value()`; MoonBit does not expose that method in this project.
Decode each token as before but skip the `if remaining == 0` branch when
there is only one block type for that stream.

Common pitfalls:

- Decrementing **before** the switch check is wrong: the switch happens at
  the boundary, after the previous token consumed the last unit of the old
  block. The skeleton above is correct: check, then decrement.
- Block-length sentinel of 0 is illegal per RFC §6; reject with
  `BrotliInvalidMetablock`.
- `prev_type_1` / `prev_type_2` must be initialized to 1 and 0 respectively
  at the start of each meta-block, per the C reference. Do not carry them
  across meta-blocks.

Required tests:

- A fixture with `NBLTYPESL >= 2` that toggles the literal block type at
  least 3 times. `monkey.compressed` is a good candidate; verify the
  fixture exercises this by checking it round-trips.
- A hand-built malformed stream with a block-length code of 0 raises
  `BrotliInvalidMetablock`.
- A stream where two streams' counters reach zero simultaneously (literals
  and distances both switching on the same command) — verify both
  block-switches are processed before the next token of either stream.

### Context Map Decoding (RFC §7.3)

Brotli refines per-token Huffman tree selection through context maps:

- **Literal context map**: 64 entries per block type, indexed by a
  `context_id` derived from the previous two literal bytes via the block's
  context mode (LSB6, MSB6, UTF-8, Signed, see RFC §7.1). Maps `(block_type
<< 6) | context_id` to one of `NTREESL` literal Huffman trees.
- **Distance context map**: 4 entries per block type, indexed by a 2-bit
  `distance_context` derived from the current copy length. Maps `(block_type
<< 2) | distance_context` to one of `NTREESD` distance Huffman trees.

Both maps are stored on the wire as run-length-encoded sequences of
8-bit indices, with an optional **Inverse Move-To-Front (IMTF)** transform
applied to the decoded sequence.

The wire format for a single context map (literal or distance):

1. **NTREES** (variable bits, RFC §9.2): the number of distinct Huffman
   trees for this stream. Encoded as: 1 bit; if 0, NTREES = 1. Otherwise
   read 3 bits as the high three bits of `(NTREES - 1)`; if those are 0,
   NTREES = 2; otherwise read further bits. Port verbatim from the C
   reference's `DecodeVarLenUint8` helper.
2. If NTREES == 1, the map is implicit (all entries 0) and steps 3-6
   are skipped. Otherwise:
3. **RLEMAX** (variable bits): the longest run-of-zeros run-length code
   used in this map. Encoded as: 1 bit; if 0, RLEMAX = 0 (no run codes
   used). Otherwise read 4 bits and `RLEMAX = decoded + 1`.
4. **Map alphabet size** is `RLEMAX + NTREES`. Read a complex Huffman code
   for this alphabet (same `read_complex_huffman_code` as the tree groups).
5. **Map symbols**: emit symbols using the Huffman code just built. A
   symbol `s` in `1..=RLEMAX` represents a run of `(1 << s) + extra` zeros,
   where `extra` is `s` additional bits read after the symbol. A symbol `0`
   emits a single zero. A symbol `s > RLEMAX` emits a single byte
   `(s - RLEMAX)`. Continue until the map is filled to its expected
   length: `64 * NBLTYPESL` for literal maps, `4 * NBLTYPESD` for
   distance maps.
6. **IMTF flag** (1 bit): if 1, apply Inverse Move-To-Front to the
   decoded sequence. If 0, the sequence is already in final form.

Inverse Move-To-Front:

```mbt nocheck
///|
fn inverse_move_to_front(map : FixedArray[Byte]) -> Unit {
  let mtf : FixedArray[Byte] = FixedArray::make(256, b'\x00')
  for i in 0..<256 {
    mtf[i] = i.to_byte()
  }
  for i in 0..<map.length() {
    let index = map[i].to_int()
    let value = mtf[index]
    map[i] = value
    // Shift mtf[0..index] one slot right and put `value` at the front.
    let mut j = index
    while j > 0 {
      mtf[j] = mtf[j - 1]
      j -= 1
    }
    mtf[0] = value
  }
}
```

This is a hot path: 64 × 256 = 16,384 IMTF operations for a maxed-out
literal map. The naive shift is fine for P1; revisit only if profiling shows
context-map decode as a bottleneck.

Required tests:

- NTREES = 1 path (implicit all-zero map). At least one fixture must
  exercise this; the upstream `empty.compressed` does.
- NTREES > 1 with no run codes (RLEMAX = 0): direct symbol output.
- NTREES > 1 with run codes covering 75%+ of the map.
- IMTF on and IMTF off. Verify a hand-built map decoded both ways.
- Malformed: a run code that overflows the map raises
  `BrotliInvalidContextMap`.
- Malformed: a symbol value `>= RLEMAX + NTREES` raises
  `BrotliInvalidContextMap`.

Context-mode lookup tables for literals (LUT0/LUT1/LUT2 in the C reference)
live in `brotli_tables.mbt` and are byte-for-byte ports of `common/context.c`.
The literal `context_id` is computed at command-execution time as:

```
context_id = LUT0[prev_byte_1] | LUT1[prev_byte_2] | LUT2[context_mode]
```

with the previous-byte tables varying by context mode. See `c/common/context.c`
for the exact 256×4-byte LUT contents; port verbatim, do not hand-recompute.

### Naming Crosswalk Between C and MoonBit

The C decoder's identifiers are dense. Use this table as a glossary so the
state machine reads naturally in MoonBit.

| C identifier                    | MoonBit identifier   | Notes                                                                |
| ------------------------------- | -------------------- | -------------------------------------------------------------------- |
| `BrotliDecoderState`            | `BrotliDecoderState` | Same type. Keep the prefix because it appears in public diagnostics. |
| `s->br` (a `BrotliBitReader`)   | `state.reader`       | Embed as a struct field.                                             |
| `s->state`                      | `state.phase`        | Avoid the word `state.state`. Use `phase`.                           |
| `s->substate_*`                 | `state.sub_phase_*`  | Sub-state enums for individual stages.                               |
| `BROTLI_STATE_METABLOCK_BEGIN`  | `MetablockBegin`     | An enum variant of `DecoderPhase`.                                   |
| `ReadHuffmanCode`               | `read_huffman_code`  | snake_case helper.                                                   |
| `ProcessCommands`               | `process_commands`   | snake_case helper.                                                   |
| `CopyUncompressedBlockToOutput` | `copy_uncompressed`  | Shorter, descriptive.                                                |

### Bit Reader (`brotli_bit_reader.mbt`)

Brotli is LSB-first. The C bit reader maintains a 64-bit accumulator and
refills from the input buffer in 8-byte chunks. MoonBit cannot do unaligned
8-byte loads, so the bit reader is structured around a 32-bit accumulator
that refills 16 bits at a time. This matches the C decoder's "safe" fallback
path and is also the model used by the existing `inflate.mbt`.

```mbt nocheck
///|
priv struct BitReader {
  buf : FixedArray[Byte]
  mut byte_pos : Int
  byte_end : Int
  mut bit_buf : UInt   // accumulator; low `bits_avail` bits are valid input
  mut bits_avail : Int // 0..=32
}

///|
fn BitReader::new(buf : FixedArray[Byte], offset : Int, length : Int) -> BitReader {
  { buf, byte_pos: offset, byte_end: offset + length, bit_buf: 0, bits_avail: 0 }
}
```

Required operations:

- `refill_to(n : Int)` — guarantees `bits_avail >= n` or raises
  `UnexpectedEOF`. Called before every read that needs `> bits_avail` bits.
- `take_bits(n : Int) -> UInt` — extracts `n` bits (0..=24) from the LSB end
  of `bit_buf`, then shifts and decrements. Refills as needed.
- `peek_bits(n : Int) -> UInt` — returns the same value but does not modify
  `bit_buf` / `bits_avail`. Used for prefix-table lookups before committing
  to a length.
- `drop_bits(n : Int)` — advances after a peek.
- `align_to_byte()` — discards bits until byte-aligned; used at the end of
  uncompressed meta-blocks (§9.2). Validate that discarded bits are zero per
  RFC §9.2 and raise `BrotliInvalidPadding` otherwise.
- `take_bytes(out : FixedArray[Byte], offset : Int, length : Int)` — copies
  byte-aligned raw bytes after `align_to_byte`. Used for uncompressed and
  metadata meta-blocks.
- `bits_consumed() -> Int` — total bits consumed since construction. Used
  for diagnostics and for the final padding check.

Correctness invariants:

- `bit_buf >> bits_avail` is always zero (high bits cleared on take).
- `refill_to` only ever loads from `buf[byte_pos..byte_end]`; never reads
  past `byte_end` even speculatively. The C decoder uses a "safety margin"
  trick that we cannot rely on in MoonBit because we do not own past-the-end
  bytes.

Performance notes:

- `refill_to(16)` loads two bytes with `buf[byte_pos]` and
  `buf[byte_pos + 1]` and combines them into `bit_buf`. Use
  `Byte::to_uint()` for promotion; do not use `to_int()` because the result
  must remain unsigned.
- Avoid `UInt64` in P1. The MoonBit `UInt64` ALU is acceptable on native but
  slower on wasm-gc; the 32-bit accumulator is enough for all Brotli reads
  except the very first 16 bits of a long meta-block size header, which the
  state machine reads in two parts anyway.
- The hottest call site is `read_symbol` (Huffman decode); see Huffman section
  for the two-level lookup pattern.

White-box tests required:

- Round-trip arbitrary bit patterns through `take_bits(1..=24)` and confirm.
- Drive `peek_bits` followed by `drop_bits` and confirm equivalence to
  `take_bits`.
- `align_to_byte` over a stream whose unaligned tail is zero — succeeds.
- `align_to_byte` over a stream whose unaligned tail is nonzero — raises
  `BrotliInvalidPadding`.
- `take_bytes` across `byte_pos` advancing into the next aligned chunk.
- EOF behavior: every operation that reads past `byte_end` raises
  `UnexpectedEOF` with the expected message.

### Huffman Decoding (`brotli_huffman.mbt`)

Brotli uses canonical Huffman tables much like DEFLATE, but with two
variants:

1. **Simple Huffman** (§3.4) — encodes 1–4 symbols with explicit symbol bits
   followed by 1–2 bit selectors. Used when the alphabet is very small.
2. **Complex Huffman** (§3.5) — first reads code-length code-lengths in a
   permuted order (`code_length_code_length_order` from
   `brotli_tables.mbt`), builds a small "code-lengths Huffman tree", then
   decodes the actual symbol code lengths with run-length-encoded repeats
   (RLE16, RLE17). Builds a canonical Huffman tree from the resulting
   lengths.

Concrete API:

```mbt nocheck
///|
/// One entry in the decoded Huffman table.
priv struct HuffmanCode {
  bits : UInt16   // number of bits to consume after a successful lookup
  value : UInt16  // symbol or link offset
}

///|
fn build_huffman_table(
  table : FixedArray[HuffmanCode],
  table_offset : Int,
  root_bits : Int,
  symbol_lists : FixedArray[UInt16],
  symbol_offset : Int,
  symbol_count : Int,
  count_arg : FixedArray[UInt16],
) -> Int raise FzipError
```

The C reference uses a two-level table: a `root_bits`-wide primary table
followed by per-collision sub-tables. Port this verbatim — the alternative
(symbol-by-symbol bit walking) costs about 5× in the decode loop.

Public helpers:

- `read_simple_huffman_code(reader, max_alphabet_size, table, table_capacity)`
- `read_complex_huffman_code(reader, alphabet_size, max_symbol, table, table_capacity)`
- `read_symbol(reader, table) -> Int` — the fast-path decode. Peek
  `HUFFMAN_TABLE_BITS` bits (`8`, matching the C reference root table),
  index into the primary table, consume `bits` bits, and follow a sub-table
  indirection if needed.

Edge cases that **must** be tested:

- A complex Huffman code with exactly one nonzero length (single-symbol
  tree). RFC requires reading 0 bits to decode the symbol.
- Over-subscription (sum of `2^(MAX_LEN - len)` exceeds 1 shifted left) —
  raise `BrotliInvalidHuffman` with message indicating "over-subscribed".
- Under-subscription (sum less than full) — raise
  `BrotliInvalidHuffman, msg="under-subscribed"` per §3.5.
- Empty code-lengths array (all zeros) — handled per RFC §3.5; if the
  alphabet is non-trivial, raise `BrotliInvalidHuffman`.

Implementation tip: avoid allocating a fresh `FixedArray` per Huffman table.
The decoder's `state.huffman_tables` is a pre-sized arena (`HUFFMAN_TABLE_SIZE`
~~ 2080 entries × tree count). Current fzip code does not use an `ArraySlice`
abstraction, so pass `(array, offset, length)` triples in hot helpers instead
of inventing a general slice type for P1.

### Static Dictionary Embedding (`brotli_dict.mbt`)

The static dictionary is 122,784 bytes (RFC §8). It is required for correct
decoding of any stream that uses dictionary back-references. There is no way
to omit it.

Three embedding options were evaluated:

**Option A: Raw byte literal.** A single `let BROTLI_DICT : FixedArray[Byte] = [...]`
spanning the full 122,784-byte content. Pros: trivial. Cons: source file
balloons to ~600 KB depending on chosen literal syntax; many editors choke
above 256 KB; some MoonBit toolchain steps (formatter, doc generator) slow
down on very large literals.

**Option B: Chunked literals.** Split the dictionary into 32 chunks of about
3,840 bytes each, expressed as `FixedArray[Byte]` constants
(`BROTLI_DICT_CHUNK_0` … `BROTLI_DICT_CHUNK_31`). Provide a lazy initializer
that concatenates them into a single `FixedArray[Byte]` on first use. Pros:
each chunk is editor-friendly; build time stays reasonable. Cons: still
~600 KB of source.

**Option C: Zlib-wrapped DEFLATE payload, decompressed at first use.** Embed a
single compressed `FixedArray[Byte]` (~52 KB after Zlib-wrapped DEFLATE) plus
an offset index. On first call to any `unbrotli_*` API, invoke fzip's existing
`unzlib_sync` (already in this package, no import needed) to materialize the
full dictionary into a `Ref[FixedArray[Byte]?]`. Pros: small source footprint;
reuses code fzip already has; the Adler-32 footer catches payload corruption.
Cons: first call pays a one-time decompression cost (~1–3 ms on commodity
hardware); the lazy init must be thread-safe in spirit (MoonBit lacks atomics
in the standard library, but the decoder is single-threaded per call so a
simple `if dict.val is None` guard suffices).

**Decision for P1: Option C.** Reasons:

- Source-tree impact is minimal — ~50 KB of source vs. ~600 KB.
- We get a runtime sanity check for free: if the embedded Zlib blob is
  corrupted by a bad merge, the first `unbrotli_sync` call fails loudly with
  `InvalidChecksum`, `InvalidLengthLiteral`, or `UnexpectedEOF`, which is much
  easier to diagnose than a silent wrong-byte at offset 79,000 in the
  dictionary.
- Build pipeline regeneration is trivial: a small helper (see
  `tools/gen_brotli_dict.mbt`, described below) reads `dictionary.bin`
  and emits a single `brotli_dict.mbt` file.

Layout of `brotli_dict.mbt`:

```mbt nocheck
///|
let BROTLI_DICT_COMPRESSED : FixedArray[Byte] = [
  // ~52,000 bytes of Zlib-wrapped DEFLATE-compressed RFC dictionary
  0x78, 0x9c, // ...
]

///|
/// `BROTLI_DICT_SIZE_BITS_BY_LENGTH[n]` gives the number of bits used to encode
/// the index into the dictionary slice of length `n`. RFC 7932 §8 Table 7.
let BROTLI_DICT_SIZE_BITS_BY_LENGTH : FixedArray[Int] = [
  0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8,
  7, 7, 8, 7, 7, 6, 6, 5, 5, 0, 0, 0, 0, 0, 0, 0,
]

///|
/// `BROTLI_DICT_OFFSETS_BY_LENGTH[n]` gives the byte offset within the
/// dictionary where slices of length `n` begin. RFC 7932 §8 Table 7.
let BROTLI_DICT_OFFSETS_BY_LENGTH : FixedArray[Int] = [
  0, 0, 0, 0, 0, 4096, 9216, 21504, 35840, 44032, 53248, 63488, 74752, 87040,
  93696, 100864, 104704, 106752, 108928, 113536, 115968, 118528, 119872,
  121280, 122016, 122784, 122784, 122784, 122784, 122784, 122784, 122784,
]

///|
let brotli_dict_cache : Ref[FixedArray[Byte]?] = { val: None }

///|
fn brotli_static_dictionary() -> FixedArray[Byte] raise FzipError {
  match brotli_dict_cache.val {
    Some(dict) => dict
    None => {
      let dict = unzlib_sync(BROTLI_DICT_COMPRESSED)
      if dict.length() != 122784 {
        raise fzip_err(
          InvalidChecksum,
          msg="brotli static dictionary failed integrity check",
        )
      }
      brotli_dict_cache.val = Some(dict)
      dict
    }
  }
}
```

The `122784` length check is the integrity guard mentioned above. The expected
SHA-256 of the dictionary must be verified by the generator. For the checked-in
Google reference at `/Users/hustcer/iWork/refs/brotli/c/common/dictionary.bin`,
the digest is:

```
20e42eb1b511c21806d4d227d07e5dd06877d8ce7b3a817f378f313653f35c70
```

Preserve this value as a comment near the top of `brotli_dict.mbt`:

```mbt nocheck
// Brotli static dictionary, RFC 7932 §8.
// Source: c/common/dictionary.bin
// SHA-256: 20e42eb1b511c21806d4d227d07e5dd06877d8ce7b3a817f378f313653f35c70
// Length: 122,784 bytes
```

A runtime SHA check is not required because the length check plus the Zlib
Adler-32 checksum is enough for production.

Generator helper (`tools/gen_brotli_dict.mbt`, run manually when the
dictionary source changes):

1. Read `c/common/dictionary.bin`.
2. Verify its length is 122,784.
3. Verify the expected SHA-256 listed above.
4. Compress with `zlib_sync(dict, opts={ level: 9, mem: 0, dictionary: None })`.
5. Emit `brotli_dict.mbt` with the constants above.
6. Run `moon fmt`.

Document the helper's usage in `tools/README.md` even though regeneration
should be rare.

### Transforms (`brotli_transform.mbt`)

RFC §8 defines 121 transforms applied to dictionary words: a prefix string,
an internal transform (identity, uppercase first, uppercase all,
omit-first-N, omit-last-N), and a suffix string. The prefix/suffix strings
together total 217 bytes; the transforms table has 121 triplets.

Port `common/transform.c` literally:

```mbt nocheck
///|
priv struct Transform {
  prefix_id : Int    // index into BROTLI_TRANSFORM_STRINGS
  middle : TransformMiddle
  suffix_id : Int
}

///|
priv enum TransformMiddle {
  Identity
  UppercaseFirst
  UppercaseAll
  OmitFirst(n~ : Int)
  OmitLast(n~ : Int)
}
```

`apply_transform(word : FixedArray[Byte], word_offset : Int, word_len : Int,
transform_id : Int, out : FixedArray[Byte], out_offset : Int) -> Int`
returns the number of bytes written. It must:

- Validate `transform_id` against the transforms table; raise
  `BrotliInvalidTransform` if out of range.
- Handle the UTF-8 case conversions byte-for-byte using the same lookup
  table the C reference uses (`kUppercaseFirst`, `kUppercaseAll`). UTF-8
  multi-byte sequences are processed byte-by-byte; do **not** convert to
  MoonBit `String` (MoonBit's `String` is UTF-16 internally and will corrupt
  surrogate pairs).
- Bounds-check against the output ring buffer; the caller passes a
  pre-validated slot, but `apply_transform` should still raise if it would
  exceed `out.length() - out_offset`.

White-box tests:

- Sample every distinct `TransformMiddle` variant with a known input.
- Tests must use `inspect(...)` on the byte sequence returned to lock down
  expected output.
- Compare a handful of transforms against the C reference's
  `BrotliTransformDictionaryWord` to catch off-by-one errors.

### Decoder State (`brotli_state.mbt`)

The decoder owns:

- The bit reader (see above).
- The output ring buffer (`FixedArray[Byte]`, sized at `1 << window_bits`).
- Distance ring buffer (`FixedArray[Int]` of length 4; RFC §4).
- Block-type ring buffers for literal/insert-and-copy/distance streams.
- Three Huffman tree groups (literal, insert-and-copy, distance) plus the
  block-switch trees.
- Two context maps (literal and distance) and their associated literal/
  distance trees.
- Sub-state enums for each phase that may suspend mid-bit-read.

Define the top-level phase enum exactly to match `BROTLI_STATE_*` in
`c/dec/state.h`:

```mbt nocheck
///|
priv enum DecoderPhase {
  Uninited
  LargeWindowBits
  Initialize
  MetablockBegin
  MetablockHeader
  MetablockHeader2
  ContextModes
  CommandBegin
  CommandInner
  CommandPostDecodeLiterals
  CommandPostWrapCopy
  Uncompressed
  Metadata
  CommandInnerWrite
  MetablockDone
  CommandPostWrite1
  CommandPostWrite2
  BeforeCompressedMetablockHeader
  HuffmanCode0
  HuffmanCode1
  HuffmanCode2
  HuffmanCode3
  ContextMap1
  ContextMap2
  TreeGroup
  BeforeCompressedMetablockBody
  Done
}
```

For sub-states, use enums with payloads instead of a flat integer:

```mbt nocheck
///|
priv enum HuffmanSubPhase {
  None
  SimpleSize
  SimpleRead(symbols_read~ : Int)
  SimpleBuild
  Complex(stage~ : Int)
  LengthSymbols
}
```

Justification: payload variants document the invariants ("we have read N
simple-Huffman symbols") that the C reference smuggles through scratch
fields like `s->symbol`.

`BrotliDecoderState::new(window_bits)` allocates:

- Ring buffer: `FixedArray::make(1 << window_bits, b'\x00')`.
- Huffman arena: `FixedArray::make(HUFFMAN_TABLE_SIZE * MAX_TREE_GROUP_SIZE,
HuffmanCode { bits: 0, value: 0 })`. Compute sizes from RFC limits.
- Block-length arrays.

Avoid per-meta-block allocation. Reuse arenas across meta-blocks by tracking
the in-use prefix.

### Decoder Main Loop (`brotli_decode.mbt`)

The C decoder's main function `BrotliDecoderDecompressStream` is a giant
`switch (s->state)` inside a `for (;;)` loop, with each case potentially
returning `NEEDS_MORE_INPUT` or transitioning. Translate to MoonBit as:

```mbt nocheck
///|
fn decode(state : BrotliDecoderState) -> Unit raise FzipError {
  loop {
    match state.phase {
      Uninited => {
        // Read WBITS per §9.1
        ...
        state.phase = Initialize
      }
      MetablockBegin => { ... state.phase = MetablockHeader }
      MetablockHeader => { ... }
      // ... every other variant
      Done => break
    }
  }
}
```

For P1, `decode` is a one-shot core called with the complete compressed buffer.
If input ends before the Brotli stream reaches `Done`, it raises
`UnexpectedEOF`. Do not overload `UnexpectedEOF` to mean "wait for the next
stream chunk"; that would make one-shot and stream behavior diverge.

If true incremental Brotli decoding is added later, change the internal API
before changing `UnbrotliStream`:

```mbt nocheck
///|
priv enum BrotliDecodeStatus {
  NeedInput
  MadeProgress
  Done
}

///|
fn decode_available(state : BrotliDecoderState) -> BrotliDecodeStatus raise FzipError
```

That version must preserve the bit-reader accumulator, byte position, and every
sub-phase across calls. Merely trimming unconsumed bytes is insufficient because
a Brotli read may suspend after consuming part of a byte.

Sub-phase pumps live in helper functions:

- `read_metablock_header(state)` — drives `MetablockHeader` through to one
  of `Uncompressed`, `Metadata`, or `BeforeCompressedMetablockHeader`.
- `read_huffman_tree_group(state, group_index)` — drives the three
  `HuffmanCode*` phases. Calls `read_huffman_code` for each tree.
- `read_context_map(state, which)` — `ContextMap1` (literal) and
  `ContextMap2` (distance).
- `process_commands(state)` — the inner command loop (`CommandBegin` →
  `CommandInner` → `CommandPostDecodeLiterals` → `CommandPostWrapCopy`).

The command loop is the hot path; spend extra care here:

- Refill the bit buffer at the top of each iteration so individual symbol
  reads never block.
- Lift `state.ring_buffer.length()` into a local before the loop; do not
  re-read the field every iteration.
- For literal copies, write directly into the ring buffer via a single
  `for k in 0..<insert_length { ring_buffer[(rb_pos + k) & mask] = ... }`
  loop. Use bitmasking (`mask = ring_buffer.length() - 1`) so the window is
  always a power of two.
- For back-reference copies that fully reside within the ring buffer
  (distance < copy_length), implement the byte-by-byte copy explicitly; do
  not use slice copy. The overlapping case is what makes LZ77 work.
- For dictionary copies (distance into the static dictionary), call
  `apply_transform` directly into the ring buffer.
- After every literal or copy, advance `rb_pos` and check whether the
  ring-buffer write head wrapped past the meta-block's logical end. When
  it does, flush ring-buffer contents into the output buffer (the decoder
  output `FixedArray[Byte]`).

### Distance Resolution

Brotli distance handling is a correctness hotspot and should have its own
implementation helper rather than being folded into the command loop.

Add a helper with this shape:

```mbt nocheck
///|
priv enum ResolvedDistance {
  Ring(distance~ : Int)
  Dictionary(word_id~ : Int, word_len~ : Int, transform_id~ : Int)
}

///|
fn resolve_distance(
  state : BrotliDecoderState,
  distance_code : Int,
  copy_length : Int,
) -> ResolvedDistance raise FzipError
```

The helper owns all distance-code rules:

- Maintain the 4-entry recent-distance ring exactly as RFC §4 specifies. Codes
  for recent distances are only valid when the referenced distance is positive
  and does not exceed the current maximum backward distance.
- Decode direct distances using `NPOSTFIX` and `NDIRECT`. Validate that
  `NDIRECT` is a multiple of `1 << NPOSTFIX` and that the computed distance
  cannot overflow `Int`.
- Decode postfix distances with the RFC formula and reject any distance that
  points before the available output window unless it resolves into the static
  dictionary range.
- For dictionary distances, compute dictionary word length, word id, and
  transform id before calling `apply_transform`. Validate the word id against
  `BROTLI_DICT_SIZE_BITS_BY_LENGTH[word_len]` and
  `BROTLI_DICT_OFFSETS_BY_LENGTH[word_len + 1]`.
  Dictionary word lengths outside 4..=24 are invalid even though the arrays
  keep 32 entries to match the C reference layout.
- Update the recent-distance ring only for real backward distances, not for
  static-dictionary references.

Required tests:

- Recent-distance codes 0..15, including the "distance + delta" forms.
- `NPOSTFIX` values 0..3 and `NDIRECT` boundary values.
- Distance exactly equal to the current output length succeeds; distance one
  larger raises `BrotliInvalidDistance`.
- Dictionary copy for at least one transform from `monkey.compressed` or
  `ukkonooa.compressed`.
- Malformed dictionary word id and transform id raise `BrotliInvalidDistance`
  and `BrotliInvalidTransform` respectively.

### Output Buffer Policy

- For `unbrotli_sync`, choose an initial output size of
  `min(max_output_size, max(input_length * 4, 4096))`, using saturating
  arithmetic before every allocation. Grow geometrically
  (`new_size = current_size * 2`) up to `opts.max_output_size`. On overflow,
  raise `InvalidZipData` with message `"output exceeds max_output_size"`.
- If `opts.out` is supplied, treat it as a fixed caller-owned output buffer.
  Raise `InvalidZipData, msg="output buffer too small"` instead of growing it.
- For P1 `UnbrotliStream`, enforce `max_input_size` across the concatenated
  buffered chunks and `max_output_size` through the final `unbrotli_sync` call.

### Public API (`brotli.mbt`)

```mbt nocheck
///|
pub(all) struct UnbrotliOptions {
  /// Optional pre-allocated output buffer; when supplied, it must fit the full
  /// decompressed payload.
  out : FixedArray[Byte]?
  /// Maximum bytes the decoder will produce. Protects against decompression
  /// bombs.
  max_output_size : Int
  /// Maximum compressed bytes accepted in a single sync call. Mirrors the
  /// limit used by `inflate_sync` and friends.
  max_input_size : Int
}

///|
pub fn UnbrotliOptions::default() -> UnbrotliOptions {
  {
    out: None,
    max_output_size: default_max_output_size,
    max_input_size: default_max_input_size,
  }
}

///|
pub fn unbrotli_sync(
  data : FixedArray[Byte],
  opts? : UnbrotliOptions = UnbrotliOptions::default(),
) -> FixedArray[Byte] raise FzipError {
  if data.length() > opts.max_input_size {
    raise fzip_err(InvalidZipData, msg="input exceeds max_input_size")
  }
  let state = BrotliDecoderState::new(data, opts)
  decode(state)
  // Strict tail check: any trailing bits must be zero padding (§9.2).
  state.reader.expect_final_padding_zero()
  state.collect_output()
}
```

`collect_output` is responsible for copying ring-buffer pages and live tail
into a single `FixedArray[Byte]` sized to exactly `state.output_length`. Do
not return the ring buffer directly; it is over-allocated by definition.

### Streaming Wrapper (`UnbrotliStream`, in `stream.mbt`)

Mirror the existing `InflateStream` implementation. P1 does not maintain a
live Brotli decoder between pushes; it buffers compressed chunks until
`final_=true`, then calls `unbrotli_sync` once and emits the decoded data
through `ondata`.

```mbt nocheck
///|
pub(all) struct UnbrotliStream {
  /// Called with decompressed data when a final chunk is pushed.
  mut ondata : FbrStreamHandler?
  priv opts : UnbrotliOptions
  priv mut chunks : Array[FixedArray[Byte]]
}

///|
pub fn UnbrotliStream::new(
  opts? : UnbrotliOptions = UnbrotliOptions::default(),
) -> UnbrotliStream {
  { ondata: None, opts, chunks: [] }
}

///|
pub fn UnbrotliStream::push(
  self : UnbrotliStream,
  chunk : FixedArray[Byte],
  final_? : Bool = false,
) -> Unit raise FzipError { ... }
```

`push` appends `chunk` into `chunks`. When `final_` is true, it concatenates
the chunks, calls `unbrotli_sync(data, opts=self.opts)`, dispatches the result
with `call_handler(h, result, true)`, and clears `chunks`.

Add stream tests modelled after `stream_wbtest.mbt`'s `InflateStream`
suite: chunk the same compressed buffer in 1-, 7-, 64-, and 4096-byte
fragments and confirm the concatenated output equals the one-shot
`unbrotli_sync` result.

### Testing Strategy (P1)

The Brotli reference repo ships a comprehensive test corpus at
`tests/testdata/`. The smallest useful set to embed in fzip:

1. `empty.compressed` — a meta-block-less stream representing the empty
   string.
2. `10x10y.compressed` — a tiny stream that exercises basic literal +
   back-reference logic.
3. `64x.compressed` — exercises a single byte repeated 64 times via
   back-reference.
4. `quickfox.compressed` — RFC §A.1 the-quick-brown-fox example. Exact bytes
   are reproduced in the RFC; cross-validates byte-by-byte conformance.
5. `quickfox_repeated.compressed` — exercises distance ring buffer.
6. `ukkonooa.compressed` — exercises Finnish text with diacritics, hits
   transform paths.
7. `monkey.compressed` — exercises a large dictionary-dominated meta-block.
8. `random_org_10k.bin.compressed` — exercises a stream with no
   compressibility; tests stored-block path.

Each fixture goes into `src/tests/brotli_fixtures/<name>.br` with the
expected output at `src/tests/brotli_fixtures/<name>.expected`. The test
loads both and asserts byte-for-byte equality on `unbrotli_sync`.

Additional black-box tests:

- **Reject malformed**: stream with `WBITS = 0xff` raises
  `BrotliInvalidWindowBits`.
- **Reject large-window / reserved**: a stream that follows the large-window
  header path raises `BrotliLargeWindowNotSupported`; a reserved non-large
  window pattern raises `BrotliInvalidWindowBits`.
- **Reject non-zero padding**: stream with garbage in the trailing byte
  raises `BrotliInvalidPadding`.
- **Trailing data after ISLAST**: first verify the Google reference decoder's
  behavior for a valid Brotli payload followed by non-zero bytes (for example,
  `cat a.br b.br > c.br`). If the reference rejects it, fzip should raise a
  `FzipError` with the offset of the unexpected bytes; if the reference accepts
  it as unused trailing input, document that behavior and match it. Do not
  hard-code `BrotliReserved` before this check.
- **Reject truncation**: every prefix of every fixture, when decoded,
  raises `UnexpectedEOF` (loop over `1..data.length() - 1`).
- **Reject bomb**: a hand-built stream that claims `MLEN = 1 << 28` but
  provides minimal input, with `max_output_size = 1 << 16`, raises
  `InvalidZipData, msg="output exceeds max_output_size"`. Reuse the
  existing zip-bomb harness in `security_wbtest.mbt`.

White-box tests live next to the package they exercise, under
`src/common`, `src/decode`, and `src/encode`. They cover individual helpers
(bit reader, Huffman, transforms, dictionary access, and encoder internals).
Aim for each helper to have at least one happy-path test and one error-path
test per error code it can raise.

Run all of the following before opening the P1 PR:

```
moon check
moon test
moon test --filter "brotli*"
moon fmt
moon info
```

`moon info` should show a single bounded set of additions to
`pkg.generated.mbti`: the new public types (`UnbrotliOptions`,
`UnbrotliStream`), the new public functions (`unbrotli_sync`,
`UnbrotliOptions::default`, `UnbrotliStream::new`,
`UnbrotliStream::push`), plus the new `FzipErrorCode` variants. No existing
public symbol should change.

### Acceptance Criteria for P1

P1 is done when, in addition to the above:

- All fixtures in `src/tests/brotli_fixtures/` decode to their expected
  outputs.
- The full Brotli reference test suite (run separately, not embedded) at
  `refs/brotli/tests/testdata/` decodes without error using the manual
  harness under `tools/conformance/`. (Add the harness; do not enable
  it in regular CI yet — runs are expensive.)
- Cross-implementation validation passes:
  - Google `brotli --decompress` decodes every fixture that MoonBit embeds.
  - MoonBit `unbrotli_sync` decodes all `.compressed` files from
    `/Users/hustcer/iWork/refs/brotli/tests/testdata`.
  - At least one fixture that uses dictionary transforms is verified against
    both Google Brotli and rust-brotli's testdata.
- A 100 MB Silesia corpus, pre-compressed with the C reference at q=11,
  round-trips through `unbrotli_sync` and matches the original SHA-256.
- `moon test --filter "brotli*"` runs in under 5 seconds on the developer
  laptop.

## Meta-block Size Limits (apply to all encoder phases)

RFC §9.2 encodes meta-block size as `MNIBBLES = read(2) + 4` nibbles, where
`MNIBBLES` is 4, 5, 6, or 7 (i.e., `MLEN` is 16, 20, 24, or 28 bits). The
maximum payload per single meta-block is therefore `(1 << 28) - 1` ≈ 256 MB,
but the C reference uses a tighter operational cap of `1 << 24 = 16 MB` per
meta-block because its memory budgets assume that ceiling.

fzip follows the C reference: the encoder emits at most **16 MB** of input
per meta-block. Inputs larger than 16 MB are split across consecutive
meta-blocks, with `ISLAST` set only on the final one. Add a constant:

```mbt nocheck
///|
/// Operational cap on uncompressed bytes per Brotli meta-block. Matches the
/// C reference `MAX_METABLOCK_SIZE`.
const MAX_METABLOCK_BYTES : Int = 1 << 24
```

Encoder phases must:

- For inputs ≤ `MAX_METABLOCK_BYTES`: emit exactly one meta-block (P2's
  simple path).
- For larger inputs: emit `ceil(len / MAX_METABLOCK_BYTES)` consecutive
  meta-blocks. All but the last have `ISLAST = 0`; the last has
  `ISLAST = 1`. Each meta-block carries its own block-type tables and
  Huffman trees in the standard path; in the q=0 fast path it reuses the
  static literal table per meta-block.
- Reject inputs larger than `opts.max_input_size` before splitting.

## P2 — Encoder at q=0 and q=1 (Fast Path)

### Goal

Deliver `brotli_sync(data, options?)` and `BrotliStream` at quality levels 0
and 1. These map to the C reference's `compress_fragment.c` (q=0, single
pass) and `compress_fragment_two_pass.c` (q=1, two passes). They produce
valid Brotli streams that the P1 decoder can read; they do not achieve
state-of-the-art compression ratios.

The reason to ship q=0/1 before q=2+ is that the fast path is a self-
contained pipeline (~2,100 LOC of C) that does not require the full
back-references infrastructure, block splitter, or sophisticated entropy
encoding. It unlocks the "compress on the way out" use case (HTTP middleware,
log shippers) that benefits most from streaming.

### File Map (P2)

| MoonBit file                | LOC    | Mirrors                                                       | Role                                                                                            |
| --------------------------- | ------ | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `brotli_bit_writer.mbt`     | ~350   | `enc/brotli_bit_stream.c` (only the bit-write primitives)     | LSB-first bit writer with a growable `FixedArray[Byte]` backing buffer.                         |
| `brotli_encode_huffman.mbt` | ~400   | `enc/entropy_encode.c` (length-limited tree builder)          | Length-limited canonical Huffman tree construction; encode complex Huffman code-length headers. |
| `brotli_encode_fast.mbt`    | ~1,200 | `enc/compress_fragment.c`, `enc/compress_fragment_two_pass.c` | The q=0 and q=1 encoders. Includes their hash tables and command emission.                      |
| `brotli_encode.mbt`         | ~400   | `enc/encode.c` (the high-level wrapper)                       | Public entry point. Quality-based dispatch. Window-bits selection.                              |
| `brotli_encode_wbtest.mbt`  | ~300   | —                                                             | White-box tests for the bit writer and the fast paths.                                          |
| Extend `stream.mbt`         | ~120   | —                                                             | `BrotliStream` wrapper.                                                                         |
| Extend `types.mbt`          | ~40    | —                                                             | `BrotliOptions`, `BrotliMode` enum.                                                             |

### Encoder Public API

```mbt nocheck
///|
pub(all) enum BrotliMode {
  Generic
  Text
  Font
} derive(Eq, Show)

// `BrotliMode` only affects encoding (it selects context modes and tuning
// heuristics; see RFC §9.1). Brotli streams do not carry this value on the
// wire; the decoder ignores it. Document this explicitly in the doc-comment.

///|
pub(all) struct BrotliOptions {
  /// 0..=11. P2 supports 0 and 1 only; higher values raise until P3/P4 land.
  quality : Int
  /// 10..=24. Selects LZ77 window size = 1 << window_bits.
  window_bits : Int
  /// Selects encoder mode. See RFC §9.1.
  mode : BrotliMode
  /// Maximum input bytes accepted by a single sync call.
  max_input_size : Int
}

///|
pub fn BrotliOptions::default() -> BrotliOptions {
  // Brotli's reference default is q=11 (best compression). fzip stages the
  // default to track what is actually implemented:
  //   - After P2 lands: default stays at quality 1 (highest supported).
  //   - After P3 lands: default moves to 9 (best non-Zopfli).
  //   - After P4 lands: default moves to 11, matching the C reference.
  // Each transition is a public behavior change; call it out in CHANGELOG.md
  // and bump fzip's minor version. Callers who want stability should pin
  // `quality` explicitly.
  {
    quality: 1,
    window_bits: 22,
    mode: Generic,
    max_input_size: default_max_input_size,
  }
}

///|
pub fn brotli_sync(
  data : FixedArray[Byte],
  opts? : BrotliOptions = BrotliOptions::default(),
) -> FixedArray[Byte] raise FzipError
```

`brotli_sync` validates options, picks the encoder backend, runs it to
completion on the whole `data` buffer, and returns the output. For P2, the
backend dispatch is:

```mbt nocheck
if data.length() > opts.max_input_size {
  raise fzip_err(InvalidZipData, msg="input exceeds max_input_size")
}
match opts.quality {
  0 => encode_fast_one_pass(data, opts.window_bits, opts.mode)
  1 => encode_fast_two_pass(data, opts.window_bits, opts.mode)
  q if q >= 2 && q <= 11 =>
    raise fzip_err(InvalidZipData, msg="quality \{q} requires phase P3")
  _ => raise fzip_err(InvalidZipData, msg="quality must be 0..=11")
}
```

### Bit Writer (`brotli_bit_writer.mbt`)

Symmetric to the bit reader. Maintain a 32-bit accumulator and a write
position. On overflow, drain into the output `FixedArray[Byte]`. Grow the
buffer geometrically. Provide:

- `write_bits(value : UInt, n : Int)`
- `write_single_bit(b : Bool)`
- `align_to_byte()` — pads with zero bits up to a byte boundary.
- `write_bytes(src : FixedArray[Byte], src_offset : Int, length : Int)` —
  only valid when aligned.
- `finish() -> FixedArray[Byte]` — flushes the accumulator (with zero
  padding) and returns the result trimmed to the exact byte count used.

White-box tests must cover round-trip equivalence with `brotli_bit_reader`:
write a known bit pattern, read it back, assert equality. This is the most
valuable test in this module.

### q=0 Encoder (`encode_fast_one_pass`)

The C implementation:

1. Scans the input once. At each byte, it computes a 4-byte hash and looks
   it up in a small (4 KB to 64 KB depending on input size) hash table.
2. On a match of length ≥ 4 bytes, emits an insert-and-copy command for the
   literal bytes since the last match plus this match.
3. On no match, advances by one byte and updates the hash.
4. At the end, emits a final command for any trailing literals.

Use a fixed Huffman code for q=0 (the C code calls it the "static literal
table") to avoid building entropy models. The static table is defined in
`compress_fragment.c`; port it verbatim into a `FixedArray[UInt16]`.

Meta-block format: a single uncompressed-or-compressed meta-block per call
when `data.length() <= MAX_METABLOCK_BYTES`; otherwise multiple meta-blocks
per the "Meta-block Size Limits" rule above. P2 `BrotliStream` buffers until
the final push, matching `DeflateStream`.

### q=1 Encoder (`encode_fast_two_pass`)

Two passes:

1. **Pass 1**: scan, build a small dynamic literal Huffman tree and a
   distance code tree based on observed frequencies.
2. **Pass 2**: emit commands using the trees from pass 1.

Two passes cost more CPU but compress noticeably better than q=0 on text
inputs. Implementation tip: keep the command list from pass 1 as a
`FixedArray[UInt]` of packed commands and re-scan it in pass 2 — do not
re-scan the input.

### `BrotliStream` (in `stream.mbt`)

Mirror the current `DeflateStream`: buffer input chunks, call
`brotli_sync(data, opts=self.opts)` when `final_=true`, emit a single final
callback, and clear the buffer. True incremental Brotli encoding can be added
later with a new internal encoder state and explicit flush semantics, but it is
not part of P2.

### Acceptance Criteria for P2

- `brotli_sync(data, options={quality: 0, ...})` produces output decoded
  correctly by `unbrotli_sync` for the full Silesia corpus.
- Same with `quality: 1`.
- Every stream produced by MoonBit at q=0 and q=1 is also decoded by the
  Google reference CLI and matches the original input. This is required; a
  MoonBit-only round trip can hide matching encoder/decoder bugs.
- At least 100 Google-reference q=0/q=1 compressed samples are decoded by
  MoonBit and round-trip to the original inputs.
- A round-trip property test: for random byte arrays of length 1, 2, 4,
  100, 10_000, and 1_000_000, `unbrotli_sync(brotli_sync(data))` equals
  `data`. Run for 1,000 random seeds.
- Output is byte-for-byte deterministic for a given input and options.
- Compression ratio benchmark: on `silesia.tar`, q=0 achieves ≥ 1.6:1 and
  q=1 achieves ≥ 2.0:1. (The C reference achieves 1.65:1 and 2.10:1
  respectively. Hitting within 5% is acceptable.)
- `moon test --filter "brotli*"` continues to run in under 10 seconds.

## P3 — Encoder at q=2 through q=9 (Standard Back-References)

### Goal

Match the C reference's q=2..9 compression ratios within 5% per quality
level. This requires the full back-references infrastructure: a configurable
hash chain, block splitter, context-mode selection, and adaptive Huffman
tree construction per meta-block.

### Major Subsystems Added in P3

| Subsystem              | C file(s)                                                                                               | MoonBit file                  | LOC    |
| ---------------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------- | ------ |
| Hash chains            | `enc/hash.h`, `enc/hash_longest_match*.h`, `enc/hash_composite_inc.h`, `enc/hash_forgetful_chain_inc.h` | `brotli_encode_hash.mbt`      | ~1,000 |
| Back-references search | `enc/backward_references.c`                                                                             | `brotli_encode_backref.mbt`   | ~700   |
| Block splitter         | `enc/block_splitter.c`, `enc/block_splitter_inc.h`                                                      | `brotli_encode_blocks.mbt`    | ~800   |
| Metablock construction | `enc/metablock.c`                                                                                       | `brotli_encode_metablock.mbt` | ~700   |
| Histogram / clustering | `enc/cluster.c`, `enc/cluster_inc.h`, `enc/histogram.c`                                                 | `brotli_encode_histogram.mbt` | ~800   |
| Quality-aware dispatch | `enc/quality.h`, `enc/encode.c` (already partially in P2)                                               | extend `brotli_encode.mbt`    | ~200   |

The C reference's hash variants (`hash_longest_match`,
`hash_longest_match_quickly`, `hash_composite`, `hash_forgetful_chain`) are
selected per quality level. Port all four; gate by quality in dispatch.

### Implementation Notes (P3)

- Brotli's hash chain is keyed by 4-byte hashes (and 8-byte hashes at higher
  qualities). The C reference uses `kHashMul32`/`kHashMul64`; port these
  constants verbatim.
- The block splitter assigns each token (literal, command, distance) to one
  of up to 256 block types. Implement the dynamic programming form from
  `block_splitter.c` (it is the only correct one; the heuristic in
  `block_splitter_inc.h` is its inner loop).
- The histogram clustering step uses Lloyd's algorithm to merge histograms
  with low KL divergence. Port `cluster.c` verbatim; this is one of the few
  numerical algorithms where a "clever" rewrite is likely to produce
  subtly worse output.
- The C reference uses `double` for entropy estimates. MoonBit `Double`
  matches IEEE 754 `double`; results should be bit-exact. If they are not,
  inspect `log2(0)` handling (the C code uses `FastLog2` from `fast_log.h`
  — port this lookup table for performance and exactness).

### Encoder Static-Dictionary Hash Table

The encoder needs a hash table mapping 5- to 24-byte prefixes of the static
dictionary back to `(word_id, word_length, transform_id)` triples. The C
reference materializes this as a pre-computed table in
`enc/dictionary_hash.c` / `enc/static_dict_lut*.c`: roughly **6,000 lines of
data** describing ~31,700 hash buckets.

Two embedding options, mirroring the P1 dictionary discussion:

**Option H1: Pre-compute at startup from the raw dictionary.** On the first
`brotli_sync` call with `quality >= 5`, walk the materialized static
dictionary (already cached from P1) and build the hash table in memory.
Cost: ~30-50 ms one-time on commodity hardware. Memory: ~256 KB.

**Option H2: Embed the C-generated tables as compressed data.** Run a
generator script over `enc/dictionary_hash.c` to extract the bucket layout,
DEFLATE-compress it (~80-100 KB compressed), embed as a `FixedArray[Byte]`
literal, and decompress at first use. Cost: ~10 ms first-use. Memory: same
~256 KB.

**Decision for P3: Option H1.** Reasons:

- Avoids embedding a second large generated data blob; the runtime cost is
  amortized over the first `brotli_sync` call at q≥5.
- The construction algorithm is small (~100 LOC) and matches the C
  reference's `BuildHashTable` helper.
- The table is per-process, not per-call, so the one-time cost happens once
  per binary load.

Layout:

```mbt nocheck
///|
priv struct DictHashEntry {
  word_id : UInt
  word_length : Byte
  transform_id : Byte
}

///|
let dict_hash_cache : Ref[FixedArray[DictHashEntry]?] = { val: None }

///|
fn brotli_encoder_dict_hash() -> FixedArray[DictHashEntry] raise FzipError {
  match dict_hash_cache.val {
    Some(table) => table
    None => {
      let dict = brotli_static_dictionary()
      let table = build_encoder_dict_hash(dict)
      dict_hash_cache.val = Some(table)
      table
    }
  }
}
```

Place this in a new `brotli_encode_dict_hash.mbt` (~250 LOC) added in P3.

Required tests:

- The table is deterministic: two calls return identical buckets.
- A handful of known prefixes (e.g., `" the "`, `" and "`) resolve to the
  expected `word_id` per RFC §8. Verify against output from the C
  reference's `BrotliCompressBufferQuality` with a dictionary-heavy input.

### Testing (P3)

Extend the random-input round-trip test to all quality levels q=0..9. Add a
dedicated benchmark suite at `src/benchmarks/brotli/` that measures:

- Compression ratio per quality level on a fixed corpus.
- Encode time per quality level.
- Memory peak per quality level.

Track these in `docs/brotli_benchmarks.md` (created in P3); regressions in
ratio > 1% or in time > 10% relative to the previous commit fail review.

### Acceptance Criteria for P3

- All q=0..9 produce streams that decode correctly via `unbrotli_sync`.
- All q=2..9 streams produced by MoonBit are accepted by the Google reference
  decoder and match the original input.
- Compression ratio is within 5% of the C reference per quality on the
  Silesia corpus.
- Encode time at q=5 is within 3× of the C reference (MoonBit overhead is
  acceptable; SIMD-less code cannot match a vectorized C reference, but 3×
  is a reasonable ceiling).

## P4 — Encoder at q=10 and q=11 (Zopfli Search)

### Goal

Match the C reference's q=10 and q=11 compression ratios within 2%. q=10
and q=11 use a near-optimal back-reference search (Zopfli-style) that runs
~10× slower than q=9 but compresses noticeably better, especially on text.

### Scope

The q=10/11 path lives in `backward_references_hq.c`. It maintains a
binary tree of suffixes (`hash_to_binary_tree_inc.h`) and runs a forward-
backward dynamic programming pass to choose the optimal sequence of
literal/copy commands.

| MoonBit file                    | LOC    | Mirrors                         |
| ------------------------------- | ------ | ------------------------------- |
| `brotli_encode_zopfli.mbt`      | ~1,500 | `enc/backward_references_hq.c`  |
| `brotli_encode_suffix_tree.mbt` | ~700   | `enc/hash_to_binary_tree_inc.h` |
| Extend `brotli_encode.mbt`      | ~50    | quality dispatch                |

### Implementation Notes (P4)

- The suffix tree uses left/right child pointers indexed into a single
  `FixedArray[Int]`. The C reference uses `uint32_t` for indices; MoonBit
  `Int` is 64-bit on native and effectively 32-bit on JS / wasm-gc. Use
  `Int` for indices, but do not allocate a blanket `1 << 27`-entry tree on
  32-bit-style backends. Derive the suffix-tree bound from the validated input
  length and `opts.max_input_size`, then reject early if the required arrays
  would exceed a backend-safe memory budget. A conservative first cap is
  64 MiB of suffix-tree storage on JS / wasm-gc and 512 MiB on native; refine
  with measurements before P4 lands.
- The Zopfli loop is forward-backward: a forward pass builds a cost map,
  then a backward pass traces the optimal command sequence. The cost
  function is a sum of per-symbol bit costs based on the histogram
  estimated from a preliminary pass. The C reference iterates up to four
  rounds; for P4, match that count.
- Memory is the main risk at q=11. The suffix tree can consume 8× the input
  size. Cap input size for q=10/11 in `BrotliOptions` validation at
  `min(max_input_size, 256 << 20)` and document the limit.

### Acceptance Criteria for P4

- q=10/11 produce streams that decode correctly.
- q=10/11 streams produced by MoonBit are accepted by the Google reference
  decoder and match the original input.
- Ratio within 2% of the C reference on Silesia.
- Encode time within 5× of the C reference.
- Memory peak within 2× of the C reference.

## Cross-Phase Concerns

### Performance Budget

MoonBit lacks SIMD, so per-byte costs are inherently higher than C. The
expected slowdown factors on the wasm-gc backend, validated by the existing
DEFLATE/Inflate benchmarks:

- Decode: 2.5× to 4× slower than C.
- Encode: 3× to 6× slower than C, quality-dependent.

These are the budgets used in acceptance criteria above. Native backend may
be faster; do not rely on it for compliance.

Hot-path conventions:

- Lift array-length and field reads out of inner loops.
- Use `UInt` for shifts and masks; convert to `Int` only at array indices.
- Avoid `Option[T]` in inner loops; prefer sentinel values or
  pre-initialization.
- Avoid creating short-lived `FixedArray` instances; reuse arenas.

### Security

- All public entry points respect `max_input_size` and `max_output_size`.
- Trailing padding bits are validated for zero (RFC §9.2).
- Output ring buffer is sized to exactly `1 << window_bits`. Never grow
  beyond that.
- Bounds-check every array access against an explicit length. MoonBit will
  raise on out-of-bounds, but we want a `FzipError` with context instead
  of an opaque crash — guard with explicit `if` checks at format
  boundaries (meta-block length, code-length count, etc.).
- Reject unsupported feature paths early, before large allocation. This applies
  directly to large-window streams. Shared / compound dictionaries are a
  future public-API feature rather than something ordinary Brotli streams
  self-describe; keep `BrotliDictionaryNotSupported` reserved for that future
  API surface.

### Error Recovery

- The decoder makes no guarantees about partial output after a failed
  decode. The caller should discard any partial output on `raise`.
- The encoder is one-shot per `brotli_sync` call; no partial output is
  exposed on failure. P2 `BrotliStream` buffers like `DeflateStream`, so its
  callback is only invoked after a successful final encode.

### Fuzz Strategy

A dedicated fuzz harness reduces the risk of correctness bugs that escape
the curated test corpus.

**Timing**: Establish the harness during P1, gate P3 entry on **24 hours of
clean fuzzing**, and rerun after every encoder phase.

**Harness layout**:

- `tools/fuzz/main.mbt` — a MoonBit binary that consumes random byte
  arrays from stdin (one per line, hex-encoded for portability) or from a
  corpus directory. For each input, calls `unbrotli_sync` and asserts it
  either returns or raises a `FzipError` — **never** panics out of MoonBit
  bounds or arithmetic.
- `tools/fuzz/corpus/` — seeded with the same fixtures used by tests
  plus 1,000 random mutations generated by a small driver
  (`tools/gen_brotli_fuzz_corpus.mbt`). Mutation strategies: bit flips,
  byte deletes, byte inserts, header truncation.
- `tools/fuzz/roundtrip.mbt` — for encoder phases (P2+): random input
  bytes → `brotli_sync` → `unbrotli_sync` → assert equality. This catches
  the most common encoder bug class.

**Stop criteria**:

- No new crashes for 24 hours of continuous fuzzing on a single laptop core.
- No deviation between MoonBit `unbrotli_sync` output and Google C reference
  decoder output on any fuzz input.

**CI integration**: do **not** run the fuzz harness in regular CI; it is too
expensive. Run on a nightly schedule, with seeded inputs from
`tools/fuzz/corpus/` plus 60 minutes of fresh random mutations. Alert
on any new crash signature.

This section supersedes the offhand "fuzz harness in P1.5" reference in the
Risk Register.

### Backwards Compatibility

- `unbrotli_sync` and `brotli_sync` are new public symbols; they cannot
  break existing code.
- Adding variants to `FzipErrorCode` is technically a breaking change for
  exhaustive matches. Existing callers in the wild typically catch the
  whole `FzipError` and inspect the code — match this idiom in
  documentation. Note the change in `CHANGELOG.md` at each phase.
- `pkg.generated.mbti` is regenerated and committed at the end of every
  phase; review the diff carefully.

## Risk Register

| Risk                                              | Probability | Impact | Mitigation                                                                                           |
| ------------------------------------------------- | ----------- | ------ | ---------------------------------------------------------------------------------------------------- |
| Static dictionary embedding bloats source tree    | Low         | Low    | Choose Option C (Zlib-wrapped compressed embed).                                                     |
| Bit reader performance is the bottleneck          | High        | Medium | Maintain 32-bit accumulator; pre-refill in command loop; benchmark every phase.                      |
| Huffman table memory exceeds expectations         | Medium      | Medium | Pre-size arena at construction; arena exceeds the C reference's `HUFFMAN_TABLE_SIZE`.                |
| State-machine bug surfaces only on rare RFC paths | High        | High   | Run the full reference test corpus; gate P3 entry on the dedicated fuzz harness (see Fuzz Strategy). |
| Encoder ratios fall short of acceptance           | Medium      | Medium | Port C reference verbatim; resist "clever" rewrites in clustering and entropy modules.               |
| Zopfli memory use blows out on large inputs       | Medium      | Low    | Document the input-size cap in `BrotliOptions`; reject early.                                        |

## Glossary

- **Meta-block**: A self-contained Brotli sub-stream with its own header,
  Huffman trees, and command sequence.
- **Insert-and-copy**: A single command encoding both a literal run (the
  insert) and a back-reference (the copy).
- **Distance ring buffer**: The four most recently used distances, used
  for short-encoded back-references.
- **NPOSTFIX / NDIRECT**: Two distance-encoding parameters in the
  meta-block header that shift the boundary between direct and computed
  distances.
- **Block type / block-switch**: Brotli partitions each stream (literals,
  insert-and-copy, distances) into block types with their own Huffman
  trees; block-switch tokens advance the current block type.
- **Context mode**: For literal streams, the conditioning rule (e.g.,
  Lutmsb6, Lutsb6) that selects a Huffman tree based on the previous one
  or two bytes.
- **Transform**: A modification (prefix, case-change, suffix) applied to a
  static-dictionary word before insertion.

## Hand-off Checklist (Per Phase)

Before considering a phase complete:

1. `moon check` clean.
2. `moon test` clean (all suites).
3. `moon test --filter "brotli*"` runs in budget (see acceptance criteria).
4. `moon fmt` produces no diff.
5. `moon info` regenerated; `src/pkg.generated.mbti` reviewed.
6. New error codes documented in `src/error.mbt` and the body of this doc.
7. New fixtures committed to `src/tests/brotli_fixtures/`.
8. CHANGELOG entry under the appropriate version.
9. Benchmark suite updated (P3 onward).
10. Tag the commit with a milestone marker (e.g., `brotli-p1-decoder`).

# CHANGELOG

All notable changes to this project will be documented in this file.

## v0.1.0

### Added

- Brotli compression and decompression support (RFC 7932).
  - `unbrotli_sync(data, opts?)` and `UnbrotliStream` decode any RFC 7932
    Brotli stream, including the full upstream conformance corpus (22 fixtures)
    and 100 MiB Silesia q=11 acceptance.
  - `brotli_sync(data, opts?)` and `BrotliStream` produce RFC 7932 streams at
    quality levels 0 through 11. q9 enables the mixed-dictionary candidate
    alongside hash-chain matches; q10/q11 deepen the high-quality parser and
    add static dictionary words from the identity, same-length, and trailing
    space transform sets. Every quality level decodes back through Google's
    reference `brotli` CLI.
  - New error codes: `BrotliInvalidWindowBits`, `BrotliInvalidMetablock`,
    `BrotliInvalidHuffman`, `BrotliInvalidContextMap`, `BrotliInvalidDistance`,
    `BrotliInvalidTransform`, `BrotliDictionaryNotSupported`,
    `BrotliLargeWindowNotSupported`, `BrotliReserved`, `BrotliInvalidPadding`.
  - Options structs `UnbrotliOptions` (with `out`, `max_output_size`,
    `max_input_size`) and `BrotliOptions` (with `quality`, `window_bits`,
    `max_input_size`), each with `::default()` constructors.
- Split public imports into `hustcer/fbr/decode`, `hustcer/fbr/encode`, and
  the root `hustcer/fbr` facade so users can choose decode-only, encode-only,
  or combined APIs.
- Static RFC dictionary embedded as chunked bytes and copied into the
  `FixedArray[Byte]` used by the codec.
- Tools under `tools/brotli/`:
  - `tools/brotli/bench/ratio.nu`, `tools/brotli/bench/chunk-match.nu`, and
    `tools/brotli/bench/target-perf.nu` for ratio, density, and wasm-gc/native
    encode/decode benchmarks.
  - `tools/brotli/conformance/run.nu` for the upstream Google Brotli test
    corpus.
  - `tools/brotli/fuzz/gen-corpus.nu` and `tools/brotli/fuzz/run.nu` for
    short fuzz runs against the decoder.
  - `tools/brotli/encode/verify.nu` and `tools/brotli/silesia/verify.nu` for
    Google CLI cross-validation.

### Performance

- Changed the Brotli static dictionary representation from a single large
  `FixedArray[Byte]` literal to chunked `Bytes` copied into the same public
  `FixedArray[Byte]` value. This preserves the dictionary data and avoids
  per-byte wasm-gc initialization code for the large literal.
- Brotli chunked q3+ encoding now carries the selected candidate's
  recent-distance cache and the previous two decoded bytes into following
  meta-blocks. This fixes multi-meta-block compressed streams whose
  UTF-8 literal-context trees or short-distance codes depended on decoder
  state from the previous chunk. External Google Brotli validation now passes
  on `silesia-2m.bin` q3/q5/q9.
- Brotli q9 now uses a 2 MiB standard chunk, letting high-quality LZ77 and
  mixed-dictionary candidates cost matches and literal contexts across the
  previous 1 MiB boundary. On 2 MiB Silesia, q9 improves from 542,335 to
  535,421 bytes versus Google q9's 511,433 bytes, reducing overhead from
  6.04% to 4.69%. Sampled 64 KiB target-perf remains 21,514 bytes versus
  Google q9's 22,063 bytes, with wasm-gc/native encode at 523.417/89.076 ms.
- Brotli q2 uses the same 2 MiB chunk strategy with a proportional natural
  parser command budget. On 2 MiB Silesia, q2 improves from 693,243 to
  652,695 bytes versus Google q2's 637,343 bytes, reducing overhead from
  8.77% to 2.41%. Sampled 64 KiB target-perf remains 25,245 bytes versus
  Google q2's 24,364 bytes, with wasm-gc/native encode at 480.975/75.117 ms.
- Brotli q3 through q8 now also use 2 MiB chunks, with natural/intermediate
  parser command budgets scaled only for chunks larger than 1 MiB. On 2 MiB
  Silesia, q3/q4 beat Google by 0.94%/0.43%, and q5/q6/q7/q8 are within
  1.99%/4.20%/3.38%/4.47% of Google. Sampled q8 64 KiB target-perf keeps
  output at 22,261 bytes and records wasm-gc/native encode at
  524.749/112.349 ms.
- Brotli q4 through q8 now exact-cost an intermediate hash-chain candidate
  between the q2/q3 fast path and the q9 high-quality path. On 1 MiB Silesia,
  q4 improves from 313,577 to 287,092 bytes, q5/q6 to 278,961 bytes, and
  q7/q8 to 273,633 bytes, bringing all measured q4..q8 outputs inside the
  5% P3 ratio window. Sampled 64 KiB target-perf: q5 native is 110.135 ms
  versus Google q5 43.496 ms (2.53x), with output 22,336 versus 22,271 bytes.
- Brotli q6/q7 skip the intermediate 4-byte hash candidate on inputs up to
  64 KiB while retaining it for larger chunks. Sampled 64 KiB target-perf
  improves q6 native encode from 143.404 to 126.045 ms and q7 native encode
  from 153.878 to 139.976 ms while keeping 1 MiB Silesia output unchanged.
- Brotli q5 skips the redundant natural 4-byte hash candidate while retaining
  the intermediate 4-byte candidate that wins the accepted stream. Sampled
  64 KiB target-perf keeps output at 22,336 bytes and improves native encode
  from 142.394 to 94.185 ms and wasm-gc encode from 541.752 to 524.160 ms.
- Brotli q4+ now exact-costs a command-block histogram split candidate when
  command symbols differ enough across the command stream. Silesia 128 KiB
  q5/q9 output remains stable at 40,328/39,081 bytes, and sampled 64 KiB
  target-perf records q5 wasm-gc/native encode at 81.122/52.656 ms and q9 at
  77.966/45.555 ms.
- Brotli q4+ now exact-costs a distance-block histogram split candidate when
  explicit distance symbols differ enough across the distance stream. Silesia
  128 KiB q5/q9 output remains stable at 40,328/39,081 bytes, and sampled
  64 KiB target-perf records q5 wasm-gc/native encode at 82.182/53.730 ms and
  q9 at 79.780/47.608 ms.
- Brotli q9 ratio improved by enabling the mixed-dictionary candidate. On
  Silesia, q9 1 MiB falls from 273,633 to 271,776 bytes (overhead vs Google
  q9 263,791 reduced from 3.73% to 3.03%), q9 128 KiB falls from 40,013 to
  39,081 bytes (-1.55% vs Google 39,695), and q9 64 KiB falls from 22,261
  to 21,514 bytes (-2.49% vs Google 22,063). Encode time on q9 64 KiB rises
  from 140.583 to 161.436 ms (wasm-gc) and 60.651 to 77.168 ms (native).
- Brotli decoder back-reference output copying uses fast paths for distance=1
  non-overlapping copies, and overlapping periodic copies; command symbol info
  is precomputed to remove per-symbol prefix-offset loops from decode and
  encode command handling.
- Brotli q10/q11 heuristic optimization is paused at a documented release
  checkpoint. The current streams are valid and externally decodable, but the
  documented 2% P4 ratio target still requires a real bounded
  shortest-path/Zopfli backend or an explicit release exception.
- Brotli q10/q11 now exact-cost a bounded small-input shortest-path seed
  candidate for inputs up to 32 KiB. The candidate uses a bounded DP over
  hash-chain matches and is selected only when the final written meta-block is
  smaller than the existing high-quality and mixed-dictionary candidates.
- The q10/q11 bounded shortest-path seed now enumerates multiple hash-chain
  matches per input position before the bounded DP chooses copy transitions,
  making the candidate graph closer to the planned Zopfli parser while keeping
  the same 32 KiB cap and exact-cost final selection.
- The same bounded q10/q11 seed now propagates the selected path's
  recent-distance cache through DP states and uses that cache for match
  enumeration and short-distance copy-cost estimates.
- The q10/q11 bounded seed now keeps a two-state beam at each input position,
  retaining a second low-cost parser state with its own recent-distance cache
  and traceback.
- The q10/q11 bounded seed initializes its lightweight parser cost model from
  the current greedy LZ77 command stream, using observed literal and distance
  histograms to estimate transition costs before exact-cost selection.
- The q10/q11 bounded seed now also uses a bounded suffix binary-tree match
  source, giving the small-input shortest-path candidate a first suffix-tree
  style match provider alongside the existing hash-chain matches.
- The q10/q11 bounded seed now shares one bounded-copy transition helper for
  hash-chain and suffix-tree matches, keeping recent-distance-cache updates and
  beam insertion behavior aligned for future P4 parser work.
- The q4+ LZ77 meta-block writer now exact-costs a combined command-block plus
  distance-block split candidate when both histogram estimators find useful
  independent boundaries, extending P3 block-clustering coverage beyond
  single-dimension split candidates.
- The q4+ writer also exact-costs a combined literal-block plus command-block
  split candidate with independent literal-event and command-event boundaries,
  giving the P3 block-layout search a second accepted multi-stream clustering
  shape.
- The q4+ writer now has the remaining combined literal-block plus
  distance-block split candidate as well, completing pairwise literal,
  command, and distance block-layout coverage without enabling the rejected
  three-stream joint split.

### Tests and docs

- New `docs/brotli.md` planning document with phased delivery details.
- New `docs/brotli_benchmarks.md` recording every accepted size/time delta
  for the Brotli encoder/decoder.
- In-package tests cover Brotli decoder helpers, transforms, fixtures,
  roundtrips, q0..q11 end-to-end, stream chunking, and security limits across
  `wasm`, `wasm-gc`, `js`, and `native`.
- Brotli release-validation checkpoint recorded: q0/q1 2 MiB stored streams
  pass external Google Brotli decode, q2..q9 2 MiB Silesia outputs stay within
  the 5% P3 window, q10/q11 remain valid with a documented P4 ratio exception,
  22 upstream conformance fixtures pass, and the 25-input local fuzz gate
  passes.
- Brotli fuzz runner now batches generated white-box tests. The 25-input local
  gate drops from 54.73s to 2.19s on this machine, and the current 58-input
  corpus completes in 7.00s, making broader release validation practical.
- Brotli fuzz runner accepts `--target`, so the same generated corpus can now
  be checked on `native`, `wasm-gc`, `js`, or `all` targets during release
  validation.
- Added `tools/brotli/fuzz/roundtrip.nu`, a deterministic encoder fuzz harness
  that checks random byte inputs through `brotli_sync` -> `unbrotli_sync` for
  selected quality levels and MoonBit backends.
- Brotli fuzz harness locks now record an owner PID and automatically recover
  stale locks left by interrupted local validation runs.
- Added `tools/brotli/release/validate.nu` to run the practical Brotli release
  validation gate from one Nushell command.
- Added `docs/brotli_release_report.md` with the current Brotli release
  readiness summary, validation evidence, and accepted P4 ratio exception.
- Added Justfile entries for the full, smoke, and package-only Brotli release
  validation gates, and added package verification to the release runner.
- Added `tools/brotli/fuzz/soak.nu` plus Justfile entries for the scripted
  Brotli long fuzz soak gate.
- Made Brotli fuzz corpus generation deterministic with `--seed` and
  `--corpus-dir` options for reproducible release-validation corpora.
- Added a generated deterministic Brotli fuzz corpus path to the practical
  release validation runner and Justfile.
- Recorded broader Brotli release fuzz validation evidence for the generated
  corpus gate and bounded soak runner.
- Added a phase-by-phase Brotli release audit that separates stream-valid
  release readiness from incomplete P3/P4 algorithm targets.
- Added a bounded full-corpus Brotli fuzz soak Justfile entry for repeatable
  finite release-validation runs.
- Accepted the q10/q11 Brotli P4 ratio exception for the current
  Brotli-capable release candidate while keeping P4 marked incomplete.
- Added aggregate Brotli release-candidate Justfile entries for full and smoke
  release-validation gate sets.
- Recorded a full `just release-candidate` pass covering the practical
  release gate, generated corpus gate, and bounded full-corpus soak.
- Brotli soak runner now accepts `--append-log` so interrupted or segmented
  long fuzz soaks can preserve existing JSONL evidence and continue iteration
  numbering.
- Added direct Justfile recipes for Brotli conformance, decoder fuzz, encoder
  roundtrip fuzz, ratio checks, and wasm-gc/native target-perf, and simplified
  generated-test batch runners with Nushell `generate` pipelines.
- Brotli conformance, decoder fuzz, and encoder roundtrip fuzz harnesses now
  restore ignored placeholder white-box test files instead of deleting the
  generated source path, avoiding stale `_build` missing-input failures in
  subsequent incremental MoonBit commands.
- Brotli conformance and target-perf harnesses now use the same owner-PID
  stale-lock recovery as the fuzz runners; target-perf also uses a stable
  ignored placeholder white-box test path.
- `tools/brotli/size/verify.nu` now builds decode-only, encode-only, and full
  temporary applications. It scans JS artifacts for opposite-side package
  markers and can also report wasm-gc artifact sizes.
- Updated `README.md` to document the leaf package imports, root facade, and
  wasm-gc dictionary representation.

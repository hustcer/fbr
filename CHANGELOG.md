# CHANGELOG

All notable changes to this project will be documented in this file.

## v0.8.1

### Changed

- Migrated the module manifest from `moon.mod.json` to `moon.mod` and updated
  the codebase for the current MoonBit formatter and checker without changing
  the public API.
- Enabled the bounded optimal-parse pass for q11 chunks up to 1 MiB. On the
  measured Silesia inputs, q11 output decreased from 21,302 to 20,904 bytes at
  64 KiB and from 264,341 to 256,952 bytes at 1 MiB, with higher encode time.

### Performance

- Reduced q2 encode time by 11.3% on native and 13.4% on wasm-gc for the
  measured 64 KiB input, with encoded size unchanged.
- Adjusted recent-distance probing for q4-q8. Across the measured 64 KiB and
  128 KiB rows, aggregate encode time decreased by 10.6% and aggregate encoded
  size increased by 0.116%.

### Tools and docs

- Updated the release benchmark report and checked-in benchmark data.
- Fixed the release validation script for Nushell 0.114 strict return-type
  checking by returning elapsed milliseconds as an integer.

## v0.8.0

### Changed

- Changed Brotli q0/q1 encoding from stored-only meta-blocks to compressed
  low-quality streams.
- Tuned q0/q1 low-quality search and writer selection for a practical
  speed/size balance while keeping the measured q2 guard rows unchanged.

### Performance

- On the Silesia 64 KiB and 128 KiB benchmark slices, q0/q1 encoded sizes are
  now within +2.38% of Google Brotli in the measured rows.
- In the same target-perf runs, q0 native encode min time was 3.95 ms versus
  Google Brotli 4.21 ms on 64 KiB; q1 native encode min time was 4.85 ms
  versus Google Brotli 4.30 ms on 64 KiB.

## v0.7.1

### Performance

- Widened the Brotli decoder bit-reader accumulator to 64 bits so a 4-byte
  refill can be appended without discarding remaining buffered bits. Same-time
  `decode-compare` validation passed across the checked `wasm-gc` and native
  rows, with an aggregate decode improvement of about 1.1% in that run.

### Compatibility

- Updated internal checked-error handling and tests for `moonc` v0.10.0
  warnings without changing the public API.

### Tools and docs

- Removed the native benchmark `cc-o0` compiler workaround now that default
  native release builds complete reliably with the current MoonBit toolchain.
- Changed the benchmark report and decode comparison defaults to
  `--repeats 20`, and documented that MoonBit timings amortize one `moon run`
  process startup across repeats.
- Regenerated `docs/brotli_release_report.md` and the checked-in current
  benchmark JSONL files with the updated harness.

## v0.7.0

### Changed

- `UnbrotliStream` now decodes incrementally: it emits output through `ondata`
  as complete Brotli meta-blocks become available (intermediate calls report
  `is_final=false`), instead of buffering all input and emitting once on the
  final `push`. Consumers that assumed a single `ondata` call with the whole
  result must now concatenate the emitted chunks.
- `UnbrotliStream` now ignores `UnbrotliOptions.out`; streaming output is
  delivered only through `ondata`. One-shot `unbrotli_sync` still honors `out`.
- `UnbrotliStream::push` now rejects non-empty input pushed after the stream has
  finished.

### Added

- `BrotliDistanceRing::clone` in the `common` package, used by the streaming
  decoder to speculatively decode a meta-block and roll back on short input.

### Tests

- Added `UnbrotliStream` coverage: output equivalence against one-shot
  `unbrotli_sync` across every input split point, byte-at-a-time decoding,
  `max_input_size` enforcement, post-finish rejection, the empty-input final
  marker, and truncated-input errors.
- Added white-box coverage for `common`, `decode`, and `encode` helpers.

### Tools and docs

- Documented the `UnbrotliStream` streaming trade-offs in the README: output is
  retained for the stream lifetime (memory is not window-bounded), each `push`
  may re-decode the in-progress meta-block, and `out` is ignored.
- Reworked the coverage-analysis script (`tools/analyze-coverage.nu`) and
  `COVERAGE_ANALYSIS.md`.

## v0.6.0

### Performance

- Adjusted Brotli encoder candidate gating for quality levels 3 through 11.
  The current selection keeps intermediate LZ77 candidates for q4-q8, narrows
  four-byte high-quality and mixed-dictionary candidates to q10/q11, and avoids
  several q3/q9 candidate passes that were recorded as rejected trials.
- In the regenerated `just bench` report, q3 encode min timings improve by
  1.78x-2.49x versus v0.5.0 on the Silesia 64 KiB and 128 KiB inputs. The q3
  output size increases by 3.3% on 64 KiB and 4.2% on 128 KiB.
- The same report shows q9 encode min timings improving by 1.57x-3.48x. The
  64 KiB q9 output is unchanged; the 128 KiB q9 output grows from 38,926 to
  40,207 bytes, changing its Google-size delta from -1.46% to +1.78%.
- q10 and q11 encode min timings improve by 1.33x-1.54x with unchanged output
  size in the measured rows. q2 also improves by 1.10x-1.23x with unchanged
  output size.
- q0 and q1 output sizes are unchanged, with measured min timings 2.7%-13.8%
  slower. q4 through q8 output sizes are unchanged, with measured min timings
  ranging from 10.6% faster to 7.6% slower depending on quality, target, and
  input.
- Added small decoder hot-path changes for command info lookup, short-distance
  handling, explicit distance decoding, and validated Huffman tree-group access.
  The regenerated decode report shows native min timings 5.7%-7.4% faster than
  v0.5.0; wasm-gc rows range from 3.6% faster to 0.3% slower.

### Tools and docs

- Moved Brotli tooling from `tools/brotli/` to direct `tools/` subdirectories
  and updated `just` recipes and documentation paths.
- Added same-time benchmark harnesses for comparing encode and decode behavior
  against a baseline git ref.
- Updated the size verification script to report `size` as a filesize value and
  to select native `.exe` artifacts explicitly.
- Documented recent `js`, `wasm-gc`, and `native` size-verification results in
  the README.

### Tests

- Added white-box coverage for context-map validation, command-info table
  lookup, validated short-distance decoding, explicit distance formulas, and
  encoder candidate gating.

## v0.5.0

### Performance

- Improved Brotli q4-q8 encode time by pruning expensive candidate passes,
  reusing match-chain tables, disabling lazy matching for those qualities, and
  preferring the context8 writer when applicable.
- In the `5591fe6` `target-perf` report, q4-q8 encode min timings improved
  from v0.3.1 by 2.15x-3.01x on `wasm-gc` and 3.08x-3.95x on native for the
  Silesia 64 KiB input, and by 2.57x-3.25x on `wasm-gc` and 3.39x-4.88x on
  native for the Silesia 128 KiB input. The same benchmark rows grew output
  size by 1.77%-2.63%.
- The same report shows q2-q3 encode min timings improving by 1.11x-1.34x and
  q9-q11 by 1.13x-1.77x on the Silesia 64 KiB and 128 KiB inputs, with
  unchanged output sizes in those rows.
- Optimized Brotli encoder prefix lookup paths for command lengths and
  distances, plus context8 literal-tree reuse.
- Added a decoder fast path for compressed meta-blocks with one literal tree
  and one literal block type, avoiding per-literal block tracking.
- Decode benchmark min timings for the 1 MiB Google-produced Silesia streams
  ranged from 1.6% slower to 3.5% faster than v0.3.1, so no material decode
  speedup is claimed for this release.

### Tests and docs

- Added white-box coverage for command-prefix tables, distance-prefix mapping,
  hash-chain boundary pre-checks, candidate gating, shared previous-match
  tables, and lazy-match deferral.
- Added roundtrip coverage for literal-heavy streams and lazy-match deferral
  inputs across multiple Brotli qualities.
- Regenerated the 0.5.0 Brotli release benchmark report and current benchmark
  JSONL files.

## v0.3.0

### Added

- Added `just bench`, backed by `tools/bench/report.nu`, to regenerate
  the Brotli release benchmark report and current benchmark JSONL files.
- Added checked-in Brotli benchmark data under `docs/current-bench/`, including
  Google Brotli 1 MiB comparison streams.

### Performance

- Improved Brotli decode hot paths by sizing dynamic output buffers from the
  compressed input length, refilling the bit reader four bytes at a time, and
  skipping zero-width command extra-bit reads.
- Packed decoded Brotli Huffman table entries into `FixedArray[Int]` and
  updated encoder/decoder users to avoid boxed table-entry loads.
- Optimized compressed meta-block literal decoding with a single-literal-tree
  fast path, a streamlined multi-tree path, and one reused command record per
  meta-block.

### Tests and docs

- Added white-box coverage for the decode optimizations, packed Huffman table
  behavior, output capacity sizing, and command record reuse.
- Regenerated `docs/brotli_release_report.md` from the current release-build
  benchmarks for `wasm-gc` and native targets against Google Brotli CLI 1.2.0.

## v0.2.0

### Breaking

- Renamed Brotli error APIs from `FzipError`, `FzipErrorCode`, `fzip_err`, and
  `fzip_error_code_to_int` to `FbrError`, `FbrErrorCode`, `fbr_err`, and
  `fbr_error_code_to_int`.
- Renamed the stream callback wrapper from `FlateStreamHandler` to
  `FbrStreamHandler`.

### Changed

- Updated package metadata and README examples for version `0.2.0`.
- Updated Brotli verification tooling and generated API metadata to use the
  `hustcer/fbr` package naming consistently.

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
- Tools under `tools/`:
  - `tools/bench/ratio.nu`, `tools/bench/chunk-match.nu`, and
    `tools/bench/target-perf.nu` for ratio, density, and wasm-gc/native
    encode/decode benchmarks.
  - `tools/conformance/run.nu` for the upstream Google Brotli test
    corpus.
  - `tools/fuzz/gen-corpus.nu` and `tools/fuzz/run.nu` for
    short fuzz runs against the decoder.
  - `tools/encode/verify.nu` and `tools/silesia/verify.nu` for
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
- Added `tools/fuzz/roundtrip.nu`, a deterministic encoder fuzz harness
  that checks random byte inputs through `brotli_sync` -> `unbrotli_sync` for
  selected quality levels and MoonBit backends.
- Brotli fuzz harness locks now record an owner PID and automatically recover
  stale locks left by interrupted local validation runs.
- Added `tools/release/validate.nu` to run the practical Brotli release
  validation gate from one Nushell command.
- Added `docs/brotli_release_report.md` with the current Brotli release
  readiness summary, validation evidence, and accepted P4 ratio exception.
- Added Justfile entries for the full, smoke, and package-only Brotli release
  validation gates, and added package verification to the release runner.
- Added `tools/fuzz/soak.nu` plus Justfile entries for the scripted
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
- `tools/size/verify.nu` now builds decode-only, encode-only, and full
  temporary applications. It scans JS artifacts for opposite-side package
  markers and can also report wasm-gc artifact sizes.
- Updated `README.md` to document the leaf package imports, root facade, and
  wasm-gc dictionary representation.

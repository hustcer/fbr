# Findings: Brotli Support

This file keeps durable Brotli facts for future development. It is a curated
reference, not a full session transcript.

## Repository Facts

- Source lives under `src/`; Brotli packages are split across `src/common/`,
  `src/decode/`, `src/encode/`, and `src/tests/`.
- Public generated API summaries are checked in as `pkg.generated.mbti`; run
  `moon info` when public APIs change.
- The installed reference CLI is `brotli 1.2.0`.
- `compress_sync` / `decompress_sync` must not auto-detect Brotli. Brotli is
  exposed through explicit peer APIs.
- Stream wrappers buffer chunks until `final_=true`.
- Tooling should be Nushell and should live under `tools/brotli/`.

## Current Implementation Facts

- Decoder supports compressed and uncompressed meta-blocks, simple and complex
  Huffman trees, block switching, context maps, literal context modes, recent
  distance state across meta-blocks, explicit distance formulas, output window
  validation, and static dictionary transforms.
- Static dictionary back-references must not update the recent-distance ring.
- Decoder window validation uses `(1 << window_bits) - 16`, capped by current
  output position. Older total-output-length validation would accept stale
  window references after output grew beyond the Brotli window.
- q0/q1 encoder emits valid stored meta-blocks.
- q2 is the fast P3 profile. q3..q9 use progressively stronger parser,
  dictionary, block-layout, and chunk strategies.
- q10/q11 share the current high-quality mixed-dictionary output on the
  recorded Silesia slices; they are valid but still outside the revised 5%
  ratio target.
- q2..q9 use 2 MiB P3 chunks with command budgets scaled only above 1 MiB.
- q4+ has guarded exact-costed pairwise block-layout candidates for literal,
  command, and distance histograms. A full three-stream joint split was tried
  and rejected.

## Current Ratio And Performance Baselines

- Revised policy: q2..q11 target encoded-size overhead is approximately <=5%
  versus Google Brotli on agreed corpora. q0/q1 are excluded unless reopened.
- q2..q9 are inside the measured 1 MiB, 2 MiB, and 64 KiB Silesia windows.
  Recorded `silesia-2m.bin` overheads: q2 +2.41%, q3 -0.94%, q4 -0.43%,
  q5 +1.99%, q6 +4.20%, q7 +3.38%, q8 +4.47%, q9 +4.69%.
- q10/q11 latest recorded 1 MiB Silesia result: 264,422 bytes versus Google
  q10 242,485 (+9.05%) and q11 239,314 (+10.49%).
- q10/q11 2 MiB chunk promotion was a real size lever but not enough:
  q10/q11 improved to +9.72%/+11.18% while native `cc-o0` encode regressed by
  roughly 17-36%. Do not retry a plain larger chunk without a parser/pruning
  change that offsets cost and closes more of the gap.
- Native target-perf currently reports `native_cc: "cc-o0"` because default
  generated-C `clang -O2` does not finish reliably on this package.

## P3 Release-Corpus Notes

- The release gate now fails q2..q9 rows above `--p3-max-overhead`, default
  `0.05`.
- Very small files need a special policy. Example: an 84-byte dictionary text
  sample showed 20%+ percentage overhead from only 14-15 extra bytes.
- `periodic-allbytes-200k.bin` is a useful regression input for long periodic
  copies over all 256 literals. The accepted single-copy fast path improved
  q2 to 301 bytes versus Google 293 (+2.73%) and q3..q9 to 272 bytes, with q9
  just over the line versus Google 259 (+5.02%).

## P4 q10/q11 Guidance

- Minor writer selection changes have not moved q10/q11 size; reaching 5%
  probably requires a material command-stream improvement or distinct q11
  parser behavior.
- Try low-cost exact-costed changes first:
  guarded mixed-dictionary subsets, improved high-quality parser scoring,
  distance-cache-aware match selection, and reuse of q4+ block-layout
  candidates.
- Escalate only in measured steps: 64 KiB/128 KiB bounded shortest-path caps,
  small beam-width trials, better suffix-tree pruning, and greedy-seeded cost
  refinement.
- Previously rejected P4 directions:
  mixed-dictionary min length 8 -> 6, block split prefilter 384 -> 128,
  exact-cost pure 4-byte LZ77 wrapper, 32 KiB max match length, 64 KiB
  shortest-path seed, q10-only wider transform subset `[1, 4, 16, 28, 47]`,
  384/512 hash-chain checks, 1 MiB DP prototype, and plain q10/q11 1.5-2 MiB
  chunk-size promotion.

## Release And Fuzz Tooling

- `tools/brotli/release/validate.nu` aggregates the practical release gate:
  all-target MoonBit checks, conformance, q0..q11 external decode/ratio
  coverage, decoder fuzz, encoder roundtrip fuzz, packaging, publish dry-run
  package verification, and `git diff --check`.
- `Justfile` exposes `brotli-release`, `brotli-release-smoke`,
  `brotli-release-package`, `brotli-release-candidate`, and
  `brotli-release-candidate-smoke`.
- Decoder fuzz runner batches generated white-box tests. The 25-input local
  gate dropped from about 54.73s to 2.19s; the 58-input corpus ran in about
  7.00s.
- Fuzz runners support target selection (`native`, `wasm-gc`, `js`, `all`).
- Generated-test harness locks store owner PID and recover stale locks while
  rejecting active concurrent runs.
- Deterministic fuzz corpora support `--seed` and `--corpus-dir`.
- Soak tooling writes JSONL under `target/brotli-fuzz-soak/` and supports
  append/resume style segmented runs.

## Decode Performance Guardrail

Use same-time comparisons whenever possible. The preferred harness is
`tools/brotli/bench/decode-compare.nu` via `just decode-compare`.

Accepted decode increments all removed redundant work while preserving
validation invariants:

- Removed duplicate Huffman tree-group bounds check after header/context
  validation; same-session q0/q5/q9/q11 aggregate improved by about 2.49%.
- Added validated short-distance helper for already-constrained short codes;
  aggregate improved by about 2.44%.
- Fused non-short explicit-distance formula work after Huffman range validation;
  aggregate improved by about 2.87%.
- Read the existing command info table directly after command Huffman
  validation; aggregate improved by about 1.79%.

Rejected decode strategies. Do not retry unchanged:

- Single distance-tree/block fast paths.
- Distance-1 exponential copy fill.
- Exact final meta-block capacity fitting and lower initial output capacity.
- Dedicated root-8 Huffman decoder.
- Two-byte refill branch, 64-bit accumulator, intrinsic `Bytes` word loads, or
  accumulator-width changes in the bit reader.
- Skipping literal handling for zero-insert commands.
- Inlining `max_distance` or reusing `output_before_copy` for it.
- Single command-block or split single-literal-body fast paths.
- Unchecked `take_bits_fast` for table-known widths.
- Manual short-copy loops and copy-branch reorderings.
- Direct recent-distance ring inlining, ring-slot `& 3` rewrites, or
  local-cached distance ring aliases.
- Packed decode-only command-info tables or command-symbol fast paths.
- Empty single-tree context maps.
- Prechecked or unchecked copy helpers.
- Removing literal byte-range checks.
- `ensure(0)` early return.
- Splitting normal-copy remaining bookkeeping.
- Removing refill conditions, zero-width `take_bits` calls, or final refill
  returns.
- Combining command insert/copy extra-bit reads.
- Rewriting hot literal loops from `for` to `while`.
- Inlining command decode into the compressed-body loop.
- Pre-resolved or cached context maps, literal trees, distance trees, or
  command trees.
- Removing unreachable-looking validation branches in copy, skip metadata, or
  final max-output checks.
- Unsafe `FixedArray` access in Huffman table reads. Same-time comparison
  showed bounds checks are not the current material cost.

High-level decode lesson: current native target-perf uses `cc-o0`, so added
branches, locals, aliases, and helper reshaping often cost more than they save.
Accepted changes removed operations; rejected changes usually changed code
shape or added a branch for a narrow stream shape.

## Validation Invariants Worth Preserving

- Upstream corpus details caught by conformance:
  code-length-code length reading stops when Huffman space is complete;
  single-symbol Huffman tables may have zero-bit entries; dictionary transform
  output can differ from copy length; static dictionary distances do not update
  the recent-distance ring.
- Silesia q11 long-stream context details:
  UTF8 second-last bytes `208..223` contribute `0`, not `2`, and DEL (`127`)
  is classified as control for both UTF8 context tables.
- Manual Brotli temp-test harnesses must not run concurrently. Moon test
  discovery sees all `src/*_wbtest.mbt` files, so generated-test writes must be
  serialized.

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
- Tooling should be Nushell; the current benchmark, encode, fuzz, and release
  entry points live under `tools/bench/`, `tools/encode/`, `tools/fuzz/`, and
  `tools/release/`.

## Current Implementation Facts

- Decoder supports compressed and uncompressed meta-blocks, simple and complex
  Huffman trees, block switching, context maps, literal context modes, recent
  distance state across meta-blocks, explicit distance formulas, output window
  validation, and static dictionary transforms.
- Static dictionary back-references must not update the recent-distance ring.
- Decoder window validation uses `(1 << window_bits) - 16`, capped by current
  output position. Older total-output-length validation would accept stale
  window references after output grew beyond the Brotli window.
- q0/q1 encoder now routes through the standard compressed path. q0 uses a
  q0-specific natural low-quality LZ77 candidate without literal contexts;
  q1 uses the natural low-quality path with a context8 writer. Guard q2..q11
  for obvious regressions when changing this code.
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
- Reopened q0/q1 target from 2026-06-14: work toward roughly -7%..+7%
  encoded-size overhead versus Google Brotli on the release-report Silesia
  windows, then optimize speed within that size envelope. User clarified that
  entering the target band is not enough by itself; continue looking for better
  q0/q1 performance and size while preserving other qualities.
- Rejected q0 trial (2026-06-14): routing q0 through only the default
  `hash_config` simple LZ77 candidate with `allow_contexts=false` failed the
  ratio objective. On `silesia-64k.bin`, the candidate was not smaller than
  stored according to the existing exact-size guard, so output fell back to
  65,540 bytes (+140.73% vs Google q0). Do not retry unchanged.
- Rejected q0 trial (2026-06-14): lowering q0 natural hash-chain checks from
  4 to 2 exceeded the reopened ratio target. Silesia 64 KiB became 29,961
  bytes (+10.05% vs Google q0) and 128 KiB became 55,507 bytes (+9.18%).
  The accepted follow-up point is 3 checks with a longer minimum match.
- Rejected q0 trial (2026-06-14): lowering q0 minimum match length from 7 to
  6 over-compressed outside the requested -7% lower bound. Silesia 64 KiB
  became 25,123 bytes (-7.72% vs Google q0) and 128 KiB became 46,147 bytes
  (-9.23%).
- Rejected q0 trial (2026-06-14): raising q0 minimum match length from 8 to
  9 stayed inside the target but gave a worse tradeoff. Silesia 64 KiB became
  28,540 bytes (+4.83% vs Google q0) and 128 KiB became 52,586 bytes
  (+3.43%), while target-perf barely improved and 128 KiB wasm-gc was noisier.
- q0 accepted candidate (2026-06-14): natural low-quality hash config with
  3 hash-chain checks, min match length 8, no literal-context writer, and no
  low-quality split writer. Silesia 64 KiB: 27,541 bytes (+1.16% vs Google
  q0), target-perf min about wasm-gc 5.42 ms / native 3.95 ms at repeats=20;
  128 KiB: 50,842 bytes (+0.00%), target-perf min about wasm-gc 9.04 ms /
  native 5.85 ms after re-running one native outlier.
- Rejected q1 trial (2026-06-14): disabling literal contexts for q1 and using
  only the weighted LZ77 writer exceeded the target. Silesia 64 KiB became
  28,302 bytes (+9.25% vs Google q1) and 128 KiB became 51,717 bytes
  (+8.93%). Keep a context writer for q1 unless another candidate recovers
  the lost ratio.
- Rejected q1 trial (2026-06-14): replacing the q1 context8 writer with
  context4 kept ratio inside the target but was worse overall. Silesia 64 KiB
  grew to 26,792 bytes (+3.42% vs Google q1) and target-perf did not improve
  versus context8 (native about 5.37 ms vs context8 about 5.26 ms). Keep
  context8 for the current q1 balance.
- Rejected q1 trial (2026-06-14): q1 131,072-entry natural hash table matched
  Google's nominal q1 table size but produced identical Silesia bytes to the
  32,768-entry table while adding memory footprint. Keep the smaller table
  unless a broader corpus shows a real size or speed win.
- Rejected q1 trial (2026-06-14): lowering q1 minimum match length from 8 to
  7 over-compressed outside the requested lower bound. Silesia 64 KiB became
  23,830 bytes (-8.01% vs Google q1) and 128 KiB became 43,476 bytes
  (-8.43%). Final q1 restored min match length 10 to preserve q2-vs-q1
  quality expectations and test semantics.
- Rejected q1 trial (2026-06-14): reducing q1 natural hash-chain checks from
  4 to 3 stayed inside the target but cost too much size for a small speed
  gain. Silesia 64 KiB became 26,810 bytes (+3.49% vs Google q1) and 128 KiB
  became 49,355 bytes (+3.95%). Keep 4 checks for the current balance.
- q1 accepted candidate (2026-06-14): chunked natural low-quality path with
  4 hash-chain checks, min match length 10, context8 writer, no low-quality
  split writer, and the smaller 32,768-entry table. Silesia 64 KiB:
  26,501 bytes (+2.30% vs Google q1), target-perf min about wasm-gc
  6.90 ms / native 4.85 ms at repeats=20; 128 KiB: 48,610 bytes (+2.38%),
  target-perf min about wasm-gc 11.47 ms / native 7.54 ms.
- Syntax pitfall (2026-06-14): MoonBit rejects `match if ... { ... } { ... }`
  without wrapping/binding the `if` expression. Bind the context candidate to a
  local before `match`.
- Tooling caution (2026-06-14): do not run `moon check` concurrently with
  `tools/bench/target-perf.nu`. The benchmark rewrites
  `src/brotli_target_perf_main/`; a concurrent check can observe a transient
  invalid package and report spurious "Package fbr not found" errors.
- q2..q9 are inside the measured 1 MiB, 2 MiB, and 64 KiB Silesia windows.
  Recorded `silesia-2m.bin` overheads: q2 +2.41%, q3 -0.94%, q4 -0.43%,
  q5 +1.99%, q6 +4.20%, q7 +3.38%, q8 +4.47%, q9 +4.69%.
- q10/q11 latest recorded 1 MiB Silesia result: 264,422 bytes versus Google
  q10 242,485 (+9.05%) and q11 239,314 (+10.49%).
- q10/q11 2 MiB chunk promotion was a real size lever but not enough:
  q10/q11 improved to +9.72%/+11.18% while native `cc-o0` encode regressed by
  roughly 17-36%. Do not retry a plain larger chunk without a parser/pruning
  change that offsets cost and closes more of the gap.
- (2026-06-12) The historical "generated-C `clang -O2` does not finish"
  failure no longer reproduces on moon 0.1.20260529+ / moonc v0.10.0 with
  Apple clang (Darwin 24.6.0): decode main compiles at -O2 in 0.84s, the
  3 MB full main in 2.4s. The cc-o0 MOON_CC workaround was removed from
  `tools/bench/target-perf.nu`; native release rows now report
  `native_cc: "default"` and run roughly 4-5x faster than the old cc-o0
  rows (decode q5 ~38 -> ~9 ms/op at repeats=10).
- (2026-06-12) Harness fixed-overhead caveat: one `moon run` process start
  (~110 ms wasm-gc, ~28 ms native) is amortized across `--repeats`. At the
  old repeats=3 the per-op decode numbers were dominated by startup, not
  decoding. `report.nu` and `decode-compare.nu` now default to repeats=20.
  True per-op decode on silesia-1m (repeats=25, 2026-06-12 session):
  wasm-gc ~13-18 ms, native ~6.5-8.6 ms versus Google CLI ~8-10 ms
  (which includes one process spawn per op).

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

- (post-O2, 2026-06-12) Raising the `brotli_read_symbol` refill trigger from
  `bits_avail < root_bits` to `bits_avail < 15` (refill once for root +
  sub-table). wasm-gc improved slightly but native -O2 regressed
  (q0 +0.34%, q9 +0.50%, q11 +1.45%); strict decode-compare gate FAIL.
  Keep the root_bits trigger; the 64-bit accumulator already makes the
  sub-table refill branch rare.
- (post-O2, 2026-06-12) Inlined root-table literal fast path in the literal
  loops (lookup + length-fits-bits_avail guard, falling back to
  `brotli_read_symbol`), in both the single-tree loops and the multi-tree
  general loop. Aggregate only -0.4..-0.7% with different rows regressing
  on each run (noise around zero); cannot pass the strict all-rows gate.
- (post-O2, 2026-06-12) `#inline` attribute on `brotli_read_symbol`.
  Wash: aggregate -0.2..-0.3% with mixed row signs at repeats=25.

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

High-level decode lesson: most of the rejected-trial cache above was measured
while native release benchmarks were built with the cc-o0 workaround, where
added branches, locals, aliases, and helper reshaping often cost more than
they saved. Since 2026-06-12 native builds with default clang -O2; one cc-o0
era rejection (the 64-bit accumulator bit reader) requalified and landed with
a uniform all-rows win (~-1.1% aggregate at repeats=5, diluted by harness
startup). Post-O2 retries of refill-threshold, inlined literal fast paths,
and `#inline` hints all landed in the +-1% noise band and stayed rejected:
the remaining per-symbol work is already tight, and wasm-gc's residual gap
versus native (~1.7x true per-op) looks engine-bound rather than
code-shape-bound.

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

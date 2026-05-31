# Task Plan: Brotli Support

**Goal:** Implement Brotli support end to end: Brotli decode, encode quality
0 through 11, stream wrappers, fixtures, conformance tooling, tests, generated
interfaces, changelog updates, and phase commits. The codec acceptance target
has been revised from strict C-reference algorithm parity to measured
compression/performance parity that is practical for pure MoonBit across
native, JavaScript, and wasm-gc.

**Source of truth:** `docs/brotli.md` plus the current worktree. Reference
implementations are available at `/Users/hustcer/iWork/refs/brotli` and
`/Users/hustcer/iWork/refs/rust-brotli`.

## Constraints

- Keep fzip's single-package `src/` layout and MoonBit style.
- Target native, JavaScript, and wasm-gc.
- Use pure MoonBit implementation in the library code.
- Preserve existing APIs; Brotli is added as explicit peer APIs.
- P1 through P4 each need tests, review, and at least one commit.
- More than four commits are allowed for meaningful verified increments.
- Use Nushell for any new scripts.
- Revised acceptance policy as of 2026-05-30:
  - q2..q11 target encoded-size overhead is around 5% versus Google Brotli at
    the same quality on the agreed validation corpora.
  - q10/q11 no longer require a full C-reference Zopfli implementation if the
    5% size target can be reached with bounded high-quality parser,
    dictionary, block-layout, or shortest-path improvements.
  - q0/q1 remain valid stored-fast modes and are excluded from the q2..q11
    ratio target unless the product decision explicitly reopens P2 ratio work.
  - `tools/brotli/bench/target-perf.nu` is the default decision harness; codec
    optimization commits must include wasm-gc/native encode/decode and
    encoded-size evidence in the commit body.
- Decode performance guardrail as of 2026-05-31: before retrying decode hot-path
  ideas, read `.planning/brotli-support/findings.md`, section
  `2026-05-31 — Rejected decode performance trials`, and treat the full list
  there as a negative cache. Do not repeat unchanged versions of any listed
  trial, including single-tree/block fast paths, copy-loop rewrites, Huffman or
  bit-reader micro-specializations, command/distance inline shortcuts,
  context-map allocation changes, output-capacity/`ensure(0)` tweaks, literal
  range-check removal, or checked-copy splitting. Future decode candidates
  should improve both `wasm-gc` and native `cc-o0` on q0/q5/q9/q11 before full
  `just bench`.

## Phase Checklist

- [x] P1 decoder: `unbrotli_sync`, `UnbrotliStream`, RFC decoder,
      static dictionary, transforms, conformance harness, fixtures, fuzz harness.
- [x] P2 encoder q=0/q=1: `brotli_sync`, `BrotliStream`, bit writer,
      stored-meta-block fast path, deterministic roundtrip tests, Google CLI
      validation. Note: the implementation is RFC-valid and externally decodable,
      but it does not meet the original q0/q1 Silesia ratio target from
      `docs/brotli.md`; reopen P2 only if that target remains mandatory.
- [ ] P3 encoder q=2..9: q2..q9 now have measured Silesia-window ratio and
      64 KiB target-perf evidence, q4..q8 have an intermediate search path that
      brings measured 1 MiB outputs inside the 5% target, q6/q7 have accepted
      small-input runtime tuning, q5 skips the redundant natural 4-byte candidate,
      and q2..q9 all have measured 2 MiB Silesia ratio evidence inside the 5%
      target. Under the revised policy, remaining P3 work is broader release
      validation corpus coverage and regression protection, not mandatory
      C-reference Lloyd clustering unless a corpus slice regresses above 5%.
- [ ] P4 encoder q=10/q=11: current code uses a deeper high-quality hash
      parser plus mixed static-dictionary matches, memory caps, and a bounded
      small-input shortest-path seed candidate. The target is revised to roughly
      5% size overhead with acceptable wasm-gc/native performance. Current
      q10/q11 are still outside that target, so remaining P4 work is to reduce
      q10/q11 from about +9.05%/+10.49% to <=5% without large performance
      regressions; a full Zopfli backend is optional and should be used only if
      lower-cost candidates cannot reach the target.

## Current Implementation Snapshot

- `brotli_sync` accepts q0..q11. q0/q1 write standard uncompressed
  meta-blocks; q2/q3 use the fast standard compressed candidate path; q4..q8
  add an intermediate hash-chain search path; q9 uses the high-quality parser
  plus gated mixed static-dictionary search; q10/q11 use a 4-byte high-quality
  mixed dictionary path with 256 hash-chain checks and a 131,072-entry table.
  q5 lighter q4-style intermediate config trial was measured and rejected:
  native runtime worsened and size moved close to the 5% ratio ceiling. The
  code is back on the accepted q5 16-check, 180,000-command, 5-byte-minimum
  path.
- q2 is treated as the fast P3 profile. It favors bounded runtime on
  wasm-gc/native and uses one natural LZ77 candidate for large chunks.
- q9 currently has the strongest documented P3 ratio evidence:
  `silesia-1m.bin` improved from 273,633 to 271,776 bytes versus Google q9
  263,791 bytes, reducing overhead from 3.73% to 3.03%.
- q4..q8 have measured 1 MiB Silesia overhead inside 5% after the
  intermediate search commit: q4 -1.80%, q5 1.78%, q6 3.46%, q7 2.45%,
  q8 3.33%. A rejected q5 lighter-config trial worsened q5 1 MiB size to
  287,092 bytes versus Google 274,088 bytes, or 4.74% overhead, so q5 keeps
  the accepted 278,961-byte path.
- q2..q9 are all inside the measured 1 MiB and 64 KiB Silesia 5% ratio
  window. Sampled native target-perf for q5 improved from 142.394 to 94.185
  ms/op by skipping only the redundant natural 4-byte candidate while
  preserving the q5 1 MiB ratio. q6/q7 small-input tuning reduced sampled
  native runtime to 126.045 and 139.976 ms/op while preserving the measured
  1 MiB ratio window. q4+ now also has exact-costed command-block and
  distance-block histogram split candidates; current Silesia 64 KiB and 128
  KiB q5/q9 samples keep the same output sizes while synthetic skew coverage
  proves both two-block writer and selector paths.
- Broader 2 MiB validation exposed and then fixed a chunked encoder state bug:
  q3/q5/q9 streams now carry the winning LZ77 candidate's recent-distance
  cache and the previous two decoded bytes used by UTF-8 literal contexts
  across compressed meta-blocks. q2..q9 now use 2 MiB P3 chunks with command
  budgets scaled only for chunks larger than 1 MiB. On `silesia-2m.bin`,
  q2 is +2.41%, q3 -0.94%, q4 -0.43%, q5 +1.99%, q6 +4.20%, q7 +3.38%,
  q8 +4.47%, and q9 +4.69% versus Google Brotli.
- q10/q11 currently share the same mixed-dictionary high-quality output on the
  recorded Silesia slices. Refreshed 1 MiB result is 264,422 bytes versus
  Google q10 242,485 (+9.05%) and q11 239,314 (+10.49%), so P4 remains open.
  Refreshed 64 KiB target-perf: q10 wasm-gc/native 510.253/121.332 ms,
  q11 wasm-gc/native 547.539/75.297 ms. A q10-only wider mixed-dictionary
  transform trial `[1, 4, 16, 28, 47]` was rejected: it saved only 107 bytes
  on `silesia-1m.bin` q10 and 32 bytes on `silesia-128k.bin` q10 while moving
  the 128 KiB native target-perf sample from 91.262 to 97.858 ms/op. A
  384-check high-quality parser trial was also rejected: it improved q10/q11
  1 MiB size to 263,700 bytes, but q10 128 KiB target-perf regressed native
  from 91.262 to 143.997 ms/op and wasm-gc from 172.893 to 660.508 ms/op.
- P4 heuristic optimization is no longer blocked on the original 2% Zopfli
  parity goal. q10/q11 exact-cost a bounded shortest-path candidate on inputs
  up to 32 KiB, enumerate multiple hash-chain matches per position, propagate
  recent-distance cache through the DP, keep a two-state beam per input
  position, seed a lightweight cost model from the current greedy LZ77 command
  stream, and have a bounded suffix binary-tree match source. q10/q11 are
  valid and externally decodable, but the revised 5% target still requires
  measured size improvements from about +9.05%/+10.49% without large
  wasm-gc/native encode regressions.
- Practical release validation has now passed for the current checkpoint:
  q0/q1 2 MiB stored streams pass external Google Brotli decode, q2..q9 2 MiB
  Silesia outputs stay inside the measured 5% P3 window, q10/q11 pass external
  decode with the documented P4 ratio exception, representative wasm-gc/native
  target-perf is recorded, all 22 conformance fixtures pass, and the 25-input
  local fuzz gate passes. The 24-hour fuzz gate remains reserved for final
  release readiness.
- The decoder fuzz runner now batches generated white-box tests. The 25-input
  local gate dropped from 54.73s to 2.19s, and the current 58-input corpus runs
  in 7.00s, so broader local fuzz validation is now practical.
- The fuzz runner now accepts `--target`, preserving native as the default and
  allowing the same generated corpus to run through `wasm-gc`, `js`, or `all`
  during release validation.
- The encoder-side roundtrip fuzz harness now exists as
  `tools/brotli/fuzz/roundtrip.nu`. It deterministically generates byte inputs,
  runs `brotli_sync` followed by `unbrotli_sync`, and covers selected quality
  levels and MoonBit targets.
- Brotli generated-test harness locks now record an owner PID and recover stale
  locks left by interrupted validation runs while still rejecting active
  concurrent runs.
- `tools/brotli/release/validate.nu` now aggregates the practical release gate:
  MoonBit all-target checks, conformance, q0..q11 external decode/ratio
  coverage, decoder fuzz, encoder roundtrip fuzz, packaging, publish dry-run
  package verification, and `git diff --check`.
- `Justfile` exposes `brotli-release`, `brotli-release-smoke`, and
  `brotli-release-package` entries for the practical Brotli release gates.
- `Justfile` also exposes `brotli-release-candidate` and
  `brotli-release-candidate-smoke` to aggregate the accepted full and smoke
  release-validation gate sets.
- `tools/brotli/fuzz/soak.nu` and the `brotli-fuzz-soak` Justfile entries make
  the long fuzz gate repeatable and log progress as JSONL under
  `target/brotli-fuzz-soak/`. `--append-log` supports interrupted or segmented
  long soaks by preserving existing JSONL rows and continuing iteration
  numbering.
- `just brotli-fuzz-soak-bounded` exposes a full-corpus finite soak entry that
  reruns the same decoder-fuzz and encoder-roundtrip loops without requiring a
  24-hour wall-clock run.
- `tools/brotli/fuzz/gen-corpus.nu` now accepts `--seed` and `--corpus-dir`,
  and uses Nushell `generate` to produce deterministic mutation corpora for
  reproducible release validation.
- `tools/brotli/release/validate.nu` can now generate a deterministic decoder
  fuzz corpus before running decoder fuzz, exposed through
  `just brotli-release-generated-fuzz`.
- `just brotli-release-generated-fuzz` has passed with 1,000 deterministic
  mutations and seed `1`; the bounded soak runner has passed 3 decoder-fuzz
  iterations and 3 encoder-roundtrip iterations.
- `docs/brotli_release_report.md` records the current release-readiness state,
  size/perf evidence, full practical release-gate result, and accepted
  q10/q11 P4 ratio exception boundary.
- `tools/brotli/bench/target-perf.nu` is the default performance harness for
  Brotli decisions. It now runs through a temporary ignored MoonBit main
  package instead of a full-package generated white-box test. Native target
  rows currently report `native_cc: "cc-o0"` because default native release
  `clang -O2` still does not finish reliably on the generated Brotli C output;
  treat these as explicit native-codegen measurements with the C compiler
  optimization workaround, not as default `clang -O2` release results. Every
  optimization commit must include wasm-gc/native encode/decode and
  encoded-size evidence in the commit body.
- Current accepted decode performance increment: private Huffman tree-group
  lookup no longer repeats an explicit bounds check after compressed-header,
  block-tracker, and context-map validation. Same-time q0/q5/q9/q11 decode
  screening improved aggregate wasm-gc/native min time by 2.49%, and
  `just bench` confirmed encode output sizes stayed unchanged.
- Follow-up accepted decode increment: decode-private validated short-distance
  lookup avoids the public short-code range check when the command/distance
  alphabet already guarantees the code range. q0/q5/q9/q11 screening improved
  aggregate wasm-gc/native min time by 2.44%; `just bench` passed and was saved
  under `target/brotli-perf-notes/2026-06-01-short-distance/` instead of being
  committed.

## Current Increment

- [x] Audit `docs/brotli.md` against current code and evidence.
- [x] Correct P3/P4 status: dispatch commits are stream-valid increments, not
      documented P3/P4 completion because ratio/search criteria are unmet.
- [x] Add first q2+ compressed meta-block path for single-byte runs using an
      inserted literal and a distance-1 LZ77 copy.
- [x] Verify the generated q2 repeated-run stream with the external Brotli CLI.
- [x] Generalize q2+ compressed path to unique short periods 1..4, including
      literal payload bits and explicit distances 1..4.
- [x] Verify a generated q2 `ABCD` periodic stream with the external Brotli CLI.
- [x] Generalize q2+ LZ77 matching beyond whole-input short periods to one
      literal prefix plus one copied suffix.
- [x] Verify a generated q2 `XABCABC...` stream with the external Brotli CLI.
- [x] Add greedy multi-command q2+ path for inputs with up to four distinct
      literal bytes and simple command/distance alphabets.
- [x] Verify a generated q2 multi-command small-alphabet stream with the
      external Brotli CLI.
- [x] Replace simple-Huffman alphabet caps with complex Huffman tree emission
      for literal, command, and distance alphabets.
- [x] Verify q2 streams that require complex literal and command Huffman trees
      with the external Brotli CLI.
- [x] Add Nushell ratio benchmark harness comparing MoonBit output against the
      Google Brotli CLI.
- [x] Record q2 ratio baseline for small synthetic corpus and 100 MiB Silesia.
- [x] Add chunked q2 large-input encoding with bounded hash-chain matching for
      very low-alphabet chunks.
- [x] Fix chunked stored-block emission so uncompressed meta-block padding is
      written at the active stream bit offset.
- [x] Re-run q2 Silesia ratio after chunking; full-corpus output is stream-valid
      but still a stored-block baseline.
- [x] Add frequency-weighted Huffman code-length selection for low-alphabet q2
      compressed chunks.
- [x] Replace the strict low-alphabet q2 gate with a sampled dense-match gate
      that admits highly repetitive high-alphabet chunks.
- [x] Increase q2 hash-match copy extension to reduce command count on
      repetitive chunks.
- [x] Add a chunk match diagnostic harness to measure natural-data copy
      opportunities before relaxing the q2 gate.
- [x] Split current q2 hash-chain helpers into `brotli_encode_hash.mbt` as the
      first P3 file-boundary step.
- [x] Thread a quality-aware hash config through the q2+ compressed-chunk path
      without changing current matcher behavior.
- [x] Add hash-config admission fields and command-literal accounting, then
      reject a measured q9 sparse-match trial that produced no ratio gain.
- [x] Add repeat-zero RLE for complex Huffman code-length streams to reduce
      sparse alphabet tree overhead.
- [x] Add repeat-previous RLE for complex Huffman code-length streams to reduce
      repeated nonzero length overhead.
- [x] Add a literal-only compressed chunk candidate for low-alphabet data when
      no back-reference candidate is accepted.
- [x] Extend literal-only chunks to high-alphabet natural data with a
      length-limited weighted literal tree and entropy precheck.
- [x] Add a first q2+ identity static-dictionary command candidate for small
      single-block inputs.
- [x] Add a first midpoint two-literal-block split candidate for literal-only
      q2+ meta-blocks.
- [x] Add a cheap split-admission estimator to preserve the midpoint split
      ratio gain while reducing candidate-write overhead.
- [x] Select the best admitted literal split among quarter/midpoint/three-quarter
      candidates while still writing at most one split meta-block.
- [x] Add a separate large-input long-match candidate so natural q2+ chunks can
      use sparse back-references without regressing small inputs.
- [x] Tune the large-input long-match candidate from 32-byte to 16-byte minimum
      copies after exact-cost benchmarks showed a larger Silesia win.
- [x] Raise the q2+ standard chunk size to 256 KiB with a proportional natural
      command cap so long matches can cross the previous 65 KiB boundary.
- [x] Raise the q2+ standard chunk size to 1 MiB after validation showed a
      small additional Silesia gain without fixture regressions.
- [x] Use weighted Huffman lengths for command and distance trees, not just
      literal trees.
- [x] Add a lazy-match check for the natural long-match candidate so it can
      delay a copy when the next position has a substantially longer match.
- [x] Raise the natural candidate's max copy length to reduce command overhead
      on long repeated regions.
- [x] Add a q9-only exact-costed high-quality long-match candidate so q9 can
      improve independently from q2.
- [x] Skip the q2 natural long-match candidate for q9 once the q9-specific
      candidate covers the same fixtures with identical bytes.
- [x] Raise baseline, natural, and high-quality hash tables to 32K entries
      after Silesia q2/q9 benchmarks showed fewer collision losses without fixture
      regressions.
- [x] Increase q2 natural hash-chain checks to 8 after validation showed a
      Silesia q2 win; keep q9 high-quality checks at 4 after the 8-check trial
      regressed q9.
- [x] Add an exact-costed eight-tree UTF-8 literal-context candidate after
      Silesia q2/q9 benchmarks showed a material ratio win without fixture
      regressions.
- [x] Add an exact-costed sixteen-tree UTF-8 literal-context candidate after
      Silesia q2/q9 benchmarks showed another material ratio win without fixture
      regressions.
- [x] Lower the q2 natural match threshold to 10 bytes and raise the q2
      command cap after exact-costed Silesia benchmarks brought q2 within 0.15% of
      Google Brotli without fixture regressions.
- [x] Lower the q9 high-quality match threshold to 10 bytes and raise the q9
      command cap after exact-costed Silesia benchmarks cut q9 overhead to 25.91%
      without fixture regressions.
- [x] Lower the q9 high-quality match threshold further to 6 bytes with a
      150,000-command cap after 8-byte and 4-byte trials showed 6 bytes was the
      best exact-costed Silesia result.
- [x] Emit Brotli distance-cache short codes from the LZ77 command builder,
      improving Silesia q2/q9 and small repeated fixtures without decode
      regressions.
- [x] Apply lazy-match lookahead to short-match natural/high-quality parsers,
      improving Silesia q2 below Google q2 and reducing q9 overhead to 15.01%.
- [x] Tune lazy-match lookahead to delay on any longer next match, improving
      Silesia q2 to 1.04% smaller than Google q2 and q9 overhead to 14.21%.
- [x] Extend lazy-match lookahead to three following positions after two-byte
      and four-byte trials showed three bytes was best on Silesia q9.
- [x] Probe Brotli recent-distance candidates before hash-chain matches so the
      parser can preserve cheap short-code distances; Silesia q2 is now 2.13%
      smaller than Google q2 and q9 overhead is 12.51%.
- [x] Extend the encoder static-dictionary index to same-length uppercase
      transforms, using Brotli transform indices in dictionary distances and
      validating an uppercase dictionary fixture.
- [x] Extend encoder static-dictionary commands to selected suffix/prefix
      transforms where transformed output length differs from dictionary word
      length, including meta-block length accounting and external decode coverage.
- [x] Give q10/q11 a distinct high-quality parser configuration with deeper
      hash-chain checks, shorter accepted copies, and a larger command cap, cutting
      Silesia 1 MiB q10/q11 output from 296,784 to 288,988 bytes.
- [x] Tune q11 separately from q10 with 32 hash-chain checks and a larger
      command cap, cutting Silesia 1 MiB q11 output further to 283,133 bytes.
- [x] Add a q2 fast large-chunk profile that runs one natural LZ77 candidate
      and prunes expensive intermediate exact-costed meta-block writers, cutting
      Silesia 1 MiB q2 benchmark time roughly in half while staying within 5% of
      Google q2.
- [x] Promote q9/q10 high-quality parsing to q11's deeper 32-check,
      300,000-command configuration, cutting Silesia 1 MiB q9 to 283,133 bytes
      and q10 to 283,133 bytes.
- [x] Thread recent-distance cache state through q2 compressed chunks so future
      multi-meta-block compressed streams can preserve Brotli short-code state
      instead of restarting from the RFC initial cache per chunk.
- [x] Enable lazy lookahead for 5-byte high-quality matches, bringing Silesia
      1 MiB q9 within the 5% P3 ratio target window at 273,641 bytes.
- [x] Mark final compressed chunks as final and use a full 1 MiB standard
      chunk boundary, trimming Silesia q2/q9/q10/q11 by 8-9 bytes without fixture
      regressions.
- [x] Reduce q2 fast-profile scanning by collecting 16 literal contexts in one
      pass and limiting q2 natural parser lookahead/probes, cutting Silesia q2
      1 MiB time to about 28s while staying within 5% of Google q2.
- [x] Replace O(n \* unique-symbols) literal-set collectors with per-byte seen
      tables, improving q2 target-perf encode time on wasm-gc/native without
      changing encoded size.
- [x] Re-audit current Brotli code against the plan and staged diff.
- [x] Record that q0..q11 are implemented as valid round-tripping encoders,
      with q9/q10/q11 using high-quality hash configs and q11 now using a deeper
      128-check / 131,072-entry parser configuration.
- [x] Record staged distance-symbol fast-path optimization in
      `src/brotli_encode.mbt`; it is behavior-preserving and does not change the
      public API.
- [x] Remove the conservative low-alphabet q2 gate by adding general
      natural-data block splitting and entropy decisions.
- [x] Measure ratio delta against Google Brotli on Silesia.
- [x] Validate q11's current deeper parser configuration against the ratio
      harness and external Google Brotli decode, then record the exact size/time
      deltas.
- [x] Enable q9 mixed-dictionary search with a word-boundary admission gate,
      improving q9 Silesia ratio while avoiding unconditional dictionary scanning.
- [x] Trim the mixed dictionary index allocation to the exact same-length plus
      selected-extra transform subset used by the q9/q10/q11 mixed path.
- [x] Raise q9's standard chunk size to 2 MiB and allow high-quality LZ77 /
      mixed-dictionary candidates to cost 2 MiB inputs. `silesia-2m.bin` q9 now
      encodes to 535,421 bytes versus Google q9's 511,433 bytes (+4.69%), while
      sampled 64 KiB target-perf records 21,514 bytes and 523.417/89.076 ms
      wasm-gc/native.
- [x] Raise q2's standard chunk size to 2 MiB with a doubled natural parser
      command budget. `silesia-2m.bin` q2 now encodes to 652,695 bytes versus
      Google q2's 637,343 bytes (+2.41%), while sampled 64 KiB target-perf records
      25,245 bytes and 480.975/75.117 ms wasm-gc/native.
- [x] Raise q3..q8 standard chunk size to 2 MiB with command budgets scaled
      only above 1 MiB. `silesia-2m.bin` q3..q8 are now all inside the 5% target
      window; sampled q8 64 KiB target-perf records 22,261 bytes and
      524.749/112.349 ms wasm-gc/native.

## Next Increment

Remaining development plan under the revised ~5% size-overhead target:

1. **Stabilize measurement evidence before more codec changes.**
   Finish committing the `target-perf.nu` main-package harness change after
   reviewing the diff and validation output. This is required because native
   release target-perf was previously blocked by generated white-box tests and
   `clang -O2`; future optimization commits need reliable wasm-gc/native
   encode/decode and size evidence in their commit bodies.
2. **Refresh the accepted baseline matrix.**
   Re-run `ratio.nu` for q2..q11 on the agreed Silesia slices and run
   `target-perf.nu` on representative encode/decode samples for `wasm-gc` and
   native (`native_cc: "cc-o0"` until the default C compiler path is fixed).
   Record q10/q11 separately because they remain outside the 5% target.
3. **Close P3 release validation, not new P3 algorithm work by default.**
   q2..q9 already fit the measured Silesia 5% window, so the next P3 task is
   broader corpus validation: small files, text-heavy data, binary-heavy data,
   deterministic fuzz corpus roundtrips, and regression gates. Only reopen
   C-reference-style clustering/splitting if one of these corpora exceeds
   ~5% or shows a material wasm-gc/native regression.
4. **Attack P4 q10/q11 size first with bounded low-cost candidates.**
   Current q10/q11 are around +9%/+10% on Silesia slices. Start with changes
   that can alter the command stream or entropy model without exploding
   runtime: distinct q10 vs q11 parser scoring, better distance-cache-aware
   match selection, q10/q11 reuse of existing exact-costed block-layout
   candidates, and tightly guarded mixed-dictionary extensions. Keep only
   changes that move size materially toward <=5% with acceptable wasm-gc/native
   encode cost.
5. **Escalate P4 only if low-cost candidates stall.**
   If the remaining gap cannot be closed cheaply, extend the bounded
   shortest-path/Zopfli-style seed in small measured steps: larger 64 KiB or
   128 KiB caps, small beam-width trials, better suffix-tree pruning, and
   cost-model refinement from the greedy command stream. Do not accept a
   broad DP path unless target-perf shows the size win justifies the encode
   cost on wasm-gc and native.
6. **Promote to release readiness only after measured acceptance.**
   When q10/q11 are <=5% on the agreed corpora, rerun external Google decode,
   MoonBit roundtrip/fuzz/conformance gates, `moon check --target all`,
   `moon test --target all`, `moon info`, `git diff --check`, and the required
   target-perf matrix. Then update the release report and commit with the
   target-perf improvement data in the body.

Historical priority order and completed release-directed work:

- [x] **P0 release gate:** commit the staged distance-symbol fast path after
      target-perf evidence on wasm-gc/native encode and decode, plus MoonBit
      check/test/info validation.
- [x] **P0 release gate:** establish and record target-perf baselines for
      decode, q2 encode, q9 encode, and q11 encode on representative Silesia
      slices; every Brotli performance commit must carry these numbers in the
      commit body.
- [x] **P0 release gate:** validate q11's current deeper parser configuration
      against target-perf and external Google Brotli decode, then update
      `progress.md` with exact size/time deltas.
- [x] **P0 release gate:** run the practical full validation matrix
      (`moon fmt`, `moon check --target all`, `moon test --target all`,
      `moon info`, `git diff --check`) before any release candidate.
- [x] **P1 performance:** use target-perf output to choose the next small
      encode/decode hotspot; prefer bounded improvements that preserve current
      ratios over speculative ratio-only work.
  - [x] Optimize Brotli back-reference output copying for distance=1 and
        non-overlapping copies; validated with q11 decode target-perf.
  - [x] Optimize overlapping Brotli back-reference output copying by doubling
        already-copied periodic regions with `blit_to`; q11 1 MiB decode
        target-perf improved from 258.079 to 242.629 ms/op on wasm-gc and from
        40.152 to 27.770 ms/op on native.
  - [x] Precompute Brotli command symbol info to remove repeated prefix-offset
        loops from decode and encode command handling.
- [x] **P1 correctness/perf evidence:** run and record fuzz/conformance gates
      that fit local release timing; reserve the documented 24-hour fuzz gate for
      final release readiness.
  - [x] Ran 25-input local fuzz gate generated from embedded fixtures.
  - [x] Ran all 22 upstream Google Brotli conformance fixtures through
        `unbrotli_sync`.
- [ ] **P3 5% release completion:** q2..q9 are already inside the measured
      5% Silesia windows. Finish broader corpus coverage and regression gates;
      only add more C-reference-style splitter/clustering work if a validation
      corpus slice exceeds the 5% size target or shows unacceptable performance.
  - [x] Enable bounded q2 split/context exact-costing for medium inputs,
        bringing `silesia-64k.bin` q2 within the 5% ratio target while preserving
        an explicit target-perf tradeoff record.
  - [x] Extend the same bounded q2 split/context exact-costing to 128 KiB
        chunks, bringing `silesia-128k.bin` q2 within the 5% ratio target.
  - [x] Enable q9 mixed-dictionary search with measured Silesia q9 overhead
        reduced to 3.03% on the 1 MiB slice.
  - [x] Measure and record q3..q8 with `target-perf.nu` and `ratio.nu` on the
        same representative corpus slices used for q2/q9.
  - [x] Add quality-aware q4..q8 differentiation. Current q3..q8 output is
        byte-identical on the measured Silesia slices; q4..q8 miss the 5% target
        because Google improves with quality while MoonBit does not.
  - [x] Record the current q2..q9 1 MiB ratio and 64 KiB wasm-gc/native
        target-perf matrix.
  - [x] Tune q6/q7 small-input runtime without losing the measured 5% ratio
        window.
  - [x] Revert the current q5 lighter-config trial and keep q5 on the
        accepted 16-check intermediate path. Trial evidence on `silesia-64k.bin`
        q5: size 22,785 bytes versus previous 22,336 bytes, wasm-gc 535.757 ms/op
        versus previous 541.752 ms/op, native 145.131 ms/op versus previous
        142.394 ms/op; the wasm-gc delta is too small to justify worse native
        runtime and worse 1 MiB ratio margin.
  - [x] Skip q5's redundant natural 4-byte candidate while keeping the q5
        intermediate 4-byte candidate. `silesia-1m.bin` q5 stays 278,961 bytes
        versus Google 274,088; `silesia-64k.bin` target-perf keeps 22,336 bytes,
        improves wasm-gc from 541.752 to 524.160 ms/op, and improves native from
        142.394 to 94.185 ms/op.
  - [x] Raise q9's standard chunk size to 2 MiB, bringing `silesia-2m.bin` q9
        from +6.04% to +4.69% versus Google while preserving 64 KiB q9
        target-perf evidence.
  - [x] Recover the 2 MiB q2 ratio gap with a 2 MiB chunk and proportional
        command budget; current evidence is +2.41% versus Google q2.
  - [x] Apply the 2 MiB chunk strategy to q3..q8 with dynamic command-budget
        scaling above 1 MiB; all measured `silesia-2m.bin` q3..q8 outputs are now
        within 5% of Google.
  - [x] Implement richer histogram/block clustering beyond current single
        split/context candidates, covering literal, command, and distance block
        layouts with guarded command-only, distance-only, literal+command,
        command+distance, and literal+distance exact-costed candidates. This closes
        the currently practical pairwise block-layout work, but not the original
        full C-reference dynamic block splitter / Lloyd clustering requirement.
- [ ] Broaden q2..q9 validation beyond the current Silesia slices, covering
      small files, text-heavy data, binary-heavy data, and selected fuzz-corpus
      roundtrips. Keep q2..q9 within roughly 5% of Google Brotli on agreed release
      corpora while preserving current wasm-gc/native target-perf baselines.
  - [x] Enforce the revised 5% q2..q9 Silesia ratio target inside
        `tools/brotli/release/validate.nu` via `--p3-max-overhead 0.05`, so the
        release gate now fails on measured P3 ratio regressions instead of only
        printing JSON evidence.
  - [x] Add a large single-copy periodic fast path for <=256 KiB inputs, with
        exact-costed stored-prefix plus copy-only suffix output. This improves
        `periodic-allbytes-200k.bin` q2 from 350 to 301 bytes and q3..q9 from
        350 to 272 bytes; q9 native encode target-perf improves from 666.810 to
        72.173 ms/op while preserving Silesia 128 KiB q2/q5/q9 sizes.
  - [ ] Decide small-file ratio policy: strict percentage overhead is too noisy
        for inputs like 84-byte dictionary text and likely needs an absolute-byte
        allowance or minimum input-size threshold.
  - [ ] Continue periodic/synthetic tuning for q9 if the exact threshold is
        strict; the large single-copy split brings q2..q8 within the 5% window on
        the 200 KiB periodic sample, while q9 is 272 bytes versus Google 259
        (+5.02%).
  - [ ] Select and measure the broader non-Silesia release corpus before
        closing this item.
- [ ] **P4 5% completion:** bring q10/q11 from the current
      +9.05%/+10.49% Silesia 1 MiB overhead to <=5% on the agreed validation
      corpora while preserving acceptable wasm-gc/native encode performance.
      Completing the full C-reference Zopfli/suffix-tree backend is no longer a
      mandatory acceptance criterion; it remains an option if lower-cost
      high-quality parser, dictionary, block-layout, or bounded shortest-path
      candidates cannot reach the 5% target.
  - [ ] Rebaseline q10/q11 under the revised target with
        `tools/brotli/bench/target-perf.nu` for wasm-gc/native encode plus
        representative decode, and with `tools/brotli/bench/ratio.nu` on Silesia
        64 KiB, 128 KiB, 1 MiB, and 2 MiB slices.
  - [ ] First try low-risk exact-costed q10/q11 candidates that can improve
        size without changing the parser cost shape drastically: broader but
        guarded mixed-dictionary subsets, q10/q11 use of existing q4+ pairwise
        block-layout candidates, and improved high-quality parser scoring.
  - [ ] If low-risk candidates cannot reach <=5%, extend the existing bounded
        shortest-path seed incrementally: 64 KiB/128 KiB caps, small beam-width
        trials, better suffix-tree candidate pruning, and greedy-seeded cost model
        refinement. Accept only candidates with target-perf evidence that the
        size win is worth the wasm-gc/native encode cost.
  - [ ] Reject changes that only make tiny q10/q11 size gains while causing
        large wasm-gc/native regressions. Prior rejected trials remain relevant:
        wider mixed transforms, 384 checks, 512 checks, and the 1 MiB DP prototype
        all had poor size/performance tradeoffs. Also rejected a plain q10/q11
        2 MiB chunk-size promotion: it saved 11,064 bytes on `silesia-2m.bin`, but
        still left q10/q11 at +9.72%/+11.18% and regressed native `cc-o0` encode
        by roughly 17-36%.
  - [ ] When q10/q11 reach <=5%, rerun external Google decode, MoonBit
        roundtrip, fuzz smoke, and target-perf gates before marking P4 complete
        under the revised acceptance policy.
  - [x] Deepen q11 hash-chain search to 256 checks and preserve recent-distance
        matches unless a hash-chain candidate is at least two bytes longer,
        improving q11 ratio with explicit wasm-gc/native target-perf tradeoff
        evidence. Rejected 512 checks as too encode-expensive for the release
        direction.
  - [x] Reject local q10/q11 greedy knobs that do not move both size and
        wasm-gc/native performance in the right direction: stricter lazy skipping,
        distance-bit candidate scoring, 4-byte minimum matches, direct context16
        writing, skipping preliminary candidates, and q10-only wider selected
        mixed-dictionary transforms. Rejected the 384-check q10/q11 parser trial:
        the 1 MiB size win was too small for the 128 KiB q10 wasm-gc/native
        target-perf regression and the q11 64 KiB native regression.
  - [x] Remove duplicate mixed static-dictionary command construction from the
        chunked q10/q11 path, preserving the `silesia-128k.bin` q10/q11 byte sizes
        while improving encode target-perf on both wasm-gc and native `cc-o0`.
  - [ ] **Highest remaining priority under the revised target:** reach the
        q10/q11 <=5% size window with the cheapest acceptable implementation. Start
        with exact-costed high-quality parser, dictionary, and block-layout work;
        escalate to a broader bounded shortest-path/Zopfli-style candidate only if
        those lower-cost candidates cannot close the remaining gap.
    - [x] Prototype and reject a bounded 1 MiB q10/q11 shortest-path DP
          candidate: it improved 1 MiB q10/q11 Silesia output from 266,056 to
          263,496 bytes, but regressed native debug encode target-perf from
          4275.087 ms to 18179.669 ms and was not commit-ready.
    - [x] Add a conservative 32 KiB q10/q11 shortest-path seed, then extend it
          to enumerate multiple previous hash-chain matches per position while
          preserving exact-cost final selection and the documented P4 release
          exception.
    - [x] Extend the bounded seed's single-best DP state to carry Brotli
          recent-distance cache state, so q10/q11 can safely model short-code
          distance savings without corrupting large streams.
    - [x] Extend from single-best DP state to a bounded two-state beam while
          preserving 32 KiB cap and exact-cost final selection.
    - [x] Initialize the bounded seed's lightweight cost model from the current
          greedy command stream's literal and distance histograms.
    - [x] Add a bounded suffix binary-tree match source to the small-input seed
          while preserving the 32 KiB cap and exact-cost final selection.
    - [x] Share the bounded seed's copy-transition helper between hash-chain
          and suffix-tree match providers so future P4 parser work has one recent
          distance cache and beam insertion path to extend.
  - [x] **Old heuristic stop point:** local greedy/hash-chain q10/q11 tuning
        was paused under the original 2% P4 target. Under the revised 5% target,
        reopen q10/q11 optimization with stricter size/perf tradeoff gates instead
        of requiring a full Zopfli backend by default.
  - [x] **Current practical block-layout work:** add block/histogram clustering beyond the current
        single split/context candidates, covering literal, command, and distance
        block layouts rather than command-block or literal-block splits alone.
    - [x] Add a bounded q10/q11 mixed static-dictionary + high-quality LZ77
          parser candidate for 8+ byte identity dictionary words, improving
          Silesia q10/q11 ratio with wasm-gc/native target-perf evidence while
          keeping the main high-quality parser cost near the previous release
          baseline.
    - [x] Extend the mixed dictionary index to the three known same-length
          transforms `[0, 9, 44]`, gaining another small q10/q11 ratio win without
          returning to the rejected all-transform scan cost.
    - [x] Add the two trailing-space selected extra transforms `[1, 4]` to the
          q10/q11 mixed dictionary index, improving text ratio while rejecting the
          full selected-extra transform scan as too slow.
    - [x] Reject a binary literal/command/distance joint block split: exact
          costing at 1/4, 1/2, and 3/4 command boundaries did not improve
          `silesia-64k.bin` or `silesia-1m.bin`.
    - [x] Add a guarded two-command-block histogram split candidate for q4+,
          with exact-cost selection and synthetic command-skew roundtrip coverage.
    - [x] Add a guarded two-distance-block histogram split candidate for q4+,
          with exact-cost selection and synthetic distance-skew roundtrip coverage.
    - [x] Add a guarded combined command-block plus distance-block split
          candidate for q4+, keeping independent command and explicit-distance
          boundaries while exact-cost selection protects existing natural-corpus
          outputs.
    - [x] Add a guarded combined literal-block plus command-block split
          candidate for q4+, keeping independent literal-event and command-event
          boundaries while exact-cost selection protects existing natural-corpus
          outputs.
    - [x] Add a guarded combined literal-block plus distance-block split
          candidate for q4+, completing pairwise literal/command/distance
          block-layout coverage without enabling the rejected three-stream joint
          split.
    - [x] Add a guarded combined literal-block plus command-block split
          candidate for q4+, keeping independent literal-event and command-event
          boundaries while exact-cost selection protects existing natural-corpus
          outputs.
    - [x] Add a guarded combined literal-block plus distance-block split
          candidate for q4+, completing pairwise literal/command/distance
          block-layout coverage without enabling the rejected three-stream joint
          split.
  - [x] **Practical release validation checkpoint:** with the q10/q11 P4 ratio
        exception documented, rerun ratio, wasm-gc/native target-perf, external
        Brotli decode, MoonBit all-target check/test/info, conformance, and the
        short local fuzz gate.
  - [x] **Release validation tooling:** batch fuzz harness inputs so the full
        checked-in corpus can run as a normal local gate instead of invoking
        `moon test` once per input.
  - [x] **Release validation tooling:** add fuzz-runner target selection so the
        generated corpus can cover `native`, `wasm-gc`, `js`, or `all` backends.
  - [x] **Release validation tooling:** add an encoder roundtrip fuzz harness
        for selected qualities and MoonBit targets.
  - [x] **Release validation tooling:** make fuzz harness locks recover stale
        interrupted-run state without allowing concurrent generated-test writes.
  - [x] **Release validation tooling:** add a single Nushell release gate that
        runs the current practical validation matrix without invoking target-perf by
        default.
  - [x] **Release reporting:** write the current Brotli release-readiness report
        with validation evidence, target-perf baseline references, and explicit P4
        exception status.
  - [x] **Release packaging gate:** add Justfile entries and package validation
        so local release checks cover `moon package` and `moon publish --dry-run`
        package verification.
  - [x] **Long fuzz gate tooling:** add a repeatable soak runner and Justfile
        entries for the 24-hour fuzz gate; smoke validation covers one decoder fuzz
        iteration and one encoder roundtrip fuzz iteration.
  - [x] **Corpus reproducibility:** make fuzz corpus generation seed-driven and
        output-directory configurable so broader release corpora can be reproduced
        exactly.
  - [x] **Generated corpus gate:** wire deterministic corpus generation into
        the practical release runner and Justfile so broader decoder fuzz sweeps are
        one-command reproducible.
  - [x] **Final release readiness:** run the broader generated release corpus
        and a bounded multi-iteration soak to verify the current release-validation
        runner and soak path.
  - [x] **Final release tooling:** expose the bounded full-corpus soak as a
        Justfile entry so release validation can rerun the finite soak evidence
        without spelling out the Nushell command.
  - [x] **Final release tooling:** expose aggregate release-candidate Justfile
        entries for the accepted full and smoke release-validation gate sets.
  - [x] **Final release tooling:** add explicit soak log append mode so
        interrupted or segmented long fuzz soaks can preserve evidence and resume
        iteration numbering.
  - [x] **Final release tooling:** add direct Justfile recipes for
        conformance, decoder fuzz, encoder roundtrip fuzz, ratio, and
        wasm-gc/native target-perf checks, and simplify generated-test batch
        runners with Nushell `generate`.
  - [x] **Final release tooling:** keep ignored placeholder generated-test
        files after conformance, decoder fuzz, and encoder roundtrip fuzz runs so
        later incremental MoonBit commands do not fail on stale `_build` inputs.
  - [x] **Final release tooling:** extend owner-PID stale-lock recovery to
        conformance and target-perf, and make target-perf use a stable ignored
        generated-test placeholder path.
  - [ ] **Final release tooling:** land the updated target-perf main-package
        harness. It keeps an ignored placeholder main package, reads native inputs
        through tool-only C FFI, and labels native rows with `native_cc: "cc-o0"`
        until the default `clang -O2` release path is made practical.
  - [ ] **Final release readiness:** run any project-required 24-hour fuzz soak
        before cutting a final public release artifact.

## Validation Matrix

```bash
moon check --target all
moon test --target native
moon test --target wasm-gc
moon test --target js
moon fmt
moon info
```

For phase completion, also run the phase-specific conformance and benchmark
commands recorded in `docs/brotli.md`.

## Status

- 2026-05-24: started Brotli implementation from a clean worktree. Existing
  project-root planning files belong to a completed ZIP performance task, so
  this scoped plan lives under `.planning/brotli-support/`.
- 2026-05-24: P1 public API foundation implemented and validated. This is not
  P1 completion; the RFC decoder core, dictionary, fixtures, conformance
  harness, and fuzz harness remain.
- 2026-05-24: P1 uncompressed meta-block path implemented and validated. This
  enables q=0/stored Brotli fixture decoding but still does not cover compressed
  Huffman meta-blocks or dictionary paths.
- 2026-05-24: P1 Huffman foundation implemented and validated. This covers
  two-level table decode and simple Huffman headers; complex Huffman headers and
  compressed command decoding remain.
- 2026-05-24: P1 complex Huffman reader implemented and validated. The full
  compressed meta-block state machine still needs block/context maps and command
  decoding.
- 2026-05-24: P1 block metadata helpers implemented and validated. These are
  not wired into the main decoder yet, so temporary unused-helper warnings are
  expected.
- 2026-05-24: P1 context map decoding implemented and validated. Tree groups
  and the compressed command loop remain before compressed meta-blocks can
  decode real payloads.
- 2026-05-24: P1 Huffman tree group reader implemented and validated. The
  compressed meta-block header still needs to wire block trees, context maps,
  distance parameters, and tree groups together.
- 2026-05-24: P1 compressed meta-block header reader implemented and wired into
  the scaffold. The command/body loop, distance resolution, ring buffer, and
  dictionary paths remain.
- 2026-05-24: P1 command prefix lookup and first-command reading implemented.
  Literal insertion, copy/back-reference handling, and block switching remain.
- 2026-05-24: P1 minimal literal-only compressed body path implemented. Copy,
  distance resolution, block switching, context modes, and dictionary handling
  remain.
- 2026-05-24: P1 implicit short-distance copy path implemented and validated.
  Explicit distance symbols, block switching, literal/distance contexts, and
  dictionary handling remain.
- 2026-05-24: P1 explicit distance formula/tree path implemented and
  validated. Block switching, literal/distance contexts, static dictionary, and
  corpus tooling remain.
- 2026-05-24: P1 block switching wired into compressed body decoding and
  validated. Full literal context modes, static dictionary, and corpus tooling
  remain.
- 2026-05-24: P1 literal context modes wired into compressed body decoding and
  validated. Static dictionary, cross-meta-block distance cache persistence,
  and corpus tooling remain.
- 2026-05-24: P1 decoder state introduced and recent-distance cache persistence
  validated. Static dictionary and corpus tooling remain.
- 2026-05-24: P1 static dictionary identity-transform path implemented and
  validated. Non-identity transforms and corpus tooling remain.
- 2026-05-24: P1 static dictionary transform metadata and non-identity
  transform application implemented and validated. Corpus tooling and broader
  real fixture coverage remain.
- 2026-05-24: P1 embedded fixture tests and full upstream conformance harness
  added and validated. This is still not P1 completion; window-distance limits,
  explicit malformed/truncation/bomb tests, fuzz harness scaffolding, and
  Silesia q=11 acceptance evidence remain.
- 2026-05-24: P1 window-distance hardening, negative tests, and fuzz harness
  scaffolding implemented and validated. This is still not P1 completion;
  Silesia q=11 acceptance evidence and warning cleanup/justification remain.
- 2026-05-24: 100 MiB Silesia q=11 acceptance artifact decoded successfully
  through the JavaScript backend. Remaining P1 work is longer fuzz evidence and
  final phase bookkeeping.
- 2026-05-24: P1 acceptance bookkeeping completed with focused timing,
  rust-brotli fixture proof, and Google dictionary-transform fixture proof.
- 2026-05-24: P2 q=0/q=1 encoder backend implemented as RFC-valid
  uncompressed meta-block output. 100 MiB Silesia q=0/q=1 streams decode with
  the external Brotli CLI to the original SHA-256.
- 2026-05-24: P3 q=2..9 dispatch enabled through the current RFC-valid backend.
  This satisfies stream validity and API coverage, but it is not P3 completion:
  the documented hash-chain/back-reference/block-splitter/ratio criteria remain
  incomplete.
- 2026-05-24: P4 q=10/q=11 dispatch enabled through the same RFC-valid backend.
  All standard quality levels now produce externally decodable Brotli streams,
  but this is not P4 completion: Zopfli search, suffix tree, and 2% ratio
  criteria remain incomplete.
- 2026-05-24: First real q2 compressed meta-block encoder path landed for
  single-byte runs. A 1 KiB repeated `A` input encodes to 11 bytes and decodes
  correctly through the external Brotli CLI.
- 2026-05-24: q2 compressed path generalized to unique short periods 1..4.
  A 1 KiB repeated `ABCD` input encodes to 15 bytes and decodes correctly
  through the external Brotli CLI.
- 2026-05-24: q2 compressed path generalized to one literal prefix plus one
  copied suffix. A 1 KiB `XABCABC...` input encodes to 15 bytes and decodes
  correctly through the external Brotli CLI.
- 2026-05-24: q2 compressed path generalized to greedy multi-command output for
  small literal alphabets. A 1207-byte `ABCABCX + ABCABC...` input encodes to
  17 bytes and decodes correctly through the external Brotli CLI.
- 2026-05-24: q2 compressed path gained complex Huffman tree emission. A
  five-literal periodic input encodes to 22 bytes, and the previously
  uncompressed 1400-byte irregular small-alphabet input now encodes to 306
  bytes; both decode correctly through the external Brotli CLI.
- 2026-05-24: Added `tools/brotli/bench/ratio.nu`. Current q2 Silesia baseline
  is MoonBit 104857629 bytes versus Google 35495150 bytes, confirming the
  remaining P3 work is large-data matching/block splitting rather than stream
  validity.
- 2026-05-24: q2 large-input chunking now compresses a 200 KiB periodic
  `ABCDE` input to 2,820 bytes and decodes through Google Brotli. Full 100 MiB
  Silesia q2 now completes through the ratio harness at 104,862,404 bytes
  versus Google 35,495,150 bytes, so P3 remains open for general block
  splitting, entropy coding, and natural-data matching.
- 2026-05-24: q2 low-alphabet chunks now use frequency-weighted Huffman
  lengths when they beat fixed-length trees. The irregular 1400-byte
  small-alphabet fixture improved from 306 to 231 bytes versus Google 169
  bytes, while the 200 KiB periodic chunked fixture remains at 2,820 bytes.
  Silesia remains unchanged while the natural-data gate is in place.
- 2026-05-24: q2 chunk selection now allows high-alphabet chunks when sampled
  positions show very dense repeated 4-byte sequences. A 200 KiB corpus cycling
  all 256 byte values encodes to 5,878 bytes and decodes through Google Brotli.
  Silesia remains stored because ordinary natural-data block splitting is still
  not implemented.
- 2026-05-24: q2 hash matches now extend up to 4,096 bytes instead of 64.
  The 200 KiB `ABCDE` periodic corpus improved from 2,820 to 249 bytes, and
  the 200 KiB all-256-byte periodic corpus improved from 5,878 to 1,399 bytes.
  Full Silesia q2 remains unchanged at 104,862,404 bytes versus Google
  35,495,150 bytes.
- 2026-05-24: added `tools/brotli/bench/chunk-match.nu` to measure per-chunk
  unique literals, sampled 4-byte match density, and bounded greedy-copy
  estimates. First 16 Silesia chunks cap out at 1,201 commands for min lengths
  4 and 8, while min length 16 averages 909 commands and 35.02% copied bytes;
  periodic all-byte chunks remain easy at 16 commands and 99.61% copied bytes.
- 2026-05-24: split the active q2 hash helpers out of `brotli_encode.mbt` into
  `brotli_encode_hash.mbt`, matching the P3 file plan before expanding the
  hash-chain implementation.
- 2026-05-24: threaded `BrotliHashConfig` through standard q2+ encoding so
  table size, search depth, match length, and density thresholds are no longer
  hardcoded in the meta-block writer.
- 2026-05-24: added config fields for min match length, scan step, command
  cap, copied-byte admission, and dense-density gating. A q9 sparse-match trial
  on 1 MiB Silesia stayed stored at 1,048,628 bytes and took 12.158s, so the
  trial was documented and left disabled.
- 2026-05-24: complex Huffman tree encoding now uses repeat-zero code-length
  RLE. `small-alpha-multi-1400.bin` q2 improved from 231 to 195 bytes, and
  `periodic-abcde-200k.bin` q2 improved from 249 to 240 bytes; both decode
  through Google Brotli.
- 2026-05-24: complex Huffman tree encoding now uses repeat-previous
  code-length RLE. `periodic-allbytes-200k.bin` q2 improved from 1,399 to
  1,382 bytes and decodes through Google Brotli.
- 2026-05-24: low-alphabet chunks can now use a literal-only compressed
  meta-block. A 16 KiB 64-symbol xorshift fixture improved from stored 16,004
  bytes to 12,022 bytes, slightly smaller than Google q2's 12,029 bytes for
  that artificial corpus.
- 2026-05-24: high-alphabet literal-only chunks now use length-limited weighted
  literal Huffman trees behind an entropy precheck. The 1 MiB Silesia q2 slice
  improved from the stored 1,048,628-byte baseline to 657,233 bytes versus
  Google q2's 320,418 bytes.
- 2026-05-24: q2+ can now emit identity static-dictionary copies for small
  single-block inputs. A generated dictionary-word fixture encodes to 76 bytes
  versus Google q2's 78 bytes and decodes through Google Brotli; the broad
  chunked Silesia dictionary trial was rejected because it was slower and
  slightly larger.
- 2026-05-24: q2+ literal-only candidates can now split a meta-block into two
  literal block types at the midpoint. The 1 MiB Silesia q2 slice improved
  from 657,233 to 656,982 bytes versus Google q2's 320,418 bytes; this is a
  structural block-splitting increment, not P3 completion.
- 2026-05-24: midpoint split candidates now use a Huffman-length admission
  estimator. The 1 MiB Silesia q2 size stays 656,982 bytes while the ratio
  harness time drops from about 20.6s to 14.7s.
- 2026-05-24: the literal splitter now estimates quarter, midpoint, and
  three-quarter split points, then writes only the best admitted split. The
  1 MiB Silesia q2 slice improves from 656,982 to 656,614 bytes.
- 2026-05-24: q2+ now tries a separate long-match natural-data candidate for
  large inputs. The 1 MiB Silesia q2 slice improves from 656,614 to 579,879
  bytes while the small 1.4 KiB alpha fixture stays at 195 bytes.
- 2026-05-24: the long-match candidate minimum copy length was tuned to 16
  bytes. The 1 MiB Silesia q2 slice improves further to 471,230 bytes.
- 2026-05-24: q2+ chunked encoding now uses 256 KiB meta-block chunks and a
  proportional natural command cap. The 1 MiB Silesia q2 slice improves to
  462,172 bytes, and the periodic-allbytes fixture improves to 494 bytes.
- 2026-05-24: q2+ chunked encoding now uses 1 MiB meta-block chunks. The
  1 MiB Silesia q2 slice improves to 460,961 bytes.
- 2026-05-24: weighted Huffman tree construction now applies to command and
  distance alphabets. The 1 MiB Silesia q2 slice improves to 457,776 bytes.
- 2026-05-24: the natural long-match candidate now uses a one-byte lazy-match
  check. The 1 MiB Silesia q2 slice improves to 455,386 bytes.
- 2026-05-24: the natural candidate max copy length was raised to 16 KiB.
  `periodic-allbytes-200k.bin` q2 improves from 494 to 350 bytes; Silesia is
  unchanged at 455,386 bytes.
- 2026-05-24: q9 now tries an additional high-quality long-match candidate with
  a 12-byte minimum copy length. The 1 MiB Silesia q9 slice improves from
  455,386 to 422,673 bytes while q2 remains 455,386 bytes.
- 2026-05-24: q9 now skips the q2 natural long-match candidate. The 1 MiB
  Silesia q9 size remains 422,673 bytes while ratio-harness time drops from
  about 45.9s to 23.7s.

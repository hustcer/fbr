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

## P4 q10/q11 Root-Cause Diagnostic (2026-06-15)

- The gap is in PARSING (match selection), not entropy coding. Evidence from
  the 2026-06-13 release report, Silesia 64 KiB:
  - q9: Google 21,904 vs MoonBit 21,397 (MoonBit BEATS Google q9 by -2.31%).
  - q10: Google 19,463 vs MoonBit 21,302 (+9.45%).
  - q11: Google 19,154 vs MoonBit 21,302 (+11.21%).
  - Google jumps 21,904 -> 19,463 from q9 to q10 (-11%). MoonBit barely moves
    21,397 -> 21,302 (-0.4%). Since MoonBit's q9 entropy coding already beats
    Google's q9, the entropy/Huffman/context/block-split stack is competitive;
    the missing 9-11% is the optimal (Zopfli-style) parse that Google switches
    on at q10/q11 and MoonBit does not yet match.
- Current code state (confirmed by reading src/encode/encode.mbt):
  - q10/q11 dispatch DOES call `brotli_build_bounded_shortest_path_command_candidate`
    (line ~6164) but `brotli_bounded_shortest_path_config` sets
    `max_input_length: 32768` (line ~3048), so the DP returns None for the
    64 KiB/128 KiB benchmark chunks. The committed q10/q11 output is the fast
    greedy mixed-dictionary result (21,302 / 38,565), not the DP.
  - The DP cost model (`brotli_bounded_shortest_path_copy_cost`, line ~2984)
    uses a FLAT command/length base cost of `8 + length_extra_bits +
    distance_bits`. It does not model real command-symbol entropy, and the
    whole DP is a SINGLE pass with a cost model seeded from one greedy parse
    (`brotli_bounded_shortest_path_cost_model`). Google q11 iterates the cost
    model to convergence; that iteration is the untried high-leverage lever.
  - beam width = 2 (`brotli_bounded_shortest_path_beam_width`). A 4-element
    `current_cache` FixedArray is allocated per position per slot inside the
    DP loop (line ~3268) -> heavy GC pressure, a likely speed cost.
- Speed budget is large and currently unused: committed q10/q11 ~12 ms (64 KiB)
  / ~21 ms (128 KiB) native vs Google q11 69 ms / 147 ms. The 250% ceiling is
  ~172 ms (64 KiB) / ~368 ms (128 KiB). The rejected DP activation was 439 ms
  (64 KiB), i.e. ~2.5x over the 64 KiB ceiling, so a viable DP needs both a
  ratio gain (past +6.66%) AND a ~2.5x speedup.
- Strategy order for this pass (user instruction: size first, then speed):
  Phase 1 chase the -7%..+3.5% size target (cheap to measure via
  `tools/encode/verify.nu`); Phase 2 optimize speed to <=250% of Google.
  Untried levers, highest leverage first: (1) iterate the DP cost model
  (re-seed from the DP's own output and re-parse), (2) real command-symbol
  cost in the cost model, (3) remove per-position allocations / beam=1 trial
  for speed.

## P4 q10/q11 2026-06-15 measured results (this session)

- DP single-pass live baseline (max_input_length raised to 131072,
  max_commands 131072): 128 KiB q10 = 37,814 bytes (+6.67%), reproducing the
  prior reverted trial exactly. 64 KiB still 21,302 because 64 KiB uses the
  `brotli_encode_standard` inline path (line ~6538, mixed-dict only, no DP),
  while 128 KiB routes through `brotli_encode_chunked_standard` ->
  `brotli_try_compressed_chunk` which has the DP (line ~6164).
- FAILED attempt 1 — DP cost-model iteration (Zopfli re-seed, 2 passes):
  128 KiB q10 37,814 -> 37,806 (8 bytes, +6.67% -> +6.65%). Negligible. Root
  cause: `brotli_bounded_shortest_path_cost_model_from_commands` only refines
  literal_bits and distance_bits; the command/copy-length cost in
  `brotli_bounded_shortest_path_copy_cost` is a FLAT 8, so iteration never
  refines command structure. Reverted (kept the unused `cost_model_override?`
  param for possible reuse).
- DECISIVE speed finding — DP single-pass 128 KiB q10 encode time
  (`target-perf.nu --repeats 20 --samples 3`): native 580.2 ms, wasm-gc
  502.8 ms vs Google 55.6 ms. That is 10.4x (native) / 9.0x (wasm-gc) of
  Google = ~1040% / 900%, far above the 250% ceiling (q10 128 KiB budget
  ~137 ms). The DP is strictly dominated: slower than Google's real Zopfli AND
  worse ratio (+6.6% vs 0). It is UNCOMMITTABLE on speed as architected.
  Note q11's budget is looser (Google 147 ms -> 368 ms ceiling), so the DP is
  only ~1.6x over for q11; a q11-only slower-better path is the one place the
  DP could fit on speed, but it still misses the size target at +6.6%.
- Working conclusion: the +3.5% size target requires true Zopfli-quality
  optimal parsing (Google's q9->q10 -11% jump is exactly that). The available
  bounded-DP plateaus ~+6.6% and is 10x over budget; entropy coding is already
  competitive (MoonBit q9 beats Google q9), so there is no 9% to recover
  there. Reaching the target appears to need the H10 + ZopfliNode + iterated
  full cost model backend the plan explicitly de-scoped, which would also
  stress the speed budget.
- Feasibility probe — DP deep search (max_match_checks 32->256,
  max_match_length 4096->65536, single pass): 128 KiB q10 37,814 -> 37,501
  (+6.67% -> +5.79%, 313 bytes). So match-finding depth IS a real lever
  (more than iteration's 8 bytes), but it still misses +3.5% by ~2.3 points
  (~812 bytes short) and makes the already-10x-over-budget DP ~8x more
  match work, i.e. far slower. Combining deep search + iteration + a full
  command cost model might close more size but every lever raises an
  already-uncommittable encode time.
- DECISION POINT (2026-06-15): size target (+3.5%) and speed ceiling (<=250%)
  are mutually exclusive under the current architecture. The shallow DP fits
  only q11's looser budget (~1.6x over, a possible q11-only path) at +6.6%
  size, which misses the target; reaching the size target needs deep
  search + iteration that pushes encode time to ~15-20x Google. The only way
  to get BOTH is Google's efficient Zopfli (H10 binary tree makes deep search
  cheap + clean O(n) shortest-path), a large de-scoped rewrite. All
  experimental encode.mbt edits were reverted; the tree is back to the
  committed fast greedy q10/q11 (+8.79%/+9.45%). Surfaced the fork to the user
  rather than burning the remaining attempt budget on negative-cache tweaks.
- OUTCOME (2026-06-15): user chose the q11-partial path. LANDED a committable
  q11 improvement. What worked:
  - Gate the bounded optimal-parse DP to q11 ONLY (site A chunked path
    `quality >= 11`; site B `brotli_encode_standard` inline path adds a q11 DP
    candidate). q10 untouched -> q0..q10 byte-identical (zero regression).
  - Raise DP `max_input_length` 32768 -> 131072 and `max_commands` -> 131072 so
    64k/128k single chunks qualify. (Inputs whose chunk exceeds 131072 fall
    back to greedy; q11 chunk size is 1 MiB, so >128 KiB inputs are not
    improved yet — see future work.)
  - beam_width 2 -> 1: ratio cost is only 11 bytes (64k) / 18 bytes (128k) but
    halves DP work. The beam-2 distance-cache divergence almost never pays here.
    This is the single biggest speed lever and is essentially ratio-free.
  - Remove per-(match,length) `next_cache` + per-match `bounded_lengths`
    allocations (reuse one 4-int buffer; inline length selection) and reuse the
    main-loop `current_cache` buffer. Pure refactors, size unchanged.
  - Drop the half-length DP representative (3 -> 2 lengths). Costs 1-3 bytes,
    real speed gain.
  - Net: native 128k q11 598.9 ms -> 330.7 ms.
- LANDED results (just bench 2026-06-15): q11 64k 20,904 (+9.14%, was +11.21%),
  native 2.02x / wasm-gc 1.97x Google; q11 128k 37,833 (+8.01%, was +10.10%),
  native 2.2x / wasm-gc 2.09x Google. All four cells within the 250% ceiling
  (not the 150% preference). q10 and q0..q9 unchanged. Validated: moon fmt,
  moon check --target all, moon test --target all (165), conformance (21),
  roundtrip fuzz q10/q11 (80 cases), report regenerated.
- The beam-2 code path is kept behind `brotli_bounded_shortest_path_beam_width
  >= 2` guards (offer_state + terminal) so beam can be re-enabled without
  rewriting the helper; the wbtest was updated to assert the live beam=1
  single-best-state behavior.
- Future work (recorded, not done): (1) let q11 use <=128 KiB chunks so larger
  inputs also get the DP within budget; (2) the only path to the original
  -7%..+3.5% target is an efficient H10 + O(n) ZopfliNode + iterated full
  command cost-model backend.

## P5 Efficient Zopfli backend blueprint (2026-06-15, from c/enc)

Goal: rewrite a proper Zopfli backend for q11 (H10-style matches + O(n)
shortest path + iterated full cost model). Reference: brotli
`c/enc/backward_references_hq.c` + `hash_to_binary_tree_inc.h`.

- q11 = `BrotliCreateHqZopfliBackwardReferences`: precompute all matches per
  position, then run EXACTLY 2 iterations:
  - iter 0: cost model = `ZopfliCostModelSetFromLiteralCosts` (per-literal
    entropy estimate; heuristic cmd cost `log2(11+i)`, dist cost `log2(20+i)`).
  - iter 1: cost model = `ZopfliCostModelSetFromCommands` (real literal/cmd/dist
    histograms from iter-0 commands, via SetCost entropy).
  Each iter: reset nodes/dist_cache, run ZopfliIterate (the DP), then
  BrotliZopfliCreateCommands. Final = iter-1 commands.
- Cost model (`SetCost`): per-symbol Shannon bits `cost[i]=log2(sum)-log2(hist[i])`,
  missing symbol = `log2(missing_sum)+2`, min 1 bit. Literals get a CUMULATIVE
  prefix-sum array `literal_costs_[0..n]` so the cost of inserting literals
  [from,to) is O(1) = `literal_costs_[to]-literal_costs_[from]` (with a float
  carry term for precision). Also `min_cost_cmd_` = min over cmd costs.
- DP node (`ZopfliNode`): per end-position store length(+code modifier),
  distance, insert_length(+short dist code), cost, and a backtrack `next`/
  `shortcut`. `nodes[0].cost=0`.
- O(n) magic = `StartPosQueue`: keeps the 8 lowest-`costdiff` start positions
  (costdiff = node_cost - literal_costs(0,pos)). For each pos, `UpdateNodes`
  only starts commands FROM those <=8 queued starts (not all O(n) starts).
  `MaxZopfliCandidates` start positions tried (q11 small, e.g. <=4); for k>=2
  only last-distance matches are tried.
- `UpdateNodes(pos)`: (1) EvaluateNode pushes pos to queue if reachable cheaply
  and computes its distance cache via ComputeDistanceCache/Shortcut; (2) for
  each queued start: inscode=GetInsertLengthCode(pos-start),
  base_cost=start_costdiff+insert_extra+literal_costs(0,pos); try the 16
  distance-cache short codes (each: find match len, for each l update
  nodes[pos+l] if cost cheaper) then (k<2) all H10 matches with normal distance
  codes. cost = cmd_cost(cmdcode)+copy_extra+dist_cost+base/dist_cost.
- `ComputeMinimumCopyLength`: skip lengths already reached at <= min possible
  future cost; `skip`/`BROTLI_LONG_COPY_QUICK_STEP` fast-forwards long copies
  (EvaluateNode-only) to stay O(n). `MaxZopfliLen` q11=325 collapses very long
  matches to a single candidate + skip.
- Backtrack (`ComputeShortestPathFromNodes` + `BrotliZopfliCreateCommands`):
  walk nodes[].next to emit (insert_len, copy_len, distance, dist_code),
  updating the real distance cache (dist_code 0 / dictionary refs do NOT update
  the ring).
- MoonBit reuse plan: use the existing `brotli_bounded_suffix_tree_match_table`
  (a suffix BST = morally H10) as the per-position match source; reuse the
  existing command/distance prefix encoders, BrotliEncodeCommand, and the
  meta-block writer (`brotli_write_best_lz77_metablock`). New code only needs
  the cost model + StartPosQueue DP + node backtrack -> command list. Plan to
  put it in a new file `src/encode/zopfli.mbt`, wired as a q11 candidate that
  replaces the bounded-DP candidate.

## P5 Zopfli rewrite ATTEMPT OUTCOME (2026-06-15) — reverted, not shipped

- Implemented the full backend in `src/encode/zopfli.mbt` (~700 lines): SetCost
  entropy cost model, sliding-window per-literal cost
  (`BrotliEstimateBitCostsForLiterals` non-UTF8 port), set-from-commands model,
  StartPosQueue (ring buffer, 8 slots), UpdateNodes DP with last-distance +
  new-match loops, ComputeDistanceShortcut/Cache, ComputeMinimumCopyLength,
  node backtrack to commands, 2-iteration driver. It COMPILES on all targets
  and produces VALID streams (roundtrip verified on synthetic data; the
  pipeline roundtrips through the Google decoder fine).
- Match source: hash chains (`brotli_bounded_previous_hash_matches_with_cache`)
  + suffix tree, deduped by distance, then a Pareto transform (sort by distance
  asc, keep strictly-increasing length) to get the H10 invariant. The table is
  rich: ~1.06M matches over 49,253/65,536 non-empty positions, maxlen 355. So
  match finding is NOT the problem.
- PROBLEM: the parse quality is WORSE than the existing bounded-DP and even the
  greedy mixed path. On Silesia 64 KiB q11:
  - iter 0 (heuristic/windowed cost): 4,103 commands, 55% copy coverage,
    written 26,511 bytes.
  - iter 1 (cost from iter-0 commands): DEGENERATES to ~400 commands
    (~92% literals), written ~35 KB.
  - vs bounded-DP 20,904 and mixed 21,302. So the new backend never wins; the
    final q11 output stayed 21,302 (mixed) because the Zopfli candidate is
    larger than mixed.
- Bugs found and fixed during the attempt (kept in the notes for a retry):
  - set-from-commands distance histogram must count the ACTUAL distance code
    (implicit last-distance commands, command symbol < 128, use short code 0),
    otherwise cost_dist[0] becomes the missing-symbol cost (~13.5 bits) and the
    DP avoids cheap last-distance copies. Fixed.
  - the match list must satisfy the H10 invariant (nearest distance per length)
    or the DP's running-length loop assigns far distances to short lengths.
    Fixed with the distance-sorted Pareto transform.
  - global literal histogram is too flat; switched iter-0 to the sliding-window
    estimate. Small effect here.
  - the `k >= 2` "last-distance only" restriction starved new-match coverage;
    removing it lifted copy coverage 37% -> 55% but still not enough.
- UNRESOLVED root cause (for a future retry): the StartPosQueue DP still finds
  fewer/worse copies than the beam-based bounded-DP that uses the SAME matches,
  and it skews toward explicit/far distances, so the written stream is larger.
  iter-1's collapse is a SYMPTOM of a suboptimal iter-0 (its literal/command
  distribution poisons the from-commands model). Likely suspects to check next:
  (a) the StartPosQueue is not retaining the optimal recent start positions
  (verify costdiff signs/ordering and `at(k)` ring indexing against a tiny
  hand-traced example); (b) distance-cost calibration vs the context-modeling
  writer; (c) the UTF8 windowed literal-cost variant
  (`EstimateBitCostsForLiteralsUTF8`) for text; (d) the `skip` long-copy
  fast-forward was omitted (correctness ok, but interacts with the queue).
- DECISION (2026-06-15): reverted the wiring to the working bounded-DP
  (q11 64k 20,904 / 128k 37,833, within the 250% budget — the shipped win, zero
  regression) and removed `src/encode/zopfli.mbt` + the debug test +
  the `moonbitlang/core/math` import. The source tree is byte-identical to
  commit 9007367 again. A future Zopfli retry should start from this blueprint
  and the bug list above, and validate iter-0 beats greedy on real 64 KiB data
  BEFORE wiring iterations.

## P5b bounded-DP + full cost model ATTEMPT OUTCOME (2026-06-15) — reverted

- Per the user's pivot (keep the working beam bounded-DP, upgrade its cost
  model), added an entropy copy-length-code cost (`copy_code_bits[24]`,
  default 8) to `BrotliBoundedShortestPathCostModel`, built it in
  `cost_model_from_commands`, used it in `copy_cost` (replacing the flat 8),
  added a `cost_model_override?` param, and wired a 2-pass iteration in both q11
  dispatch sites (seed from greedy, re-seed from the first DP output).
- RESULT: a wash / slightly negative. Silesia 64k q11 20,904 -> 20,991
  (+87 B, a small regression) and 128k 37,833 -> 37,808 (-25 B). The copy-code
  entropy changed the greedy-seed pass's parse and slightly hurt 64k; the
  iteration recovered little. Consistent with the long-standing finding that
  cost-model tweaks on the bounded-DP are a wash ("minor writer/cost changes
  have not moved q10/q11 size"). Reverted to the committed bounded-DP.
- COMBINED CONCLUSION (both 2026-06-15 attempts): the +3.5% size target is not
  reachable via either a from-scratch StartPosQueue Zopfli (parse-quality bugs,
  worse than greedy) or bounded-DP cost-model upgrades (a wash). The bounded-DP
  at q11 64k 20,904 (+9.06%) / 128k 37,833 (+7.96%), within the 250% speed
  budget, is the practical ceiling of the current match+parse machinery.
  Reaching Google's q11 (19,154 / 35,027) needs its exact H10 binary-tree match
  finder + ZopfliNode shortest path tuned to parity — a large effort that this
  session's from-scratch port did not achieve to quality. Recommend keeping the
  shipped bounded-DP q11 win; treat closing the rest of the gap as a separate,
  larger project.

- Minor writer selection changes have not moved q10/q11 size; reaching 5%
  probably requires a material command-stream improvement or distinct q11
  parser behavior.
- 2026-06-14 user constraint for the resumed q10/q11 pass: try at most ten
  independent strategies before stopping if no useful result appears. Test one
  strategy at a time. Commit only when an improvement is real, and keep encode
  time within 250% of Google Brotli, preferably within 150%.
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
- Rejected q10/q11 trial (2026-06-14): limiting the context8-first writer
  shortcut to q3..q9 so q10/q11 would exact-compare later split/context
  candidates did not change Silesia 64 KiB output at all. q10/q11 remained
  21,302 bytes with the same SHA-256, so the later writer candidates did not
  beat context8 on that command stream. Do not retry unchanged; it only adds
  writer passes.
- Rejected q10/q11 DP tuning trials (2026-06-14): adding bounded shortest-path
  representative copy lengths `[8, 16, 32, 64, 128]` on top of
  `min/half/full` saved only 4 bytes on Silesia 64 KiB while increasing search
  cost. Raising the bounded beam width from 2 to 4 saved 0 bytes on the same
  row. Keep the two-state `min/half/full` DP shape unless a different cost
  model or candidate source changes the tradeoff.
- Rejected q10/q11 DP activation trial (2026-06-14): enabling the existing
  bounded shortest-path candidate for 64 KiB and 128 KiB direct q10/q11 input
  produced real but insufficient size wins and an unacceptable speed hit.
  Best 64 KiB combination tested (DP + approximate command-symbol cost +
  q10/q11 min match 3 + mixed transform 49 + mixed cost seed) reached only
  20,760 bytes versus Google q10 19,463 (+6.66%), while
  `target-perf.nu --repeats 5 --samples 1` measured native 439.98 ms and
  wasm-gc 352.50 ms versus Google 34.31 ms. Do not land this bounded-DP
  activation unchanged; it misses the size target and is 10x+ slower.
- Rejected q10/q11 DP micro-tweaks from the same trial: lowering high-quality
  min match length 5 -> 4 saved only about 45 bytes on Silesia 64 KiB q10;
  4 -> 3 saved only another 11 bytes and slowed search further. Adding mixed
  dictionary transform 49 (`ing `) saved only about 3 bytes. Using mixed
  dictionary commands as the DP cost-model seed saved about 1 byte. Reopening
  these knobs needs a different parser design, not another isolated retry.
- Rejected q10/q11 greedy parser tie-break (2026-06-14): for
  `max_match_checks >= 256`, allowing equal-length hash-chain candidates to
  replace the incumbent when they had a smaller estimated distance code did
  not change Silesia 64 KiB q10/q11 output or SHA-256. Do not retry unchanged;
  the current Silesia command stream has no useful equal-length cheaper-distance
  substitutions on that row.
- Rejected q10/q11 strategy 1 (2026-06-14 constrained loop): replacing the
  q10/q11 greedy "longest match wins" rule with an official-style
  distance-aware backward-reference score, including score-based lazy
  lookahead, worsened Silesia 64 KiB q10/q11 from 21,302 to 21,311 bytes.
  `moon check src/encode --target all` passed before the ratio run, but the
  size result regressed and the source change was reverted. Do not retry this
  plain scoring replacement unchanged.
- Rejected q10/q11 strategy 2 (2026-06-14 constrained loop): adding a 3-byte
  high-quality candidate before the current q10/q11 4-byte high-quality mixed
  candidate produced identical Silesia 64 KiB q10/q11 output, 21,302 bytes with
  the same SHA-256. `moon check src/encode --target all` passed; the source
  change was reverted. Do not retry plain 3-byte HQ candidate competition
  unchanged.
- Rejected q10/q11 strategy 3 (2026-06-14 constrained loop): making q10/q11
  lazy matching less aggressive by requiring `next_length > current_length +
  skipped_literals` worsened Silesia 64 KiB q10/q11 from 21,302 to 21,388
  bytes. `moon check src/encode --target all` passed; the source change was
  reverted. Keep the existing `next_length > current_length` lazy rule unless
  a broader parser redesign changes the tradeoff.
- Rejected q10/q11 strategy 4 (2026-06-14 constrained loop): raising
  high-quality q10/q11 lazy lookahead from 3 to 4 worsened Silesia 64 KiB
  q10/q11 from 21,302 to 21,424 bytes. `moon check src/encode --target all`
  passed; the source change was reverted. Do not spend more attempts on plain
  deeper lazy lookahead unless combined with a different parser cost model.
- Rejected q10/q11 strategy 5 (2026-06-14 constrained loop): adding the bounded
  suffix-tree match table as an extra greedy match source did improve Silesia
  64 KiB q10/q11 by 5 bytes, from 21,302 to 21,297, but it missed the size
  target and exceeded the user performance ceiling. `target-perf.nu` on
  64 KiB q10 measured native 115.89 ms and wasm-gc 104.30 ms versus Google
  38.49 ms, i.e. 270%..301% of Google and above the 250% hard limit. Source
  was reverted; do not retry suffix-tree-as-greedy-source unchanged.

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

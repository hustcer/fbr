# Progress Log: Brotli Support

This log has been compacted. Detailed historical trial output was removed from
the planning directory because it duplicated git history, benchmark artifacts,
or durable findings now summarized in `findings.md`.

## 2026-06-12 — decode performance session (feature/perf)

- Discovered the historical "generated-C clang -O2 hangs" blocker no longer
  reproduces on the current toolchain; removed the cc-o0 MOON_CC workaround
  from `tools/bench/target-perf.nu`. Native decode ~4.3x faster, native
  encode ~4.9x faster in target-perf terms (commit 24417e9).
- Landed the 64-bit accumulator bit reader (a requalified cc-o0-era
  rejection): strict decode-compare PASS on all 8 rows, aggregate -1.14%
  (commit fe02ae7).
- Rejected post-O2 retries (registered in findings.md): refill trigger at 15
  bits, inlined literal root-table fast paths, `#inline` on
  brotli_read_symbol.
- Identified harness fixed-overhead distortion (one `moon run` start
  amortized over repeats; ~110 ms wasm-gc, ~28 ms native). Bumped default
  repeats to 20 in `report.nu` and `decode-compare.nu` and documented the
  caveat in the generated report. True per-op decode on silesia-1m:
  wasm-gc ~13-18 ms, native ~6.5-8.6 ms vs Google CLI ~8-10 ms.
- Regenerated `docs/brotli_release_report.md` via `just bench` with the
  default-O2 native rows and repeats=20 timing shape.

## 2026-06-01 — planning files curated

- Replaced the long historical `task_plan.md`, `findings.md`, and
  `progress.md` contents with concise reference-oriented files.
- Kept current acceptance policy, current P1/P2/P3/P4 state, validation entry
  points, P4 guidance, release tooling notes, and decode negative-cache
  information.
- Removed low-value per-increment checklists, repeated benchmark rows, commit
  narration, and superseded work-in-progress notes.

## Durable Milestones

- P1 decoder landed with RFC compressed/uncompressed meta-block support,
  static dictionary transforms, conformance fixtures, stream API, and fuzz
  harnesses.
- P2 q0/q1 encoder landed as RFC-valid stored streams with external Google
  Brotli decode validation.
- P3 q2..q9 encoder evolved from synthetic compressed paths to natural-data
  chunking, weighted Huffman trees, distance-cache use, dictionary candidates,
  block-layout candidates, and 2 MiB chunk validation. Current measured Silesia
  windows are inside the revised 5% target.
- P4 q10/q11 gained high-quality mixed-dictionary parsing, bounded
  shortest-path seed work, suffix-tree match source, recent-distance state in
  the bounded seed, and pairwise block-layout candidates. The streams are valid
  but still outside the revised 5% size target.
- Release tooling now covers conformance, ratio, target-perf, decoder fuzz,
  encoder roundtrip fuzz, deterministic corpus generation, package validation,
  and aggregate release-candidate checks.
- Decode optimization has an explicit same-time harness and a large rejected
  trial cache. Four operation-removal changes were accepted; branch/local/cache
  reshaping and bit-reader rewrites were mostly rejected.

## Current Next Steps

- Select and measure a broader P3 release corpus beyond Silesia.
- Define small-file ratio policy using absolute-byte or minimum-size allowance.
- Continue q10/q11 size work under the revised 5% target, starting with cheap
  exact-costed parser/dictionary/block-layout candidates.
- Run final release gates, generated fuzz corpus, soak validation as required,
  and package verification before public release.

## 2026-06-14 — q10/q11 ratio work resumed

- Restored `.planning/brotli-support` context and re-read
  `docs/brotli_release_report.md`. Current q10/q11 outputs are valid but
  still materially larger than Google: Silesia 64 KiB q10 +9.45% / q11
  +11.21%, 128 KiB q10 +8.79% / q11 +10.10%, and 1 MiB q10 +9.00% / q11
  +10.46% in the fresh rerun.
- Confirmed q10 and q11 currently produce identical MoonBit streams on the
  measured Silesia inputs, so q11 has no distinct stronger parser path yet.
- Failed trial: disabled the context8-first writer shortcut for q10/q11 so
  later split/context writer candidates could compete. `moon check
  src/encode --target all` passed, but Silesia 64 KiB q10/q11 remained exactly
  21,302 bytes with the same SHA-256. Reverted the code change and recorded the
  rejection in `findings.md`.
- Partial DP trial: activated the existing bounded shortest-path candidate for
  q10/q11 direct 64 KiB input and then for 128 KiB input. This reduced Silesia
  64 KiB q10 from 21,302 to 20,890 bytes (+7.33% vs Google) and Silesia 128
  KiB q10 from 38,565 to 37,814 bytes (+6.67%), but it still missed the target
  and increased JS verifier runtime sharply. Follow-up DP breadth trials were
  rejected and recorded in `findings.md`.
- Rejected the bounded-DP activation line after target-perf sampling. Extra
  command-symbol cost, min-match 3, transform 49, mixed cost seed, and full
  q10/q11 writer comparison only reached 20,760 bytes on Silesia 64 KiB q10
  (+6.66%) while low-repeat target-perf measured native 439.98 ms and wasm-gc
  352.50 ms versus Google 34.31 ms. Reverted all source edits; only planning
  notes remain from this failed attempt.

## 2026-06-14 — q10/q11 constrained strategy loop

- User set a hard stop after ten independent strategies if no good result is
  found, requested one strategy per attempt, and asked to commit only real
  improvements. Size must reach the target interval while encode time stays
  under 250% of Google Brotli and should preferably stay under 150%.
- Strategy 1 failed and was reverted: q10/q11-only official-style
  distance-aware match scoring plus score-based lazy lookahead passed
  `moon check src/encode --target all`, but Silesia 64 KiB q10/q11 grew from
  21,302 to 21,311 bytes. No performance run or commit was made.
- Strategy 2 failed and was reverted: adding a 3-byte high-quality candidate
  before the existing q10/q11 4-byte high-quality mixed candidate passed
  `moon check src/encode --target all`, but Silesia 64 KiB q10/q11 output and
  SHA were identical to baseline. No performance run or commit was made.
- Strategy 3 failed and was reverted: changing q10/q11 lazy matching to require
  the future match to beat current length plus skipped literals passed
  `moon check src/encode --target all`, but Silesia 64 KiB q10/q11 grew to
  21,388 bytes. No performance run or commit was made.
- Strategy 4 failed and was reverted: raising q10/q11 high-quality lazy
  lookahead from 3 to 4 passed `moon check src/encode --target all`, but
  Silesia 64 KiB q10/q11 grew to 21,424 bytes. No performance run or commit
  was made.
- Strategy 5 failed and was reverted: using the bounded suffix-tree match table
  as an extra q10/q11 greedy match source reduced Silesia 64 KiB q10/q11 by
  only 5 bytes, to 21,297, and `target-perf.nu` measured 64 KiB q10 native
  115.89 ms / wasm-gc 104.30 ms versus Google 38.49 ms, above the 250% hard
  limit. No commit was made.

## 2026-06-14 — q0/q1 ratio work reopened

- Restored `.planning/brotli-support` context and confirmed the previous plan
  intentionally treated q0/q1 as stored-only; the current user goal reopens
  that work.
- Read `docs/brotli_release_report.md`: q0/q1 are fast but roughly
  +140%..+176% larger than Google on 64 KiB and 128 KiB Silesia slices.
- Located current implementation: `src/encode/encode.mbt` dispatches
  `quality 0 | 1` directly to `brotli_encode_uncompressed`; existing standard
  encoder paths already contain `quality < 3` candidate logic that can be
  evaluated for q0/q1 with minimal blast radius.
- Noted current tree tooling paths differ from older plan references:
  benchmarks live under `tools/bench/`, not `tools/brotli/bench/`.
- First minimal trial routed q0/q1 through `brotli_encode_standard`. q1 entered
  the requested ratio band on Silesia 64 KiB/128 KiB (-3.16%/-2.50% vs Google
  q1), but q0 over-compressed slightly (-7.86%/-8.95%) and had q2-like target
  cost, so it needs a distinct speed/ratio tradeoff.
- Rejected a shallow q0-only simple-LZ77/no-context candidate: it fell back to
  stored output on 64 KiB Silesia (+140.73%). Also observed that running
  `moon check` in parallel with `target-perf.nu` can produce a spurious
  generated-harness package error; keep MoonBit build/check commands serial
  around target-perf runs.
- Accepted working q0/q1 direction in progress: q0 uses the natural low-quality
  hash candidate without literal contexts and skips low-quality split; q1 uses
  the same chunked low-quality path but keeps a context8 writer. Current
  measured Silesia ratio: q0 64 KiB 29,023 bytes (+6.60%) / 128 KiB 53,336
  bytes (+4.91%) with 4 hash-chain checks; q1 context8 64 KiB 25,943 bytes
  (+0.15%) / 128 KiB 47,332 bytes (-0.31%). q2 sampled size remained unchanged.
- Rejected follow-up trials: q0 2 hash-chain checks exceeded the +7% target;
  q1 context4 had worse size and no target-perf win over context8.
- Rebalanced q0 after the first accepted point: 3 hash-chain checks with
  minimum match length 8 gave a better speed/size balance than 4 checks/min7.
  Final measured Silesia ratio: 64 KiB 27,541 bytes (+1.16% vs Google q0) and
  128 KiB 50,842 bytes (+0.00%). Final target-perf min times: 64 KiB
  wasm-gc 5.42 ms / native 3.95 ms; 128 KiB wasm-gc 9.04 ms / native
  5.85 ms after re-running around one native outlier.
- Rebalanced q1 search depth while keeping the context8 writer required for
  ratio. 4 hash-chain checks gave a better tradeoff than 8/6/5 checks for the
  current speed-oriented q1 profile while staying inside target. Final
  measured Silesia ratio: 64 KiB 26,501 bytes (+2.30% vs Google q1) and
  128 KiB 48,610 bytes (+2.38%). Final target-perf min times: 64 KiB
  wasm-gc 6.90 ms / native 4.85 ms; 128 KiB wasm-gc 11.47 ms / native
  7.54 ms.
- q2 guard sample remained unchanged by the q0/q1-specific branches:
  Silesia 64 KiB 25,087 bytes (+3.77% vs Google q2) and 128 KiB 46,290 bytes
  (+3.90%).
- Validation completed for the final patch: `moon fmt`, `moon info`,
  `moon check --target all`, `moon test src/encode --target all`, and
  `moon test --target all` all passed.

## 2026-06-15 — q10/q11 ratio work resumed (Phase 1: size)

- User goal: get q10/q11 encoded-size overhead into roughly -7%..+3.5% vs Google
  on the release-report Silesia windows, then optimize speed for balance. Stop
  when the goal is met OR after 8 consecutive failed attempts with no progress.
- Re-read planning files. Recorded the root-cause diagnostic in `findings.md`:
  the gap is in PARSING (MoonBit q9 already beats Google q9, so entropy coding
  is fine; Google's q9->q10 -11% jump is the optimal parse MoonBit lacks).
- Confirmed the bounded shortest-path DP exists but is gated to <=32 KiB
  (`max_input_length: 32768`), so the committed 64/128 KiB q10/q11 output is the
  fast greedy result. Untried high-leverage lever: iterate the DP cost model
  (Zopfli-style), plus real command-symbol cost; defer speed to Phase 2.
- Measurement loop: `tools/encode/verify.nu <input> -q <quality>` for size
  (also roundtrips through the Google CLI decoder), known Google baselines
  64k q10 19,463 / q11 19,154, 128k q10 35,448 / q11 35,027. Keep MoonBit
  build/check serial around any `target-perf.nu` runs.
- Measured this session (all reverted afterward): single-pass DP 128k q10
  37,814 (+6.67%); +cost-model iteration 37,806 (8 bytes); +deep search
  (checks 256, maxlen 65536) 37,501 (+5.79%). DP encode time 128k q10 native
  580 ms / wasm-gc 503 ms vs Google 55.6 ms (10.4x / 9.0x) — 4x over the q10
  250% ceiling. Concluded size +3.5% and speed <=250% are mutually exclusive
  under the current architecture.
- DECISION (user, 2026-06-15): take the "q11 partial improvement" path. Enable
  the optimal-parse DP for q11 ONLY (its speed budget is looser: Google q11
  64k 69 ms -> 173 ms ceiling, 128k 147 ms -> 368 ms ceiling). Target: q11
  from +10.1% to ~+6.6%, with q11 encode time <=250% (ideally <=150%) of
  Google q11. Keep q10 on the fast greedy path; zero regression to q0..q10.
  Critical sub-task: speed up the DP ~1.6x (128k) / ~2.5x (64k) — first lever
  is removing the per-position 4-int cache allocation, then beam-width tuning.

## 2026-06-15 — q11 optimal-parse DP landed (within 250% speed budget)

- Wired the bounded optimal-parse DP for q11 ONLY: site A (chunked path,
  `brotli_try_compressed_chunk`, used by 128k) gated to `quality >= 11`; site B
  (`brotli_encode_standard` inline path, used by 64k) adds a q11 DP candidate
  via `brotli_try_compressed_commands`. q10 stays on the fast mixed-dict path.
  Raised the DP `max_input_length` 32768 -> 131072 and `max_commands`
  12000 -> 131072 so 64k/128k single chunks qualify.
- Speed work on the DP (q11-only, so q0..q10 untouched):
  - Removed the per-match `bounded_lengths` array and the per-(match,length)
    `next_cache` allocation (reused a single 4-int buffer). Pure refactor,
    size unchanged. Native 128k q11 598.9 -> 515.4 ms.
  - beam_width 2 -> 1 (guarded offer_state/terminal slot-1 logic). Ratio cost
    is tiny: 64k +11 bytes, 128k +18 bytes (the beam-2 distance-cache
    divergence rarely matters here). Native 128k q11 515.4 -> ~346 ms.
  - Reused the main-loop `current_cache` buffer (pure refactor, size
    unchanged); minor.
  - Dropped the half-length DP representative (3 -> 2 lengths: min + full).
    Ratio cost 1-3 bytes; native 128k q11 ~348 -> 330.7 ms.
- Final measured (verify.nu size, target-perf.nu --repeats 20 --samples 3):
  - q11 64k: 20,904 bytes (+9.14% vs Google q11 19,154; was +11.21%); native
    142.6 ms / wasm-gc 140.6 ms vs Google 70.7 ms = 2.01x / 1.98x (250%
    budget 176.5 ms, ~20% margin).
  - q11 128k: 37,833 bytes (+8.01% vs Google q11 35,027; was +10.10%); native
    330.7 ms / wasm-gc 309.4 ms vs Google 147 ms = 2.22x / 2.08x (250% budget
    372.7 ms, ~11-17% margin).
  - q10 64k 21,302 and 128k 38,565 unchanged (q10 path untouched).
- 250% hard ceiling met on all four cells; the 150% preference is not met
  (would need ~1.4x more, which costs ratio). Limitation: DP only runs for q11
  inputs whose chunk is <= 131072 (chunk size for q11 is 1 MiB), so q11 inputs
  larger than ~128 KiB fall back to the fast mixed path (no improvement, no
  regression). Recorded as future work in findings.md.
- Validation (all PASS): `moon fmt`, `moon check --target all`, `moon info`
  (public API unchanged), `moon test --target all` (165/165 on wasm, wasm-gc,
  js, native), `just conformance` (21 fixtures), `just roundtrip native 40
  6000 "10,11"` (80 cases ok), `just bench` regenerated
  `docs/brotli_release_report.md` (+ `docs/current-bench/*.jsonl`) confirming
  q0..q10 byte-identical and the q11 rows above. Updated the one wbtest that
  asserted beam=2 to assert the live beam=1 single-best-state behavior, and the
  report.nu executive-summary prose for q10/q11.
- Goal status: the q11-partial goal the user selected is met (real q11 size win
  within the 250% budget, zero regression). The original -7%..+3.5% aspiration
  is NOT met and requires the de-scoped Zopfli backend.

## 2026-06-15 — efficient Zopfli backend rewrite ATTEMPT (reverted)

- User goal: rewrite an efficient Zopfli backend (H10-style matches + O(n)
  shortest path + iterated full cost model), q11 first, validate size+speed on
  64k/128k, then decide on q10/large inputs.
- Studied the reference (`c/enc/backward_references_hq.c`,
  `hash_to_binary_tree_inc.h`, `quality.h`, `literal_cost.c`) and recorded the
  full blueprint in findings.md (P5 section).
- Implemented `src/encode/zopfli.mbt` (~700 lines): entropy SetCost model,
  sliding-window literal cost, set-from-commands model, StartPosQueue,
  UpdateNodes DP (last-distance + new-match loops), distance shortcut/cache,
  min-copy-length, node backtrack to commands, 2-iteration q11 driver. Reused
  the existing suffix-tree + hash-chain matches and the command/distance prefix
  encoders. It compiled on all targets and produced valid (roundtrip-checked)
  streams; on synthetic repetitive data it parsed optimally (2 commands /4096).
- BUT on real Silesia 64k it underperformed: iter-0 26,511 bytes (55% copy
  coverage), iter-1 degenerated to ~400 commands (~35 KB). vs the bounded-DP's
  20,904 and mixed's 21,302, so the new backend never won. Fixed several real
  bugs along the way (distance histogram for implicit last-distance codes; H10
  Pareto match ordering; windowed literal cost; the k>=2 new-match restriction)
  but could not get the StartPosQueue DP to match the beam-based bounded-DP's
  parse quality in the time spent. See findings.md P5 outcome for the bug list
  and the unresolved root cause (queue not retaining optimal starts / distance
  skew; iter-1 collapse is a symptom of suboptimal iter-0).
- DECISION: reverted to the working bounded-DP (zero regression: q11 64k 20,904
  / 128k 37,833, within 250%); removed zopfli.mbt + debug test + the math
  import. Tree is byte-identical to commit 9007367. Recommend keeping the
  bounded-DP; a future Zopfli retry should validate iter-0 beats greedy on real
  64k BEFORE wiring iterations.

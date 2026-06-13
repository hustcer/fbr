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

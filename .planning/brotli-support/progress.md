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

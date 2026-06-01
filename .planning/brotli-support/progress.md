# Progress Log: Brotli Support

This log has been compacted. Detailed historical trial output was removed from
the planning directory because it duplicated git history, benchmark artifacts,
or durable findings now summarized in `findings.md`.

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

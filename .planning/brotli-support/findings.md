# Findings: Brotli Support

## Repository Facts

- Source root is `src/`, configured by `moon.mod.json`.
- fzip is a single MoonBit package; all `.mbt` files in `src/` share scope.
- Public options live in `src/types.mbt`.
- Error codes and `FzipError` live in `src/error.mbt`.
- Stream wrappers live in `src/stream.mbt` and buffer chunks until
  `final_=true`.
- `compress_sync` / `decompress_sync` in `src/fzip.mbt` must not auto-detect
  Brotli.
- The installed CLI is `brotli 1.2.0`, useful for reference validation.

## Plan Facts From `docs/brotli.md`

- P1 public API is `unbrotli_sync(data, opts?)`, `UnbrotliOptions`, and
  `UnbrotliStream`.
- P2 public API adds `brotli_sync(data, opts?)`, `BrotliOptions`,
  `BrotliMode`, and `BrotliStream`.
- The full library must compile on native, JavaScript, and wasm-gc.
- Brotli code should be pure MoonBit and use `FixedArray[Byte]` APIs.
- Static dictionary is required for a conformant decoder.
- The final decoder must pass the upstream corpus at
  `/Users/hustcer/iWork/refs/brotli/tests/testdata/`.

## Open Technical Risks

- Full Brotli decoder and encoder are large ports from C; avoid claiming phase
  completion until all acceptance criteria have direct evidence.
- `target-perf.nu` no longer depends on full-package white-box tests for
  performance measurement. It generates an ignored temporary main package and
  uses native C FFI to read input files for native runs. This fixes the
  previous 64 KiB+ byte-literal source explosion, but default native release
  `clang -O2` still does not finish reliably on the generated Brotli C output.
  Native target-perf rows are therefore explicit about the current workaround:
  `native_cc: "cc-o0"` means MoonBit release codegen with the C compiler
  optimization flag rewritten from `-O2` to `-O0`.
- A minimal scaffold is useful only as an implementation increment. It does
  not satisfy P1 completion until compressed meta-blocks, dictionaries, and the
  corpus harness pass.
- Current compressed-body support handles implicit recent-distance short codes,
  explicit distance tree symbols, RFC direct/postfix distance formulas, and
  direct output back-references. Block switching is wired for literal, command,
  and distance trees with context-map selection. Literal context modes LSB6,
  MSB6, UTF8, and SIGNED now select literal trees from the previous two output
  bytes. The recent-distance ring now lives in decoder state and persists across
  compressed meta-block bodies. Static dictionary references are supported using
  embedded `dictionary.bin` plus the standard transform triplet table from
  `c/common/transform.c`.
- The full upstream reference corpus currently contains 22 `.compressed`
  fixtures with matching expected files. `nu tools/brotli/conformance/run.nu`
  decodes all 22 with `unbrotli_sync` on the native backend.
- Google `brotli -d -c` successfully decodes every embedded fixture under
  `src/tests/brotli_fixtures/` to the committed expected bytes.
- Upstream corpus coverage exposed four decoder details that the smaller
  white-box tests missed: code-length-code length reading must stop when the
  Huffman space is complete, single-symbol Huffman tables may have zero-bit
  entries, dictionary transform output can differ from copy length, and static
  dictionary distances must not update the recent-distance ring.
- Remaining P1 correctness risk: backward-copy validation still compares
  against total output length. The P1 plan requires validation against the
  currently available Brotli window (`1 << window_bits`) so old data outside
  the ring cannot be referenced.
- Resolved P1 window-distance risk: decoder state now derives the maximum
  legal LZ77 backward distance from the advertised window bits as
  `(1 << window_bits) - 16`, then caps it by current output position. Static
  dictionary addresses are computed from `distance - max_distance - 1`, matching
  the C reference. The old total-output-length calculation would have accepted
  stale-window back-references and misaddressed dictionary words after the
  output grew beyond the Brotli window.
- Manual Brotli temp-test harnesses must not run concurrently. Moon's test
  discovery includes all `src/*_wbtest.mbt` files, so one harness removing its
  temporary file while another harness is compiling can produce a compiler ICE.
  `tools/brotli/conformance/run.nu` and `tools/brotli/fuzz/run.nu` now share
  `tools/brotli/.harness-lock` to serialize those runs.
- Silesia q=11 long-stream coverage exposed two UTF8 literal-context boundary
  mismatches that small fixtures missed: second-last bytes `208..223` contribute
  `0` in UTF8 mode, not `2`, and DEL (`127`) is classified as control for both
  UTF8 context tables. The 100 MiB artifact now decodes to SHA-256
  `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
- Focused P1 Brotli native tests passed 32/32 in 1.69s, under the 5s
  acceptance budget from `docs/brotli.md`.
- rust-brotli `testdata/alice29.txt.compressed` decodes through fzip's JS
  decoder and Google `brotli -d` to SHA-256
  `7467306ee0feed4971260f3c87421154a05be571d944e9cb021a5713700c38f0`.
- Google `ukkonooa.compressed`, an embedded dictionary-transform fixture, passes
  fzip's native conformance harness and Google `brotli -d`.
- P2 q=0/q=1 currently emits uncompressed meta-blocks. The streams are
  RFC-valid and externally decodable, but compression ratio intentionally does
  not improve until P3/P4 back-reference and entropy coding work lands.
- MoonBit q=0/q=1 Silesia encoder output is deterministic for both qualities:
  encoded size `104857629`, encoded SHA-256
  `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25`,
  external decode SHA-256
  `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`.
- A 50-input fuzz smoke generated from embedded Brotli fixtures passed without
  native panics or unchecked bounds failures.
- q=2 and q=9 Silesia encoder validation currently produce the same
  uncompressed stream as q=0/q=1 and decode externally to the original SHA-256.
  This means quality dispatch is correct for stream validity, but not yet for
  compression-ratio acceptance.
- q=10 and q=11 Silesia encoder validation also produce the same RFC-valid
  uncompressed stream and decode externally to the original SHA-256. All
  standard quality values are now API-supported for correctness, with the
  ratio gap tracked separately.
- Completion audit correction: the q2..q11 dispatch commits are not P3/P4
  completion under `docs/brotli.md`. They prove stream validity and public API
  coverage only. P3 still requires real hash-chain/back-reference/block
  splitting/Huffman output and Silesia ratio within 5% of C reference. P4 still
  requires Zopfli-style q10/q11 search, suffix-tree memory caps, and Silesia
  ratio within 2% of C reference.
- The decoder accepts a compact compressed meta-block for a single inserted
  literal plus explicit distance-1 copy. Encoder q2+ now uses that path for
  single-byte runs up to one Brotli meta-block. A 1024-byte `A` run encodes to
  11 bytes and external `brotli -d` verifies the output.
- Simple Huffman payload bits can be derived by building the same simple table
  used by the decoder and selecting any root-table index whose entry matches
  the target symbol. This enabled q2+ short-period encoding for period lengths
  1..4. A 1024-byte repeated `ABCD` input encodes to 15 bytes and external
  `brotli -d` verifies the output.
- q2+ can now encode one inserted prefix plus one copied suffix, as long as the
  inserted prefix has at most four distinct literal byte values. A 1024-byte
  `XABCABC...` input encodes to 15 bytes and external `brotli -d` verifies the
  output. This is the next stepping stone toward multi-command LZ77 output.
- Greedy multi-command q2+ output works for inputs with at most four literal
  byte values, at most four command symbols, and at most four distance symbols.
  A 1207-byte `ABCABCX + ABCABC...` input encodes to 17 bytes and external
  `brotli -d` verifies the output.
- A more irregular 1400-byte small-alphabet chunk pattern originally fell back
  to uncompressed output because the simple-Huffman command alphabet exceeded
  four symbols. This confirms complex Huffman tree emission is the next
  structural requirement for broader P3 coverage.
- Complex Huffman tree emission now writes code-length-code lengths with the
  fixed prefix table, then emits target alphabet code lengths without RLE.
  Code lengths are currently fixed-width and padded to a power of two with
  dummy symbols, which keeps the tree valid and deterministic but not
  entropy-optimal.
- External validation for complex trees:
  - `periodic-abcde-1025.bin` q2 encoded size 22 bytes, decoded by Google CLI.
  - `small-alpha-multi-1400.bin` q2 encoded size 306 bytes, decoded by Google
    CLI. This is the same pattern that previously fell back to uncompressed
    output.
- Ratio benchmark harness baseline:
  - `small-alpha-multi-1400.bin` q2: MoonBit 306 bytes vs Google 169 bytes.
  - `silesia-100m.bin` q2: MoonBit 104857629 bytes vs Google 35495150 bytes.
  - Conclusion: complex Huffman and small synthetic LZ77 paths work, but the
    realistic corpus still falls back to stored blocks. Next structural work is
    large-data metablock splitting and broader hash/back-reference search.
- Chunked q2 hash-match increment:
  - Large q2 inputs now split into 65,535-byte chunks so the existing simple
    LZ77 meta-block writer can be reused per chunk.
  - The previous independent stored-chunk bitstream composition was invalid:
    uncompressed meta-block padding depends on the active stream bit offset.
    Stored chunks must be written directly to the main `BrotliBitWriter`; only
    compressed candidate chunks can be spliced bit-for-bit.
  - The q2 matcher now uses a bounded 3-byte hash chain and requires a proved
    4-byte match before extension. This keeps low-alphabet chunk matching
    practical in the JavaScript verification harness.
  - General natural-data chunks are currently gated out when they exceed 16
    unique literal bytes. This avoids slow or malformed speculative q2 output
    until the encoder has frequency-weighted Huffman lengths and broader block
    splitting.
  - External validation: `periodic-abcde-200k.bin` q2 encodes to 2,820 bytes
    and decodes to SHA-256
    `24a7979ddb84c3eefb28a14793d9a66bfbc1e8c8ce61b326c699458dc9e951c5`.
  - Full Silesia q2 ratio now completes: MoonBit 104,862,404 bytes, SHA-256
    `75561d5802aec1cfcfb8eec0a66c1a9883f93806e58b8209b1bf52855aab1458`,
    versus Google 35,495,150 bytes. This remains far outside the P3 5% target.
- Weighted Huffman q2 increment:
  - Complex Huffman tree emission can now describe arbitrary code lengths by
    generating a valid code-length-code tree and writing each target length
    through that tree without RLE.
  - Low-alphabet q2 chunks now build frequency-weighted literal, command, and
    distance code lengths for alphabets up to 16 symbols, falling back to the
    fixed deterministic lengths outside that scope.
  - The encoder now costs fixed versus weighted q2 trees and selects the
    smaller valid meta-block.
  - `small-alpha-multi-1400.bin` q2 improved from 306 bytes to 231 bytes versus
    Google 169 bytes, and decodes through Google Brotli.
  - `periodic-abcde-200k.bin` q2 stays at the 2,820-byte fixed-tree output
    because the weighted tree header is larger than the savings for that
    regular pattern.
  - Full Silesia q2 remains 104,862,404 bytes versus Google 35,495,150 bytes
    while the low-alphabet gate prevents natural-data compressed chunks.
- Sampled q2 match-density gate:
  - The strict `<=16` literal-symbol gate has been replaced by a two-part
    admission test: low-alphabet chunks still pass immediately, while
    high-alphabet chunks pass only if sampled positions show very dense
    repeated 4-byte sequences.
  - A command-count cap of 1,200 keeps accidental natural-data candidates from
    spending unbounded time in the JavaScript verifier.
  - `periodic-allbytes-200k.bin` cycles all 256 byte values, q2 encodes it to
    5,878 bytes, and Google Brotli decodes it to SHA-256
    `c7a7d73b68d21102bf7d6d9be27b4106497efc8119224bebfbd26b375541bde7`.
  - Silesia 1 MiB and 100 MiB remain stored-block baselines. This proves the
    new gate is bounded and valid, but not sufficient for the P3 ratio target;
    real natural-data block splitting remains required.
- Longer q2 hash matches:
  - The bounded hash matcher now extends matches up to 4,096 bytes instead of
    64 bytes. Command-prefix encoding already supports these copy lengths, so
    no format changes were required.
  - `periodic-abcde-200k.bin` q2 improved from 2,820 bytes to 249 bytes.
  - `periodic-allbytes-200k.bin` q2 improved from 5,878 bytes to 1,399 bytes.
  - `small-alpha-multi-1400.bin` stayed at 231 bytes versus Google 169 bytes.
  - Full Silesia q2 stayed at 104,862,404 bytes versus Google 35,495,150 bytes
    because ordinary natural-data chunks still fail the conservative candidate
    gate.
- q2 chunk diagnostics:
  - `tools/brotli/bench/chunk-match.nu` measures unique byte counts, sampled
    4-byte match density, and greedy-copy estimates using the active q2 chunk
    size and command cap.
  - On the first 16 Silesia chunks, min lengths 4 and 8 hit the 1,201-command
    cap in every chunk, while min length 16 averages 909.125 commands and
    35.02% copied bytes. This explains why short-match natural-data admission
    cannot be a simple gate tweak.
  - On a high-alphabet all-256-byte periodic chunk, the sampled 4-byte density
    is 99.61% and all tested min lengths encode with 16 commands and 99.61%
    copied bytes. This validates the current density gate for highly
    repetitive data.
- P3 file boundaries:
  - The current q2 hash helpers now live in `src/brotli_encode_hash.mbt`,
    matching the P3 subsystem table in `docs/brotli.md`.
  - This is intentionally behavior-preserving; it prepares the package for the
    larger quality-aware hash variants without mixing that work into the
    meta-block writer.
- Quality-aware hash config:
  - `BrotliHashConfig` now carries table size, search depth, max match length,
    and sampled-density thresholds through the q2+ encoder path.
  - Current quality tiers intentionally return the same config so this remains
    a safe plumbing increment; future q5/q9 changes can be localized to
    `brotli_hash_config_for_quality`.
- Sparse natural-data trial:
  - q9 with min match length 16, one candidate check, scan step 8, command cap
    1,200, and 35% copied-byte admission did not improve `silesia-1m.bin`; it
    stayed at 1,048,628 bytes and took 12,158.154 ms in the ratio harness.
  - The same q9 trial regressed `small-alpha-multi-1400.bin` from 231 bytes to
    stored 1,404-byte output.
  - Conclusion: keep the admission fields and command-literal accounting, but
    do not relax dense-match gating until block splitting or a better
    compressed-size estimator can reject low-value natural chunks before the
    expensive write path.
- Complex Huffman repeat-zero RLE:
  - Code-length symbol 17 can compact zero runs in complex Huffman trees, but
    consecutive repeat-zero symbols are not independent; the decoder accumulates
    repeat state for the same repeat symbol. Long zero runs must be broken by a
    literal zero code length between repeat-zero symbols.
  - After adding this split rule, Google Brotli accepts the generated streams.
  - `small-alpha-multi-1400.bin` q2 improved from 231 bytes to 195 bytes versus
    Google 169 bytes.
  - `periodic-abcde-200k.bin` q2 improved from 249 bytes to 240 bytes.
  - Silesia remains stored because this only reduces tree overhead after a
    chunk has already passed the conservative compressed-chunk gate.
- Complex Huffman repeat-previous RLE:
  - Code-length symbol 16 repeats the previous nonzero code length and uses the
    same accumulating repeat-state mechanism as symbol 17. Long nonzero runs
    need a literal code length between repeat-previous symbols.
  - `periodic-allbytes-200k.bin` q2 improved from 1,399 bytes to 1,382 bytes
    and decodes through Google Brotli.
  - `small-alpha-multi-1400.bin` and `periodic-abcde-200k.bin` were unchanged
    because repeat-zero RLE already captured their dominant tree overhead.
- Literal-only compressed candidates:
  - Insert-only commands can use any command cell when the insert length fills
    the remaining meta-block because the decoder returns before consuming a
    distance. The previous no-copy prefix search was too restrictive for long
    inserts.
  - The chunk-level stored comparison must use rounded-up candidate byte size
    (`shft(bit_pos) + 1`), otherwise a candidate can be one byte larger than
    stored and still be selected.
  - A cheap `brotli_count_unique_literals_up_to(..., 64)` gate keeps this path
    off ordinary high-alphabet chunks. This restored `silesia-1m.bin` to the
    prior stored size and runtime range after a broad literal-only trial slowed
    the ratio harness.
  - `alpha64-xorshift-16000.bin` q2 improved from stored 16,004 bytes to
    12,022 bytes versus Google q2's 12,029 bytes.
- Literal-set collection was a measurable encode hotspot because several
  helpers used linear duplicate checks against the current symbol list. A
  256-entry `seen` table preserves Brotli symbol order while making collection
  O(n). On `target-perf.nu` q2 `silesia-128k.bin`, this reduced wasm-gc encode
  avg from ~178.97 ms to ~163.79 ms and native avg from ~521.30 ms to
  ~470.19 ms with unchanged 51,928-byte output.
- `target-perf.nu` must be serialized with the other Brotli temporary
  white-box harnesses. Unique filenames are not enough, because Moon test-info
  generation scans all package white-box files and can observe another run's
  generated file after it has been removed.
- Current code audit on 2026-05-25 confirms the API surface and round-trip
  implementation are ahead of the formal phase checklist: qualities 0..11 are
  accepted and tested, but P3/P4 completion still depends on ratio algorithms
  and evidence, not just valid streams.
- q11's active parser config in code is deeper than the last benchmark entry:
  131,072-entry table, 128 checks, 5-byte minimum matches, and 600,000-command
  cap. This needs a fresh ratio run before drawing conclusions from older
  q11 measurements.
- The staged `brotli_command_uses_distance_symbol` optimization is a
  behavior-preserving internal fast path: explicit distance symbols are needed
  exactly when the command symbol is in cells 2+ (`symbol >= 128`). Native
  Brotli tests pass with this staged change.
- For small per-commit target-perf evidence, q2 split-literal data is a poor
  signal for distance-symbol changes, but q9 Silesia is useful. The
  distance-symbol fast path improved wasm-gc release q9 `silesia-128k.bin`
  encode from 231.168 to 228.405 ms/op and native debug q9 `silesia-64k.bin`
  encode from 657.714 to 642.933 ms/op, with unchanged encoded sizes.
- `target-perf.nu` native release currently has a practical benchmarking
  limitation: generated white-box tests embed input bytes directly, and native
  release compilation can take minutes for 64 KiB+ inputs. Treat wasm-gc
  release plus native debug/smaller-input numbers as quick commit evidence
  until the harness supports a faster native-release path.
- q11 current-code validation on `silesia-64k.bin`:
  - target-perf encode size is 22,155 bytes versus Google q11's 19,258 bytes,
    a 15.04% overhead.
  - wasm-gc release encode avg is 155.733 ms/op versus Google 105.995 ms/op.
  - native debug encode avg is 664.039 ms/op versus Google 103.792 ms/op.
  - external `brotli -d` decodes the generated q11 stream byte-for-byte, so
    the immediate release blocker is ratio/performance evidence, not format
    validity on this slice.
- Back-reference output copying is a real decode hot path. Special-casing
  distance=1 and non-overlapping copies improved q11 Silesia 64 KiB decode
  target-perf from 23.077 to 19.023 ms/op on wasm-gc release and from 28.675
  to 28.553 ms/op on native debug, without changing decoded bytes.
- `brotli_command_info` is hot enough in q9 native debug encode to justify a
  precomputed table. Replacing per-call prefix-offset loops with a table lookup
  improved q9 `silesia-64k.bin` native debug encode from 652.482 to
  432.617 ms/op and preserved encoded size.
- Practical correctness evidence as of 2026-05-25: a generated 25-input fuzz
  gate and all 22 available Google Brotli upstream conformance fixtures pass
  through the native test harness. This is meaningful local release evidence
  but not a substitute for the planned long fuzz run.
- q2 medium-input ratio can be moved into the P3 5% target window without the
  full candidate matrix. On `silesia-64k.bin`, exact-costing only split and
  context16 candidates improves size from 27,968 to 25,245 bytes versus Google
  q2's 24,364 bytes. The cost is measurable but bounded: wasm-gc release
  encode rises from 109.058 to 115.819 ms/op and native debug rises from
  300.358 to 329.200 ms/op.
- The same bounded q2 split/context path also works for `silesia-128k.bin`:
  size improves from 51,928 to 46,509 bytes versus Google q2's 44,794 bytes,
  while wasm-gc release encode rises from 124.937 to 132.088 ms/op and native
  debug rises from 308.044 to 333.868 ms/op.
- q11 ratio responds to deeper hash-chain search, but the encode-cost curve is
  steep. On `silesia-1m.bin`, 256 checks improves q11 from 267,620 bytes to
  266,056 bytes versus Google q11's 239,314 bytes, reducing overhead from
  11.83% to 11.17%. A 512-check trial improved further to 264,938 bytes
  (10.71% overhead) but raised the legacy verification encode time to
  ~199.8s versus ~96.7s at HEAD and ~137.8s at 256 checks, so 512 checks is
  rejected for now under the encode-performance constraint.
- q11 recent-distance preference should not be applied broadly. A global
  "hash-chain must beat distance-cache match by at least two bytes" trial
  improved q11 slightly but regressed q9 `silesia-64k.bin` from 22,261 to
  22,265 bytes. The accepted version limits that margin to the q11 256-check
  config, keeping q9 at the prior size.
- Rejected follow-up q11 parameter probes after commit `bfa4782`: raising
  `max_match_length` from 16 KiB to 32 KiB did not change `silesia-64k.bin`;
  a chunk diagnostic on `silesia-1m.bin` found no 16 KiB/32 KiB minimum-length
  copy opportunities; raising the q11 hash table to 262,144 entries did not
  change `silesia-64k.bin`; trying seven literal split points instead of
  quarter/midpoint/three-quarter did not change q2 or q11 64 KiB outputs; and
  q11 lazy lookahead 4/6 regressed the 64 KiB output to 22,254/22,749 bytes.
- Rejected a q11 two-command-block candidate after probing it as a smaller
  P4 block-splitting subproblem. The candidate wrote separate command Huffman
  trees for quarter/midpoint/three-quarter command splits, first with a
  conservative 2048-command/384-bit admission threshold and then with a looser
  512-command/64-bit threshold. `silesia-64k.bin` q11 stayed at 22,139 bytes,
  so command-block splitting alone is not the current ratio bottleneck.
- The old q2 low-alphabet gate is no longer active in the natural-data path.
  q2 chunks at least 8 KiB use `brotli_natural_hash_config_for_quality(2)`,
  whose density gate is disabled, and `brotli_collect_unique_literals` no
  longer enforces a symbol-count cap. Remaining whole-input calls that ignored
  its return payload were dead scans and safe to remove; this preserved q2/q9/q11
  output sizes while improving `target-perf.nu` encode times slightly.
- q10 should not share q9's high-quality parser settings. After q11 was
  deepened, q10 still used the q9 32-check / 32K-table configuration and was
  byte-identical to q9. Promoting q10 to the q11 256-check / 131K-table config
  improves `silesia-1m.bin` q10 from 273,633 to 266,056 bytes, reducing
  overhead versus Google q10 from 12.85% to 9.72%, at the expected high-quality
  encode-time cost.
- For q10/q11, the 4-byte high-quality hash candidate dominates the 3-byte
  candidate on the measured Silesia slices. Running only the 3-byte candidate
  regresses `silesia-64k.bin` to 22,145 bytes, but running only the 4-byte
  candidate preserves 22,139 bytes on 64 KiB and 266,056 bytes on 1 MiB while
  cutting q10/q11 target-perf encode time nearly in half.
- Rejected q10/q11 parser and writer shortcuts after commit `f82896a`:
  - A stricter high-quality lazy-skip rule that required the future match to
    cover skipped literals regressed `silesia-64k.bin` q10/q11 from 22,139 to
    22,212 bytes.
  - A hash-chain candidate score that penalized estimated distance extra bits
    regressed `silesia-64k.bin` q10/q11 to 22,203 bytes and was slower in the
    legacy ratio harness.
  - Lowering q10/q11 minimum match length from 5 to 4 regressed
    `silesia-64k.bin` q10/q11 to 22,179 bytes.
  - Returning the context16 writer directly for q10/q11 preserved size on 64
    KiB and 1 MiB Silesia but slowed `target-perf.nu` versus HEAD on both
    wasm-gc and native debug in the controlled comparison, so exact-costed
    writer selection should stay in place.
  - Skipping q10/q11's preliminary low-quality/literal/dictionary candidates
    preserved `silesia-64k.bin` at 22,139 bytes and `silesia-1m.bin` at
    266,056 bytes, but only improved q10 wasm-gc while regressing native debug
    q10/q11 by about 1-4%; reject under the native-performance requirement.
  - Conclusion: q10/q11's remaining 9.72%/11.17% 1 MiB overhead is unlikely to
    come from these local greedy knobs. The next release-critical ratio work
    should be a real shortest-path/Zopfli candidate with a cost model and
    traceback, or block/histogram clustering that exact-costs multiple literal,
    command, and distance block layouts.
- Rejected a bounded two-step shortest-path probe for q10/q11. The candidate
  kept the current greedy parser, then added an exact-costed q10/q11 command
  stream that could shorten a long copy by up to 16 bytes when the shortened
  boundary exposed a longer following match. It preserved `silesia-64k.bin`
  q10/q11 at 22,139 bytes and `silesia-1m.bin` q11 at 266,056 bytes, but
  did not improve size and made the legacy verification path much slower
  (`silesia-1m.bin` q11 ~173s). Conclusion: the remaining gap is not from
  greedy over-extension at local copy boundaries; implement the real Zopfli
  node/cost-model traceback rather than another local two-step heuristic.
- A bounded q10/q11 shortest-path DP candidate improved only at full 1 MiB
  chunk scale but is not acceptable yet. Restricting it to 1 MiB chunks
  preserved the prior 512 KiB q10/q11 path and improved `silesia-1m.bin`
  q10/q11 from 266,056 to 263,496 bytes, but native debug target-perf q11
  regressed from 4275.087 ms to 18179.669 ms. Lowering the search depth to
  64 checks still took 17075.047 ms; a 32-check / 16-candidate trial removed
  the ratio gain but still took 12191.136 ms. DP traceback must emit explicit
  distances until the state includes Brotli's recent-distance ring; using
  short codes without that state caused valid smaller streams but corrupt 1
  MiB streams with Google Brotli reporting `FORMAT_TRANSFORM`.
- Rejected a joint literal/command/distance two-block clustering candidate.
  The candidate exact-costed q10/q11 splits at 1/4, 1/2, and 3/4 command
  boundaries, with two literal block types, two command block types, and two
  distance block types. It compiled on all targets, but did not improve either
  measured Silesia slice: `silesia-64k.bin` q10/q11 stayed at 22,139 bytes,
  and `silesia-1m.bin` q10/q11 stayed at 266,056 bytes. The 1 MiB legacy
  verification path also paid the extra candidate-writing cost, so this form
  of bounded two-block clustering is not release-useful. The remaining
  block-clustering path needs richer clustering than a single command-boundary
  binary split, or should be deferred behind a parser/search improvement.
- A bounded mixed static-dictionary + high-quality LZ77 q10/q11 parser is a
  useful ratio increment when the dictionary path is used as the primary
  high-quality parser rather than exact-costed after a separate hq parse.
  Full same-length/extra transform probing improved 64 KiB and 1 MiB Silesia
  more, but doubled native debug encode time. Restricting the mixed index to
  8+ byte identity dictionary words and skipping the separate q10/q11 hq
  writer kept target-perf close to the previous release baseline while still
  improving size:
  - `silesia-64k.bin` q10/q11: 22,139 -> 21,681 bytes.
  - `silesia-1m.bin` q10/q11: 266,056 -> 265,056 bytes.
  - q11 64 KiB target-perf: wasm-gc 30.943 -> 33.636 ms/op; native debug
    149.348 -> 154.935 ms/op.
  - q10 64 KiB target-perf: wasm-gc 31.815 -> 33.620 ms/op; native debug
    144.376 -> 155.233 ms/op.
- Extending the mixed dictionary index from identity-only to the three
  same-length static-dictionary transforms `[0, 9, 44]` is a small additional
  q10/q11 ratio win. It avoids scanning all 121 transform indices, preserving
  most of the identity-only performance profile while adding uppercase
  variants:
  - `silesia-64k.bin` q10/q11: 21,681 -> 21,595 bytes.
  - `silesia-1m.bin` q10/q11: 265,056 -> 264,840 bytes.
  - q11 64 KiB target-perf: wasm-gc 33.636 -> 34.509 ms/op; native debug
    154.935 -> 162.666 ms/op.
  - q10 64 KiB target-perf: wasm-gc 33.620 -> 35.151 ms/op; native debug
    155.233 -> 162.467 ms/op.
- Rejected adding the selected extra transform list to the q10/q11 mixed
  dictionary index. It improved `silesia-64k.bin` q10/q11 from 21,595 to
  21,332 bytes, but q11 native debug encode target-perf regressed from
  162.666 to 241.425 ms/op. That cost is too high for the release direction
  unless the index becomes substantially cheaper.
- Rejected raising q10/q11 high-quality hash-chain checks from 256 to 512
  after the mixed dictionary work. It improved `silesia-1m.bin` q10/q11 from
  264,840 to 263,738 bytes, but q11 1 MiB native debug target-perf was
  5,954.132 ms/op and the legacy verification path grew to ~85.5s. The ratio
  win still leaves q10/q11 far outside the 2% P4 target, so the performance
  cost is not release-acceptable.
- Adding only the two trailing-space selected extra transforms `[1, 4]` to
  the q10/q11 mixed dictionary index is a useful middle ground. It captures
  common `word + space` dictionary matches without the rejected full selected
  extra transform scan:
  - `silesia-64k.bin` q10/q11: 21,595 -> 21,415 bytes.
  - `silesia-1m.bin` q10/q11: 264,840 -> 264,422 bytes.
  - q11 64 KiB target-perf native debug: 162.666 -> 170.831 ms/op.
  - q10 64 KiB target-perf native debug: 162.467 -> 170.846 ms/op.
- Rejected expanding the mixed extra transform subset from `[1, 4]` to
  `[1, 4, 16, 28, 47]` (`in`, `a`, `is` suffixes). It only improved
  `silesia-64k.bin` q10/q11 from 21,415 to 21,396 bytes, while q11 native
  debug target-perf regressed from 170.831 to 191.219 ms/op.
- Current implementation alignment as of 2026-05-28:
  - q0/q1 are RFC-valid stored-meta-block encoders. They match the implemented
    code and release docs, but not the original `docs/brotli.md` q0/q1 ratio
    target. Treat that target as a product decision: reopen P2 if strict
    phase acceptance is required, otherwise keep q0/q1 as fast/stored modes.
  - q2 is the bounded fast P3 profile; q9 has the strongest P3 natural-corpus
    evidence after the mixed-dictionary gate, with 1 MiB Silesia overhead
    reduced to 3.03% versus Google q9.
  - q3..q8 are implemented and round-trip through the standard encoder path,
    but do not yet have a per-quality Silesia ratio/target-perf acceptance
    matrix. This is the main P3 bookkeeping and tuning gap before claiming
    q2..q9 complete.
  - q10/q11 are high-quality hash-parser variants with mixed static-dictionary
    matches, not the documented P4 Zopfli/suffix-tree backend. Latest recorded
    1 MiB Silesia output is 264,422 bytes, still about 9.05% over Google q10
    and 10.49% over Google q11.
  - Commit `9075033` gates q9 mixed-dictionary search with
    `brotli_mixed_dictionary_may_pay`, avoiding unconditional mixed-dictionary
    work on chunks where the preliminary hq parse already wins.
  - Commit `b910f87` trims the mixed dictionary index allocation to the same
    transform subset the mixed path actually builds, reducing allocation
    overhead without changing encoded output.

## 2026-05-30 — Revised q2..q11 ratio target

- Maintainer guidance: the original P4 2% q10/q11 ratio target is too strict
  for the current project priorities. A roughly 5% target is acceptable across
  quality levels when compression efficiency does not drop sharply and
  wasm-gc/native performance remains a first-class constraint.
- Planning consequence:
  - q2..q9 are effectively within the revised measured Silesia target already,
    with remaining work focused on broader corpus validation and regression
    gates rather than mandatory full C-reference Lloyd clustering.
  - q10/q11 remain the primary development gap because the latest recorded
    1 MiB Silesia overhead is +9.05% for q10 and +10.49% for q11.
  - P4 completion should be judged by q10/q11 reaching <=5% on agreed corpora
    with acceptable wasm-gc/native target-perf, not by mandatory full Zopfli
    algorithm parity.
  - A full bounded shortest-path/Zopfli backend remains a valid fallback, but
    cheaper exact-costed improvements should be tried first: guarded
    dictionary subsets, q10/q11 block-layout reuse, high-quality parser scoring,
    and bounded seed expansion.
- q0/q1 remain a separate product decision. Current q0/q1 stored streams are
  valid and externally decodable but intentionally excluded from the q2..q11
  ratio target unless P2 ratio work is explicitly reopened.

## 2026-05-30 — q10/q11 5% baseline and first rejected directions

- Current q10/q11 size gap is stable across Silesia slices, not isolated to
  the 1 MiB report number:
  - 64 KiB: q10 +9.45%, q11 +11.20%.
  - 128 KiB: q10 +8.67%, q11 +10.09%.
  - 512 KiB: q10 +8.67%, q11 +10.09%.
  - 1 MiB: q10 +9.05%, q11 +10.49%.
- q10/q11 still emit byte-identical streams on the measured Silesia slices.
  Reaching the 5% target probably requires a real parser difference for q11
  or a material command-stream improvement shared by q10/q11; minor writer
  selection changes are not moving size.
- Rejected first low-risk trials:
  - mixed dictionary minimum output length 8 -> 6: no 64 KiB size change.
  - block split prefilter threshold 384 -> 128: no 64 KiB size change.
  - exact-cost q10/q11 pure 4-byte high-quality LZ77 against mixed dictionary:
    no 64 KiB size change.
  - q10/q11 max match length 16 KiB -> 32 KiB: no 64 KiB/128 KiB size change.
  - bounded shortest-path seed expanded to 64 KiB and wired into the
    single-metablock path: no 64 KiB size change and a large candidate-cost
    regression.
- `tools/brotli/bench/target-perf.nu` native release evidence is currently
  blocked by the generated native white-box test hanging in `clang -O2` after
  `moon clean`. This is a target-perf tooling problem to fix before relying on
  refreshed native release data. wasm-gc target-perf still runs and should be
  used for quick candidate screening meanwhile.

## 2026-05-30 — target-perf harness restoration follow-up

- `target-perf.nu` has been restored in commit `9180398` by generating a
  temporary ignored MoonBit main package rather than a full-package white-box
  test. This removes the large embedded-source compile blowup from the
  performance harness path.
- Native target-perf remains explicitly marked as `native_cc: "cc-o0"`.
  Default generated-C `clang -O2` still does not finish reliably on this
  package, so final native evidence should be read as MoonBit native codegen
  with the C compiler optimization workaround, not as default release
  `clang -O2` throughput.
- A q11-only pure 4-byte high-quality LZ77 exact-cost trial was rejected:
  it produced no size change on `silesia-64k.bin` or `silesia-128k.bin` while
  adding candidate cost. This reinforces that simply comparing the current
  mixed dictionary stream with the plain high-quality parser does not close the
  5% q10/q11 gap; remaining work needs a real command-stream improvement
  rather than another top-level exact-cost wrapper around the same parser.

## 2026-05-30 — P3 regression gate enforcement

- `tools/brotli/release/validate.nu` previously ran the q2..q9 ratio matrix
  but did not fail on a future ratio regression. It now parses the JSON rows
  and fails when any measured q2..q9 row exceeds `--p3-max-overhead`, default
  `0.05`.
- This is release-gate enforcement, not new corpus coverage. The separate P3
  broadened-corpus task remains open until agreed text/binary/small-file
  inputs are measured and either accepted or tuned.

## 2026-05-30 — q10/q11 chunked encode duplicate work

- The chunked q10/q11 path had a pure duplicate-work pattern:
  `brotli_build_mixed_dictionary_lz77_commands` was called with a default
  distance cache only to decide whether to then call
  `brotli_build_mixed_dictionary_lz77_command_candidate` with the real carried
  distance cache. Removing the first call preserves 128 KiB output size and
  significantly improves q10/q11 encode target-perf.
- This is a performance win, not a size win. It does not close the remaining
  P4 ratio gap, but it reduces the cost of future q10/q11 chunked parser work.

## 2026-05-30 — q10/q11 2 MiB chunk-size trial

- Current q10/q11 2 MiB overhead is worse than the 1 MiB slice:
  q10 +12.08%, q11 +13.57%. This confirms P4 is not only a small-file issue.
- Raising q10/q11 chunk and high-quality max-input limits to 2 MiB is a real
  size lever: it saved 11,064 bytes on `silesia-2m.bin`. However, it only
  improved q10/q11 to +9.72%/+11.18%, still far outside the 5% target, while
  regressing native `cc-o0` encode by roughly 17-36% on the same input.
- A 1.5 MiB chunk-size compromise saved only 1,717 bytes and left q10/q11 at
  +11.71%/+13.20%, so it is not a useful compromise point.
- Do not retry a plain 2 MiB q10/q11 chunk-size promotion without an additional
  parser or pruning change that offsets the native cost and closes much more of
  the size gap.

## 2026-05-30 — P3 broad-corpus periodic finding

- A strict 5% percentage gate is not appropriate for very small text samples
  such as the 84-byte `dictionary-words.txt`: MoonBit q3/q5..q9 were only
  14-15 bytes larger than Google, but the percentage overhead appears as
  22-25%. Small-file release policy should use an absolute-byte allowance or a
  minimum input-size threshold.
- `periodic-allbytes-200k.bin` is a useful broad-corpus regression input
  because it is large enough for percentage overhead to matter and stresses
  long periodic copies with all 256 literals. The old chunked path missed the
  existing single-copy fast path for this input because it returned to chunked
  encoding before trying `brotli_find_single_copy_match`.
- Allowing inputs up to 256 KiB to try the single-copy detector before chunking
  and exact-costing a stored-prefix plus copy-only compressed suffix improves
  q3..q9 from 350 to 272 bytes. q2 keeps the faster single-compressed form:
  301 bytes versus Google 293 (+2.73%) and native `cc-o0` encode improves
  from 91.339 to 73.513 ms/op. q3 beats Google on this synthetic sample,
  q4..q8 are +4.62%, and q9 is just over the line at +5.02%. The q9 native
  encode target-perf cliff is removed (666.810 -> 72.173 ms/op on native
  `cc-o0`). The broader P3 task remains open for agreed text/binary samples
  and the small q9 periodic margin.

## 2026-05-31 — Rejected decode performance trials

Context: after reading `git show opt/perf:docs/brotli_benchmarks.md`, decode
was the open performance target. The report showed Google 1 MiB streams decode
at roughly 2.6x-3.8x slower than Google on wasm-gc and 4.0x-5.7x slower on
native `cc-o0`. Several isolated strategies were tried one at a time and
rejected because they did not improve both benchmark targets across q0/q5/q9/q11.

Rejected strategies. Do not retry these unchanged:

- **Single distance-tree / single distance-block fast path in
  `brotli_decode_compressed_metablock_body`:** bypassed
  `brotli_context_map_tree_index` when `distance_context_map.num_trees == 1`
  and skipped `distance_blocks.ensure_ready` when there was only one distance
  block type. Narrow q0 improved, but q5/q9/q11 regressed or were mixed,
  especially native `cc-o0`. Baseline worktree comparison confirmed this was
  not a stable win.
- **`distance == 1` copy expansion with exponential self-`blit_to`:** replaced
  the repeated-byte loop in `BrotliOutputBuilder::copy_from_distance` with
  seed-one-byte plus doubling blits for longer runs. This was worse on native
  and high-quality streams; the plain per-byte loop is still better for the
  current MoonBit backends and benchmark corpus.
- **Final meta-block output capacity fitting:** used final meta-block length to
  resize output to the exact final size before decode so `finish()` could avoid
  the trailing `trim_buf` copy. A follow-up variant started with zero capacity
  and preallocated from each meta-block header. Both variants were mixed to
  worse; the zero-capacity version also made `brotli_initial_output_capacity`
  unused. The existing compressed-size hint plus final trim remains preferable.
- **Dedicated `brotli_read_symbol8` root-table Huffman decoder:** specialized
  the common `root_bits == 8` symbol path and switched literal/command/distance
  and block/context-map callers to it, leaving root-5 code-length decoding on
  the generic function. wasm-gc showed small point gains, but native `cc-o0`
  regressed across multiple qualities. The generic `brotli_read_symbol` stays
  as the better cross-target implementation.
- **Two-byte `BrotliBitReader::refill_to` fast path for `bits_avail <= 16`:**
  added a 16-bit refill between the existing 24-bit refill and byte-at-a-time
  fallback. q0/q5/q9/q11 target-perf did not show a stable win and native
  `cc-o0` regressed on q5/q11. Do not re-add this exact branch unless a profiler
  shows a changed refill distribution or the native backend changes.
- **Skip literal handling when `command.insert_length == 0`:** wrapped the
  literal decode block in `if command.insert_length > 0` so zero-insert copy
  commands avoid `output.ensure(0)`, local buffer setup, and empty loops. It
  improved q5 slightly in one run, but same-time baseline comparison showed
  q0/q9/q11 were mixed or slower; q11 regressed on both wasm-gc and native
  `cc-o0`. The extra branch is not a stable cross-target win.
- **Inline `BrotliDecoderState::max_distance` inside the copy loop:** replaced
  the method call with direct `output_len < max_backward_distance` logic in
  `brotli_decode_compressed_metablock_body`. This made `max_distance` unused,
  produced a warning, and did not improve native `cc-o0`; q5/q9/q11 native
  regressed in screening. Keep the method call unless a future compiler/backend
  profile proves this call is still material and can be removed cleanly.
- **Single command-block fast path:** skipped `command_blocks.ensure_ready` and
  `command_blocks.remaining -= 1` when `header.command_block.num_types == 1`.
  q0 native improved, but q5/q9 were unstable and q11 native regressed
  severely in screening. The extra branch and different hot-loop shape are not
  worthwhile for the current decode corpus.
- **`BrotliBitReader::take_bits_fast` for table-known extra bits:** added a
  refill/mask/drop helper without `peek_bits`/`drop_bits` width checks and used
  it for command, distance, and block-length extra bits. Native improved in a
  few points, but same-time baseline showed q5/q9 wasm-gc regressions and q9
  native was not better. Do not retry this exact unchecked helper on the current
  backends.
- **Manual small-copy loop for `distance >= length && length <= 8`:** replaced
  short non-overlapping `FixedArray.blit_to` copies with a hand-written loop.
  This regressed native `cc-o0` across the q0/q5/q9/q11 screening set. The
  backend/library `blit_to` path is better even for these small Brotli copies.
- **Inline implicit `distance_code == 0` recent-distance lookup:** bypassed
  `BrotliDistanceRing::take_short_code(0)` in the command loop and directly
  updated the ring fields. It passed tests/check, but q5/q9/q11 native
  screening regressed. Keep the common ring helper on the current backends.
- **Packed decode-only command info tables:** replaced
  `@common.brotli_command_info(symbol)` record access in `BrotliCommand::read_into`
  with two private packed `FixedArray[Int]` tables for offsets and metadata.
  q5/q9/q11 had mixed point wins, but q0 native `cc-o0` regressed sharply
  (about 69 ms to 73 ms in screening). Do not retry this exact packed-table
  representation unless q0 is separately protected or the packing overhead is
  eliminated.
- **Empty single-tree context maps:** changed `brotli_read_context_map` to store
  an empty map when `num_trees == 1` and made
  `brotli_context_map_tree_index` return 0 for single-tree maps. This removed
  small header allocations but added a helper branch and changed test
  assumptions; same-time baseline showed native `cc-o0` slower across
  q0/q5/q9/q11. Keep the materialized zero maps.
- **Prechecked back-reference copy helper:** split
  `BrotliOutputBuilder::copy_from_distance` into a checked wrapper and an
  unchecked/pre-ensured copy helper used by the decode loop after
  `distance <= max_distance`. It passed tests but made the checked wrapper
  unused and screened slower on native `cc-o0` across q0/q5/q9/q11. Keep the
  existing single checked helper.
- **Remove per-literal byte-range checks:** deleted `literal < 0 || literal >
  255` checks from the literal decode loops, relying on the 256-symbol literal
  alphabet and Huffman-table validation. It passed tests/check but screened
  slower on q0/q5/q9/q11, likely due to backend code-layout effects. Keep the
  explicit checks.
- **Early return from `BrotliOutputBuilder::ensure(0)`:** added a zero-size
  fast return to avoid capacity checks for zero-insert commands without adding
  a branch in the decode loop. Same-time baseline showed native `cc-o0` slower
  on q0/q5/q9/q11. Keep the existing uniform `ensure` path.
- **Lower initial output capacity hint from 5.0x to 4.5x compressed size:**
  changed `brotli_initial_output_capacity` to reserve `input_len * 9 / 2`
  instead of `input_len * 5`. It passed decode tests/check after updating the
  white-box expectation, but same-time baseline comparison was not a stable
  win: q0 native, q5 wasm-gc/native, q9 native, and q11 native were slower.
  Keep the 5.0x hint unless a future candidate changes the larger allocation
  and final trim behavior together with broader evidence.
- **Normal-copy `remaining` bookkeeping split:** moved the normal
  `distance <= max_distance` path to precheck `command.copy_length <=
  remaining` and subtract `command.copy_length` directly, leaving
  `output.len - output_before_copy` only for dictionary copies. It passed
  tests/check but immediately regressed q0 in same-time screening
  (wasm-gc/native both slower), so the uniform post-copy length-delta path is
  better for current backends.
- **Remove redundant `bits_avail < n` condition in the 24-bit refill branch:**
  `BrotliBitReader::refill_to` already returns when `bits_avail >= n`, so the
  later 24-bit refill branch can be written with only `bits_avail <= 8` and
  input-room checks. It passed tests/check, but q0 screening was only tied on
  wasm-gc and slower on native `cc-o0`; keep the old condition because its code
  shape is faster on the current native backend.
- **Combine command insert/copy extra-bit reads when total width <= 24:**
  read both command extra fields with one `take_bits(total)` and split the
  lower insert bits from the higher copy bits, falling back to separate reads
  for wider commands. It passed tests/check and q0 wasm-gc was slightly better,
  but q0 native `cc-o0` regressed, so the added branching is not worthwhile.
- **Skip `take_bits(0)` for zero-width block/distance extra bits:** added
  branches in `brotli_read_block_length` and `brotli_read_distance` to return
  the base/offset directly when `extra_bits == 0`. It passed tests/check, but
  q0 same-time screening regressed on both wasm-gc and native `cc-o0`; the
  extra branch costs more than the empty read path on the current hot streams.
- **Replace the hottest single-literal range `for` loop with a `while pos <
  end` loop:** changed only the single literal tree + single literal block path
  to avoid range-loop bookkeeping. It passed tests/check, but q0 native
  `cc-o0` regressed immediately, so the existing `for _ in 0..<insert_length`
  code shape is better.
- **Inline command decode into the compressed-body loop:** replaced the reused
  mutable `BrotliCommand` record and `read_into` method call with local command
  variables in the loop. It passed tests/check and q0 improved slightly, but
  q5 wasm-gc/native and q9/q11 native regressed in same-time baseline
  comparison. Keep the reused command record; the local-variable code shape is
  not a stable cross-quality win.
- **Direct distance context-map access in the explicit-distance path:** replaced
  `brotli_context_map_tree_index(...)` with direct indexing into
  `header.distance_context_map.map` after block/context validation. This passed
  `moon check --target native` and `moon test src/decode --target native`, but
  made the checked helper unused and failed same-time screening: q0/q9/q11 were
  mostly faster, but q5 wasm-gc regressed from 33.412 to 33.785 ms/op. Reverted;
  do not retry this exact direct-index substitution unless it is paired with a
  broader structure that also protects q5 wasm-gc.
- **Remove the per-symbol single-symbol Huffman table check:** relied on
  single-symbol tables being replicated across the root table and let the
  normal root lookup handle zero-bit entries. This passed native check and
  decode tests, but failed screening because q0 wasm-gc regressed from 42.017
  to 44.907 ms/op. Keep the early `table[0]` zero-bit check; q0 literal-heavy
  streams appear to benefit from it more than higher-quality streams benefit
  from removing the branch.
- **Remove `brotli_read_block_length` symbol range check:** relied on block
  length Huffman tree construction to constrain symbols and deleted the explicit
  `code < 0 || code >= brotli_num_block_length_symbols` guard. It passed native
  check and decode tests, but failed same-time q0/q5/q9/q11 screening: q0
  native, q5 wasm-gc, and both q9 rows were slower or effectively tied in the
  wrong direction. Reverted; keep the checked block-length helper.
- **Remove Huffman table sentinel checks in `brotli_read_symbol`:** deleted the
  per-lookup checks for negative root/sub-table entry lengths, relying on the
  Huffman builder to fill every reachable entry. It passed native check and
  decode tests, but failed q0/q5/q9/q11 screening: q0 was slower on both
  targets, q5 wasm-gc regressed, and q9/q11 native regressed. Reverted; keep
  the sentinel checks.
- **Identity static-dictionary transform early return:** added a fast path in
  `copy_transformed_dictionary_word` for transform 0 to blit dictionary bytes
  directly and skip prefix/suffix/uppercase setup. It passed native check and
  decode tests, but q0/q5/q9/q11 screening failed badly on q5 wasm-gc and did
  not produce stable wins on q9/q11 wasm-gc. Reverted; keep the uniform
  transform path.
- **Decode-private literal context id helper:** replaced
  `@common.brotli_literal_context_id` in the multi-literal-tree path with a
  local non-raising helper that directly indexes the context LUTs. It passed
  native check and decode tests, and q5/q9/q11 mostly improved, but q0 native
  regressed from 63.370 to 63.494 ms/op in same-time screening. Reverted; keep
  the public helper call unless q0 is protected by a larger restructuring.
- **Decode-private validated recent-distance record:** replaced
  `BrotliDistanceRing::record(distance)` after normal back-reference copies
  with a local helper that skips the public `distance <= 0` check. It passed
  native check and decode tests, and native improved across q0/q5/q9/q11, but
  q5 wasm-gc regressed from 31.903 to 32.085 ms/op. Reverted; keep the checked
  record helper.
- **Pre-resolved literal context-to-tree table:** built a per-meta-block
  `FixedArray[FixedArray[Int]]` for multi-literal-tree context maps so the
  general literal path could index the actual Huffman tree directly instead of
  loading a map byte and calling `literal_trees.tree(tree_index)` per literal.
  The change passed `moon check --target native` and `moon test src/decode
  --target native`, but same-time q0 screening failed before higher-quality
  runs: baseline q0 was 39.862/61.388 ms on wasm-gc/native, while the trial
  measured 40.208/63.243 ms. Reverted; do not retry this exact pre-resolved
  tree table shape unless the single-tree path has no extra setup cost and
  q0 is protected by direct same-time evidence.
- **Remove unreachable `copy_from_distance` zero-length branch:** relied on
  the Brotli command table's minimum copy length of 2 and deleted the private
  helper's `if length == 0 { return }` check after `ensure(length)`. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 screening was mixed: wasm-gc was effectively tied/slightly faster
  (39.715 ms versus baseline 39.741 ms), while native regressed to 64.856 ms
  versus 61.449 ms. Reverted; keep the zero-length branch because the current
  native backend prefers this code shape despite the branch being unreachable
  from valid Brotli command copies.
- **`BrotliBlockTracker::ensure_ready` fast path as `remaining != 0`:** used
  the invariant that tracker remaining counts should never be negative on valid
  decode paths, changing the hot fast-path condition from `> 0` to `!= 0`.
  It passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening was mixed: wasm-gc improved slightly
  (39.766 ms versus baseline 39.852 ms), while native regressed to 63.282 ms
  versus 61.478 ms. Reverted; keep the `> 0` comparison for the current
  native codegen.
- **Tail-only root Huffman EOF check:** added a `tail_decode` flag in
  `brotli_read_symbol` so the `entry_bits > reader.bits_avail` check only ran
  for the end-of-input residual-bit path after `refill_to(root_bits)` could
  not be called. This preserved correctness in `moon check --target native`
  and `moon test src/decode --target native`, but q0 screening failed:
  baseline was 39.834/61.472 ms on wasm-gc/native and the trial measured
  39.904/63.624 ms. Reverted; keep the unconditional root-entry availability
  check because the extra flag/code shape is slower on current targets.
- **Direct hot-path `BrotliHuffmanTreeGroup.trees[index]` access:** replaced
  `tree(index)` calls in `brotli_decode_compressed_metablock_body` with direct
  array field access and temporarily updated white-box tests after the private
  method became unused. The change passed `moon check --target native` and
  `moon test src/decode --target native`. q0 screening twice showed a
  consistent split: native improved materially (about 61.6 -> 59.9 ms, then
  61.5 -> 59.3 ms), but wasm-gc regressed slightly (39.7 -> 39.8 ms, then
  39.9 -> 40.0 ms). Reverted; do not retry direct tree-array access alone
  unless wasm-gc is protected or the call removal is target-specific.
- **Split single literal-tree/block body into a separate loop:** moved the
  dominant `num_trees == 1 && literal_block.num_types == 1` shape into a
  private helper so it could avoid allocating a literal block tracker and skip
  the per-command `single_literal_tree` / `single_literal_block` branches. The
  change passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening failed immediately: baseline measured
  39.921/61.522 ms on wasm-gc/native, while the split loop measured
  40.059/63.253 ms. Reverted; keep the integrated loop because the function
  split and duplicated code shape are slower on current backends.
- **Copy branch order with non-overlap before `distance == 1`:** moved the
  `distance >= length` branch ahead of the repeated-byte distance-1 path in
  `BrotliOutputBuilder::copy_from_distance`, preserving semantics but
  prioritizing non-overlapping copies. It passed `moon check --target native`
  and `moon test src/decode --target native`, but q0 screening failed:
  baseline measured 39.885/61.469 ms on wasm-gc/native, while the reordered
  branch measured 40.227/63.410 ms. Reverted; keep the distance-1 branch first
  on current backends.
- **Hoist single-symbol literal tree fill:** detected when the single literal
  tree was itself a single-symbol Huffman table and filled insert runs directly
  with that byte, bypassing per-literal Huffman reads. It passed `moon check
  --target native` and `moon test src/decode --target native`, but q0 screening
  was not a cross-target win: wasm-gc improved slightly (39.778 ms versus
  baseline 39.803 ms), while native regressed to 63.108 ms versus 61.525 ms.
  Reverted; keep the per-literal `brotli_read_symbol` call because the extra
  branch and code shape hurt native on the current corpus.
- **Temporary decode shape probe:** instrumented decoder state locally, then
  reverted the probe. Observed q0 Google 1 MiB streams have 2 compressed
  meta-blocks, both single literal tree/block, with 143,528 commands,
  112,708 inserted literals, 935,872 copy bytes, 36,702 short distances,
  106,824 explicit distances, no dictionary copies, and almost all normal
  copies non-overlapping. q5/q9/q11 each use one multi-literal-tree
  meta-block, about 75k-86k commands, about 74k-85k explicit distances,
  about 0.6k-1.4k short distances, dictionary copies increasing from 1,316
  at q5 to 5,759 at q11, and almost all normal copies non-overlapping. This
  supports focusing on explicit distance decode and normal non-overlap copy
  shape, but prior copy branch/order trials remain rejected.
- **Precompute distance direct limit and postfix mask per meta-block:** added a
  private `brotli_read_distance_with_limits` helper taking
  `direct_limit = 16 + ndirect` and `postfix_mask = (1 << npostfix) - 1` from
  the compressed-body loop, then updated the white-box distance test to call
  that helper. It passed `moon check --target native` and `moon test
  src/decode --target native`, but q0 screening failed: baseline measured
  39.576/61.460 ms on wasm-gc/native, while the helper measured
  40.170/63.361 ms. Reverted; the extra arguments/helper shape are slower than
  recomputing those constants in the existing function on current backends.
- **Postfix-0 explicit distance helper:** added a specialized
  `brotli_read_distance_postfix0` path that removes the postfix mask and final
  shift when `header.distance_postfix_bits == 0`, selected from the compressed
  body with a precomputed Boolean. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 39.860/61.640 ms on wasm-gc/native, while the specialized helper
  measured 40.023/62.795 ms. Reverted; even the common postfix-0 case is
  slower when split into a separate helper/branch on current backends.
- **Prefer explicit-distance branch in command loop:** reordered
  `if command.distance_code >= 0` to make the measured dominant explicit
  distance path the first branch (`command.distance_code < 0`) while keeping
  the same computations. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 39.940/61.612 ms on wasm-gc/native, while the reordered branch
  measured 40.109/63.183 ms. Reverted; keep the short-distance branch first
  despite explicit distances being more common.
- **Meta-block window-covered max distance:** computed a per-meta-block
  `metablock_within_window` flag and used `output.len` directly as
  `max_distance` when the whole meta-block fits within the Brotli window,
  avoiding `state.max_distance(output.len)` in the hot loop for 1 MiB samples.
  It passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening failed: baseline measured 39.891/61.385 ms on
  wasm-gc/native, while the trial measured 40.145/62.783 ms. Reverted; the
  extra hot-loop Boolean branch is slower than the existing method call/branch.
- **Lazy literal block tracker for single-block streams:** avoided constructing
  `BrotliBlockTracker` for literals when the meta-block had a single literal
  tree and a single literal block, keeping the integrated body loop rather than
  splitting a helper. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 39.803/61.580 ms on wasm-gc/native, while the lazy tracker trial
  measured 40.221/63.116 ms. Reverted; even avoiding the unused tracker
  allocation is slower with the added option/guard code shape.
- **Remove duplicate dictionary transform-index check:** deleted the private
  `copy_transformed_dictionary_word` transform-index range check because its
  only production caller, `copy_from_dictionary_after_max_distance`, already
  validates the computed transform index. It passed `moon check --target
  native` and `moon test src/decode --target native`, but q0 screening failed:
  baseline measured 39.846/61.702 ms on wasm-gc/native, while the trial
  measured 40.001/63.191 ms. Reverted; even dictionary-path-only source
  changes can perturb current q0 codegen/layout enough to fail the guardrail.
- **Remove final `unbrotli_sync` max-output check:** deleted the public wrapper
  `out.length() > opts.max_output_size` check after `brotli_decode_scaffold`,
  relying on `BrotliOutputBuilder::ensure` and fixed-output checks to enforce
  the same cap during decode. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 39.519/61.550 ms on wasm-gc/native, while the trial measured
  40.026/63.419 ms. Reverted; keep the redundant-looking final guard because
  the current generated code is faster with it.
- **Validated insert `ensure` helper:** added `BrotliOutputBuilder::ensure_validated`
  without the impossible negative-length check and used it only for
  `output.ensure(command.insert_length)` after command length validation. It
  passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening failed: baseline measured 40.124/61.315 ms on
  wasm-gc/native, while the trial measured 40.010/63.321 ms. Reverted; the
  duplicated helper/code shape hurts native more than the skipped check helps.
- **Local `buf` alias in `copy_from_distance`:** cached `self.buf` in a local
  variable and used it for repeated-byte, non-overlap, and overlap copies to
  reduce repeated field access in the normal-copy hot path. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 screening was mixed and failed the cross-target rule: baseline measured
  39.966/61.354 ms on wasm-gc/native, while the trial measured
  39.820/63.373 ms. Reverted; local buffer aliasing helps wasm-gc slightly but
  hurts native codegen.
- **Lazy `literal_tree0` lookup:** moved `header.literal_trees.tree(0)` from
  meta-block setup into the `single_literal_tree` branch so multi-literal-tree
  streams avoid an unused lookup. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed badly
  because the single-tree hot path now repeats the lookup per command: baseline
  measured 39.702/61.525 ms on wasm-gc/native, while the trial measured
  39.915/66.209 ms. Reverted; keep the eager per-meta-block lookup.
- **Cached command tree between block switches:** kept a mutable
  `command_tree` and `command_tree_type` inside the compressed-body loop,
  updating the tree only when `command_blocks.current_type` changed instead of
  calling `header.command_trees.tree(command_blocks.current_type)` for every
  command. It passed `moon check --target native` and `moon test src/decode
  --target native`, and repeated q0 screening showed native improved
  (61.479 -> 60.753 ms, then 61.546 -> 60.885 ms), but wasm-gc regressed
  slightly in both runs (39.926 -> 39.995 ms, then 39.888 -> 40.045 ms).
  Reverted; do not retry this exact command-tree cache unless wasm-gc can be
  protected or the optimization becomes target-specific.
- **Temporary command-symbol distribution probe:** instrumented command decode
  locally, then reverted the probe. q0's top command symbols are concentrated
  around explicit-distance no-extra-bit commands: 131 (22,575), 1 (14,627),
  136 (13,648), 132 (12,050), 133 (7,856), 144 (7,504), 2 (7,099), 192
  (5,467), 134 (4,964), 152 (4,817). q5/q9/q11 similarly have very hot
  explicit-distance symbols 131..135 and 192..198, with insert extra bits
  usually zero and copy extra bits often zero or small. This suggests command
  decode remains an attractive area, but table/branch shape is fragile.
- **Fast path for command symbols 128..135:** added a hand-coded
  `BrotliCommand::read_into` branch for the common explicit-distance,
  no-extra-bit symbols 128 through 135, setting insert length 0, copy length
  2..9, distance code -1, and the distance context directly without reading
  `brotli_command_info_table`. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 39.632/61.269 ms on wasm-gc/native, while the trial measured
  40.107/62.850 ms. Reverted; the extra symbol-range branch hurts current
  codegen more than avoiding the table lookup for these symbols helps.
- **Cached distance tree by block type and distance context:** cached the
  resolved distance Huffman tree inside the compressed-body loop and refreshed
  it only when either the distance block type or `command.distance_context`
  changed. It passed `moon check --target native` and `moon test src/decode
  --target native`, but q0 screening was mixed and failed the cross-target
  rule: baseline measured about 40.036/61.579 ms on wasm-gc/native, while the
  trial measured about 39.954/61.731 ms. Reverted; the small wasm-gc gain does
  not justify the native regression.
- **Remove `copy_from_distance` trusted-call checks:** removed the private
  helper's negative-length and backward-distance guards, relying on the command
  table and the caller's `distance <= max_distance` check in the compressed
  body loop. It passed `moon check --target native` and `moon test src/decode
  --target native`, but q0 screening failed on both targets: baseline measured
  41.961/63.099 ms on wasm-gc/native, while the trial measured 42.393/65.051
  ms. Reverted; keep the duplicate-looking checks because the current generated
  code is faster with them.
- **Short-distance code 0 fast path inside helper:** split
  `brotli_take_short_code_validated` so code 0 directly reads the ring slot,
  decrements the index, and sets the distance context without computing
  `offset` and `1 >> code`. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 41.841/61.987 ms on wasm-gc/native, while the trial measured
  41.907/63.901 ms. Reverted; keep the compact shared `code <= 3` branch.
- **Single command-symbol 1 fast path:** added a narrow
  `BrotliCommand::read_into` branch for q0-hot symbol 1, setting insert length
  0, copy length 3, short distance code 0, and distance context 1 without
  reading the command-info table. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed: baseline
  measured 41.723/61.866 ms on wasm-gc/native, while the trial measured
  41.941/63.835 ms. Reverted; even a single-symbol branch perturbs the current
  command decode shape too much.
- **Cache command-info record fields in locals:** loaded command-info extra-bit
  widths and length offsets into local variables inside `BrotliCommand::read_into`
  before the extra-bit branches, aiming to reduce repeated record field access.
  It passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening failed on both targets: baseline measured
  41.603/61.591 ms on wasm-gc/native, while the trial measured 42.129/63.820
  ms. Reverted; the extra locals/code shape are slower than direct field access
  on current backends.
- **Validated distance context-map helper:** added
  `brotli_context_map_tree_index_validated` with direct map indexing and used
  it for explicit-distance tree selection, preserving a helper boundary rather
  than inlining the direct access into the command loop. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 screening was mixed: baseline measured 42.440/61.707 ms on
  wasm-gc/native, while the trial measured 41.761/62.949 ms. Reverted; like
  the earlier direct distance context-map access, removing the checks helps
  wasm-gc in this sample but hurts native.
- **`distance == 1` copy fill as a `while` loop:** rewrote only the repeated
  byte copy branch in `BrotliOutputBuilder::copy_from_distance` from
  `for i in 0..<length` to an explicit `while pos < end` loop, leaving copy
  branch order and non-overlap `blit_to` unchanged. It passed `moon check
  --target native` and `moon test src/decode --target native`, but q0
  screening was mixed: baseline measured 41.959/62.016 ms on wasm-gc/native,
  while the trial measured 41.878/64.014 ms. Reverted; keep the range loop for
  native codegen.
- **Inline the `take_bits` drop after `peek_bits`:** changed
  `BrotliBitReader::take_bits` to shift `bit_buf` and decrement `bits_avail`
  directly after `peek_bits(n)`, keeping the checked `drop_bits` method for
  direct callers. This removes a redundant validation after `peek_bits` has
  checked width and refilled enough bits. It passed `moon check --target
  native` and `moon test src/decode --target native`, but q0 screening was
  mixed: baseline measured 41.858/61.916 ms on wasm-gc/native, while the trial
  measured 41.012/64.882 ms. Reverted; the change helps wasm-gc but hurts
  native codegen substantially.
- **Early insert-length `remaining` decrement:** moved
  `remaining -= command.insert_length` to immediately after the insert-length
  bounds check and before literal output, intending to shorten the live range
  of `command.insert_length` before distance/copy handling. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 screening failed on both targets: baseline measured 41.749/62.831 ms on
  wasm-gc/native, while the trial measured 42.179/67.102 ms. Reverted; keep the
  decrement after literal decode.
- **Literal single-block Boolean order:** rewrote
  `single_literal_tree && header.literal_block.num_types == 1` as
  `header.literal_block.num_types == 1 && single_literal_tree` to see whether
  native codegen preferred checking the direct field before the derived flag.
  It passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening was mixed: baseline measured 42.194/62.385 ms on
  wasm-gc/native, while the trial measured 42.067/64.606 ms. Reverted; keep
  the existing order.
- **Reuse `direct_limit` for explicit-distance `xcode`:** changed
  `let xcode = code - ndirect - 16` to `let xcode = code - direct_limit` inside
  `brotli_read_distance`, reusing the already-computed direct distance
  threshold without adding branches or helper arguments. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 screening failed on both targets: baseline measured 41.670/61.877 ms on
  wasm-gc/native, while the trial measured 41.888/64.271 ms. Reverted; keep the
  original expression.
- **Cache decoded command fields in the body loop:** copied
  `command.insert_length`, `copy_length`, `distance_code`, and
  `distance_context` into local variables immediately after `read_into`, then
  used the locals through literal, distance, and copy handling. This targeted
  repeated mutable-record field loads without changing `read_into` itself. It
  passed `moon check --target native` and `moon test src/decode --target
  native`, but q0 screening failed on both targets: baseline measured
  41.709/61.770 ms on wasm-gc/native, while the trial measured 42.031/63.569
  ms. Reverted; keep direct command field reads in the integrated loop.
- **Merge `copy_from_distance` tail length assignment:** rewrote the
  `distance == 1`, `distance >= length`, and overlap-copy branches to share one
  final `self.len = start + length` assignment instead of returning from the
  first two branches after assigning. It passed `moon check --target native`
  and `moon test src/decode --target native`, but q0 screening failed on both
  targets: baseline measured 41.459/62.060 ms on wasm-gc/native, while the
  trial measured 41.899/64.228 ms. Reverted; keep the branch-local assignments
  and early returns.
- **Inline distance-tree lookup into `brotli_read_distance` call:** removed the
  local `distance_tree` binding in the explicit-distance branch and passed
  `header.distance_trees.tree(distance_tree_index)` directly to
  `brotli_read_distance`, leaving validation and tree lookup semantics
  unchanged. It passed `moon check --target native` and `moon test src/decode
  --target native`, but q0 screening failed on both targets: baseline measured
  41.796/61.613 ms on wasm-gc/native, while the trial measured 42.230/64.555
  ms. Reverted; keep the local binding.
- **Inline short-distance ring slot mask:** replaced
  `@common.brotli_distance_ring_slot(...)` calls inside the decode-private
  `brotli_take_short_code_validated` helper with direct `& 3` indexing, leaving
  the public distance-ring API unchanged. It passed `moon check --target
  native` and `moon test src/decode --target native`, but q0 screening failed:
  baseline measured 42.455/61.732 ms on wasm-gc/native, while the trial
  measured 42.538/64.644 ms. Reverted; keep the shared slot helper call.
- **Constant-fold direct-distance return expression:** changed
  `return code - brotli_num_distance_short_codes + 1` to `return code - 15` in
  the direct-distance branch of `brotli_read_distance`, leaving the surrounding
  branch and explicit-distance formula unchanged. It passed `moon check
  --target native` and `moon test src/decode --target native`, but q0
  screening failed on both targets: baseline measured 41.853/61.854 ms on
  wasm-gc/native, while the trial measured 42.088/64.186 ms. Reverted; keep the
  named-constant expression.
- **Remove 24-bit refill post-check return:** deleted the
  `if self.bits_avail >= n { return }` branch at the end of
  `BrotliBitReader::refill_to`'s 24-bit fast path, relying on the following
  `while self.bits_avail < n` condition to skip byte-at-a-time refill when
  enough bits are available. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 screening failed on both
  targets: baseline measured 41.954/62.302 ms on wasm-gc/native, while the
  trial measured 42.398/64.191 ms. Reverted; keep the explicit return.
- **Direct mask table lookup in `peek_bits`:** changed
  `BrotliBitReader::peek_bits` from `self.bit_buf & brotli_low_mask(n)` to
  direct `brotli_low_mask_lut[n]` access, matching the Huffman hot path while
  leaving the helper available for other callers. It passed `moon check
  --target native` and `moon test src/decode --target native`, but q0
  screening failed on both targets: baseline measured 41.780/61.786 ms on
  wasm-gc/native, while the trial measured 41.916/64.126 ms. Reverted; keep
  the helper call in `peek_bits`.
- **Move `distance == 1` length update before fill:** in
  `BrotliOutputBuilder::copy_from_distance`, moved `self.len = start + length`
  to before the repeated-byte fill loop in the `distance == 1` branch, relying
  on `ensure(length)` to reserve the output space. It passed `moon check
  --target native` and `moon test src/decode --target native`, but q0
  screening was mixed: baseline measured 41.835/61.793 ms on wasm-gc/native,
  while the trial measured 41.812/64.109 ms. Reverted; keep the length update
  after the fill loop.
- **Cache Huffman root entry value:** added a local `entry_value = entry >> 16`
  in `brotli_read_symbol` and reused it for both the root-table return and the
  sub-table offset, avoiding repeated high-half extraction from the same packed
  entry. It passed `moon check --target native` and `moon test src/decode
  --target native`, but q0 screening failed on both targets: baseline measured
  41.774/61.720 ms on wasm-gc/native, while the trial measured 41.871/63.701
  ms. Reverted; keep the repeated shifts because the extra local worsens
  current codegen.
- **Remove zero-length metadata skip branch:** deleted the `length == 0`
  special case in `brotli_skip_metadata`, letting `FixedArray::make(0, ...)`
  and `reader.take_bytes(..., length=0)` handle alignment uniformly. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 screening was mixed even though the path is cold for the benchmark:
  baseline measured 42.225/62.271 ms on wasm-gc/native, while the trial
  measured 41.942/64.998 ms. Reverted; keep the explicit zero-length metadata
  branch.

Screening commands used for these negative trials:

```bash
just target-perf-decode target/brotli-current-bench/google-1m/silesia-1m.q0.br target/brotli-bench/silesia-1m.bin wasm-gc,native 5 3
just target-perf-decode target/brotli-current-bench/google-1m/silesia-1m.q5.br target/brotli-bench/silesia-1m.bin wasm-gc,native 5 3
just target-perf-decode target/brotli-current-bench/google-1m/silesia-1m.q9.br target/brotli-bench/silesia-1m.bin wasm-gc,native 5 3
just target-perf-decode target/brotli-current-bench/google-1m/silesia-1m.q11.br target/brotli-bench/silesia-1m.bin wasm-gc,native 5 3
```

Policy for future decode optimization: a candidate should beat the current
code on both `wasm-gc` and native `cc-o0` across at least q0, q5, q9, and q11
before spending time on full `just bench`. If it only helps q0 or only helps
wasm-gc, treat it as a failed narrow optimization and revert.

## 2026-06-01 — Accepted decode performance trial

- **Remove duplicate explicit Huffman tree-group bounds check from hot lookup:**
  `BrotliHuffmanTreeGroup::tree` now relies on the underlying array access
  after header parsing, block tracking, and context-map validation have already
  constrained tree indexes. This keeps the fast-path API package-private and
  avoids rechecking the same invariant for every command, multi-context
  literal, and explicit-distance tree lookup.
- Same-time q0/q5/q9/q11 screening with
  `just target-perf-decode ... wasm-gc,native 5 3` improved every target:
  aggregate min time across eight rows improved from 382.314 ms/op to
  372.795 ms/op, a 2.49% decode speedup. Individual min-time gains were
  approximately q0 wasm/native +2.22%/+2.49%, q5 +1.54%/+3.09%,
  q9 +2.04%/+1.85%, and q11 +2.74%/+3.44%.
- `just bench` completed after the change and regenerated
  `docs/current-bench/*.jsonl` and `docs/brotli_release_report.md`. Encode
  output sizes were byte-for-byte unchanged versus the previous
  `docs/current-bench/encode.jsonl`, so the optimization does not change
  encoder behavior.
- Added `brotli_context_map_tree_index rejects invalid mapped tree` white-box
  coverage to document the validation invariant used by the hot tree lookup.
- **Validated short-distance helper:** added a decode-private helper for short
  distance codes whose range is already guaranteed by command symbols or the
  distance Huffman alphabet, avoiding the public `take_short_code` range check
  in the compressed-body hot path. Same-session q0/q5/q9/q11 screening with
  `wasm-gc,native`, repeats=5, samples=3 improved aggregate min time from
  371.619 to 362.544 ms/op, a 2.44% decode speedup. Each of the eight screened
  rows improved. `just bench` completed, and its results were saved under
  `target/brotli-perf-notes/2026-06-01-short-distance/` rather than committed.
  Encode output sizes were unchanged versus the checked-in
  `docs/current-bench/encode.jsonl`.
- **Fused explicit-distance formula in decode-private path:** replaced the
  non-short explicit-distance path's separate calls to
  `brotli_distance_extra_bits` and `brotli_distance_offset` with one local
  calculation after the Huffman code has already established the code range.
  This avoids duplicate checks and recomputing `xcode`. Same-session
  q0/q5/q9/q11 screening with `wasm-gc,native`, repeats=5, samples=3 improved
  aggregate min time from 363.756 to 353.315 ms/op, a 2.87% decode speedup.
  Each of the eight screened rows improved. `just bench` completed, and its
  results were saved under
  `target/brotli-perf-notes/2026-06-01-distance-formula/` rather than
  committed. Encode output sizes were unchanged versus the checked-in
  `docs/current-bench/encode.jsonl`.
- **Direct command info table lookup:** changed the command decode hot path
  from the checked `brotli_command_info(symbol)` helper to direct access of
  the same `brotli_command_info_table`, relying on command Huffman table
  construction to constrain symbols to the command alphabet. This is distinct
  from the rejected packed-table representation: it keeps the existing record
  table and only removes the redundant public-helper range check. Same-session
  q0/q5/q9/q11 screening with `wasm-gc,native`, repeats=5, samples=3 improved
  aggregate min time from 353.828 to 347.499 ms/op, a 1.79% decode speedup.
  Each screened row improved. `just bench` completed, and its results were
  saved under `target/brotli-perf-notes/2026-06-01-command-info-table/` rather
  than committed. Encode output sizes were unchanged versus the checked-in
  `docs/current-bench/encode.jsonl`.

## 2026-06-01 — Rejected decode performance trial

- **Cache multi-literal path field references:** cached `header.context_modes`
  and `header.literal_trees` into locals in the multi literal-tree branch of
  `brotli_decode_compressed_metablock_body`, aiming to reduce repeated record
  field access for q5/q9/q11 literal-context decoding while leaving the q0
  single-tree branch semantically unchanged. It passed `moon check --target
  native` and `moon test src/decode --target native`, but same-time q0
  screening failed: baseline measured 42.0888/61.6848 ms on wasm-gc/native,
  while the trial measured 42.2274/64.5204 ms. Reverted; even cold-branch
  local caching perturbs current decode codegen enough to fail the guardrail.
- **Inline empty Huffman refill:** inlined the `bits_avail == 0` four-byte
  refill case directly in `brotli_read_symbol`, keeping tail and partial
  accumulator refill in `BrotliBitReader::refill_to`. The candidate passed
  `moon check --target native` and `moon test src/decode --target native`, and
  q0 same-time screening was slightly faster on both targets (baseline
  41.3968/63.7920 ms, trial 41.2974/63.5768 ms for wasm-gc/native). q5 failed
  the cross-target rule: wasm-gc improved 34.0830 -> 33.6478 ms, but native
  regressed 51.2378 -> 53.5978 ms. Reverted; do not retry this exact Huffman
  empty-refill inlining unless native codegen changes or the optimization can
  be isolated to wasm-gc.
- **Command double-zero extra-bit fast return:** added a branch in
  `BrotliCommand::read_into` for command-info records where both insert and
  copy extra-bit widths are zero, directly assigning the precomputed offsets
  and returning. This differs from the earlier symbol-specific command fast
  paths and combined extra-bit read trial, but it still failed q0 same-time
  screening after passing `moon check --target native` and
  `moon test src/decode --target native`: baseline measured 41.4432/61.8700 ms
  on wasm-gc/native, while the trial measured 41.8366/64.2958 ms. Reverted;
  keep the two existing independent zero-width branches.
- **Split single-literal-block body loop:** moved the single literal tree plus
  single literal block meta-block shape into a separate specialized compressed
  body loop, avoiding literal tracker construction and the per-command
  `single_literal_tree`/`single_literal_block` branches for q0-style streams.
  This passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 same-time screening failed:
  baseline measured 41.7002/61.7896 ms on wasm-gc/native, while the trial
  measured 41.8904/63.4546 ms. Reverted; the extra helper/code layout cost is
  higher than removing the hot-loop branch in current backends.
- **Early command distance-field writes:** moved `BrotliCommand::read_into`
  assignments for `distance_code` and `distance_context` before the insert/copy
  extra-bit reads, leaving semantics unchanged but testing whether the current
  backends preferred a different mutable-record write order. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 same-time screening failed the cross-target rule: baseline measured
  44.3026/63.1218 ms on wasm-gc/native, while the trial measured
  39.9522/64.9398 ms. Reverted; even though this noisy sample helped wasm-gc,
  native regressed.
- **Reuse `output_before_copy` for max-distance input:** changed
  `state.max_distance(output.len)` to `state.max_distance(output_before_copy)`
  immediately after `let output_before_copy = output.len`, preserving
  semantics while avoiding an apparent duplicate field read. It passed
  `moon check --target native` and `moon test src/decode --target native`, but
  q0 same-time screening failed on both targets: baseline measured
  41.7680/62.0576 ms on wasm-gc/native, while the trial measured
  42.3574/64.4980 ms. Reverted; the current direct field read gives better
  generated code than reusing the local.
- **Cache decoder distance ring in a local:** added
  `let distance_ring = state.distance_ring` in
  `brotli_decode_compressed_metablock_body` and used it for short-distance
  resolution, explicit-distance reads, successful records, and dictionary-copy
  compensation. It passed `moon check --target native` and
  `moon test src/decode --target native`, but q0 same-time screening failed on
  both targets: baseline measured 41.7348/62.0278 ms on wasm-gc/native, while
  the trial measured 42.0638/64.3754 ms. Reverted; local aliasing of hot
  decoder state worsens current generated code.

## 2026-06-01 — Decode optimization brainstorm (unchecked-access strategy family)

Context: continuing decode optimization after the four accepted trials
(tree-group bounds check, validated short-distance helper, fused
explicit-distance formula, direct command-info lookup). Re-read the rejected
list: almost every rejected trial regressed native `cc-o0`. Root cause insight:
the native benchmark compiler is `cc-o0` (no optimization), so generated-code
operation count maps directly to runtime. Every added branch/local/helper costs
instructions; the compiler will not fold redundancy. The accepted trials all
*removed* operations. Therefore the highest-leverage untried mechanism is
removing operations that the existing code still pays but does not need.

New mechanism not present in any prior trial: MoonBit exposes
`FixedArray::unsafe_get` / `unsafe_set` (intrinsics `%fixedarray.unsafe_get` /
`%fixedarray.unsafe_set`) and `FixedArray::unsafe_blit`. The checked `[]`
(`FixedArray::at` / `%fixedarray.get`) emits a real bounds compare+branch at
`-O0`; the unsafe variants skip it. This is distinct from every prior rejected
"remove an `if`" trial — those removed *semantic* validation; this removes the
*implicit array bounds check* on accesses whose index is already provably
in-bounds. Expected to help both backends because both pay the check.

Candidate queue (each screened independently against the q0/q5/q9/q11 ×
wasm-gc+native guardrail; revert if it does not beat baseline on both targets):

- C1 `brotli_read_symbol` table reads (`table[0]`, root `table[index]`,
  sub-table `table[(entry>>16)+sub_index]`). Hottest decode function (every
  literal, command, distance, block-length, code-length symbol). Safety: root
  index masked `< 2^root_bits <= table.length()`; sub-table offset+index sized
  by the builder `< total_size == table.length()`; sentinel checks still
  validate contents.
- C2 literal-write `buf[pos] = literal.to_byte()` in the single-literal-tree
  and single-literal-block paths. Safety: `output.ensure(insert_length)` runs
  before the loop, so the whole run is reserved.
- C3 bit-reader refill byte loads in `refill_to` (4-byte and 3-byte fast
  paths). Safety: guarded by `byte_pos + 3 < byte_end` / `+ 2 < byte_end`.
- C4 `copy_from_distance` blits → `unsafe_blit`, and the `distance == 1` fill
  loop → `unsafe_get`/`unsafe_set`. Safety: `ensure(length)` reserves the run;
  back-distance bounds already validated. Distinct from the rejected
  manual-loop and blit-reorder trials (different mechanism: drop blit's check).
- C5 distance-ring slot access (`distances[slot]`). Safety: ring is size 4 and
  every index passes through `brotli_distance_ring_slot` (`& 3`).
- C6 `brotli_command_info_table[symbol]`, block-length base/extra tables, and
  validated context maps. Safety: indices are Huffman-alphabet-constrained or
  already validated.

Lateral / structural ideas held in reserve (larger, higher-risk; try only if
the C-family stalls):

- L1 64-bit bit accumulator (`bit_buf : UInt64`): refill 4–8 bytes per fill so
  refills happen roughly half as often. Brotli never needs > 24 bits per field,
  so a 64-bit buffer comfortably covers any single read with far fewer refills.
  Risk: 64-bit ops on `cc-o0` may offset the win.
- L3 `Bytes`-backed reader using the intrinsic `Bytes::unsafe_read_uint32_le` /
  `unsafe_read_uint64_le` (single-instruction LE word load) for refill instead
  of the byte-load+shift+OR chain. Requires a one-time `FixedArray[Byte]` ->
  `Bytes` copy of the compressed input. Pairs naturally with L1.

## 2026-06-01 — Rejected decode performance trial (unchecked-access family)

Built a reusable same-time comparison harness (`tools/brotli/bench/decode-compare.nu`,
`just decode-compare`) that interleaves trial (working tree) and baseline
(a throwaway git worktree pinned to a ref) and reports per-(quality,target)
deltas with a strict guardrail verdict. This removes the between-run machine
drift that made earlier single-shot screens unreliable (the control Google
binary alone drifted ~5% between two separated runs).

- **C1 `unsafe_get` in `brotli_read_symbol` table reads:** replaced the three
  provably in-bounds `table[..]` reads (`table[0]`, root `table[index]`,
  sub-table `table[(entry>>16)+sub_index]`) with `FixedArray::unsafe_get`.
  Passed `moon check` (both targets) and `moon test src/decode` (56/56). But
  the rounds=2 same-time screen REGRESSED 7 of 8 rows (only q9 native improved,
  -1.23%); aggregate per-op min went 345.69 -> 347.81 ms, +0.61% slower. The
  deltas were mixed/small (the signature of a non-improvement inside noise),
  not the consistent across-the-board gain the accepted trials showed.
  Reverted.
- **Insight:** array bounds checks are NOT a material cost in the decode hot
  path on the current MoonBit backends — the dominant cost is the bit-reader
  refill / Huffman traversal arithmetic, not `FixedArray::at`'s bounds compare.
  This deprioritizes the rest of the unchecked-access family (C2 literal-write
  `unsafe_set`, C3 refill-byte `unsafe_get`, C5 ring-slot, C6 table lookups):
  same mechanism, less hot, so unlikely to beat the guardrail. Do not spend
  time grinding C2/C3/C5/C6 unless a profiler shows bounds checks dominating.
  Pivot to structural changes that cut real hot-path operations: reduce refill
  *frequency* (64-bit accumulator) and refill *cost* (intrinsic word load).

## 2026-06-01 — Rejected decode performance trial (L1+L3 combined bit reader)

- **L1+L3 combined: 64-bit accumulator + zero-copy `Bytes` intrinsic word
  load.** Rewrote `BrotliBitReader` to use `bit_buf : UInt64` (was `UInt`),
  widened `brotli_low_mask_lut` to `FixedArray[UInt64]`, added a zero-copy
  `bytes : Bytes` view of the input (`unsafe_reinterpret_as_bytes`, `%identity`),
  and refilled with `Bytes::unsafe_read_uint64_le` (empty accumulator, 8 input
  bytes) / `unsafe_read_uint32_le` (partial, 4 input bytes) instead of the
  per-byte shift/OR chain. Updated the two `brotli_read_symbol` Huffman lookups
  from `.reinterpret_as_int()` to `.to_int()` for the wider mask, and added 3
  white-box tests for 64-bit refill / wide padding behavior. Passed
  `moon check` (both targets) and `moon test src/decode` (59/59).
- **Same-time `decode-compare` (rounds=4) verdict: FAIL — native uniformly
  FASTER, wasm-gc uniformly SLOWER.** Per (quality, target) delta vs HEAD:
  - native: q0 -2.71%, q5 -0.68%, q9 -1.71%, q11 -3.21% (all faster).
  - wasm-gc: q0 +1.40%, q5 +0.18%, q9 +1.40%, q11 +0.23% (all slower).
  - aggregate -0.98%, but the strict guardrail rejects any regressed row, and
    all four wasm-gc rows regressed.
- **Methodology note: rounds=2 was misleading on this borderline change.** The
  first rounds=2 screen showed q9/q11 wasm-gc as faster and only flagged
  q0/q5 wasm; rounds=4 revealed the true uniform wasm-gc regression. For
  small/borderline decode deltas, use rounds>=4 before drawing a verdict.
- **Root cause:** on wasm-gc the `UInt64` accumulator arithmetic (shift/mask/or
  per `peek_bits`/`drop_bits`/`refill`) costs more than the `UInt32` path, and
  the literal-heavy low-quality streams (q0/q5) do not refill often enough for
  the halved refill frequency to pay it back. native benefits because its
  64-bit ops are cheap and the intrinsic word load removes real instructions.
  This is a classic helps-one-target / hurts-the-other change, exactly what the
  guardrail rejects. Do not re-add a 64-bit accumulator to the bit reader on the
  current backends.
- **Decomposition follow-up:** the native win comes from fewer/cheaper refill
  operations, and L3 (intrinsic word load) is the operation-reducing half that
  does NOT require widening the accumulator. The next candidate is **L3-alone**:
  keep `bit_buf : UInt` (32-bit) and only replace the empty-accumulator 4-byte
  byte/shift/OR chain with `Bytes::unsafe_read_uint32_le`. Hypothesis: keeps
  part of the native win without the wasm-gc 64-bit penalty.

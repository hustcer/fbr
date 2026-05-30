# Brotli Benchmarks

This file records phase validation measurements for the MoonBit Brotli encoder.
Run commands from the repository root.

## 2026-05-24 — P3/P4 Baseline q=2..11

Corpus: `target/brotli-silesia/silesia-100m.bin`

Input SHA-256:
`89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579`

Validation commands:

```nu
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 9
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 10
nu tools/brotli/encode/verify.nu target/brotli-silesia/silesia-100m.bin --quality 11
```

Results:

| Quality | Encoded bytes | Encoded SHA-256                                                   | External decode SHA-256                                           |
| ------- | ------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| 2       | 104857629     | `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |
| 9       | 104857629     | `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |
| 10      | 104857629     | `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |
| 11      | 104857629     | `63ee36d1ba0c643aad2a6c2e395bdea906413166fccc439c7a24097a566c0e25` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |

The q=2..11 backend currently reuses the uncompressed-meta-block encoder. These
streams are RFC-valid and externally decodable, but they do not yet meet the
planned ratio target against the C reference. Back-reference search, block
splitting, and entropy coding remain the next ratio-focused work.

## 2026-05-24 — First Compressed q2 Path

Corpus: `target/brotli-encode/repeated-a-1k.bin`

Input: 1024 bytes of `A`

Validation command:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/repeated-a-1k.bin --quality 2
```

Result:

| Quality | Encoded bytes | Encoded SHA-256                                                   | External decode SHA-256                                           |
| ------- | ------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| 2       | 11            | `11374c099faa11902a4c6dc08f14a34f0e7b46892d705492c9cd83dff75b9473` | `6ab72eeb9e77b07540897e0c8d6d23ec8eef0f8c3a47e1b3f4e93443d9536bed` |

This increment adds a real compressed meta-block path for single-byte runs:
one inserted literal followed by a distance-1 copy. It is a command/Huffman
foundation for P3, not the full Silesia-ratio encoder.

## 2026-05-24 — Short Periodic q2 Path

Corpus: `target/brotli-encode/periodic-abcd-1k.bin`

Input: 1024 bytes of repeated `ABCD`

Validation command:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcd-1k.bin --quality 2
```

Result:

| Quality | Encoded bytes | Encoded SHA-256                                                   | External decode SHA-256                                           |
| ------- | ------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| 2       | 15            | `b93fc934c730cff0147930ef7572a745f2c8fd28153e836d3f103d6026ab2aeb` | `c2bc376eb7cee7a17331cb38d1637fe08c710b3d8167764f7ec92fd865814d8e` |

This extends the compressed path to period lengths 1 through 4 when the period
symbols are unique. It proves literal payload emission for simple Huffman trees,
explicit distances 1 through 4, and larger insert/copy command prefixes.

## 2026-05-24 — Single-Copy q2 Prefix Path

Corpus: `target/brotli-encode/prefix-x-abc-1k.bin`

Input: 1024 bytes: `X` followed by repeated `ABC`

Validation command:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/prefix-x-abc-1k.bin --quality 2
```

Result:

| Quality | Encoded bytes | Encoded SHA-256                                                   | External decode SHA-256                                           |
| ------- | ------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| 2       | 15            | `c4b785c5553afc3e367bb3db0cb9a487292d4cc127eb107ff502043aab815993` | `b0ac63f256924c623429f859f6106c51afb4b2e2da1623ba19ec644765f48914` |

This moves beyond whole-input periods: the encoder can now insert a short
literal prefix, then copy the remaining suffix from an earlier distance. The
literal prefix is still limited to four distinct byte values so it can use
Brotli simple Huffman trees.

## 2026-05-24 — Multi-Command q2 Small-Alphabet Path

Corpus: `target/brotli-encode/small-alpha-multicopy-1207.bin`

Input: `ABCABCX` followed by 200 repetitions of `ABCABC`

Validation command:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multicopy-1207.bin --quality 2
```

Result:

| Quality | Encoded bytes | Encoded SHA-256                                                   | External decode SHA-256                                           |
| ------- | ------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| 2       | 17            | `e3004449f7c34d354c3e42c25c80af9eb20fa9a316a7e2266ee9de23161e178e` | `5cda1187aab97e0d2172c16e206ea42c02a568ccb804f9d0e316520da2f677a7` |

This adds a greedy multi-command path for inputs with up to four distinct
literal bytes. It still uses Brotli simple Huffman trees, so command and
distance alphabets are capped at four symbols each.

## 2026-05-24 — Complex Huffman q2 Path

Corpora:

- `target/brotli-encode/periodic-abcde-1025.bin`
- `target/brotli-encode/small-alpha-multi-1400.bin`

Validation commands:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-1025.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multi-1400.bin --quality 2
```

Results:

| Corpus                  | Quality | Encoded bytes | Encoded SHA-256                                                   | External decode SHA-256                                           |
| ----------------------- | ------- | ------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| periodic-abcde-1025     | 2       | 22            | `7cc14af91a972848744c19fec74d38a850ef059aaffaa490e566a0886fceefb0` | `f4dc1e54e392d07b8c8d9756d1960471cc7b55a2ac7d6ccf2765952d5d1acfb1` |
| small-alpha-multi-1400  | 2       | 306           | `385baf3fcd2396020985a9736ad9517ad1b4eaf45644043495fa9d04912a89cc` | `0a8c1bc877ff95d68eaea55b7112864aab6b4f048bafc7502419b2d9f7e14406` |

This removes the previous four-symbol cap by emitting Brotli complex Huffman
tree descriptions for literal, command, and distance alphabets when needed.
The implementation currently uses fixed-length canonical codes padded to a
power of two, which is simple and deterministic but not yet entropy-optimal.

## 2026-05-24 — Ratio Harness Baseline

Tool:

```nu
nu tools/brotli/bench/ratio.nu <input> --qualities <list>
```

Results:

| Corpus                  | Quality | MoonBit bytes | Google bytes | MoonBit ratio | Google ratio |
| ----------------------- | ------- | ------------- | ------------ | ------------- | ------------ |
| small-alpha-multi-1400  | 2       | 306           | 169          | 4.58          | 8.28         |
| silesia-100m            | 2       | 104857629     | 35495150     | 1.00          | 2.95         |

The small synthetic corpus shows the q2 compressed path working but still
larger than Google. The Silesia baseline shows the current encoder mostly
falls back to uncompressed meta-blocks on realistic mixed data. Closing this
requires block splitting plus a broader match finder over large meta-blocks.

## 2026-05-24 — Chunked q2 Hash-Match Path

Corpora:

- `target/brotli-encode/periodic-abcde-200k.bin`
- `target/brotli-bench/silesia-1m.bin`
- `target/brotli-silesia/silesia-100m.bin`

Validation commands:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-128k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2
```

Results:

| Corpus                 | Quality | MoonBit bytes | Google bytes | MoonBit SHA-256                                                   | External decode SHA-256                                           |
| ---------------------- | ------- | ------------- | ------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| periodic-abcde-200k    | 2       | 2,820         | n/a          | `39f3ef856d8b1099306bd1c3272c176cd237c4f5ae8395c5562b2483c6d17327` | `24a7979ddb84c3eefb28a14793d9a66bfbc1e8c8ce61b326c699458dc9e951c5` |
| silesia-1m             | 2       | 1,048,628     | 320,418      | n/a                                                               | verified by ratio harness                                         |
| silesia-100m           | 2       | 104,862,404   | 35,495,150   | `75561d5802aec1cfcfb8eec0a66c1a9883f93806e58b8209b1bf52855aab1458` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |

This increment adds large-input q2 chunking and replaces the local distance
scan with a bounded hash-chain matcher. Stored chunks are written directly into
the active stream because uncompressed meta-block padding depends on the current
bit offset; compressed candidate chunks are only spliced when they beat a stored
chunk estimate. The q2 compressed path is deliberately gated to very
low-alphabet chunks until frequency-weighted Huffman coding and general block
splitting land. The 100 MiB Silesia result is therefore still a stored-block
baseline, about 195% larger than Google q2.

## 2026-05-24 — Weighted q2 Huffman Lengths

Corpora:

- `target/brotli-encode/small-alpha-multi-1400.bin`
- `target/brotli-encode/periodic-abcde-200k.bin`
- `target/brotli-silesia/silesia-100m.bin`

Validation commands:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/small-alpha-multi-1400.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2
```

Results:

| Corpus                  | Quality | MoonBit bytes | Google bytes | MoonBit SHA-256                                                   | External decode SHA-256                                           |
| ----------------------- | ------- | ------------- | ------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| small-alpha-multi-1400  | 2       | 231           | 169          | `9f089e3ac9defbfbd82c19370b93e716d3f35ae2b500d4dd4e2655531423ad8b` | `0a8c1bc877ff95d68eaea55b7112864aab6b4f048bafc7502419b2d9f7e14406` |
| periodic-abcde-200k     | 2       | 2,820         | n/a          | `39f3ef856d8b1099306bd1c3272c176cd237c4f5ae8395c5562b2483c6d17327` | `24a7979ddb84c3eefb28a14793d9a66bfbc1e8c8ce61b326c699458dc9e951c5` |
| silesia-100m            | 2       | 104,862,404   | 35,495,150   | `75561d5802aec1cfcfb8eec0a66c1a9883f93806e58b8209b1bf52855aab1458` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |

The complex Huffman writer can now describe arbitrary code lengths using a
generated code-length-code tree, and q2 low-alphabet chunks use frequency
weighted literal, command, and distance lengths when they are smaller than the
fixed-length alternative. This improves the irregular small-alphabet fixture
from 306 to 231 bytes while preserving the 2,820-byte fixed-tree result for the
highly regular 200 KiB fixture. Silesia remains unchanged because the
conservative natural-data gate still falls back to stored chunks.

## 2026-05-24 — Sampled q2 Match-Density Gate

Corpora:

- `target/brotli-encode/periodic-allbytes-200k.bin`
- `target/brotli-bench/silesia-1m.bin`
- `target/brotli-silesia/silesia-100m.bin`

Validation commands:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2
```

Results:

| Corpus                 | Quality | MoonBit bytes | Google bytes | MoonBit SHA-256                                                   | External decode SHA-256                                           |
| ---------------------- | ------- | ------------- | ------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| periodic-allbytes-200k | 2       | 5,878         | n/a          | `e4f96c81a833bc5e8052c8af716c3095120504681924ea9470821d622121b5a7` | `c7a7d73b68d21102bf7d6d9be27b4106497efc8119224bebfbd26b375541bde7` |
| silesia-1m             | 2       | 1,048,628     | 320,418      | n/a                                                               | verified by ratio harness                                         |
| silesia-100m           | 2       | 104,862,404   | 35,495,150   | `75561d5802aec1cfcfb8eec0a66c1a9883f93806e58b8209b1bf52855aab1458` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |

The q2 compressed-chunk gate now admits high-alphabet chunks when sampled
positions show very dense repeated 4-byte sequences, with a command-count cap
to keep JavaScript verification bounded. This removes the strict 16-literal
ceiling for highly repetitive data, proven by the all-256-byte periodic corpus.
It still rejects ordinary Silesia chunks and therefore does not change the
full-corpus ratio; general natural-data block splitting remains the next P3
requirement.

## 2026-05-24 — Longer q2 Hash Matches

Corpora:

- `target/brotli-encode/periodic-abcde-200k.bin`
- `target/brotli-encode/periodic-allbytes-200k.bin`
- `target/brotli-encode/small-alpha-multi-1400.bin`
- `target/brotli-silesia/silesia-100m.bin`

Validation commands:

```nu
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2
```

Results:

| Corpus                  | Quality | MoonBit bytes | Google bytes | MoonBit SHA-256                                                   | External decode SHA-256                                           |
| ----------------------- | ------- | ------------- | ------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| periodic-abcde-200k     | 2       | 249           | n/a          | `59992ec9753734496469262136d5063839da2dacc00434c4f43a185a897d5c8c` | `24a7979ddb84c3eefb28a14793d9a66bfbc1e8c8ce61b326c699458dc9e951c5` |
| periodic-allbytes-200k  | 2       | 1,399         | n/a          | `75a268e3beae7baff6fb8ca4eedf07306b7a8155f8854ccadf5275fb4fb19c3e` | `c7a7d73b68d21102bf7d6d9be27b4106497efc8119224bebfbd26b375541bde7` |
| small-alpha-multi-1400  | 2       | 231           | 169          | unchanged                                                         | verified by ratio harness                                         |
| silesia-100m            | 2       | 104,862,404   | 35,495,150   | `75561d5802aec1cfcfb8eec0a66c1a9883f93806e58b8209b1bf52855aab1458` | `89ed4fcaea193564aa75b37f596ccee2687985b4584ea29b8b8e72f36ef27579` |

The bounded hash matcher now extends copies up to 4,096 bytes instead of 64
bytes. This sharply reduces command count on repetitive chunks while preserving
the exact stored fallback on Silesia. Natural-data ratio still requires block
splitting and less conservative candidate admission.

## 2026-05-24 — Timed q2 Ratio Harness

The ratio harness now supports exact JSON output with MoonBit and Google encode
durations:

```nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-silesia/silesia-100m.bin --qualities 2 --json
```

Results:

| Corpus       | Quality | MoonBit bytes | Google bytes | MoonBit time ms | Google time ms | Size overhead |
| ------------ | ------- | ------------- | ------------ | --------------- | -------------- | ------------- |
| silesia-1m   | 2       | 1,048,628     | 320,418      | 836.648         | 44.078         | 227.27%       |
| silesia-100m | 2       | 104,862,404   | 35,495,150   | 76,009.389      | 817.288        | 195.43%       |

The MoonBit timing currently includes JavaScript bundle rebuild/launch plus
external decode verification, so it is a conservative end-to-end harness time
rather than pure encoder CPU time. It is still useful for regression tracking
while the encoder remains under active P3 development.

## 2026-05-24 — q2 Chunk Match Diagnostics

Added `tools/brotli/bench/chunk-match.nu` to summarize per-chunk match density
and bounded greedy-copy estimates before changing q2 natural-data heuristics.
The script uses the same 65,535-byte chunk size and 1,200-command cap as the
current q2 compressed-chunk path.

Validation commands:

```nu
nu --ide-check 100 tools/brotli/bench/chunk-match.nu
nu tools/brotli/bench/chunk-match.nu target/brotli-bench/silesia-1m.bin --max-chunks 16 --min-lengths 4,8,16,24,32 --json
nu tools/brotli/bench/chunk-match.nu target/brotli-encode/periodic-allbytes-200k.bin --max-chunks 1 --min-lengths 4,16,32 --json
```

First 16 Silesia chunks:

| Min match length | Avg commands | Avg copy ratio | Capped chunks |
| ---------------- | ------------ | -------------- | ------------- |
| 4                | 1,201.000    | 15.09%         | 16            |
| 8                | 1,201.000    | 27.53%         | 16            |
| 16               | 909.125      | 35.02%         | 0             |
| 24               | 486.375      | 24.07%         | 0             |
| 32               | 233.000      | 14.08%         | 0             |

One 65,535-byte all-256-byte periodic chunk:

| Min match length | Commands | Unique literals | Sampled 4-byte density | Copy ratio |
| ---------------- | -------- | --------------- | ---------------------- | ---------- |
| 4                | 16       | 256             | 99.61%                 | 99.61%     |
| 16               | 16       | 256             | 99.61%                 | 99.61%     |
| 32               | 16       | 256             | 99.61%                 | 99.61%     |

The diagnostic confirms the existing sampled-density gate is appropriate for
pathological periodic data but is not a substitute for natural-data block
splitting. On Silesia, short matches either exceed the current command cap or
do not produce enough copied bytes once the minimum match length is raised.

## 2026-05-24 — q9 Sparse-Match Trial Rejected

An experimental q9 configuration tried to admit ordinary natural-data chunks
with longer matches only: minimum match length 16, one candidate check, scan
step 8, 1,200-command cap, and a 35% copied-byte precheck. The implementation
was not kept enabled because it did not improve the benchmark slice and made
encoding much slower.

Validation commands:

```nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
```

Rejected-trial results:

| Corpus                 | Quality | MoonBit bytes | Google bytes | MoonBit time ms | Outcome                                      |
| ---------------------- | ------- | ------------- | ------------ | --------------- | -------------------------------------------- |
| silesia-1m             | 9       | 1,048,628     | 263,791      | 12,158.154      | No ratio gain versus stored fallback         |
| small-alpha-multi-1400 | 9       | 1,404         | 69           | 333.415         | Regressed from the existing 231-byte q2 path |

The retained code from this trial is limited to safe plumbing: hash config
fields for minimum match length, scan step, command cap, copy-ratio admission,
and whether dense-match sampling is required. The encoder still uses the
previous dense-match configuration for all qualities until a stronger
block/cost model can prove that a sparse natural-data chunk should be written.

## 2026-05-24 — Complex Huffman Repeat-Zero RLE

Complex Huffman tree encoding now uses Brotli code-length symbol 17 to encode
runs of zero code lengths. Long zero runs are split with a literal zero between
repeat-zero symbols because Brotli repeat codes accumulate repeat state when
the same repeat symbol appears consecutively.

Validation commands:

```nu
moon test --target native --filter '*complex command Huffman*'
moon test --target native --filter '*high alphabet repetitive*'
moon test --target native --filter '*chunked large input*'
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
```

Results:

| Corpus                  | Quality | Previous MoonBit bytes | New MoonBit bytes | Google bytes | Notes                    |
| ----------------------- | ------- | ---------------------- | ----------------- | ------------ | ------------------------ |
| small-alpha-multi-1400  | 2       | 231                    | 195               | 169          | External decode verified |
| small-alpha-multi-1400  | 9       | 231                    | 195               | 69           | Uses same current backend |
| periodic-abcde-200k     | 2       | 249                    | 240               | n/a          | External decode verified |
| periodic-allbytes-200k  | 2       | 1,399                  | 1,399             | n/a          | Unchanged                |
| silesia-1m              | 2       | 1,048,628              | 1,048,628         | 320,418      | Still stored fallback    |
| silesia-1m              | 9       | 1,048,628              | 1,048,628         | 263,791      | Still stored fallback    |

This narrows the synthetic q2 gap for sparse alphabets without relaxing the
natural-data gate. Silesia remains unchanged because ordinary chunks still
fall back to uncompressed meta-blocks.

## 2026-05-24 — Complex Huffman Repeat-Previous RLE

Complex Huffman tree encoding now also uses Brotli code-length symbol 16 to
repeat the previous nonzero code length. As with repeat-zero, consecutive
repeat-previous symbols accumulate repeat state, so long nonzero runs are split
with a literal code length between repeat codes.

Validation commands:

```nu
moon test --target native --filter '*complex command Huffman*'
moon test --target native --filter '*high alphabet repetitive*'
moon test --target native --filter '*chunked large input*'
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
```

Results:

| Corpus                  | Quality | Previous MoonBit bytes | New MoonBit bytes | Google bytes | Notes                    |
| ----------------------- | ------- | ---------------------- | ----------------- | ------------ | ------------------------ |
| small-alpha-multi-1400  | 2       | 195                    | 195               | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195                    | 195               | 69           | Unchanged                |
| periodic-abcde-200k     | 2       | 240                    | 240               | n/a          | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,399                  | 1,382             | n/a          | External decode verified |
| silesia-1m              | 2       | 1,048,628              | 1,048,628         | 320,418      | Still stored fallback    |
| silesia-1m              | 9       | 1,048,628              | 1,048,628         | 263,791      | Still stored fallback    |

The gain appears on high-alphabet periodic chunks where generated complex
trees contain repeated nonzero code lengths. Natural-data ratio remains gated
on block splitting and candidate admission.

## 2026-05-24 — Literal-Only Compressed Candidates

The q2+ chunk selector now tries a literal-only compressed meta-block for
chunks with at most 64 distinct literal bytes. This uses one insert-only
command that fills the meta-block; the decoder returns after the insert and
therefore does not consume the command's nominal copy distance. A cheap
`brotli_count_unique_literals_up_to(..., 64)` gate avoids building this
candidate for ordinary high-alphabet chunks.

The chunk stored-size comparison was also tightened to compare the candidate's
rounded-up byte size, avoiding one-byte stored regressions.

Validation commands:

```nu
moon test --target native --filter '*literal chunks*'
moon test --target native --filter '*complex command Huffman*'
moon test --target native --filter '*high alphabet repetitive*'
moon test --target native --filter '*chunked large input*'
nu tools/brotli/bench/ratio.nu target/brotli-encode/alpha64-xorshift-16000.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-abcde-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous MoonBit bytes | New MoonBit bytes | Google bytes | Notes                    |
| ----------------------- | ------- | ---------------------- | ----------------- | ------------ | ------------------------ |
| alpha64-xorshift-16000  | 2       | 16,004                 | 12,022            | 12,029       | External decode verified |
| small-alpha-multi-1400  | 2       | 195                    | 195               | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195                    | 195               | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382                  | 1,382             | n/a          | Unchanged                |
| periodic-abcde-200k     | 2       | 240                    | 240               | n/a          | Unchanged                |
| silesia-1m              | 2       | 1,048,628              | 1,048,628         | 320,418      | Still stored fallback    |
| silesia-1m              | 9       | 1,048,628              | 1,048,628         | 263,791      | Still stored fallback    |

This adds a real compressed path for low-alphabet data even when no accepted
back-reference candidate exists. It does not remove the main Silesia blocker:
ordinary natural chunks still need block splitting and a stronger candidate
admission model.

## 2026-05-24 — High-Alphabet Literal Entropy Candidates

Literal-only compressed chunks now use length-limited weighted Huffman trees
for literal alphabets larger than 16 symbols. A cheap entropy precheck admits
high-alphabet chunks only when the literal code lengths have enough margin to
beat stored output, and the final rounded-byte comparison still rejects any
candidate that does not actually win.

This also fixed a shared Huffman helper bug: its sentinel frequency was too
small for 65 KiB Brotli chunks, which could panic when one symbol appeared
more than 25,001 times.

Validation commands:

```nu
moon test --target native --filter '*literal chunks*'
moon test --target native --filter '*huffman*'
moon test --target native --filter '*q0 through q11*'
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-128k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous MoonBit bytes | New MoonBit bytes | Google bytes | Notes                    |
| ----------------------- | ------- | ---------------------- | ----------------- | ------------ | ------------------------ |
| silesia-128k            | 2       | stored fallback        | 82,602            | n/a          | External decode verified |
| silesia-1m              | 2       | 1,048,628              | 657,233           | 320,418      | External decode verified |
| small-alpha-multi-1400  | 2       | 195                    | 195               | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195                    | 195               | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382                  | 1,382             | n/a          | Unchanged                |

This is the first natural-data ratio gain on Silesia: q2 improves from the
stored fallback to a 1.60x ratio on the 1 MiB slice. It remains 105.12% larger
than Google q2 on that slice, so P3 still needs block splitting and
back-reference admission beyond entropy-only chunks.

## 2026-05-24 — Identity Static-Dictionary Candidate

The q2+ candidate selector can now build insert/copy command streams that
reference identity-transform words from the RFC static dictionary. This first
encoder dictionary path is deliberately narrow: it is enabled for small
single-block inputs only, after a chunked Silesia trial showed that broad
per-chunk dictionary probing added runtime and selected streams 10 bytes larger
on the 1 MiB slice.

Validation commands:

```nu
moon test --target native --filter '*static dictionary words*'
moon test --target native --filter '*literal chunks*'
moon test --target native --filter '*chunked large input*'
nu tools/brotli/encode/verify.nu target/brotli-encode/dictionary-words.txt --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-words.txt --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | MoonBit bytes | Google bytes | Notes                    |
| ----------------------- | ------- | ------------- | ------------ | ------------------------ |
| dictionary-words        | 2       | 76            | 78           | External decode verified |
| silesia-1m              | 2       | 657,233       | 320,418      | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382         | n/a          | Unchanged                |

This adds the first static-dictionary encoder surface but does not count as
P3 completion. The production-sized ratio target still needs broader
dictionary heuristics, block splitting, and back-reference cost modeling.

## 2026-05-24 — Two-Literal-Block Split Candidate

The literal-only q2+ candidate selector can now try one midpoint literal block
split inside a compressed meta-block. This writes two literal block types, a
block-length tree, a compact trivial context map, and separate weighted literal
trees for each half. The candidate is exact-costed against the existing
single-tree literal-only, LZ77, dictionary, and stored fallbacks.

Validation commands:

```nu
moon test --target native --filter '*splits literal*'
moon test --target native --filter '*literal chunks*'
moon test --target native --filter '*static dictionary words*'
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous MoonBit bytes | New MoonBit bytes | Google bytes | Notes                    |
| ----------------------- | ------- | ---------------------- | ----------------- | ------------ | ------------------------ |
| split-literals-8k       | 2       | single-tree candidate  | 4,464             | 3,455        | External decode verified |
| silesia-1m              | 2       | 657,233                | 656,982           | 320,418      | External decode verified |
| small-alpha-multi-1400  | 2       | 195                    | 195               | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195                    | 195               | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382                  | 1,382             | n/a          | Unchanged                |

A broader trial with three split points improved Silesia further to 656,639
bytes but took 37,346 ms on the 1 MiB ratio harness. The retained midpoint-only
candidate keeps the structural block-split support while reducing that run to
20,575 ms. P3 still needs a cheaper splitter and stronger back-reference cost
model before full Silesia validation can approach the reference ratio.

## 2026-05-24 — Split-Candidate Admission Heuristic

The midpoint split candidate now runs behind a cheap Huffman-length estimator.
Before writing the full two-block meta-block, the encoder compares the expected
literal bit cost of one tree against two midpoint trees and requires at least a
384-bit margin. This preserves the split wins while avoiding expensive
candidate writes for chunks whose literal distribution is not meaningfully
different across the midpoint.

Validation commands:

```nu
moon test --target native --filter '*splits literal*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Bytes after split | Bytes after heuristic | Notes                    |
| ----------------------- | ------- | ----------------- | --------------------- | ------------------------ |
| silesia-1m              | 2       | 656,982           | 656,982               | Harness time 20,575 ms -> 14,736 ms |
| split-literals-8k       | 2       | 4,464             | 4,464                 | External decode verified |
| small-alpha-multi-1400  | 2       | 195               | 195                   | Unchanged                |
| small-alpha-multi-1400  | 9       | 195               | 195                   | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382             | 1,382                 | Unchanged                |

This is a performance guardrail for the block-splitting path. It does not
change the P3 ratio target; it keeps the current ratio gain while reducing
candidate overhead.

## 2026-05-24 — Three-Point Literal Split Selector

The literal split estimator now scores quarter, midpoint, and three-quarter
split points from a shared single-tree literal cost, then writes only the best
admitted two-block meta-block candidate. This recovers most of the earlier
three-split ratio gain without running the expensive split writer three times
per chunk.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*splits literal*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 656,982        | 656,614   | 320,418      | Harness time 16,404 ms   |
| split-literals-8k       | 2       | 4,464          | 4,464     | 3,455        | External decode verified |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382          | 1,382     | n/a          | External decode verified |

P3 is still open: the Silesia 1 MiB q2 slice remains 104.92% larger than
Google q2, so the next ratio work needs broader back-reference admission and a
real token/block splitter rather than more literal-only split tuning.

## 2026-05-24 — Large-Input Long-Match Candidate

The q2+ encoder now keeps the dense-match LZ77 baseline unchanged and tries a
second natural-data candidate only for inputs/chunks of at least 8 KiB. The
new candidate disables the dense 4-byte match gate, requires 32-byte copies,
and rejects command streams with less than 12% copied bytes. It is exact-costed
against the existing literal, split-literal, dictionary, and stored fallbacks,
so small inputs keep the previous better candidate.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*high alphabet repetitive*'
moon test --target native --filter '*chunked large input*'
moon test --target native --filter '*literal chunks*'
moon test --target native --filter '*splits literal*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 656,614        | 579,879   | 320,418      | Harness time 32,999 ms   |
| split-literals-8k       | 2       | 4,464          | 3,434     | 3,455        | External decode verified |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 1,382          | 1,382     | n/a          | External decode verified |

This is the first broad natural-data back-reference win, reducing the Silesia
1 MiB q2 overhead from 104.92% to 80.98% versus Google q2. Runtime is still
far above the P3 target, so the next work needs a cheaper token cost model and
real block splitting rather than more brute-force candidate writing.

## 2026-05-24 — Long-Match Threshold Tuning

The large-input natural candidate's minimum copy length was tuned after
benchmarking shorter thresholds under the same 8 KiB input gate and 12%
copied-byte floor.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*splits literal*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Natural min copy | Silesia-1m q2 bytes | Notes                                  |
| ---------------- | ------------------- | -------------------------------------- |
| 32               | 579,879             | Initial safe threshold                 |
| 24               | 524,560             | Better ratio, fixtures unchanged       |
| 16               | 471,230             | Best tested threshold, selected        |
| 12               | 646,930             | Rejected; command overhead dominates   |

At the selected 16-byte threshold, `split-literals-8k.bin` stays 3,434 bytes,
`small-alpha-multi-1400.bin` stays 195 bytes for q2/q9, and
`periodic-allbytes-200k.bin` stays 1,382 bytes with external decode verified.
The Silesia 1 MiB q2 overhead is now 47.07% versus Google q2.

## 2026-05-24 — Larger Standard Chunks

The q2+ chunked standard encoder now uses 262,143-byte chunks instead of
65,535-byte chunks. The simple LZ77 builder accepts chunks up to 256 KiB, and
the natural long-match command cap rises proportionally from 1,200 to 4,800
commands. The dense baseline remains capped at 1,200 commands.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*chunked large input*'
moon test --target native --filter '*high alphabet repetitive*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 471,230        | 462,172   | 320,418      | Harness time 22,755 ms   |
| periodic-allbytes-200k  | 2       | 1,382          | 494       | n/a          | External decode verified |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |

The Silesia 1 MiB q2 overhead is now 44.24% versus Google q2. This improves
ratio and reduces the ratio-harness time versus four 65 KiB long-match chunks,
but the remaining gap still needs better token/block cost modeling.

## 2026-05-24 — One-MiB Standard Chunks

The q2+ chunked standard encoder now uses 1,048,575-byte chunks. The simple
LZ77 builder accepts chunks up to 1 MiB, and the natural long-match command cap
rises proportionally from 4,800 to 19,200 commands.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*chunked large input*'
moon test --target native --filter '*high alphabet repetitive*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 462,172        | 460,961   | 320,418      | Harness time 23,655 ms   |
| periodic-allbytes-200k  | 2       | 494            | 494       | n/a          | External decode verified |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |

The Silesia 1 MiB q2 overhead is now 43.86% versus Google q2. The small ratio
gain is valid, but future work should focus on token/block cost modeling before
raising chunk size further.

## 2026-05-24 — Weighted Command and Distance Trees

Weighted Huffman construction now applies to command and distance alphabets as
well as literals. Previously, non-literal alphabets with more than 16 symbols
fell back to uniform code lengths, which overpaid on natural LZ77 command
streams.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*splits literal*'
moon test --target native --filter '*chunked large input*'
moon test --target native --filter '*literal chunks*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 460,961        | 457,776   | 320,418      | Harness time 23,837 ms   |
| periodic-allbytes-200k  | 2       | 494            | 494       | n/a          | External decode verified |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |

The Silesia 1 MiB q2 overhead is now 42.87% versus Google q2.

## 2026-05-24 — Natural Lazy Matching

The natural long-match path now performs a one-byte lazy-match check: when the
next position has a match more than four bytes longer than the current match,
the encoder delays the copy by one literal. This is gated to long-match
candidates (`min_match_length >= 16`) so dense small-input behavior is
unchanged.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*splits literal*'
moon test --target native --filter '*chunked large input*'
moon test --target native --filter '*literal chunks*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 457,776        | 455,386   | 320,418      | Harness time 23,909 ms   |
| periodic-allbytes-200k  | 2       | 494            | 494       | n/a          | External decode verified |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |

The Silesia 1 MiB q2 overhead is now 42.12% versus Google q2.

## 2026-05-24 — Longer Natural Copies

The natural long-match candidate now allows copies up to 16 KiB instead of
4 KiB. This does not move Silesia, but it reduces command overhead on long
periodic data.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*chunked large input*'
moon test --target native --filter '*high alphabet repetitive*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 455,386        | 455,386   | 320,418      | Unchanged                |
| periodic-allbytes-200k  | 2       | 494            | 350       | n/a          | External decode verified |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |

## 2026-05-24 — High-Quality Long-Match Candidate

Quality 9 now tries an additional exact-costed long-match candidate with a
12-byte minimum copy length and a 25,600 command cap. The existing q2 natural
candidate still runs first, so q9 uses this path only when it produces a smaller
meta-block. A 10-byte trial was rejected because it did not beat the q2-sized
stream on Silesia.

Validation commands:

```nu
moon check --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 455,386        | 455,386   | 320,418      | Unchanged                |
| silesia-1m              | 9       | 455,386        | 422,673   | 263,791      | First distinct q9 stream |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB q9 overhead is now 60.23% versus Google q9. q9 is now
quality-distinct, but P3 still needs real token/block splitting and a better
cost model to reach the documented 5% target.

## 2026-05-24 — Q9 Candidate Runtime

Quality 9 now skips the q2 natural long-match candidate and runs only the q9
high-quality long-match candidate after the shared dense, literal,
split-literal, and dictionary candidates. The q9-specific candidate produced
the same bytes on the measured fixtures, so the q2 natural pass was duplicate
work for q9.

Validation commands:

```nu
moon check --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Previous time | New time  | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------- | --------- | ------------------------ |
| silesia-1m              | 2       | 455,386        | 455,386   | n/a           | 23,739 ms | Unchanged                |
| silesia-1m              | 9       | 422,673        | 422,673   | 45,860 ms     | 23,732 ms | Same bytes, faster       |
| split-literals-8k       | 9       | 3,434          | 3,434     | n/a           | 4,619 ms  | Unchanged                |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a           | n/a       | External decode verified |

## 2026-05-24 — LZ77 Literal Block Split Candidate

LZ77 command streams now try an exact-costed two-literal-tree candidate when
the inserted literal stream has a profitable split. The split point is measured
in inserted literals, not output bytes, so copies do not consume the literal
block length. This is separate from the literal-only splitter and competes
against the existing weighted and fixed LZ77 writers.

Validation commands:

```nu
moon check --target native
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 455,386        | 455,319   | 320,418      | Small split-LZ77 win     |
| silesia-1m              | 9       | 422,673        | 422,567   | 263,791      | Small split-LZ77 win     |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 42.10% at q2 and 60.19% at q9. The ratio
target is still open; this change only adds a valid block-splitting candidate
inside the existing single-meta-block LZ77 model.

## 2026-05-24 — Implicit Last-Distance Commands

The LZ77 encoder now prefers Brotli command symbols with implicit distance 0
when a copy exactly repeats the last distance. The meta-block writers skip the
distance alphabet symbol for those commands, matching the decoder contract.
This keeps explicit distance symbols for non-repeated distances and for
dictionary commands.

Validation commands:

```nu
moon check --target native
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 455,319        | 455,267   | 320,418      | Small distance-code win  |
| silesia-1m              | 9       | 422,567        | 422,497   | 263,791      | Small distance-code win  |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 42.09% at q2 and 60.16% at q9.

## 2026-05-24 — UTF-8 Literal Context Candidate

LZ77 command streams now try a second context-mode candidate that uses Brotli's
UTF-8 literal context mode and two literal trees: one for contexts following
lowercase letters and one for all other contexts. The candidate is exact-costed
against the existing weighted, fixed, and split-literal LZ77 writers before it
is selected.

Validation commands:

```nu
moon check --target native
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 455,267        | 438,806   | 320,418      | UTF-8 context win        |
| silesia-1m              | 9       | 422,497        | 408,875   | 263,791      | UTF-8 context win        |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 36.95% at q2 and 55.00% at q9. This is a
large P3 ratio improvement but remains outside the 5% target.

## 2026-05-24 — Four-Tree UTF-8 Literal Context Candidate

The complex Huffman writer now supports non-power-of-two code-length
alphabets by building a bounded Huffman tree for the code-length-code alphabet
instead of rejecting 17- and 18-symbol descriptors. This enables a richer
exact-costed UTF-8 literal-context candidate with four literal trees:
control/space/digit contexts, punctuation/other contexts, uppercase contexts,
and lowercase contexts.

Validation commands:

```nu
moon check --target native
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 438,806        | 424,532   | 320,418      | Four-tree context win    |
| silesia-1m              | 9       | 408,875        | 396,969   | 263,791      | Four-tree context win    |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 32.49% at q2 and 50.49% at q9. P3 still
needs better match parsing, block splitting, and histogram clustering to reach
the documented 5% target.

## 2026-05-24 — Four-Byte Natural Hash Candidate

Natural and high-quality LZ77 matching now keep the existing three-byte hash
chain and also try a four-byte hash-chain candidate. The candidate is
exact-costed against the current LZ77 writers, so small fixtures that are
better with the older chain keep their previous output. This matches the P3
plan's 4-byte hash requirement while preserving regression fixtures.

Validation commands:

```nu
moon check --target native
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 424,532        | 419,583   | 320,418      | Four-byte hash win       |
| silesia-1m              | 9       | 396,969        | 390,314   | 263,791      | Four-byte hash win       |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Exact-cost kept old path |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Exact-cost kept old path |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 30.95% at q2 and 47.96% at q9. The
additional hash-chain candidate roughly doubles the 1 MiB benchmark runtime,
so later P3 work needs cheaper admission/cost heuristics rather than trying
all candidates unconditionally.

## 2026-05-24 — Wider Natural Hash Table

Natural and high-quality LZ77 matching now use a 32K-entry hash table instead
of 4K entries. On 1 MiB natural data this reduces hash collisions enough for
the q2 natural parser and q9 high-quality parser to find better long matches.

Validation commands:

```nu
moon fmt
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 419,583        | 407,942   | 320,418      | Wider-table match win    |
| silesia-1m              | 9       | 390,314        | 376,154   | 263,791      | Wider-table match win    |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 27.32% at q2 and 42.60% at q9.

## 2026-05-24 — Deeper Natural Match Chains

The q2 natural LZ77 parser now checks up to 8 previous hash-chain entries
instead of 4. The q9 high-quality parser remains at 4 checks: an 8-check q9
trial regressed Silesia from 376,154 to 376,699 bytes.

Validation commands:

```nu
moon fmt
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 407,942        | 396,543   | 320,418      | Deeper natural chain win |
| silesia-1m              | 9       | 376,154        | 376,154   | 263,791      | Unchanged                |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 23.76% at q2 and remains 42.60% at q9.

## 2026-05-24 — Eight-Tree UTF-8 Literal Context Candidate

The LZ77 meta-block writer now exact-costs an additional UTF-8 literal-context
candidate with eight literal trees. The candidate further splits the previous
four context classes and is selected only when its full encoded bit count beats
the existing weighted, split-literal, two-tree, and four-tree candidates.

Validation commands:

```nu
moon fmt
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 396,543        | 379,211   | 320,418      | Eight-tree context win   |
| silesia-1m              | 9       | 376,154        | 361,642   | 263,791      | Eight-tree context win   |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 18.35% at q2 and 37.09% at q9.

## 2026-05-24 — Sixteen-Tree UTF-8 Literal Context Candidate

The LZ77 meta-block writer now exact-costs a sixteen-tree UTF-8 literal-context
candidate. This splits the 64 RFC UTF-8 contexts into 16 groups and gives the
entropy selector another measured literal-tree option after the existing 2, 4,
and 8 tree candidates.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*UTF-8 context literal trees*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                     |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------- |
| silesia-1m              | 2       | 379,211        | 367,920   | 320,418      | Sixteen-tree context win  |
| silesia-1m              | 9       | 361,642        | 352,245   | 263,791      | Sixteen-tree context win  |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                 |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                 |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                 |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                 |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified  |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified  |

The Silesia 1 MiB overhead is now 14.83% at q2 and 33.53% at q9.

## 2026-05-24 — Shorter q2 Natural Match Threshold

The q2 natural parser now admits 10-byte matches and raises its command cap to
52,000 commands. Diagnostics showed that the previous 16-byte threshold copied
about 41% of the 1 MiB Silesia slice, while shorter natural matches could copy
substantially more input. The exact-costed writer now keeps the shorter-match
stream only when the extra command entropy is worth it.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*alternate hash candidates exact-costed*'
moon test --target native
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 367,920        | 320,899   | 320,418      | Shorter q2 match win     |
| silesia-1m              | 9       | 352,245        | 352,245   | 263,791      | Unchanged                |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead is now 0.15% at q2 and remains 33.53% at q9.

## 2026-05-24 — Shorter q9 High-Quality Matches

The q9 high-quality parser now also admits 10-byte matches and raises its
command cap to 52,000 commands. This lets q9 cost shorter natural matches
instead of rejecting the candidate when the command stream grows past the old
cap.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*q9 admits shorter high-quality matches*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                     |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------- |
| silesia-1m              | 9       | 352,245        | 332,140   | 263,791      | Shorter q9 match win      |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                 |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                 |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                 |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                 |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified  |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified  |

The Silesia 1 MiB overhead remains 0.15% at q2 and is now 25.91% at q9.

## 2026-05-24 — Six-Byte q9 High-Quality Matches

The q9 high-quality parser now admits 6-byte matches with a 150,000-command
cap. Trials with 8-byte matches improved Silesia q9 to 319,715 bytes, 6-byte
matches improved it further, and a 4-byte trial overpaid command entropy and
regressed to 313,641 bytes.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*q9 admits shorter high-quality matches*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 9       | 332,140        | 307,056   | 263,791      | Six-byte q9 match win    |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 195            | 195       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 195            | 195       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB overhead remains 0.15% at q2 and is now 16.40% at q9.

## 2026-05-24 — Encoder Distance-Cache Short Codes

The LZ77 command builder now computes Brotli distance-cache short codes against
the four recent distances instead of only using the implicit same-as-last
command form. Nonzero short codes are emitted through the distance tree, while
distance code 0 still uses the compact command-prefix form.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*distance-cache short codes*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                         |
| ----------------------- | ------- | -------------- | --------- | ------------ | ----------------------------- |
| silesia-1m              | 2       | 320,899        | 320,612   | 320,418      | Distance-cache code win       |
| silesia-1m              | 9       | 307,056        | 306,645   | 263,791      | Distance-cache code win       |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                     |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                     |
| small-alpha-multi-1400  | 2       | 195            | 193       | 169          | Small distance-cache win      |
| small-alpha-multi-1400  | 9       | 195            | 193       | 69           | Small distance-cache win      |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified      |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified      |

The Silesia 1 MiB overhead is now 0.06% at q2 and 16.25% at q9.

## 2026-05-24 — Short-Match Lazy Lookahead

The LZ77 parser now applies its one-byte lazy-match lookahead to short-match
natural and high-quality configurations instead of only to 16-byte-and-longer
matches. This lets the parser skip a short copy when the next byte starts a
substantially longer one.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*q9 admits shorter high-quality matches*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ----------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m              | 2       | 320,612        | 318,026   | 320,418      | Short lazy-match win     |
| silesia-1m              | 9       | 306,645        | 303,384   | 263,791      | Short lazy-match win     |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| small-alpha-multi-1400  | 2       | 193            | 193       | 169          | Unchanged                |
| small-alpha-multi-1400  | 9       | 193            | 193       | 69           | Unchanged                |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB result is now 0.75% smaller than Google q2 and 15.01% larger
than Google q9.

## 2026-05-24 — Aggressive Lazy-Match Margin

The lazy-match lookahead now delays a copy whenever the next position has any
longer match, instead of requiring the next match to beat the current match by
more than four bytes. Intermediate trials after the short-match lazy increment
showed q9 improvements at +2 and +1 margins; the zero-margin rule was best.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*q9 admits shorter high-quality matches*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                       |
| ----------------------- | ------- | -------------- | --------- | ------------ | --------------------------- |
| silesia-1m              | 2       | 318,026        | 317,081   | 320,418      | Aggressive lazy-match win   |
| silesia-1m              | 9       | 303,384        | 301,268   | 263,791      | Aggressive lazy-match win   |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                   |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                   |
| small-alpha-multi-1400  | 2       | 193            | 193       | 169          | Unchanged                   |
| small-alpha-multi-1400  | 9       | 193            | 193       | 69           | Unchanged                   |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified    |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified    |

The Silesia 1 MiB result is now 1.04% smaller than Google q2 and 14.21% larger
than Google q9.

## 2026-05-24 — Three-Byte Lazy Lookahead

The LZ77 parser now checks up to three following byte positions before taking
a short match. It still only delays when a later position has a longer match.
Two-byte lookahead improved Silesia q9 to 298,889 bytes, three-byte lookahead
improved it to 298,536 bytes, and four-byte lookahead regressed to 299,595
bytes.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*q9 admits shorter high-quality matches*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                      |
| ----------------------- | ------- | -------------- | --------- | ------------ | -------------------------- |
| silesia-1m              | 2       | 317,081        | 314,410   | 320,418      | Three-byte lazy win        |
| silesia-1m              | 9       | 301,268        | 298,536   | 263,791      | Three-byte lazy win        |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                  |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                  |
| small-alpha-multi-1400  | 2       | 193            | 193       | 169          | Unchanged                  |
| small-alpha-multi-1400  | 9       | 193            | 193       | 69           | Unchanged                  |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified   |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified   |

The Silesia 1 MiB result is now 1.88% smaller than Google q2 and 13.17% larger
than Google q9.

## 2026-05-24 — Distance-Cache Match Probes

The LZ77 match finder now probes the 16 Brotli recent-distance short-code
candidates before walking the hash chain. Equal-length hash-chain matches no
longer displace a recent-distance match, which lets the existing command
builder emit cheaper distance symbols more often. A shortened-copy parser
trial was rejected because it produced the same 298,536-byte q9 output while
raising runtime to 129,817 ms. A relaxed lazy threshold was also rejected after
regressing q9 to 303,496 bytes, and an 8-check q9 hash-chain trial remained
byte-identical at 298,536 bytes.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*matcher probes distance-cache candidates*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                  | Quality | Previous bytes | New bytes | Google bytes | Notes                       |
| ----------------------- | ------- | -------------- | --------- | ------------ | --------------------------- |
| silesia-1m              | 2       | 314,410        | 313,585   | 320,418      | Recent-distance probe win   |
| silesia-1m              | 9       | 298,536        | 296,784   | 263,791      | Recent-distance probe win   |
| split-literals-8k       | 2       | 3,434          | 3,434     | 3,455        | Unchanged                   |
| split-literals-8k       | 9       | 3,434          | 3,434     | 3,418        | Unchanged                   |
| small-alpha-multi-1400  | 2       | 193            | 179       | 169          | Recent-distance probe win   |
| small-alpha-multi-1400  | 9       | 193            | 179       | 69           | Recent-distance probe win   |
| periodic-allbytes-200k  | 2       | 350            | 350       | n/a          | External decode verified    |
| periodic-allbytes-200k  | 9       | 350            | 350       | n/a          | External decode verified    |

The Silesia 1 MiB result is now 2.13% smaller than Google q2 and 12.51% larger
than Google q9.

## 2026-05-24 — Encoder Dictionary Uppercase Transforms

The encoder static-dictionary index now includes same-length uppercase-first
and uppercase-all transform entries, in addition to identity entries. The
dictionary address stores the Brotli transform index, not the transform type;
the implementation only indexes transforms whose prefix and suffix are empty
so the emitted command copy length remains equal to the transformed output
length.

Rejected nearby trials:

- Two command-block split candidates at quarter/midpoint/three-quarter command
  positions were byte-identical on Silesia q9 and slower.
- Cached-distance bias margins of +2 and +1 bytes either regressed q9 or
  changed tokenization without reducing output size.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*uppercase static dictionary transforms*'
nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-words.txt --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-title-words.txt --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                       |
| ---------------------------- | ------- | -------------- | --------- | ------------ | --------------------------- |
| dictionary-words             | 2       | 76             | 76        | 78           | Unchanged                   |
| dictionary-words             | 9       | 76             | 76        | 61           | Unchanged                   |
| dictionary-title-words       | 2       | n/a            | 78        | 89           | Uppercase transform fixture |
| dictionary-title-words       | 9       | n/a            | 78        | 73           | Uppercase transform fixture |
| silesia-1m                   | 9       | 296,784        | 296,784   | 263,791      | Unchanged                   |
| split-literals-8k            | 2       | 3,434          | 3,434     | 3,455        | Unchanged                   |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | Unchanged                   |
| small-alpha-multi-1400       | 2       | 179            | 179       | 169          | Unchanged                   |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | Unchanged                   |
| periodic-allbytes-200k       | 2       | 350            | 350       | n/a          | External decode verified    |
| periodic-allbytes-200k       | 9       | 350            | 350       | n/a          | External decode verified    |

The Silesia 1 MiB q9 gap remains 12.51%; this is a static-dictionary
correctness/subsystem increment rather than a large-corpus ratio win.

## 2026-05-24 — Encoder Dictionary Suffix/Prefix Transforms

The encoder static-dictionary path now supports selected Brotli transforms
whose transformed output length differs from the dictionary word length, such
as identity plus a trailing space. `BrotliEncodeCommand` tracks both values:
the encoded command copy length remains the dictionary word length, while
meta-block accounting uses the transformed output length. This keeps streams
valid for dictionary transforms that emit prefixes or suffixes.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*static dictionary*'
nu tools/brotli/encode/verify.nu target/brotli-encode/title-small.txt --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/dictionary-words-spaced.txt --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-words.txt --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-title-words.txt --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/dictionary-words-spaced.txt --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                       |
| ---------------------------- | ------- | -------------- | --------- | ------------ | --------------------------- |
| dictionary-words             | 2       | 76             | 76        | 78           | Unchanged                   |
| dictionary-words             | 9       | 76             | 76        | 61           | Unchanged                   |
| dictionary-title-words       | 2       | 78             | 78        | 89           | Unchanged                   |
| dictionary-title-words       | 9       | 78             | 78        | 73           | Unchanged                   |
| dictionary-words-spaced      | 2       | n/a            | 76        | 79           | Suffix transform fixture    |
| dictionary-words-spaced      | 9       | n/a            | 76        | 62           | Suffix transform fixture    |
| silesia-1m                   | 9       | 296,784        | 296,784   | 263,791      | Unchanged                   |
| split-literals-8k            | 2       | 3,434          | 3,434     | 3,455        | Unchanged                   |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | Unchanged                   |
| small-alpha-multi-1400       | 2       | 179            | 179       | 169          | Unchanged                   |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | Unchanged                   |
| periodic-allbytes-200k       | 2       | 350            | 350       | n/a          | External decode verified    |
| periodic-allbytes-200k       | 9       | 350            | 350       | n/a          | External decode verified    |

The Silesia 1 MiB q9 gap remains 12.51%; this expands dictionary transform
coverage but does not address the remaining P3/P4 natural-corpus gap.

## 2026-05-24 — q10/q11 High-Quality Parser Tuning

Quality 10 and 11 now use a distinct high-quality hash configuration instead
of reusing q9's parser limits. The q10/q11 parser checks deeper hash chains,
accepts 5-byte matches, and allows a larger command budget. q9 stays on the
previous exact-costed settings.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*alternate hash candidates exact-costed*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 9,10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 9,10,11 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 11
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                     |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ------------------------- |
| silesia-1m                   | 9       | 296,784        | 296,784   | 263,791      | q9 unchanged              |
| silesia-1m                   | 10      | 296,784        | 288,988   | 242,485      | q10-specific parser win   |
| silesia-1m                   | 11      | 296,784        | 288,988   | 239,314      | q11-specific parser win   |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | Unchanged                 |
| split-literals-8k            | 10      | 3,434          | 3,434     | 3,420        | Unchanged                 |
| split-literals-8k            | 11      | 3,434          | 3,434     | 3,420        | Unchanged                 |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | Unchanged                 |
| small-alpha-multi-1400       | 10      | 179            | 179       | 63           | Unchanged                 |
| small-alpha-multi-1400       | 11      | 179            | 179       | 55           | Unchanged                 |
| periodic-allbytes-200k       | 11      | 350            | 350       | n/a          | External decode verified  |

The Silesia 1 MiB q10 gap drops from 22.39% to 19.18%; q11 drops from 24.01%
to 20.76%. q10/q11 still share the same parser and do not yet implement a
full Zopfli/shortest-path backend.

## 2026-05-24 — q11 Deeper Parser Tuning

Quality 11 now goes deeper than q10: 32 hash-chain checks and a 300,000-command
cap, while keeping the q10 settings unchanged. This gives q11 a distinct
measured output on natural data.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*alternate hash candidates exact-costed*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 11 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 10,11 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 11
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m                   | 10      | 288,988        | 288,988   | 242,485      | q10 unchanged            |
| silesia-1m                   | 11      | 288,988        | 283,133   | 239,314      | q11 deeper-parser win    |
| split-literals-8k            | 10      | 3,434          | 3,434     | 3,420        | Unchanged                |
| split-literals-8k            | 11      | 3,434          | 3,434     | 3,420        | Unchanged                |
| small-alpha-multi-1400       | 10      | 179            | 179       | 63           | Unchanged                |
| small-alpha-multi-1400       | 11      | 179            | 179       | 55           | Unchanged                |
| periodic-allbytes-200k       | 11      | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB q11 gap drops from 20.76% to 18.31%. P4 still needs a real
shortest-path parser and stronger entropy modeling before it can meet the
final q11 target.

## 2026-05-25 — q2 Fast Large-Chunk Profile

Quality 2 now uses a speed-first large-chunk profile instead of exact-costing
the same broad candidate set as high-quality modes. For q2 chunks at least 8
KiB, the selector tries the natural LZ77 parser directly and skips the
literal-only, split-literal, dictionary, baseline hash, and four-byte hash
candidates. For q2 LZ77 meta-blocks at least 512 KiB, the writer directly uses
the 16-tree UTF-8 literal-context candidate. Smaller q2 LZ77 blocks still keep
the weighted fallback to preserve repetitive-fixture output.

Rejected nearby trial:

- Reducing q2 natural hash-chain checks from 8 to 4 produced a 338,135-byte
  Silesia q2 stream, but Google Brotli rejected it as corrupt input.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*alternate hash candidates exact-costed*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Previous ms | New ms    | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ----------- | --------- | ------------------------ |
| silesia-1m                   | 2       | 313,585        | 325,896   | 320,418      | 82,818      | 42,558    | q2 speed profile         |
| silesia-1m                   | 9       | 296,784        | 296,784   | 263,791      | n/a         | 91,707    | q9 unchanged             |
| split-literals-8k            | 2       | 3,434          | 3,434     | 3,455        | n/a         | 5,215     | Unchanged                |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | n/a         | 5,547     | Unchanged                |
| small-alpha-multi-1400       | 2       | 179            | 179       | 169          | n/a         | 7,589     | Unchanged                |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | n/a         | 7,427     | Unchanged                |
| periodic-allbytes-200k       | 2       | 350            | 350       | n/a          | n/a         | n/a       | External decode verified |
| periodic-allbytes-200k       | 9       | 350            | 350       | n/a          | n/a         | n/a       | External decode verified |

The Silesia 1 MiB q2 result moves from 2.13% smaller than Google to 1.71%
larger than Google, while benchmark time drops by about 49%. This makes q2 a
fast mode again; deeper exact-costed alternatives remain reserved for q9+.

## 2026-05-25 — Deeper q9/q10 Parser Tuning

Quality 9 and 10 now use q11's deeper high-quality parser settings: 32
hash-chain checks, 5-byte minimum matches, and a 300,000-command cap. A
16-check q9 trial improved Silesia q9 to 288,988 bytes; the retained 32-check
setting improved it further to 283,133 bytes with similar measured runtime.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*alternate hash candidates exact-costed*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 9,10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 9,10,11 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m                   | 9       | 296,784        | 283,133   | 263,791      | Deeper q9 parser win     |
| silesia-1m                   | 10      | 288,988        | 283,133   | 242,485      | Deeper q10 parser win    |
| silesia-1m                   | 11      | 283,133        | 283,133   | 239,314      | Unchanged                |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| split-literals-8k            | 10      | 3,434          | 3,434     | 3,420        | Unchanged                |
| split-literals-8k            | 11      | 3,434          | 3,434     | 3,420        | Unchanged                |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | Unchanged                |
| small-alpha-multi-1400       | 10      | 179            | 179       | 63           | Unchanged                |
| small-alpha-multi-1400       | 11      | 179            | 179       | 55           | Unchanged                |
| periodic-allbytes-200k       | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB q9 gap drops from 12.51% to 7.33%; q10 drops from 19.18%
to 16.76%. P3/P4 still need stronger parsing and entropy modeling to reach the
final 5% target.

## 2026-05-25 — q2 Chunk Distance-Cache State

A 512 KiB high-quality chunk-size trial produced a smaller 287,762-byte
Silesia stream, but Google Brotli rejected it. The failure exposed a chunked
encoder correctness issue: LZ77 command building restarted the recent-distance
cache for every compressed chunk, while Brotli decoders preserve that cache
across meta-blocks.

The q2 chunked path now threads a persistent recent-distance cache into LZ77
command building. The chunk writer snapshots and restores the cache when a
compressed candidate is rejected in favor of a stored meta-block, since stored
blocks do not update recent distances.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*compresses chunked large input*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 2
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m                   | 2       | 325,896        | 325,896   | 320,418      | Valid external decode    |
| periodic-allbytes-200k       | 2       | 350            | 350       | n/a          | External decode verified |

This is a correctness foundation for future multi-meta-block compressed
streams. It does not change current q2 ratio because the retained chunk size
still produces one compressed chunk on the 1 MiB Silesia slice.

## 2026-05-25 — Five-Byte Lazy Lookahead

The high-quality parser now applies its three-position lazy lookahead to
5-byte-minimum match configurations. Previously, q9+ accepted 5-byte matches
but only ran the lazy lookahead for configurations with a 6-byte minimum, so
the parser could take a short match immediately before a longer one.

Validation commands:

```nu
moon fmt
moon test --target native --filter '*q9 admits shorter high-quality matches*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 9,10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 9,10,11 --json
nu tools/brotli/encode/verify.nu target/brotli-encode/periodic-allbytes-200k.bin --quality 9
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m                   | 9       | 283,133        | 273,641   | 263,791      | Five-byte lazy win       |
| silesia-1m                   | 10      | 283,133        | 273,641   | 242,485      | Five-byte lazy win       |
| silesia-1m                   | 11      | 283,133        | 273,641   | 239,314      | Five-byte lazy win       |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| split-literals-8k            | 10      | 3,434          | 3,434     | 3,420        | Unchanged                |
| split-literals-8k            | 11      | 3,434          | 3,434     | 3,420        | Unchanged                |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | Unchanged                |
| small-alpha-multi-1400       | 10      | 179            | 179       | 63           | Unchanged                |
| small-alpha-multi-1400       | 11      | 179            | 179       | 55           | Unchanged                |
| periodic-allbytes-200k       | 9       | 350            | 350       | n/a          | External decode verified |

The Silesia 1 MiB q9 gap drops from 7.33% to 3.73%, bringing q9 inside the P3
5% target window for this validation slice. q10 and q11 still need stronger P4
search and entropy modeling.

## 2026-05-25 — Chunked Final Meta-Block Boundary

Chunked standard encoding now lets the final compressed chunk set
`ISLAST=1` directly instead of always writing compressed chunks as non-final
meta-blocks and appending an empty final terminator. The standard chunk size
also moves from 1,048,575 to 1,048,576 bytes, so a 1 MiB input can be encoded
as one compressed meta-block instead of a 1-byte tail chunk.

Two P4 parser trials were measured and rejected before this boundary fix:
lowering q10's minimum match length to 4 bytes regressed Silesia q10 to
285,760 bytes, and deeper q10/q11 lazy lookahead regressed q10 to 291,763
bytes and q11 to 320,823 bytes while increasing runtime.

Validation commands:

```nu
moon test --target native --filter '*q0 through q11 round-trip*'
moon test --target native --filter '*chunk*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,9,10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2,9,10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2,9,10,11 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/periodic-allbytes-200k.bin --qualities 2,9 --json
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ------------------------ |
| silesia-1m                   | 2       | 325,896        | 325,887   | 320,418      | Final chunk boundary win |
| silesia-1m                   | 9       | 273,641        | 273,633   | 263,791      | Final chunk boundary win |
| silesia-1m                   | 10      | 273,641        | 273,633   | 242,485      | Final chunk boundary win |
| silesia-1m                   | 11      | 273,641        | 273,633   | 239,314      | Final chunk boundary win |
| split-literals-8k            | 2       | 3,434          | 3,434     | 3,455        | Unchanged                |
| split-literals-8k            | 9       | 3,434          | 3,434     | 3,418        | Unchanged                |
| split-literals-8k            | 10      | 3,434          | 3,434     | 3,420        | Unchanged                |
| split-literals-8k            | 11      | 3,434          | 3,434     | 3,420        | Unchanged                |
| small-alpha-multi-1400       | 2       | 179            | 179       | 169          | Unchanged                |
| small-alpha-multi-1400       | 9       | 179            | 179       | 69           | Unchanged                |
| small-alpha-multi-1400       | 10      | 179            | 179       | 63           | Unchanged                |
| small-alpha-multi-1400       | 11      | 179            | 179       | 55           | Unchanged                |
| periodic-allbytes-200k       | 2       | 350            | 350       | 293          | External decode verified |
| periodic-allbytes-200k       | 9       | 350            | 350       | 259          | External decode verified |

This is intentionally a small boundary-correctness increment. P4 still needs
a real Zopfli-style parser and stronger entropy modeling for the q10/q11 ratio
target.

## 2026-05-25 — q2 Fast Profile Scan Reduction

The q2 fast profile was still far slower than Google Brotli even after the
previous candidate pruning. Two hot spots were reduced:

- The 16-tree UTF-8 literal-context writer now gathers literal symbols and
  frequencies for all 16 contexts in one pass instead of scanning the command
  literals once per context for symbols and once per context for frequencies.
- The q2 natural parser no longer probes Brotli recent-distance short-code
  candidates before hash-chain candidates, and uses a one-position lazy
  lookahead instead of three. q9+ keeps the previous full recent-distance probe
  and three-position lazy lookahead.

A q2 four-hash-check trial encoded Silesia to 339,926 bytes and was rejected
by Google Brotli as corrupt, so the retained q2 parser still uses eight
hash-chain checks.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*UTF-8 context*'
moon test --target native --filter '*alternate hash candidates exact-costed*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/split-literals-8k.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/small-alpha-multi-1400.bin --qualities 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-encode/periodic-allbytes-200k.bin --qualities 2 --json
```

Results:

| Corpus                       | Quality | Previous bytes | New bytes | Google bytes | Previous ms | New ms | Notes                    |
| ---------------------------- | ------- | -------------- | --------- | ------------ | ----------- | ------ | ------------------------ |
| silesia-1m                   | 2       | 325,887        | 329,512   | 320,418      | 40,862      | 28,054 | Still within 5% window   |
| split-literals-8k            | 2       | 3,434          | 3,434     | 3,455        | n/a         | 7,335  | Unchanged                |
| small-alpha-multi-1400       | 2       | 179            | 162       | 169          | n/a         | 9,556  | Smaller than prior q2    |
| periodic-allbytes-200k       | 2       | 350            | 350       | 293          | n/a         | 6,913  | External decode verified |

The Silesia q2 1 MiB output remains 2.84% larger than Google q2, while the
measured ratio-harness time drops by about 31% versus the previous retained
baseline. It is still much slower than Google Brotli; the next q2 speed work
needs to reduce LZ77 match-search cost rather than only pruning writer scans.

## 2026-05-25 — wasm-gc/native Target Performance Harness

`tools/brotli/bench/target-perf.nu` now measures Brotli performance through
temporary MoonBit white-box tests on selected targets. The default targets are
`wasm-gc,native`; JavaScript remains useful for file-oriented verification but
is no longer the preferred performance signal. Decode time, encode time, and
encoded size should use this harness by default.

Decode command:

```nu
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-1m.bin.google.q11.br \
  --mode decode \
  --expected target/brotli-bench/silesia-1m.bin \
  --targets wasm-gc,native \
  --repeats 5 \
  --samples 2 \
  --json
```

Encode command:

```nu
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-128k.bin \
  --mode encode \
  --quality 2 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Results:

| Mode   | Corpus          | Target  | Quality | MoonBit bytes | Google bytes | Target ms | Google ms | Slowdown | Notes                         |
| ------ | --------------- | ------- | ------- | ------------- | ------------ | --------- | --------- | -------- | ----------------------------- |
| decode | silesia-1m q11  | wasm-gc | n/a     | n/a           | n/a          | 48.7      | 14.5      | 3.36x    | 1 MiB decoded output          |
| decode | silesia-1m q11  | native  | n/a     | n/a           | n/a          | 131.6     | 14.5      | 9.06x    | 1 MiB decoded output          |
| encode | silesia-128k    | wasm-gc | 2       | 51,928        | 44,794       | 185.5     | 38.5      | 4.82x    | Size reported by target run   |
| encode | silesia-128k    | native  | 2       | 51,928        | 44,794       | 504.3     | 38.5      | 13.11x   | Size reported by target run   |

The target-specific results confirm that Brotli algorithm decisions must track
both size and runtime. Ratio-only changes are not sufficient for P3/P4 review.
The older `encode/verify.nu`, `silesia/verify.nu`, and `bench/ratio.nu` scripts
remain available for file-based verification and historical size telemetry, but
they are explicitly tagged as legacy JS verification paths rather than default
benchmark harnesses.

## 2026-05-25 — Literal-Set Collector Speedup

The encoder previously collected several literal symbol sets by linearly
scanning the already-seen symbol list for every literal. Replacing those
duplicate checks with 256-entry `seen` tables preserves first-seen symbol order
while avoiding O(n * unique-symbols) collection cost.

Validation commands:

```nu
moon check --target all
moon test --target all
moon info
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-128k.bin \
  --mode encode \
  --quality 2 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 2 \
  --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2 --json
```

Results:

| Corpus       | Quality | Target  | Previous ms | New ms | MoonBit bytes | Google bytes | Notes              |
| ------------ | ------- | ------- | ----------- | ------ | ------------- | ------------ | ------------------ |
| silesia-128k | 2       | wasm-gc | 178.97      | 163.79 | 51,928        | 44,794       | Same encoded size  |
| silesia-128k | 2       | native  | 521.30      | 470.19 | 51,928        | 44,794       | Same encoded size  |
| silesia-1m   | 2       | legacy  | n/a         | n/a    | 329,512       | 320,418      | External verified  |

`target-perf.nu` now also uses the shared Brotli harness lock so concurrent
temporary white-box benchmark runs cannot invalidate each other's generated
`src/*_wbtest.mbt` files during Moon test discovery.

## 2026-05-27 — q9 mixed dictionary candidate

The q9 encoder path now also tries `brotli_build_mixed_dictionary_lz77_commands`
with the 4-byte high-quality hash config, mirroring the q10/q11 path. Dictionary
words can replace short copies on natural text, closing part of the q9 ratio
gap against Google Brotli.

Validation commands:

```nu
moon check --target all
moon test --target all
moon test --target native --filter '*mixed dictionary*'
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 1 --samples 2 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-128k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 1 --samples 2 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-1m.bin --quality 9
```

Results:

| Corpus       | Quality | Target  | Previous bytes | New bytes | Google bytes | Previous ms | New ms |
| ------------ | ------- | ------- | -------------- | --------- | ------------ | ----------- | ------ |
| silesia-64k  | 9       | wasm-gc | 22,261         | 21,514    | 22,063       | 140.583     | 161.436 |
| silesia-64k  | 9       | native  | 22,261         | 21,514    | 22,063       | 60.651      | 77.168 |
| silesia-128k | 9       | wasm-gc | 40,013         | 39,081    | 39,695       | 187.508     | 223.941 |
| silesia-128k | 9       | native  | 40,013         | 39,081    | 39,695       | 89.278      | 116.025 |
| silesia-1m   | 9       | legacy  | 273,633        | 271,776   | 263,791      | n/a         | n/a    |

q9 overhead vs Google q9: 3.73% -> 3.03% on silesia-1m. Two smaller fixtures now
encode smaller than Google q9 (silesia-64k: -2.49%; silesia-128k: -1.55%).
q10/q11 unchanged because the path was already enabled for them.

Rejected follow-ups:

- Adding the 3-byte hash high-quality candidate at q10/q11: did not change
  size on silesia-64k.bin q11 (still 21,415 bytes) and silesia-1m.bin q11
  (still 264,422 bytes), while doubling silesia-1m.bin q11 encode time
  (63,564 -> 130,114 ms on the ratio harness).
- Adding the 3-byte hash mixed-dictionary candidate at q9: did not change
  silesia-1m.bin q9 size (still 271,776 bytes), while raising the ratio
  harness time from 73,725 to 99,943 ms (about +36%).

## 2026-05-28 — q3 through q8 Baseline Matrix

This establishes the missing P3 acceptance baseline for intermediate Brotli
qualities. The current encoder accepts q3 through q8 and emits valid streams,
but these qualities still share the same standard compressed candidate output.
That is good enough for q3 on the measured Silesia slices, but q4 through q8
miss the documented 5% size target as the Google reference keeps improving
with higher quality.

Validation commands:

```nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 3,4,5,6,7,8 --json

nu -c 'for q in 3..8 {
  print $"QUALITY=($q)"
  nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
    --mode encode \
    --quality $q \
    --targets wasm-gc,native \
    --repeats 1 \
    --samples 1 \
    --json
}'
```

1 MiB ratio results:

| Quality | MoonBit bytes | Google bytes | Size overhead | MoonBit SHA-256 |
| ------- | ------------- | ------------ | ------------- | --------------- |
| 3       | 313,577       | 313,727      | -0.05%        | `fde02b28aae84889340c2291e031a45ccbfb5d9534d1711a92cc774d5351d715` |
| 4       | 313,577       | 292,364      | 7.26%         | `fde02b28aae84889340c2291e031a45ccbfb5d9534d1711a92cc774d5351d715` |
| 5       | 313,577       | 274,088      | 14.41%        | `fde02b28aae84889340c2291e031a45ccbfb5d9534d1711a92cc774d5351d715` |
| 6       | 313,577       | 269,636      | 16.30%        | `fde02b28aae84889340c2291e031a45ccbfb5d9534d1711a92cc774d5351d715` |
| 7       | 313,577       | 267,096      | 17.40%        | `fde02b28aae84889340c2291e031a45ccbfb5d9534d1711a92cc774d5351d715` |
| 8       | 313,577       | 264,815      | 18.41%        | `fde02b28aae84889340c2291e031a45ccbfb5d9534d1711a92cc774d5351d715` |

64 KiB target-perf results, `samples=1`:

| Quality | Target  | MoonBit bytes | Google bytes | Size overhead | Target ms | Google ms | Slowdown |
| ------- | ------- | ------------- | ------------ | ------------- | --------- | --------- | -------- |
| 3       | wasm-gc | 25,127        | 24,059       | 4.44%         | 533.940   | 39.377    | 13.56x   |
| 3       | native  | 25,127        | 24,059       | 4.44%         | 105.043   | 39.377    | 2.67x    |
| 4       | wasm-gc | 25,127        | 23,325       | 7.73%         | 510.333   | 43.782    | 11.66x   |
| 4       | native  | 25,127        | 23,325       | 7.73%         | 120.076   | 43.782    | 2.74x    |
| 5       | wasm-gc | 25,127        | 22,271       | 12.82%        | 529.914   | 40.805    | 12.99x   |
| 5       | native  | 25,127        | 22,271       | 12.82%        | 84.142    | 40.805    | 2.06x    |
| 6       | wasm-gc | 25,127        | 22,121       | 13.59%        | 517.090   | 44.513    | 11.62x   |
| 6       | native  | 25,127        | 22,121       | 13.59%        | 122.237   | 44.513    | 2.75x    |
| 7       | wasm-gc | 25,127        | 22,101       | 13.69%        | 510.365   | 41.356    | 12.34x   |
| 7       | native  | 25,127        | 22,101       | 13.69%        | 121.663   | 41.356    | 2.94x    |
| 8       | wasm-gc | 25,127        | 22,077       | 13.82%        | 567.508   | 41.281    | 13.75x   |
| 8       | native  | 25,127        | 22,077       | 13.82%        | 125.608   | 41.281    | 3.04x    |

Conclusion: q3 is inside the documented P3 ratio target on these slices.
q4 through q8 need distinct quality-aware parsing and/or richer
histogram/block clustering. Because q3 through q8 currently emit the same
MoonBit bytes on both measured inputs, the next P3 task should add quality
separation before spending more time on q2 or q9 tuning.

## 2026-05-28 — q4 through q8 Intermediate Search

The q4 through q8 encoder path now exact-costs an additional intermediate hash
configuration after the existing natural candidates. The configuration scales
hash-chain checks and command budget by quality:

- q4: 8 checks, 100,000-command cap, 6-byte minimum match.
- q5/q6: 16 checks, 180,000-command cap, 5-byte minimum match.
- q7/q8: 32 checks, 240,000-command cap, 5-byte minimum match.

This gives q4 through q8 a distinct P3 path while preserving q3 as the faster
baseline profile.

Validation commands:

```nu
moon fmt
moon check --target all
moon test --target native --filter '*alternate hash candidates exact-costed*'
moon test --target native --filter '*q0 through q11 round-trip*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 3,4,5,6,7,8 --json

nu -c 'for q in [4 5 8] {
  print $"QUALITY=($q)"
  nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
    --mode encode \
    --quality $q \
    --targets wasm-gc,native \
    --repeats 1 \
    --samples 1 \
    --json
}'
```

1 MiB ratio results:

| Quality | Previous bytes | New bytes | Google bytes | Previous overhead | New overhead |
| ------- | -------------- | --------- | ------------ | ----------------- | ------------ |
| 3       | 313,577        | 313,577   | 313,727      | -0.05%            | -0.05%       |
| 4       | 313,577        | 287,092   | 292,364      | 7.26%             | -1.80%       |
| 5       | 313,577        | 278,961   | 274,088      | 14.41%            | 1.78%        |
| 6       | 313,577        | 278,961   | 269,636      | 16.30%            | 3.46%        |
| 7       | 313,577        | 273,633   | 267,096      | 17.40%            | 2.45%        |
| 8       | 313,577        | 273,633   | 264,815      | 18.41%            | 3.33%        |

64 KiB target-perf results, `samples=1`:

| Quality | Target  | Previous bytes | New bytes | Google bytes | Previous ms | New ms  | New slowdown |
| ------- | ------- | -------------- | --------- | ------------ | ----------- | ------- | ------------ |
| 4       | wasm-gc | 25,127         | 22,785    | 23,325       | 510.333     | 559.701 | 14.45x       |
| 4       | native  | 25,127         | 22,785    | 23,325       | 120.076     | 148.200 | 3.83x        |
| 5       | wasm-gc | 25,127         | 22,336    | 22,271       | 529.914     | 559.509 | 12.86x       |
| 5       | native  | 25,127         | 22,336    | 22,271       | 84.142      | 110.135 | 2.53x        |
| 8       | wasm-gc | 25,127         | 22,261    | 22,077       | 567.508     | 556.979 | 11.32x       |
| 8       | native  | 25,127         | 22,261    | 22,077       | 125.608     | 105.232 | 2.14x        |

Conclusion: this closes the measured q4 through q8 P3 ratio gap on the 1 MiB
Silesia slice and sampled 64 KiB target-perf slice. q4 pays the largest native
runtime cost, but q5 and q8 remain within the native 3x performance target on
the sampled run. The remaining P3 work is broader histogram/block clustering
and a fuller q3..q9 release validation matrix, not basic q4..q8 quality
separation.

## 2026-05-28 — q2 through q9 P3 Matrix

This records the first complete q2 through q9 matrix after q4 through q8 gained
their intermediate search path. It is still a measured matrix, not final P3
completion: samples are single-run `target-perf.nu` measurements on the 64 KiB
slice, and larger release validation still needs broader corpora and the long
fuzz/conformance gates.

Validation commands:

```nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 2,3,4,5,6,7,8,9 --json

nu -c 'for q in 2..9 {
  print $"QUALITY=($q)"
  nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
    --mode encode \
    --quality $q \
    --targets wasm-gc,native \
    --repeats 1 \
    --samples 1 \
    --json
}'
```

1 MiB ratio results:

| Quality | MoonBit bytes | Google bytes | Size overhead | MoonBit time ms |
| ------- | ------------- | ------------ | ------------- | --------------- |
| 2       | 329,512       | 320,418      | 2.84%         | 8,109.918       |
| 3       | 313,577       | 313,727      | -0.05%        | 38,162.565      |
| 4       | 287,092       | 292,364      | -1.80%        | 69,483.634      |
| 5       | 278,961       | 274,088      | 1.78%         | 73,548.898      |
| 6       | 278,961       | 269,636      | 3.46%         | 784,230.003     |
| 7       | 273,633       | 267,096      | 2.45%         | 84,257.863      |
| 8       | 273,633       | 264,815      | 3.33%         | 82,696.436      |
| 9       | 271,776       | 263,791      | 3.03%         | 48,703.919      |

The q6 legacy JS verifier time is an outlier relative to adjacent qualities;
use the target-specific rows below for performance decisions.

64 KiB target-perf results, `samples=1`:

| Quality | Target  | MoonBit bytes | Google bytes | Size overhead | Target ms | Google ms | Slowdown |
| ------- | ------- | ------------- | ------------ | ------------- | --------- | --------- | -------- |
| 2       | wasm-gc | 25,245        | 24,364       | 3.62%         | 500.200   | 38.945    | 12.84x   |
| 2       | native  | 25,245        | 24,364       | 3.62%         | 73.089    | 38.945    | 1.88x    |
| 3       | wasm-gc | 25,127        | 24,059       | 4.44%         | 500.487   | 37.938    | 13.19x   |
| 3       | native  | 25,127        | 24,059       | 4.44%         | 69.511    | 37.938    | 1.83x    |
| 4       | wasm-gc | 22,785        | 23,325       | -2.32%        | 543.807   | 47.757    | 11.39x   |
| 4       | native  | 22,785        | 23,325       | -2.32%        | 138.547   | 47.757    | 2.90x    |
| 5       | wasm-gc | 22,336        | 22,271       | 0.29%         | 541.752   | 42.415    | 12.77x   |
| 5       | native  | 22,336        | 22,271       | 0.29%         | 142.394   | 42.415    | 3.36x    |
| 6       | wasm-gc | 22,336        | 22,121       | 0.97%         | 556.699   | 39.738    | 14.01x   |
| 6       | native  | 22,336        | 22,121       | 0.97%         | 143.404   | 39.738    | 3.61x    |
| 7       | wasm-gc | 22,261        | 22,101       | 0.72%         | 550.708   | 41.474    | 13.28x   |
| 7       | native  | 22,261        | 22,101       | 0.72%         | 153.878   | 41.474    | 3.71x    |
| 8       | wasm-gc | 22,261        | 22,077       | 0.83%         | 545.790   | 43.817    | 12.46x   |
| 8       | native  | 22,261        | 22,077       | 0.83%         | 112.213   | 43.817    | 2.56x    |
| 9       | wasm-gc | 21,514        | 22,063       | -2.49%        | 530.562   | 48.346    | 10.97x   |
| 9       | native  | 21,514        | 22,063       | -2.49%        | 128.080   | 48.346    | 2.65x    |

Conclusion: q2 through q9 are all inside the 5% P3 ratio target on the measured
1 MiB and 64 KiB Silesia slices. The next P3 optimization should focus on
runtime, especially q5 through q7, or broaden the validation corpus before
claiming phase completion. Broader histogram/block clustering remains useful
for corpus diversity, but the immediate measured Silesia blocker has moved from
ratio to performance/validation coverage.

## 2026-05-28 — q6/q7 Small-Input Runtime Tuning

The q6 and q7 intermediate 4-byte hash candidate is now skipped for inputs up
to 64 KiB. The candidate is still retained for larger chunks, where the 1 MiB
ratio matrix showed it is required to stay inside the 5% P3 target. q5 keeps
the 4-byte candidate at all sizes because the skip experiment regressed sampled
native runtime and worsened size.

Rejected broad skip experiment:

| Quality | Corpus      | Bytes without 4-byte | Google bytes | Overhead | Native ms |
| ------- | ----------- | -------------------- | ------------ | -------- | --------- |
| 5       | silesia-64k | 22,542               | 22,271       | 1.22%    | 194.418   |
| 6       | silesia-1m  | 288,629              | 269,636      | 7.04%    | n/a       |
| 7       | silesia-1m  | 281,225              | 267,096      | 5.29%    | n/a       |

Accepted conditional skip validation:

```nu
moon fmt
moon check --target all
moon test --target native --filter '*q0 through q11 round-trip*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 6,7 --json
nu -c 'for q in 6..7 {
  print $"QUALITY=($q)"
  nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
    --mode encode \
    --quality $q \
    --targets wasm-gc,native \
    --repeats 1 \
    --samples 1 \
    --json
}'
```

Results:

| Quality | Corpus      | Previous bytes | New bytes | Google bytes | Previous ms | New ms  | Target  |
| ------- | ----------- | -------------- | --------- | ------------ | ----------- | ------- | ------- |
| 6       | silesia-1m  | 278,961        | 278,961   | 269,636      | n/a         | n/a     | ratio   |
| 7       | silesia-1m  | 273,633        | 273,633   | 267,096      | n/a         | n/a     | ratio   |
| 6       | silesia-64k | 22,336         | 22,542    | 22,121       | 556.699     | 514.744 | wasm-gc |
| 6       | silesia-64k | 22,336         | 22,542    | 22,121       | 143.404     | 126.045 | native  |
| 7       | silesia-64k | 22,261         | 22,373    | 22,101       | 550.708     | 524.353 | wasm-gc |
| 7       | silesia-64k | 22,261         | 22,373    | 22,101       | 153.878     | 139.976 | native  |

Conclusion: this is a useful small-input runtime tradeoff. It preserves the
1 MiB q6/q7 ratio results, keeps the 64 KiB ratio inside 5%, and reduces the
sampled native encode time by 12.1% for q6 and 9.0% for q7.

## 2026-05-28 — Rejected q5 Lighter Intermediate Config

The q5 runtime follow-up tried the lighter q4-style intermediate hash config:
8 hash-chain checks, 100,000-command cap, and 6-byte minimum match. This
reduces the intermediate parser work, but it spends too much of the remaining
ratio margin and does not improve native encode performance.

Validation commands:

```nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 5 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 5 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Trial result:

| Corpus      | Target  | Accepted bytes | Trial bytes | Google bytes | Accepted ms | Trial ms | Decision |
| ----------- | ------- | -------------- | ----------- | ------------ | ----------- | -------- | -------- |
| silesia-1m  | ratio   | 278,961        | 287,092     | 274,088      | n/a         | n/a      | reject   |
| silesia-64k | wasm-gc | 22,336         | 22,785      | 22,271       | 541.752     | 535.757  | reject   |
| silesia-64k | native  | 22,336         | 22,785      | 22,271       | 142.394     | 145.131  | reject   |

Conclusion: q5 keeps the accepted 16-check, 180,000-command, 5-byte-minimum
intermediate path. The trial moved 1 MiB q5 overhead from 1.78% to 4.74%,
increased 64 KiB output from 22,336 to 22,785 bytes, and regressed native
encode time from 142.394 to 145.131 ms/op. The small wasm-gc improvement is
not enough to justify the size and native-runtime tradeoff.

## 2026-05-28 — q5 Natural 4-Byte Candidate Skip

q5 still keeps the intermediate 4-byte hash candidate because it wins the
accepted q5 stream. The natural 4-byte candidate, however, is redundant on the
measured Silesia slices: removing only that candidate preserves the q5 output
while cutting one parser/candidate-writer pass.

Validation commands:

```nu
moon fmt
moon check --target all
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 5 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 5 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Results:

| Corpus      | Target  | Previous bytes | New bytes | Google bytes | Previous ms | New ms  |
| ----------- | ------- | -------------- | --------- | ------------ | ----------- | ------- |
| silesia-1m  | ratio   | 278,961        | 278,961   | 274,088      | n/a         | n/a     |
| silesia-64k | wasm-gc | 22,336         | 22,336    | 22,271       | 541.752     | 524.160 |
| silesia-64k | native  | 22,336         | 22,336    | 22,271       | 142.394     | 94.185  |

Conclusion: this is an accepted q5 runtime improvement. The measured 1 MiB
ratio stays at +1.78% versus Google, the 64 KiB output stays at +0.29%, and
sampled native encode improves by 33.9% while wasm-gc improves by 3.2%.

## 2026-05-28 — Rejected Three-Literal-Block LZ77 Split

The next P3 block-clustering trial added a bounded three-literal-block LZ77
candidate. The estimator considered split pairs at `(1/4, 1/2)`, `(1/4, 3/4)`,
and `(1/2, 3/4)` of the command literal stream, then exact-costed a candidate
with three literal block types when the estimated literal entropy saving could
cover the extra block/context metadata.

Validation commands:

```nu
moon fmt
moon check --target all
moon test --target native --filter '*splits LZ77 command literal blocks*'
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 9 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 9 --json
```

Trial result:

| Corpus      | Target  | Accepted bytes | Trial bytes | Google bytes | Accepted ms | Trial ms   | Decision |
| ----------- | ------- | -------------- | ----------- | ------------ | ----------- | ---------- | -------- |
| silesia-1m  | ratio   | 271,776        | 271,776     | 263,791      | 48,703.919  | 52,258.807 | reject   |
| silesia-64k | wasm-gc | 21,514         | 21,514      | 22,063       | 530.562     | 504.737    | reject   |
| silesia-64k | native  | 21,514         | 21,514      | 22,063       | 128.080     | 130.972    | reject   |

Conclusion: this richer block-split candidate did not improve measured q9
size on either Silesia slice, and the native 64 KiB target-perf sample moved
slightly backward. The experiment was reverted. Future block/histogram work
should focus on clustering command and distance histograms together with
literal histograms, rather than adding more literal-only split shapes.

## 2026-05-28 — q10/q11 P4 Baseline Refresh

This refreshes the current q10/q11 evidence after the q5 and P3 exploration
commits. It is the baseline for the remaining P4 shortest-path/Zopfli work.

Validation commands:

```nu
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json
nu -c 'for q in [10 11] {
  print $"QUALITY=($q)"
  nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
    --mode encode \
    --quality $q \
    --targets wasm-gc,native \
    --repeats 1 \
    --samples 1 \
    --json
}'
```

1 MiB ratio:

| Quality | MoonBit bytes | Google bytes | Size overhead | MoonBit time ms | Google time ms |
| ------- | ------------- | ------------ | ------------- | --------------- | -------------- |
| 10      | 264,422       | 242,485      | 9.05%         | 63,742.891      | 519.757        |
| 11      | 264,422       | 239,314      | 10.49%        | 63,038.589      | 1,326.529      |

64 KiB target-perf:

| Quality | Target  | MoonBit bytes | Google bytes | Size overhead | Target ms | Google ms | Slowdown |
| ------- | ------- | ------------- | ------------ | ------------- | --------- | --------- | -------- |
| 10      | wasm-gc | 21,415        | 19,566       | 9.45%         | 510.253   | 62.649    | 8.14x    |
| 10      | native  | 21,415        | 19,566       | 9.45%         | 121.332   | 62.649    | 1.94x    |
| 11      | wasm-gc | 21,415        | 19,258       | 11.20%        | 547.539   | 115.586   | 4.74x    |
| 11      | native  | 21,415        | 19,258       | 11.20%        | 75.297    | 115.586   | 0.65x    |

Conclusion: P4 is still ratio-bound, not native-runtime-bound, on these
measured slices. q10/q11 share the same MoonBit stream and remain far outside
the documented 2% P4 ratio target. The next accepted P4 implementation needs
to reduce encoded size without reintroducing the rejected multi-second native
DP cost on 512 KiB to 1 MiB inputs.

## 2026-05-28 — Rejected q10-Only Wider Mixed Dictionary Transforms

This P4 trial widened only q10's mixed static-dictionary extra-transform set
from `[1, 4]` to `[1, 4, 16, 28, 47]`. q11 kept the accepted `[1, 4]` set to
avoid the large q11 native regression seen in the shared-transform trial.

Validation commands:

```nu
moon fmt
moon check --target all
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 10 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-128k.bin \
  --mode encode \
  --quality 10 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Trial result:

| Corpus       | Quality | Target  | Baseline bytes | Trial bytes | Google bytes | Baseline ms | Trial ms   | Decision |
| ------------ | ------- | ------- | -------------- | ----------- | ------------ | ----------- | ---------- | -------- |
| silesia-1m   | 10      | ratio   | 264,422        | 264,315     | 242,485      | 63,742.891  | 73,885.551 | reject   |
| silesia-1m   | 11      | ratio   | 264,422        | 264,422     | 239,314      | 63,038.589  | 62,264.133 | reject   |
| silesia-64k  | 10      | wasm-gc | 21,415         | 21,396      | 19,566       | 510.253     | 495.301    | reject   |
| silesia-64k  | 10      | native  | 21,415         | 21,396      | 19,566       | 121.332     | 118.007    | reject   |
| silesia-64k  | 11      | wasm-gc | 21,415         | 21,415      | 19,258       | 547.539     | 498.045    | reject   |
| silesia-64k  | 11      | native  | 21,415         | 21,415      | 19,258       | 75.297      | 79.021     | reject   |
| silesia-128k | 10      | wasm-gc | 38,713         | 38,681      | 35,624       | 172.893     | 703.386    | reject   |
| silesia-128k | 10      | native  | 38,713         | 38,681      | 35,624       | 91.262      | 97.858     | reject   |

Conclusion: the trial saved only 107 bytes on the 1 MiB q10 slice and 32 bytes
on the 128 KiB q10 slice, while the 1 MiB verifier time and 128 KiB native
target-perf moved backward. The experiment was reverted. Future q10/q11 ratio
work should avoid wider dictionary-transform scans unless they are paired with
a parser change that produces a larger size win and stable wasm-gc/native
runtime.

## 2026-05-28 — Rejected q10/q11 384-Check Parser Trial

This P4 trial increased q10/q11 high-quality hash-chain checks from 256 to
384. A follow-up narrowed the change to q10 only after q11 showed a native
small-input regression, but q10's medium-input target-perf also moved backward.

Validation commands:

```nu
moon fmt
moon check --target all
moon test --target native --filter '*alternate hash candidates exact-costed*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-1m.bin --qualities 10,11 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 10 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-128k.bin \
  --mode encode \
  --quality 10 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Trial result:

| Corpus       | Quality | Target  | Baseline bytes | Trial bytes | Google bytes | Baseline ms | Trial ms  | Decision |
| ------------ | ------- | ------- | -------------- | ----------- | ------------ | ----------- | --------- | -------- |
| silesia-1m   | 10      | ratio   | 264,422        | 263,700     | 242,485      | 63,742.891  | 80,391.065 | reject  |
| silesia-1m   | 11      | ratio   | 264,422        | 263,700     | 239,314      | 63,038.589  | 74,624.034 | reject  |
| silesia-64k  | 10      | wasm-gc | 21,415         | 21,408      | 19,566       | 510.253     | 499.135   | reject  |
| silesia-64k  | 10      | native  | 21,415         | 21,408      | 19,566       | 121.332     | 91.720    | reject  |
| silesia-64k  | 11      | wasm-gc | 21,415         | 21,408      | 19,258       | 547.539     | 523.260   | reject  |
| silesia-64k  | 11      | native  | 21,415         | 21,408      | 19,258       | 75.297      | 117.263   | reject  |
| silesia-128k | 10      | wasm-gc | 38,713         | 38,686      | 35,624       | 172.893     | 660.508   | reject  |
| silesia-128k | 10      | native  | 38,713         | 38,686      | 35,624       | 91.262      | 143.997   | reject  |

Conclusion: the 384-check parser bought a real but small 1 MiB q10/q11 size
win, and the 64 KiB q10 sample looked favorable. It was still rejected because
the same change regressed q11 native on 64 KiB and q10 wasm-gc/native on the
128 KiB target-perf slice. q10/q11 stay at 256 checks until a stronger
parser/cost-model change can produce a larger ratio win per unit of encoding
time.

## 2026-05-28 — Overlapping Back-Reference Decode Copy Fast Path

The decoder output builder already had fast paths for distance-1 runs and
non-overlapping back-references. This increment adds a general overlapping
copy fast path: copy the first distance-sized period once, then repeatedly
double the copied region with non-overlapping `blit_to` calls. This preserves
Brotli overlap semantics while avoiding one byte assignment per output byte
for periodic copies.

Validation commands:

```nu
moon fmt
moon check --target all
moon test --target native --filter '*copy_from_distance*'
moon test --target wasm-gc --filter '*copy_from_distance*'
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-1m.bin.google.q11.br \
  --mode decode \
  --expected target/brotli-bench/silesia-1m.bin \
  --targets wasm-gc,native \
  --repeats 3 \
  --samples 1 \
  --json
```

Target-perf result:

| Mode   | Corpus         | Target  | Baseline ms | New ms  | Delta  |
| ------ | -------------- | ------- | ----------- | ------- | ------ |
| decode | silesia-1m q11 | wasm-gc | 258.079     | 242.629 | -6.0%  |
| decode | silesia-1m q11 | native  | 40.152      | 27.770  | -30.8% |

Conclusion: this is an accepted decode speed improvement. It does not change
encoded size or stream semantics; it only accelerates output reconstruction for
overlapping periodic back-references.

## 2026-05-28 — Distance Ring Slot Simplification

The decoder distance ring has exactly four slots. Slot selection now uses
`index & 3` instead of `% 4` plus a negative-index correction branch. A
white-box test covers negative and positive wraparound, preserving the
short-distance-code semantics.

Validation commands:

```nu
moon fmt
moon check --target all
moon test --target native --filter '*initial implicit distance*'
moon test --target wasm-gc --filter '*initial implicit distance*'
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-1m.bin.google.q11.br \
  --mode decode \
  --expected target/brotli-bench/silesia-1m.bin \
  --targets wasm-gc,native \
  --repeats 3 \
  --samples 1 \
  --json
```

Target-perf result:

| Mode   | Corpus         | Target  | Previous ms | New ms  | Delta |
| ------ | -------------- | ------- | ----------- | ------- | ----- |
| decode | silesia-1m q11 | wasm-gc | 242.629     | 245.813 | +1.3% |
| decode | silesia-1m q11 | native  | 27.770      | 27.139  | -2.3% |

Conclusion: this is retained as an equivalent simplification with native
decode slightly faster in the sampled run and wasm-gc movement within the
noise range seen in same-day target-perf samples. Encoded size and stream
semantics are unchanged.

## 2026-05-29 — Chunked Encoder State Carry Fix

Broader validation found that q3/q5 multi-meta-block streams could be corrupt
even though each 1 MiB chunk encoded and decoded correctly in isolation. The
root cause was chunk-local encoder state: exact-costed LZ77 candidates started
from the RFC initial recent-distance cache, and UTF-8 literal-context writers
assumed the previous two decoded bytes were zero at every meta-block boundary.
The decoder instead carries both pieces of state across compressed
meta-blocks.

The encoder now wraps exact-costed command streams with their terminal
recent-distance cache, commits only the accepted compressed candidate's cache,
and passes the previous two output bytes into UTF-8 context frequency and
payload selection. Dictionary copies remain cache-neutral; interleaved LZ77
copies inside the mixed dictionary path carry cache state normally.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*UTF-8 context literal trees*'
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 3
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 5
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 9
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 2,5,9 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 5 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Correctness and ratio result:

| Corpus      | Quality | MoonBit bytes | Google bytes | Overhead | Google decode |
| ----------- | ------- | ------------- | ------------ | -------- | ------------- |
| silesia-2m  | 3       | 629,531       | n/a          | n/a      | pass          |
| silesia-2m  | 5       | 555,326       | 538,906      | +3.05%   | pass          |
| silesia-2m  | 9       | 542,335       | 511,433      | +6.04%   | pass          |

Target-perf result:

| Mode   | Corpus      | Quality | Target  | MoonBit bytes | Google bytes | MoonBit ms | Google ms |
| ------ | ----------- | ------- | ------- | ------------- | ------------ | ---------- | --------- |
| encode | silesia-64k | 5       | wasm-gc | 22,336        | 22,271       | 511.803    | 38.048    |
| encode | silesia-64k | 5       | native  | 22,336        | 22,271       | 96.357     | 38.048    |

Conclusion: this is an accepted correctness fix. It restores externally
decodable q3/q5/q9 chunked compressed streams without changing the 64 KiB q5
target-perf size. P3 remains open because the broader 2 MiB Silesia sweep shows
q2 at +8.77% and q9 at +6.04%, outside the 5% ratio target.

## 2026-05-29 — q9 Two-Mebibyte Standard Chunk

The q9 2 MiB ratio gap was caused in part by forcing high-quality parsing
through two independent 1 MiB meta-block chunks. This increment lets q9 use a
2 MiB standard chunk while keeping q2..q8 and q10/q11 at the existing 1 MiB
chunk size until they have separate target-perf evidence. High-quality LZ77 and
mixed-dictionary candidates now admit 2 MiB inputs; fast and intermediate
profiles keep the 1 MiB input bound.

A q9 64K hash-table trial was rejected before this change: increasing the q9
high-quality table from 32K to 64K produced the same 271,776-byte
`silesia-1m.bin` output and did not address the chunk boundary.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*two-mebibyte high-quality chunks*'
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 9
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 9 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 9 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Correctness and ratio result:

| Corpus     | Quality | Previous bytes | New bytes | Google bytes | Previous overhead | New overhead | Google decode |
| ---------- | ------- | -------------- | --------- | ------------ | ----------------- | ------------ | ------------- |
| silesia-2m | 9       | 542,335        | 535,421   | 511,433      | +6.04%            | +4.69%       | pass          |

Target-perf result:

| Mode   | Corpus      | Quality | Target  | MoonBit bytes | Google bytes | MoonBit ms | Google ms |
| ------ | ----------- | ------- | ------- | ------------- | ------------ | ---------- | --------- |
| encode | silesia-64k | 9       | wasm-gc | 21,514        | 22,063       | 523.417    | 42.139    |
| encode | silesia-64k | 9       | native  | 21,514        | 22,063       | 89.076     | 42.139    |

Conclusion: this is an accepted P3 ratio improvement. q9 now meets the 5%
target on the measured 2 MiB Silesia slice. P3 remains open because q2 is still
outside the 2 MiB ratio target and broader block/histogram clustering remains
unfinished.

## 2026-05-29 — q2 Two-Mebibyte Standard Chunk

The same larger-chunk strategy also applies to q2 after scaling the q2 natural
parser command budget with the doubled input bound. A first q2 2 MiB chunk
trial without the larger command budget fell back to a stored meta-block
(`2,097,157` bytes), so this increment keeps the q2 fast profile but raises its
large-chunk command cap from 52,000 to 104,000 commands. q3..q8 and q10/q11
remain at their existing 1 MiB standard chunk size.

Validation commands:

```nu
moon check --target native
nu tools/brotli/encode/verify.nu target/brotli-bench/silesia-2m.bin --quality 2
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 2 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 2 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

Correctness and ratio result:

| Corpus     | Quality | Previous bytes | New bytes | Google bytes | Previous overhead | New overhead | Google decode |
| ---------- | ------- | -------------- | --------- | ------------ | ----------------- | ------------ | ------------- |
| silesia-2m | 2       | 693,243        | 652,695   | 637,343      | +8.77%            | +2.41%       | pass          |

Target-perf result:

| Mode   | Corpus      | Quality | Target  | MoonBit bytes | Google bytes | MoonBit ms | Google ms |
| ------ | ----------- | ------- | ------- | ------------- | ------------ | ---------- | --------- |
| encode | silesia-64k | 2       | wasm-gc | 25,245        | 24,364       | 480.975    | 36.015    |
| encode | silesia-64k | 2       | native  | 25,245        | 24,364       | 75.117     | 36.015    |

Conclusion: this is an accepted P3 ratio improvement. q2 now meets the 5%
target on the measured 2 MiB Silesia slice without changing the 64 KiB encoded
size. P3's remaining ratio work is no longer the q2/q9 2 MiB gap; it is the
broader block/histogram clustering and release validation matrix.

## 2026-05-29 — q3 through q8 Two-Mebibyte Standard Chunks

The q2/q9 2 MiB chunk strategy also pays for the remaining P3 qualities. This
increment lets q3..q8 use 2 MiB standard chunks and extends the natural and
intermediate parser input bounds to 2 MiB. Command budgets remain unchanged for
chunks up to 1 MiB; only larger chunks scale the budget by chunk length. This
preserves the small-input profile while avoiding stored fallbacks when two
formerly separate chunks are costed together.

Validation commands:

```nu
moon check --target native
moon test --target native --filter '*two-mebibyte chunks*'
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 3,5,8 --json
nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-2m.bin --qualities 4,6,7 --json
nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin \
  --mode encode \
  --quality 8 \
  --targets wasm-gc,native \
  --repeats 1 \
  --samples 1 \
  --json
```

2 MiB ratio results:

| Quality | MoonBit bytes | Google bytes | Size overhead | Google decode |
| ------- | ------------- | ------------ | ------------- | ------------- |
| 3       | 617,687       | 623,577      | -0.94%        | pass          |
| 4       | 566,718       | 569,163      | -0.43%        | pass          |
| 5       | 549,625       | 538,906      | 1.99%         | pass          |
| 6       | 549,625       | 527,485      | 4.20%         | pass          |
| 7       | 537,621       | 520,020      | 3.38%         | pass          |
| 8       | 537,621       | 514,598      | 4.47%         | pass          |

Representative 64 KiB target-perf result:

| Mode   | Corpus      | Quality | Target  | MoonBit bytes | Google bytes | MoonBit ms | Google ms |
| ------ | ----------- | ------- | ------- | ------------- | ------------ | ---------- | --------- |
| encode | silesia-64k | 8       | wasm-gc | 22,261        | 22,077       | 524.749    | 42.872    |
| encode | silesia-64k | 8       | native  | 22,261        | 22,077       | 112.349    | 42.872    |

Conclusion: this is an accepted P3 ratio improvement. The measured 2 MiB
Silesia q2..q9 matrix is now inside the 5% target window. P3 still needs the
planned broader block/histogram clustering and release validation corpus before
being treated as fully complete.

## 2026-05-29 — P4 Heuristic Optimization Stop Point

This is the stop point for local q10/q11 heuristic optimization before release
validation. The current q10/q11 encoder is valid and externally decodable, but
it is still a high-quality greedy/hash-chain implementation rather than the
documented Zopfli/shortest-path backend. The measured gap is too large to close
with the small knobs tried so far, and the rejected trials show an unfavorable
size-per-runtime tradeoff.

Current P4 baseline kept for release validation:

| Corpus      | Quality | MoonBit bytes | Google bytes | Size overhead |
| ----------- | ------- | ------------- | ------------ | ------------- |
| silesia-1m  | 10      | 264,422       | 242,485      | +9.05%        |
| silesia-1m  | 11      | 264,422       | 239,314      | +10.49%       |
| silesia-64k | 10      | 21,415        | 19,566       | +9.45%        |
| silesia-64k | 11      | 21,415        | 19,258       | +11.20%       |

Current 64 KiB target-perf baseline:

| Mode   | Corpus      | Quality | Target  | MoonBit ms | Google ms | Slowdown |
| ------ | ----------- | ------- | ------- | ---------- | --------- | -------- |
| encode | silesia-64k | 10      | wasm-gc | 510.253    | 62.649    | 8.14x    |
| encode | silesia-64k | 10      | native  | 121.332    | 62.649    | 1.94x    |
| encode | silesia-64k | 11      | wasm-gc | 547.539    | 115.586   | 4.74x    |
| encode | silesia-64k | 11      | native  | 75.297     | 115.586   | 0.65x    |

Rejected q10/q11 heuristic work remains the governing evidence:

- Wider q10 mixed-dictionary transforms saved only 107 bytes on
  `silesia-1m.bin` q10 and 32 bytes on `silesia-128k.bin` q10, while the
  128 KiB native target-perf sample moved from 91.262 to 97.858 ms/op and the
  1 MiB verifier time increased.
- A 384-check parser improved q10/q11 1 MiB output from 264,422 to 263,700
  bytes, but q10 128 KiB target-perf regressed from 91.262/172.893 ms/op
  native/wasm-gc to 143.997/660.508 ms/op, and q11 64 KiB native regressed
  from 75.297 to 117.263 ms/op.
- A bounded shortest-path DP prototype improved 1 MiB q10/q11 output from
  266,056 to 263,496 bytes, but native debug encode target-perf regressed from
  4,275.087 to 18,179.669 ms and the prototype lacked recent-distance-cache
  state, so it was not commit-ready.

Conclusion: stop speculative q10/q11 heuristic optimization here. The next P4
implementation work must be a real bounded shortest-path/Zopfli backend with
recent-distance-cache state and explicit memory caps, or the release must carry
an explicit P4 ratio exception. Release validation can proceed against the
current q10/q11 implementation with this limitation documented.

## 2026-05-29 — Release Validation Checkpoint

This checkpoint validates the current Brotli implementation after the q2..q9
2 MiB chunk promotion and the q10/q11 heuristic stop decision. It is a practical
local release-validation gate, not the 24-hour fuzz gate.

MoonBit all-target gate:

```bash
moon fmt
moon check --target all
moon test --target all
moon info
git diff --check
```

Result: passed. The test matrix reported 458 passed / 0 failed on each of
`wasm`, `wasm-gc`, `js`, and `native`.

External Google Brotli decode validation:

| Corpus      | Quality | MoonBit bytes | Google bytes | Size overhead | Google decode |
| ----------- | ------- | ------------- | ------------ | ------------- | ------------- |
| silesia-2m  | 0       | 2,097,157     | n/a          | n/a           | pass          |
| silesia-2m  | 1       | 2,097,157     | n/a          | n/a           | pass          |
| silesia-2m  | 2       | 652,695       | 637,343      | +2.41%        | pass          |
| silesia-2m  | 3       | 617,687       | 623,577      | -0.94%        | pass          |
| silesia-2m  | 4       | 566,718       | 569,163      | -0.43%        | pass          |
| silesia-2m  | 5       | 549,625       | 538,906      | +1.99%        | pass          |
| silesia-2m  | 6       | 549,625       | 527,485      | +4.20%        | pass          |
| silesia-2m  | 7       | 537,621       | 520,020      | +3.38%        | pass          |
| silesia-2m  | 8       | 537,621       | 514,598      | +4.47%        | pass          |
| silesia-2m  | 9       | 535,421       | 511,433      | +4.69%        | pass          |
| silesia-1m  | 10      | 264,422       | 242,485      | +9.05%        | pass          |
| silesia-1m  | 11      | 264,422       | 239,314      | +10.49%       | pass          |

Representative 64 KiB encode target-perf:

| Quality | Target  | MoonBit bytes | Google bytes | Size overhead | MoonBit ms | Google ms | Slowdown |
| ------- | ------- | ------------- | ------------ | ------------- | ---------- | --------- | -------- |
| 2       | wasm-gc | 25,245        | 24,364       | +3.62%        | 498.394    | 39.787    | 12.53x   |
| 2       | native  | 25,245        | 24,364       | +3.62%        | 114.186    | 39.787    | 2.87x    |
| 8       | wasm-gc | 22,261        | 22,077       | +0.83%        | 525.977    | 42.859    | 12.27x   |
| 8       | native  | 22,261        | 22,077       | +0.83%        | 110.541    | 42.859    | 2.58x    |
| 9       | wasm-gc | 21,514        | 22,063       | -2.49%        | 513.957    | 44.435    | 11.57x   |
| 9       | native  | 21,514        | 22,063       | -2.49%        | 87.947     | 44.435    | 1.98x    |
| 10      | wasm-gc | 21,415        | 19,566       | +9.45%        | 497.344    | 62.929    | 7.90x    |
| 10      | native  | 21,415        | 19,566       | +9.45%        | 117.832    | 62.929    | 1.87x    |
| 11      | wasm-gc | 21,415        | 19,258       | +11.20%       | 518.946    | 107.217   | 4.84x    |
| 11      | native  | 21,415        | 19,258       | +11.20%       | 122.539    | 107.217   | 1.14x    |

Representative decode target-perf:

| Input stream              | Target  | Encoded bytes | Decoded bytes | MoonBit ms | Google ms | Slowdown |
| ------------------------- | ------- | ------------- | ------------- | ---------- | --------- | -------- |
| silesia-1m Google q11 `.br` | wasm-gc | 239,314       | 1,048,576     | 709.926    | 80.475    | 8.82x    |
| silesia-1m Google q11 `.br` | native  | 239,314       | 1,048,576     | 142.882    | 80.475    | 1.78x    |

Decoder robustness gates:

- `nu tools/brotli/conformance/run.nu`: all 22 upstream Google Brotli fixtures
  passed through `unbrotli_sync`.
- `nu tools/brotli/fuzz/run.nu --limit 25`: all 25 local fuzz inputs passed
  without native panic or unchecked bounds failure.

Conclusion: the current q0..q11 streams are externally decodable, and the
measured q2..q9 2 MiB Silesia matrix is inside the P3 5% target window. q10/q11
remain valid but outside the P4 2% ratio target, so this release checkpoint
requires the documented P4 ratio exception. Local heuristic optimization can
stop here; remaining release work should focus on broader corpus validation,
the long fuzz gate, and packaging/release checks.

## 2026-05-29 — Batched Fuzz Runner Release Gate

The decoder fuzz runner now writes multiple generated white-box tests into the
temporary `src/brotli_fuzz_wbtest.mbt` file and invokes `moon test` once per
batch. This keeps the same semantic check for each input: `unbrotli_sync` may
return decoded bytes or a typed `FzipError`, but native panics and unchecked
bounds failures still fail the run.

Fuzz-runner timing on the current corpus:

| Command | Inputs | Batch size | Result | Wall time |
| ------- | ------ | ---------- | ------ | --------- |
| `nu tools/brotli/fuzz/run.nu --limit 25` before batching | 25 | 1 | pass | 54.73s |
| `nu tools/brotli/fuzz/run.nu --limit 25` after batching | 25 | 25 | pass | 2.19s |
| `nu tools/brotli/fuzz/run.nu` after batching | 58 | 25 | pass | 7.00s |

The 25-input local gate is 25.0x faster by wall clock, and the full checked-in
corpus now runs comfortably as a local release gate. This does not replace the
documented 24-hour fuzz requirement for final release readiness; it removes the
per-input `moon test` overhead that made broader local fuzz sweeps needlessly
expensive.

## 2026-05-29 — Cross-Target Fuzz Runner Gate

The fuzz runner now accepts `--target`, forwarding it to `moon test --target`.
This keeps the default `native` behavior for local decoder robustness sweeps
while allowing release validation to run the same generated fuzz tests on
`wasm-gc`, `js`, or `all` without editing the script.

Validation:

| Command | Result |
| ------- | ------ |
| `nu tools/brotli/fuzz/run.nu --limit 2 --batch-size 1 --target native` | 2/2 passed |
| `nu tools/brotli/fuzz/run.nu --limit 5 --target wasm-gc` | 5/5 passed |
| `nu tools/brotli/fuzz/run.nu --limit 3 --target all` | 3/3 passed |

This is a release-readiness tooling change only. It does not change Brotli
encode/decode behavior or the recorded codec target-perf baseline.

## 2026-05-29 — Encoder Roundtrip Fuzz Harness

Added `tools/brotli/fuzz/roundtrip.nu` as the encoder-side fuzz companion to
the decoder robustness runner. It generates deterministic byte inputs, encodes
each input with selected Brotli quality levels, decodes the result with
`unbrotli_sync`, and asserts byte-for-byte equality.

Default release-oriented coverage:

- q0/q1 stored meta-blocks.
- q2 standard compressed path.
- q9 high-quality P3 path.
- q11 current P4 release-exception path.
- configurable MoonBit targets via `--target`.

Validation:

| Command | Result |
| ------- | ------ |
| `nu tools/brotli/fuzz/roundtrip.nu --count 2 --qualities 0,2 --target native --batch-size 2` | 4/4 passed |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --target native` | 20/20 passed |
| `nu tools/brotli/fuzz/roundtrip.nu --count 3 --max-len 256 --qualities 2,11 --target wasm-gc` | 6/6 passed |

This expands release-readiness coverage without changing Brotli encode/decode
implementation or the recorded codec target-perf baseline.

## 2026-05-29 — Fuzz Harness Stale-Lock Recovery

The decoder and encoder roundtrip fuzz runners now record the owner PID in
`tools/brotli/.harness-lock/pid`. A second active harness is still rejected,
but a lock left behind by an interrupted or crashed run is detected as stale,
removed, and reacquired.

Validation:

| Scenario | Command | Result |
| -------- | ------- | ------ |
| Stale lock recovery | create `.harness-lock/pid` with dead PID `999999`, then run `nu tools/brotli/fuzz/run.nu --limit 1 --target native` | 1/1 passed |
| Active lock protection | create `.harness-lock/pid` from a live `sleep` process, then run `nu tools/brotli/fuzz/run.nu --limit 1 --target native` | rejected with owner PID |
| Roundtrip harness normal lock path | `nu tools/brotli/fuzz/roundtrip.nu --count 2 --qualities 2,11 --target native --batch-size 2` | 4/4 passed |

This makes local release validation more robust after intentional interrupts
without weakening the mutual exclusion around temporary generated MoonBit
white-box test files.

## 2026-05-29 — Release Validation Runner

Added `tools/brotli/release/validate.nu` as the practical Brotli release gate.
The script runs the same categories currently used for the release checkpoint:

- `moon fmt`, `moon check --target all`, `moon test --target all`,
  `moon info`, and `git diff --check`.
- Upstream Google Brotli conformance fixtures.
- q0/q1 external decode validation on the 2 MiB Silesia slice.
- q2..q9 2 MiB ratio validation plus external decode validation.
- q10/q11 1 MiB external decode validation with the documented P4 ratio
  exception.
- Decoder fuzz corpus and encoder roundtrip fuzz.

Validation:

| Command | Result |
| ------- | ------ |
| `nu --ide-check 0 tools/brotli/release/validate.nu` | parsed successfully |
| `nu tools/brotli/release/validate.nu --skip-moon --skip-ratio --decoder-fuzz-limit 2 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2 --roundtrip-target native` | conformance, decoder fuzz, and encoder roundtrip fuzz passed |

The release runner intentionally does not call `target-perf.nu` by default.
Target-perf remains the decision harness for codec changes, while this script
keeps release validation reproducible for correctness and documented ratio
coverage.

## 2026-05-29 — Release Packaging Gate

The practical release runner now includes package validation by default, and
the repo `Justfile` exposes focused Brotli release entries:

- `just brotli-release`
- `just brotli-release-smoke`
- `just brotli-release-package`

`moon package --dry-run` is not implemented by the current toolchain, so the
package gate uses `moon package` plus `moon publish --dry-run`. The publish
dry-run validates the packaged zip, extracts it, and runs `moon check` against
the extracted package. Because version `0.8.0` already exists upstream, the
dry-run ends with a duplicate-version 409; the release runner treats that exact
case as success only when the packaged-zip extraction and check have already
passed.

Validation:

| Command | Result |
| ------- | ------ |
| `just --list` | lists `brotli-release`, `brotli-release-smoke`, and `brotli-release-package` |
| `just brotli-release-smoke` | decoder fuzz corpus and encoder roundtrip fuzz passed |
| `just brotli-release-package` | `moon package` and `moon publish --dry-run` package verification passed |

This is release-readiness tooling only; it does not change Brotli encode/decode
behavior or the recorded codec target-perf baseline.

## 2026-05-29 — Long Fuzz Soak Runner

Added `tools/brotli/fuzz/soak.nu` as a repeatable runner for the long Brotli
fuzz gate. Each iteration runs the decoder fuzz corpus and encoder roundtrip
fuzz harness, appends a JSONL status row to
`target/brotli-fuzz-soak/soak.jsonl`, and stops at the configured duration or
iteration limit. The default duration is 1,440 minutes for the documented
24-hour soak gate.

Justfile entries:

- `just brotli-fuzz-soak`
- `just brotli-fuzz-soak-smoke`

Validation:

| Command | Result |
| ------- | ------ |
| `nu --ide-check 0 tools/brotli/fuzz/soak.nu` | parsed successfully |
| `just --list` | lists `brotli-fuzz-soak` and `brotli-fuzz-soak-smoke` |
| `just brotli-fuzz-soak-smoke` | one decoder fuzz iteration and one encoder roundtrip fuzz iteration passed |

This scripts the long fuzz requirement but does not claim that a 24-hour soak
has already completed.

## 2026-05-29 — Deterministic Fuzz Corpus Generation

`tools/brotli/fuzz/gen-corpus.nu` now uses a seed-driven linear congruential
generator instead of Nushell's process-random commands. The script accepts
`--seed` and `--corpus-dir`, so release validation can reproduce a corpus
exactly or generate throwaway corpora outside the ignored default corpus
directory.

The implementation uses Nushell `generate` to thread PRNG state through both
byte generation and mutation generation, keeping the state transition explicit
and avoiding ad hoc mutable random loops.

Validation:

| Command | Result |
| ------- | ------ |
| `nu --ide-check 0 tools/brotli/fuzz/gen-corpus.nu` | parsed successfully |
| generate two corpora with `--count 12 --seed 12345` under separate `target/` directories and compare sorted SHA-256 manifests | identical |
| `nu tools/brotli/fuzz/run.nu --corpus-dir target/brotli-fuzz-determinism-a --target native --batch-size 10` | 20/20 passed |

This improves release-validation reproducibility without changing Brotli
encode/decode behavior or the recorded codec target-perf baseline.

## 2026-05-29 — Generated Fuzz Corpus Release Gate

The practical release runner now accepts generated deterministic decoder fuzz
corpus options:

- `--generated-fuzz-count`
- `--generated-fuzz-seed`
- `--generated-fuzz-dir`

When `--generated-fuzz-count` is greater than zero, the release runner first
calls `tools/brotli/fuzz/gen-corpus.nu`, then runs the decoder fuzz harness
against that generated corpus. The repo `Justfile` exposes this as:

```nu
just brotli-release-generated-fuzz
```

Validation:

| Command | Result |
| ------- | ------ |
| `nu --ide-check 0 tools/brotli/release/validate.nu` | parsed successfully |
| `just --list` | lists `brotli-release-generated-fuzz` |
| `nu tools/brotli/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-package --generated-fuzz-count 12 --generated-fuzz-seed 12345 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2` | generated 20 decoder fuzz inputs, decoder fuzz passed, encoder roundtrip fuzz passed |

This wires the reproducible corpus generator into release validation without
changing Brotli encode/decode behavior or the recorded codec target-perf
baseline.

## 2026-05-29 — Broader Release Fuzz Validation

The generated-corpus release gate now has a broader local release-validation
run using the default Justfile entry:

```nu
just brotli-release-generated-fuzz
```

Result:

| Step | Result | Elapsed ms |
| ---- | ------ | ---------- |
| generate deterministic decoder fuzz corpus | pass | 210.55 |
| decoder fuzz corpus | pass | 90,822.64 |
| encoder roundtrip fuzz | pass | 14,357.89 |

This generated 1,000 deterministic mutations with seed `1`, copied the 8
checked-in `.br` seed fixtures into `target/brotli-release-fuzz-corpus`, ran
the decoder fuzz harness over the generated corpus, and then ran the default
encoder roundtrip fuzz quality set.

The bounded soak runner also passed a multi-iteration local execution:

```nu
nu tools/brotli/fuzz/soak.nu --duration-min 1440 --max-iterations 3
```

The repo Justfile now exposes the same full-corpus bounded soak shape as:

```nu
just brotli-fuzz-soak-bounded
```

Result:

| Phase | Iterations | Result |
| ----- | ---------- | ------ |
| decoder fuzz | 3 | pass |
| encoder roundtrip fuzz | 3 | pass |

The soak log contained 6 successful JSONL rows in
`target/brotli-fuzz-soak/soak.jsonl`, and no temporary harness lock or
generated white-box test file remained afterward.

This strengthens release-validation evidence without changing Brotli
encode/decode behavior or the recorded codec target-perf baseline. It is not a
claim that the reserved 24-hour soak gate has completed.

## 2026-05-29 — Release Candidate Aggregate Recipes

The repo `Justfile` now exposes aggregate release-candidate entries that chain
the accepted local release gates:

```nu
just brotli-release-candidate
just brotli-release-candidate-smoke
```

`brotli-release-candidate` runs the full practical release gate, the generated
deterministic decoder fuzz gate, and the bounded full-corpus soak. The smoke
variant runs the corresponding quick gates so the aggregate wiring can be
validated without rerunning the full ratio matrix.

Validation:

| Command | Result |
| ------- | ------ |
| `just brotli-release-candidate-smoke` | release smoke, generated-corpus smoke, and soak smoke passed |
| `just brotli-release-candidate` | full practical gate, generated deterministic corpus gate, and bounded full-corpus soak passed |

The full candidate run passed the q2..q9 2 MiB ratio/decode matrix, q10/q11
ratio-exception decode, package verification, 1,000-mutation generated decoder
fuzz, default encoder roundtrip fuzz, and 3 bounded soak iterations. The final
soak log contained 6 successful rows and left no temporary harness files.

This is release-validation tooling only; it does not change Brotli
encode/decode behavior or the recorded codec target-perf baseline.

## 2026-05-30 — q10/q11 Chunked Mixed-Candidate Dedup

The chunked q10/q11 path no longer builds the mixed static-dictionary LZ77
command stream twice. Previously it first built a default-cache command list
only to test whether mixed dictionary work might apply, then rebuilt the same
candidate with the real carried distance cache. The encoder now builds the
real `BrotliCommandCandidate` once and exact-costs that candidate directly.

This is an encode-performance change for q10/q11 chunks larger than 64 KiB.
It does not change the measured output stream on the 128 KiB Silesia sample.

128 KiB q10/q11 ratio:

| Quality | MoonBit bytes | Google bytes | Overhead |
| ------- | ------------- | ------------ | -------- |
| q10     | 38,713        | 35,624       | +8.67%   |
| q11     | 38,713        | 35,164       | +10.09%  |

128 KiB encode target-perf, before -> after:

| Quality | Target  | Before ms/op | After ms/op | MoonBit bytes |
| ------- | ------- | ------------ | ----------- | ------------- |
| q10     | wasm-gc | 217.776      | 172.439     | 38,713        |
| q10     | native  | 456.867      | 295.990     | 38,713        |
| q11     | wasm-gc | 225.682      | 169.021     | 38,713        |
| q11     | native  | 454.461      | 314.528     | 38,713        |

Representative decode target-perf on the Google q11 128 KiB stream is
unchanged by this encoder-only change: wasm-gc 70.856 ms/op and native
`cc-o0` 79.969 ms/op, both versus Google 44.710 ms/op.

Validation:

| Command | Result |
| ------- | ------ |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes versus Google 35,624/35,164 |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `moon fmt && moon check --target all && moon test --target all && moon info && git diff --check` | all-target check passed; 469 tests passed on wasm, wasm-gc, js, and native; generated interface check passed |

## 2026-05-29 — q10/q11 Bounded Shortest-Path Seed

The q10/q11 encoder now tries a small-input bounded shortest-path command
candidate before the existing high-quality mixed-dictionary candidate. The
parser uses one longest hash-chain match per position and a bounded set of
copy lengths, then hands the generated command list to the exact meta-block
writer. The outer chunk selector still chooses by final bit count, so this
cannot replace a smaller existing candidate.

This is a conservative P4 seed, not the full `docs/brotli.md` Zopfli/suffix-tree
backend. It is capped at 32 KiB inputs and leaves the q10/q11 release ratio
exception in place.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded shortest-path*'` | passed; the bounded candidate writes a decodable final meta-block and q10 public roundtrip passes |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |
| `moon check --target all && moon test --target all` | all-target check passed; 461 tests passed on wasm, wasm-gc, js, and native |

`target-perf.nu` was not rerun for this increment per the latest maintainer
instruction; the 128 KiB Silesia sample is larger than the 32 KiB candidate
cap and shows no size change.

## 2026-05-29 — q10/q11 Bounded Multi-Match Seed

The bounded q10/q11 shortest-path seed now enumerates multiple previous
hash-chain matches per position instead of considering only the single longest
match. Each match still contributes only a bounded set of representative copy
lengths, and the resulting command list still goes through exact meta-block
costing before it can win chunk selection.

This moves the small-input seed closer to the planned P4 Zopfli candidate graph
without lifting the 32 KiB input cap or claiming completion of the full
suffix-tree/Zopfli backend.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded shortest-path*'` | passed; 2/2 tests cover bounded command roundtrip and multiple previous-match enumeration |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |
| `moon check --target all` | passed |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-29 — q10/q11 Bounded Recent-Distance State

The q10/q11 bounded shortest-path seed now carries the selected path's
recent-distance cache at each DP position. Literal transitions inherit the
cache unchanged, copy transitions update it with the same helper used by the
encoder, and subsequent match enumeration/copy-cost estimates use the cache for
that path. This lets the small-input seed model short-distance code savings
without expanding to a full multi-state Zopfli beam.

The candidate remains capped at 32 KiB and still goes through exact meta-block
costing before it can win chunk selection.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded shortest-path*'` | passed; 3/3 tests cover bounded command roundtrip, multiple previous-match enumeration, and recent-distance copy-cost modeling |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-30 — q10/q11 Bounded Two-State Beam

The q10/q11 bounded shortest-path seed now keeps a two-state beam at each input
position. Each retained state has its own estimated cost, recent-distance cache,
traceback slot, and chosen copy transition. Literal and copy transitions offer
successor states into the next position's two-slot beam, keeping only the two
lowest-cost states.

This is still a small-input seed: it remains capped at 32 KiB and exact-costed
before selection. It does not replace the full P4 suffix-tree/Zopfli backend,
but it removes the prior single-best-state limitation that could discard a
slightly more expensive path with a better recent-distance cache.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded shortest-path*'` | passed; 4/4 tests cover bounded command roundtrip, multiple previous-match enumeration, recent-distance copy-cost modeling, and two-state beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-30 — q10/q11 Greedy-Seeded Cost Model

The q10/q11 bounded shortest-path seed now initializes its lightweight parser
cost model from the current greedy LZ77 command stream. Literal and explicit
distance symbol frequencies are converted to Huffman code-length estimates, so
literal transitions and copy-distance transitions are guided by the same kind
of preliminary histogram information required by the P4 Zopfli plan. The
resulting command list still goes through exact meta-block costing before it
can win chunk selection.

This remains a bounded seed, not the full suffix-tree/Zopfli backend.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded shortest-path*'` | passed; 5/5 tests cover bounded command roundtrip, multiple-match enumeration, recent-distance costs, cost-model histograms, and two-state beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-30 — q10/q11 Bounded Suffix-Tree Match Source

The q10/q11 bounded shortest-path seed now has a second match provider: a
bounded suffix binary tree built over earlier positions in the current
meta-block. The tree is deliberately capped by the existing match-check budget
and remains a small-input seed for the full P4 suffix-tree/Zopfli backend.
Suffix-tree matches are offered into the same two-state beam and still go
through exact meta-block costing before selection.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded*'` | passed; 6/6 tests cover bounded command roundtrip, hash-chain multi-match enumeration, suffix-tree match enumeration, recent-distance costs, cost-model histograms, and beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-30 — q10/q11 Bounded Match Transition Cleanup

The q10/q11 bounded shortest-path seed now sends hash-chain and suffix-tree
matches through one shared bounded-copy transition helper. This is a
behavior-preserving P4 seed cleanup: both match providers still offer the same
minimum, half-length, and full-length copy candidates into the two-state beam,
with recent-distance-cache updates and exact-cost final meta-block selection
unchanged.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*bounded*'` | passed; 6/6 tests cover bounded command roundtrip, hash-chain multi-match enumeration, suffix-tree match enumeration, recent-distance costs, cost-model histograms, and beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native` | 8/8 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |

`target-perf.nu` was not rerun for this behavior-preserving cleanup per
maintainer instruction.

## 2026-05-29 — Command-Block Histogram Split Candidate

The q4+ LZ77 meta-block writer now estimates command-symbol histograms at the
1/4, 1/2, and 3/4 command boundaries. When the estimated command-tree payload
saving clears the block-header overhead guard, it writes an exact-costed
two-command-block candidate and selects it only if its final bit count beats
the existing weighted, literal-split, and context candidates.

This is the first accepted P3 block-clustering increment that changes command
block layout rather than only literal block or literal context layout.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter 'brotli_sync splits LZ77 command blocks by command histograms'` | passed; synthetic command-skew candidate beats the weighted single-command-tree writer and round-trips through `unbrotli_sync` |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json` | q5 40,328 bytes vs Google 40,515 (-0.46%); q9 39,081 bytes vs Google 39,695 (-1.55%) |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 5 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q5 output 22,336 bytes vs Google 22,271; wasm-gc/native min encode 81.122/52.656 ms |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q9 output 21,514 bytes vs Google 22,063; wasm-gc/native min encode 77.966/45.555 ms |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed |
| `moon check --target all && moon test --target all && moon info` | all-target check passed; 459 tests passed on wasm, wasm-gc, js, and native; public interface generation unchanged |

The Silesia 64 KiB and 128 KiB outputs are unchanged for the measured q5/q9
samples; the accepted value is structural coverage for command-block histogram
splitting with no measured size regression on these release samples.

## 2026-05-29 — Distance-Block Histogram Split Candidate

The q4+ LZ77 meta-block writer now also estimates explicit-distance histograms
at the 1/4, 1/2, and 3/4 distance-event boundaries. Distance block lengths
count only commands that read an explicit distance symbol, so recent-distance
short-code commands are skipped while collecting split candidates and while
emitting the block switch. The writer exact-costs a two-distance-block
candidate only when the estimated distance-tree payload saving clears the same
overhead guard used by the command-block split.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter 'brotli_sync splits LZ77 distance blocks by distance histograms'` | passed; synthetic distance-skew candidate beats the weighted single-distance-tree writer and round-trips through `unbrotli_sync` |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json` | q5 40,328 bytes vs Google 40,515 (-0.46%); q9 39,081 bytes vs Google 39,695 (-1.55%) |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 5 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q5 output 22,336 bytes vs Google 22,271; wasm-gc/native min encode 82.182/53.730 ms |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q9 output 21,514 bytes vs Google 22,063; wasm-gc/native min encode 79.780/47.608 ms |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed |
| `moon check --target all && moon test --target all && moon info` | all-target check passed; 460 tests passed on wasm, wasm-gc, js, and native; public interface generation unchanged |

The measured Silesia q5/q9 outputs remain unchanged; this increment extends P3
block clustering to the distance tree dimension with bounded extra search cost.

## 2026-05-30 — Command+Distance Block Split Candidate

The q4+ LZ77 meta-block writer now exact-costs a combined command-block plus
distance-block split candidate when both existing estimators find useful
boundaries. Unlike the rejected binary literal/command/distance joint split,
this candidate keeps the literal tree single, lets command and explicit-distance
block lengths use independent split boundaries, and still competes by final bit
count against the weighted, literal-split, context, command-only split, and
distance-only split candidates.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*splits LZ77*blocks*'` | passed; 4/4 tests cover literal, command, distance, and combined command+distance block split writers |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json` | q5 remains 40,328 bytes versus Google 40,515; q9 remains 39,081 bytes versus Google 39,695 |

`target-perf.nu` was not rerun for this structural block-layout increment per
maintainer instruction.

## 2026-05-30 — Literal+Command Block Split Candidate

The q4+ LZ77 meta-block writer now also exact-costs a combined literal-block
plus command-block split candidate. The candidate reuses the accepted literal
and command histogram estimators, but keeps independent boundaries: the
literal block switch is counted in inserted-literal events, and the command
block switch is counted in command events. It leaves distance blocks
single-tree, so this does not reintroduce the rejected binary
literal/command/distance joint split or the rejected three-literal-block trial.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*splits LZ77*blocks*'` | passed; 5/5 tests cover literal, command, distance, literal+command, and command+distance block split writers |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json` | q5 remains 40,328 bytes versus Google 40,515; q9 remains 39,081 bytes versus Google 39,695 |

`target-perf.nu` was not rerun for this structural block-layout increment per
maintainer instruction.

## 2026-05-30 — Literal+Distance Block Split Candidate

The q4+ LZ77 meta-block writer now exact-costs the remaining pairwise
block-layout candidate: literal-block plus distance-block splitting. Literal
block lengths count inserted-literal events, explicit-distance block lengths
count only commands that read a distance symbol, and the command stream stays
single-tree. Together with the literal+command and command+distance candidates,
this completes pairwise literal/command/distance block-layout coverage while
still avoiding the rejected three-stream joint split.

Validation:

| Command | Result |
| ------- | ------ |
| `moon test --target native --filter '*splits LZ77*blocks*'` | passed; 6/6 tests cover literal, command, distance, literal+command, literal+distance, and command+distance block split writers |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json` | q5 remains 40,328 bytes versus Google 40,515; q9 remains 39,081 bytes versus Google 39,695 |

`target-perf.nu` was not rerun for this structural block-layout increment per
maintainer instruction.

## 2026-05-29 — Soak Log Append Mode

`tools/brotli/fuzz/soak.nu` now accepts:

```nu
nu tools/brotli/fuzz/soak.nu --append-log
```

Normal runs still start with a clean JSONL log. With `--append-log`, the runner
keeps the existing log, ignores empty or malformed rows while scanning it, and
continues from the largest recorded `iteration` value. This makes interrupted
or deliberately segmented long soaks usable as one continuous evidence log
without weakening the default local-validation behavior.

Validation:

| Command | Result |
| ------- | ------ |
| `nu --ide-check 0 tools/brotli/fuzz/soak.nu` | parsed successfully |
| `nu tools/brotli/fuzz/soak.nu --log target/brotli-fuzz-soak-append-test/soak.jsonl --duration-min 0 --max-iterations 1 --decoder-limit 1 --roundtrip-count 1 --roundtrip-max-len 8 --roundtrip-qualities 2` | clean run wrote two iteration-1 rows |
| same command with `--append-log --max-iterations 2` | appended two iteration-2 rows, leaving four total rows |

This is release-validation tooling only; it does not change Brotli
encode/decode behavior or the recorded codec target-perf baseline.

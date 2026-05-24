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

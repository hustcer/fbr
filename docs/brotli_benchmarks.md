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

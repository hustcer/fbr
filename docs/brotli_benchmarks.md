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

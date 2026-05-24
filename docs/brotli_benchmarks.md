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

# fbr - Brotli for MoonBit

`fbr` is a pure MoonBit Brotli (`.br`) encoder and decoder.

The package is split so applications can choose the smallest dependency graph
for their use case:

- Decode only: import `hustcer/fbr/decode`
- Encode only: import `hustcer/fbr/encode`
- Full convenience API: import `hustcer/fbr`

## Small Artifacts By Design

`fbr` keeps decode, encode, and the root facade in separate packages. A
decode-only application can import `hustcer/fbr/decode` without making encoder
code reachable, and an encode-only application can import `hustcer/fbr/encode`
without making decoder code reachable. The root `hustcer/fbr` package remains a
convenience facade for applications that want both sides.

The Brotli static dictionary is also stored in a wasm-friendly form. The RFC
dictionary is 122,784 bytes; representing it as one huge `FixedArray[Byte]`
literal can make wasm-gc emit one initialization instruction per byte. `fbr`
stores the bytes as chunks and blits them into the final `FixedArray[Byte]`,
so the dictionary is data again instead of a large block of generated startup
code. This keeps decode-only wasm-gc artifacts close to the real data size
without changing the public API, the dictionary bytes, or the codec behavior.

## Installation

```bash
moon add hustcer/fbr
```

Or add this to `moon.mod.json`:

```json
{
  "deps": {
    "hustcer/fbr": "0.5.0"
  }
}
```

## Decode Only

```moonbit
let plain = @decode.unbrotli_sync(compressed)
```

Use `hustcer/fbr/decode` in `moon.pkg`:

```moonbit
import {
  "hustcer/fbr/decode"
}
```

## Encode Only

```moonbit
let compressed = @encode.brotli_sync(
  data,
  opts={
    ..@encode.BrotliOptions::default(),
    quality: 9,
    window_bits: 22,
  },
)
```

Use `hustcer/fbr/encode` in `moon.pkg`:

```moonbit
import {
  "hustcer/fbr/encode"
}
```

## Full API

The root package exposes facade wrappers and type aliases for convenience:

```moonbit
let compressed = @fbr.brotli_sync(data)
let plain = @fbr.unbrotli_sync(compressed)
```

Use `hustcer/fbr` in `moon.pkg`:

```moonbit
import {
  "hustcer/fbr"
}
```

Size-sensitive applications should import `hustcer/fbr/decode` or
`hustcer/fbr/encode` directly instead of the root facade.

## Streams

`BrotliStream` and `UnbrotliStream` buffer input chunks until
`push(chunk, final_=true)`.

```moonbit
let stream = @encode.BrotliStream::new()
stream.set_ondata((chunk, is_final) => {
  // handle compressed chunk
})
stream.push(chunk1)
stream.push(chunk2, final_=true)
```

## Status

- `brotli_sync` supports quality levels `0..=11`.
- `unbrotli_sync` decodes RFC 7932 Brotli streams, including static dictionary
  references and transforms.
- `BrotliOptions` exposes `quality`, `window_bits`, and `max_input_size`.
- `UnbrotliOptions` exposes optional caller-provided output storage,
  `max_output_size`, and `max_input_size`.
- In production builds, `decode` imports only `common`.
- In production builds, `encode` imports only `common`. Its `moon.pkg` imports
  `decode` only for white-box tests.
- The root package imports `common`, `decode`, and `encode`, and contains only
  facade wrappers, type aliases, and shared error/default aliases.
- `BrotliStream` and `UnbrotliStream` are buffering convenience wrappers, not
  true incremental Brotli codec states.
- The static dictionary is built from byte chunks instead of one byte-per-entry
  `FixedArray[Byte]` literal.
- `tools/` includes fixture, conformance, fuzz, size, and benchmark scripts.
- q0 and q1 currently emit valid stored streams and are not intended to match
  Google's low-quality compression ratio. q10 and q11 are valid but may still be
  larger than Google Brotli output; see the release report for measured data.

## Size Verification

Run the JS artifact split check before release:

```bash
just size
```

To inspect both JS and wasm-gc artifact sizes:

```bash
just size js,wasm-gc
```

The check builds three temporary release applications:

- decode-only, importing `hustcer/fbr/decode`
- encode-only, importing `hustcer/fbr/encode`
- full, importing `hustcer/fbr`

For the JS target it scans the linked artifact and fails if the decode-only
artifact contains encode package markers, or the encode-only artifact contains
decode package markers.

For wasm-gc, the same command reports the linked artifact sizes for the three
import shapes. This is useful for catching large static-data representation
regressions during review: the Brotli dictionary should be carried as
bytes/data plus a small number of chunk copies, not as tens of thousands of
`array.set` initialization instructions.

See [docs/brotli-pkg.md](https://github.com/hustcer/fbr/blob/main/docs/brotli-pkg.md) for the package split rationale
and [docs/brotli_release_report.md](https://github.com/hustcer/fbr/blob/main/docs/brotli_release_report.md) for recorded Brotli
benchmark data.

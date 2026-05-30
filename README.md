# fbr - Brotli for MoonBit

`fbr` is a pure MoonBit Brotli (`.br`) encoder and decoder.

The package is split so applications can choose the smallest dependency graph
for their use case:

- Decode only: import `hustcer/fbr/decode`
- Encode only: import `hustcer/fbr/encode`
- Full convenience API: import `hustcer/fbr`

## Installation

```bash
moon add hustcer/fbr
```

Or add this to `moon.mod.json`:

```json
{
  "deps": {
    "hustcer/fbr": "0.1.0"
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

The root package re-exports both sides for convenience:

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
- `decode` imports only `common`.
- `encode` imports only `common`.
- The root package imports both leaf packages and contains only facade
  wrappers.

## Size Verification

Run the artifact split check before release:

```bash
just size
```

The check builds three temporary release applications:

- decode-only, importing `hustcer/fbr/decode`
- encode-only, importing `hustcer/fbr/encode`
- full, importing `hustcer/fbr`

For the JS target it scans the linked artifact and fails if the decode-only
artifact contains encode package markers, or the encode-only artifact contains
decode package markers.

See [docs/brotli-pkg.md](docs/brotli-pkg.md) for the package split rationale
and [docs/brotli_benchmarks.md](docs/brotli_benchmarks.md) for recorded Brotli
benchmark data.

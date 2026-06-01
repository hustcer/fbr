# Brotli Benchmarks

This document records the current release-build Brotli benchmark results. It
does not keep historical optimization notes; use git history for older phase
measurements.

Run commands from the repository root.

## Environment

| Item                    | Value                                                              |
| ----------------------- | ------------------------------------------------------------------ |
| Date                    | 2026-05-30                                                         |
| MoonBit                 | `moon 0.1.20260522 (4a0c52f 2026-05-22)`                           |
| Google Brotli CLI       | `brotli 1.2.0`                                                     |
| MoonBit profile         | release, via `tools/bench/target-perf.nu`                   |
| MoonBit targets         | `wasm-gc`, `native`                                                |
| Native release compiler | `tools/bench/native-cc-o0.nu` (`native_cc = cc-o0`)         |
| Timing shape            | `--repeats 3 --samples 3`; tables report per-operation min and avg |

`target-perf.nu` compares MoonBit release runs against the Google `brotli` CLI.
For encode benchmarks it reports both compressed size and encode time. For
decode benchmarks it measures decoding Google-produced `.br` streams and
reports time only, with compressed size shown for context.

## Inputs

| File                                   |     Bytes | SHA-256                                                            |
| -------------------------------------- | --------: | ------------------------------------------------------------------ |
| `target/brotli-bench/silesia-64k.bin`  |    65,536 | `e3c2d13f13d16b0578e9900642807e48bd1dd1a3f70eb3d97b4a627e84b62e52` |
| `target/brotli-bench/silesia-128k.bin` |   131,072 | `3a13ecc75f46423179a64063f7f004f0d85e742833797867f1c793d89fae21a9` |
| `target/brotli-bench/silesia-1m.bin`   | 1,048,576 | `92c70e5474935758a5151c31fce538a55a4fb03101323dfad6b46c7161cc6fd2` |

Raw result files from this run:

| File                                       | SHA-256                                                            |
| ------------------------------------------ | ------------------------------------------------------------------ |
| `target/brotli-current-bench/encode.jsonl` | `7df364a6d9275668a414adf8da4013215440ee43f753f39aaac7d761d5042372` |
| `target/brotli-current-bench/decode.jsonl` | `bfa53b93d5e7287f1b65d3996ecca32c7119064c90b91dc53ce6844717504ee0` |

## Commands

Encoding matrix:

```bash
for input in target/brotli-bench/silesia-64k.bin target/brotli-bench/silesia-128k.bin; do
  for q in 0 1 2 3 4 5 6 7 8 9 10 11; do
    nu tools/bench/target-perf.nu "$input" \
      --mode encode \
      --quality "$q" \
      --targets wasm-gc,native \
      --repeats 3 \
      --samples 3 \
      --json
  done
done
```

Decode matrix:

```bash
for q in 0 1 2 3 4 5 6 7 8 9 10 11; do
  brotli -q "$q" -f -c target/brotli-bench/silesia-1m.bin \
    > "target/brotli-current-bench/google-1m/silesia-1m.q${q}.br"

  nu tools/bench/target-perf.nu \
    "target/brotli-current-bench/google-1m/silesia-1m.q${q}.br" \
    --mode decode \
    --expected target/brotli-bench/silesia-1m.bin \
    --targets wasm-gc,native \
    --repeats 3 \
    --samples 3 \
    --json
done
```

## Encode, 64 KiB Silesia Slice

| Quality | Target  | Native CC | MoonBit bytes | Google bytes | Size overhead | MoonBit min ms | MoonBit avg ms | Google min ms | Google avg ms | Slowdown min |
| ------- | ------- | --------- | ------------- | ------------ | ------------- | -------------- | -------------- | ------------- | ------------- | ------------ |
| q0      | native  | cc-o0     | 65,540        | 27,226       | 140.73%       | 24.170         | 25.599         | 15.164        | 15.340        | 1.59x        |
| q0      | wasm-gc | default   | 65,540        | 27,226       | 140.73%       | 14.091         | 14.431         | 15.164        | 15.340        | 0.93x        |
| q1      | native  | cc-o0     | 65,540        | 25,905       | 153.00%       | 23.973         | 25.693         | 15.705        | 15.740        | 1.53x        |
| q1      | wasm-gc | default   | 65,540        | 25,905       | 153.00%       | 14.348         | 14.587         | 15.705        | 15.740        | 0.91x        |
| q2      | native  | cc-o0     | 25,087        | 24,176       | 3.77%         | 95.672         | 95.917         | 15.544        | 15.659        | 6.16x        |
| q2      | wasm-gc | default   | 25,087        | 24,176       | 3.77%         | 36.113         | 37.009         | 15.544        | 15.659        | 2.32x        |
| q3      | native  | cc-o0     | 24,965        | 23,928       | 4.33%         | 136.700        | 160.195        | 15.443        | 15.635        | 8.85x        |
| q3      | wasm-gc | default   | 24,965        | 23,928       | 4.33%         | 48.445         | 49.683         | 15.443        | 15.635        | 3.14x        |
| q4      | native  | cc-o0     | 22,642        | 23,186       | -2.35%        | 250.797        | 251.451        | 16.195        | 16.442        | 15.49x       |
| q4      | wasm-gc | default   | 22,642        | 23,186       | -2.35%        | 82.709         | 83.315         | 16.195        | 16.442        | 5.11x        |
| q5      | native  | cc-o0     | 22,194        | 22,114       | 0.36%         | 225.763        | 226.239        | 16.638        | 16.783        | 13.57x       |
| q5      | wasm-gc | default   | 22,194        | 22,114       | 0.36%         | 76.870         | 77.090         | 16.638        | 16.783        | 4.62x        |
| q6      | native  | cc-o0     | 22,394        | 22,001       | 1.79%         | 207.377        | 207.812        | 16.931        | 17.138        | 12.25x       |
| q6      | wasm-gc | default   | 22,394        | 22,001       | 1.79%         | 71.094         | 71.335         | 16.931        | 17.138        | 4.20x        |
| q7      | native  | cc-o0     | 22,221        | 21,950       | 1.23%         | 212.592        | 215.482        | 16.976        | 17.160        | 12.52x       |
| q7      | wasm-gc | default   | 22,221        | 21,950       | 1.23%         | 72.042         | 73.172         | 16.976        | 17.160        | 4.24x        |
| q8      | native  | cc-o0     | 22,117        | 21,931       | 0.85%         | 285.190        | 285.894        | 19.604        | 22.650        | 14.55x       |
| q8      | wasm-gc | default   | 22,117        | 21,931       | 0.85%         | 92.981         | 94.936         | 19.604        | 22.650        | 4.74x        |
| q9      | native  | cc-o0     | 21,397        | 21,904       | -2.31%        | 202.675        | 203.300        | 19.384        | 20.044        | 10.46x       |
| q9      | wasm-gc | default   | 21,397        | 21,904       | -2.31%        | 71.618         | 71.661         | 19.384        | 20.044        | 3.69x        |
| q10     | native  | cc-o0     | 21,302        | 19,463       | 9.45%         | 142.782        | 143.218        | 38.503        | 39.476        | 3.71x        |
| q10     | wasm-gc | default   | 21,302        | 19,463       | 9.45%         | 52.532         | 53.803         | 38.503        | 39.476        | 1.36x        |
| q11     | native  | cc-o0     | 21,302        | 19,154       | 11.21%        | 142.457        | 142.789        | 81.968        | 82.595        | 1.74x        |
| q11     | wasm-gc | default   | 21,302        | 19,154       | 11.21%        | 52.769         | 53.192         | 81.968        | 82.595        | 0.64x        |

## Encode, 128 KiB Silesia Slice

| Quality | Target  | Native CC | MoonBit bytes | Google bytes | Size overhead | MoonBit min ms | MoonBit avg ms | Google min ms | Google avg ms | Slowdown min |
| ------- | ------- | --------- | ------------- | ------------ | ------------- | -------------- | -------------- | ------------- | ------------- | ------------ |
| q0      | native  | cc-o0     | 131,077       | 50,842       | 157.81%       | 23.948         | 26.440         | 15.533        | 15.655        | 1.54x        |
| q0      | wasm-gc | default   | 131,077       | 50,842       | 157.81%       | 20.756         | 21.249         | 15.533        | 15.655        | 1.34x        |
| q1      | native  | cc-o0     | 131,077       | 47,478       | 176.08%       | 23.924         | 25.219         | 15.400        | 15.689        | 1.55x        |
| q1      | wasm-gc | default   | 131,077       | 47,478       | 176.08%       | 20.802         | 21.366         | 15.400        | 15.689        | 1.35x        |
| q2      | native  | cc-o0     | 46,290        | 44,553       | 3.90%         | 84.589         | 85.343         | 15.978        | 16.314        | 5.29x        |
| q2      | wasm-gc | default   | 46,290        | 44,553       | 3.90%         | 40.179         | 40.338         | 15.978        | 16.314        | 2.51x        |
| q3      | native  | cc-o0     | 45,062        | 43,877       | 2.70%         | 215.777        | 216.339        | 15.725        | 15.911        | 13.72x       |
| q3      | wasm-gc | default   | 45,062        | 43,877       | 2.70%         | 78.641         | 78.846         | 15.725        | 15.911        | 5.00x        |
| q4      | native  | cc-o0     | 40,995        | 42,473       | -3.48%        | 454.731        | 457.015        | 16.294        | 16.535        | 27.91x       |
| q4      | wasm-gc | default   | 40,995        | 42,473       | -3.48%        | 149.824        | 150.740        | 16.294        | 16.535        | 9.20x        |
| q5      | native  | cc-o0     | 40,150        | 40,318       | -0.42%        | 382.520        | 384.921        | 17.177        | 17.298        | 22.27x       |
| q5      | wasm-gc | default   | 40,150        | 40,318       | -0.42%        | 130.002        | 130.458        | 17.177        | 17.298        | 7.57x        |
| q6      | native  | cc-o0     | 40,150        | 39,972       | 0.45%         | 478.711        | 489.572        | 17.438        | 17.727        | 27.45x       |
| q6      | wasm-gc | default   | 40,150        | 39,972       | 0.45%         | 157.444        | 158.398        | 17.438        | 17.727        | 9.03x        |
| q7      | native  | cc-o0     | 39,831        | 39,720       | 0.28%         | 499.389        | 500.758        | 18.106        | 18.687        | 27.58x       |
| q7      | wasm-gc | default   | 39,831        | 39,720       | 0.28%         | 163.426        | 165.363        | 18.106        | 18.687        | 9.03x        |
| q8      | native  | cc-o0     | 39,831        | 39,616       | 0.54%         | 496.074        | 497.260        | 19.442        | 21.799        | 25.52x       |
| q8      | wasm-gc | default   | 39,831        | 39,616       | 0.54%         | 163.690        | 164.278        | 19.442        | 21.799        | 8.42x        |
| q9      | native  | cc-o0     | 38,926        | 39,503       | -1.46%        | 333.028        | 334.196        | 21.344        | 21.401        | 15.60x       |
| q9      | wasm-gc | default   | 38,926        | 39,503       | -1.46%        | 118.154        | 118.342        | 21.344        | 21.401        | 5.54x        |
| q10     | native  | cc-o0     | 38,565        | 35,448       | 8.79%         | 245.169        | 246.047        | 66.866        | 67.844        | 3.67x        |
| q10     | wasm-gc | default   | 38,565        | 35,448       | 8.79%         | 88.626         | 88.940         | 66.866        | 67.844        | 1.33x        |
| q11     | native  | cc-o0     | 38,565        | 35,027       | 10.10%        | 244.419        | 246.437        | 160.503       | 162.077       | 1.52x        |
| q11     | wasm-gc | default   | 38,565        | 35,027       | 10.10%        | 88.383         | 88.592         | 160.503       | 162.077       | 0.55x        |

## Decode, 1 MiB Silesia Google Streams

Each input stream in this table was produced by Google `brotli -q <quality>`
from `target/brotli-bench/silesia-1m.bin`.

| Google quality | Target  | Native CC | Compressed bytes | Decoded bytes | MoonBit min ms | MoonBit avg ms | Google min ms | Google avg ms | Slowdown min |
| -------------- | ------- | --------- | ---------------- | ------------- | -------------- | -------------- | ------------- | ------------- | ------------ |
| q0             | native  | cc-o0     | 372,056          | 1,048,576     | 100.355        | 101.000        | 17.633        | 21.929        | 5.69x        |
| q0             | wasm-gc | default   | 372,056          | 1,048,576     | 66.479         | 66.854         | 17.633        | 21.929        | 3.77x        |
| q1             | native  | cc-o0     | 342,151          | 1,048,576     | 95.356         | 95.984         | 17.638        | 17.859        | 5.41x        |
| q1             | wasm-gc | default   | 342,151          | 1,048,576     | 63.408         | 67.654         | 17.638        | 17.859        | 3.60x        |
| q2             | native  | cc-o0     | 320,237          | 1,048,576     | 85.695         | 85.984         | 17.153        | 17.832        | 5.00x        |
| q2             | wasm-gc | default   | 320,237          | 1,048,576     | 58.091         | 58.971         | 17.153        | 17.832        | 3.39x        |
| q3             | native  | cc-o0     | 313,613          | 1,048,576     | 82.065         | 82.787         | 17.519        | 17.901        | 4.68x        |
| q3             | wasm-gc | default   | 313,613          | 1,048,576     | 56.779         | 57.107         | 17.519        | 17.901        | 3.24x        |
| q4             | native  | cc-o0     | 292,262          | 1,048,576     | 75.520         | 75.800         | 17.281        | 17.321        | 4.37x        |
| q4             | wasm-gc | default   | 292,262          | 1,048,576     | 53.113         | 53.635         | 17.281        | 17.321        | 3.07x        |
| q5             | native  | cc-o0     | 274,097          | 1,048,576     | 75.305         | 75.575         | 17.419        | 17.488        | 4.32x        |
| q5             | wasm-gc | default   | 274,097          | 1,048,576     | 51.670         | 51.867         | 17.419        | 17.488        | 2.97x        |
| q6             | native  | cc-o0     | 269,541          | 1,048,576     | 74.244         | 74.889         | 17.152        | 17.387        | 4.33x        |
| q6             | wasm-gc | default   | 269,541          | 1,048,576     | 50.870         | 52.103         | 17.152        | 17.387        | 2.97x        |
| q7             | native  | cc-o0     | 267,018          | 1,048,576     | 74.376         | 78.164         | 17.080        | 17.323        | 4.35x        |
| q7             | wasm-gc | default   | 267,018          | 1,048,576     | 50.392         | 50.971         | 17.080        | 17.323        | 2.95x        |
| q8             | native  | cc-o0     | 264,917          | 1,048,576     | 72.716         | 74.612         | 17.261        | 17.583        | 4.21x        |
| q8             | wasm-gc | default   | 264,917          | 1,048,576     | 50.499         | 50.764         | 17.261        | 17.583        | 2.93x        |
| q9             | native  | cc-o0     | 263,547          | 1,048,576     | 73.192         | 73.257         | 16.946        | 17.328        | 4.32x        |
| q9             | wasm-gc | default   | 263,547          | 1,048,576     | 49.788         | 50.661         | 16.946        | 17.328        | 2.94x        |
| q10            | native  | cc-o0     | 242,514          | 1,048,576     | 71.215         | 72.178         | 17.299        | 17.736        | 4.12x        |
| q10            | wasm-gc | default   | 242,514          | 1,048,576     | 47.038         | 54.619         | 17.299        | 17.736        | 2.72x        |
| q11            | native  | cc-o0     | 239,302          | 1,048,576     | 70.715         | 73.986         | 17.552        | 17.745        | 4.03x        |
| q11            | wasm-gc | default   | 239,302          | 1,048,576     | 46.273         | 52.652         | 17.552        | 17.745        | 2.64x        |

## Notes

- q0 and q1 currently emit stored meta-block streams. They are valid Brotli
  streams, but they are not intended to match Google Brotli's low-quality
  compression ratio.
- q2 through q9 are the current measured ratio-focused range. On these 64 KiB
  and 128 KiB slices, MoonBit output is within 5% of Google output.
- q10 and q11 remain valid but larger than Google output on these slices. This
  matches the current documented high-quality ratio limitation.
- Timing is command-harness timing, not an isolated in-process library
  microbenchmark. Use the same commands and inputs when comparing future
  changes.

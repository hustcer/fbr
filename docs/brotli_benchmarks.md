# Brotli Benchmarks

This file records phase validation measurements for the MoonBit Brotli encoder.
Run commands from the repository root.

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

| Quality | MoonBit bytes | Google bytes | Size overhead | MoonBit SHA-256                                                    |
| ------- | ------------- | ------------ | ------------- | ------------------------------------------------------------------ |
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

This P4 trial increased q10/q11 high-quality hash-chain checks from 256 to 384. A follow-up narrowed the change to q10 only after q11 showed a native
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

| Corpus       | Quality | Target  | Baseline bytes | Trial bytes | Google bytes | Baseline ms | Trial ms   | Decision |
| ------------ | ------- | ------- | -------------- | ----------- | ------------ | ----------- | ---------- | -------- |
| silesia-1m   | 10      | ratio   | 264,422        | 263,700     | 242,485      | 63,742.891  | 80,391.065 | reject   |
| silesia-1m   | 11      | ratio   | 264,422        | 263,700     | 239,314      | 63,038.589  | 74,624.034 | reject   |
| silesia-64k  | 10      | wasm-gc | 21,415         | 21,408      | 19,566       | 510.253     | 499.135    | reject   |
| silesia-64k  | 10      | native  | 21,415         | 21,408      | 19,566       | 121.332     | 91.720     | reject   |
| silesia-64k  | 11      | wasm-gc | 21,415         | 21,408      | 19,258       | 547.539     | 523.260    | reject   |
| silesia-64k  | 11      | native  | 21,415         | 21,408      | 19,258       | 75.297      | 117.263    | reject   |
| silesia-128k | 10      | wasm-gc | 38,713         | 38,686      | 35,624       | 172.893     | 660.508    | reject   |
| silesia-128k | 10      | native  | 38,713         | 38,686      | 35,624       | 91.262      | 143.997    | reject   |

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

| Corpus     | Quality | MoonBit bytes | Google bytes | Overhead | Google decode |
| ---------- | ------- | ------------- | ------------ | -------- | ------------- |
| silesia-2m | 3       | 629,531       | n/a          | n/a      | pass          |
| silesia-2m | 5       | 555,326       | 538,906      | +3.05%   | pass          |
| silesia-2m | 9       | 542,335       | 511,433      | +6.04%   | pass          |

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

| Corpus     | Quality | MoonBit bytes | Google bytes | Size overhead | Google decode |
| ---------- | ------- | ------------- | ------------ | ------------- | ------------- |
| silesia-2m | 0       | 2,097,157     | n/a          | n/a           | pass          |
| silesia-2m | 1       | 2,097,157     | n/a          | n/a           | pass          |
| silesia-2m | 2       | 652,695       | 637,343      | +2.41%        | pass          |
| silesia-2m | 3       | 617,687       | 623,577      | -0.94%        | pass          |
| silesia-2m | 4       | 566,718       | 569,163      | -0.43%        | pass          |
| silesia-2m | 5       | 549,625       | 538,906      | +1.99%        | pass          |
| silesia-2m | 6       | 549,625       | 527,485      | +4.20%        | pass          |
| silesia-2m | 7       | 537,621       | 520,020      | +3.38%        | pass          |
| silesia-2m | 8       | 537,621       | 514,598      | +4.47%        | pass          |
| silesia-2m | 9       | 535,421       | 511,433      | +4.69%        | pass          |
| silesia-1m | 10      | 264,422       | 242,485      | +9.05%        | pass          |
| silesia-1m | 11      | 264,422       | 239,314      | +10.49%       | pass          |

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

| Input stream                | Target  | Encoded bytes | Decoded bytes | MoonBit ms | Google ms | Slowdown |
| --------------------------- | ------- | ------------- | ------------- | ---------- | --------- | -------- |
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

| Command                                                  | Inputs | Batch size | Result | Wall time |
| -------------------------------------------------------- | ------ | ---------- | ------ | --------- |
| `nu tools/brotli/fuzz/run.nu --limit 25` before batching | 25     | 1          | pass   | 54.73s    |
| `nu tools/brotli/fuzz/run.nu --limit 25` after batching  | 25     | 25         | pass   | 2.19s     |
| `nu tools/brotli/fuzz/run.nu` after batching             | 58     | 25         | pass   | 7.00s     |

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

| Command                                                                | Result     |
| ---------------------------------------------------------------------- | ---------- |
| `nu tools/brotli/fuzz/run.nu --limit 2 --batch-size 1 --target native` | 2/2 passed |
| `nu tools/brotli/fuzz/run.nu --limit 5 --target wasm-gc`               | 5/5 passed |
| `nu tools/brotli/fuzz/run.nu --limit 3 --target all`                   | 3/3 passed |

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

| Command                                                                                       | Result       |
| --------------------------------------------------------------------------------------------- | ------------ |
| `nu tools/brotli/fuzz/roundtrip.nu --count 2 --qualities 0,2 --target native --batch-size 2`  | 4/4 passed   |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --target native`                   | 20/20 passed |
| `nu tools/brotli/fuzz/roundtrip.nu --count 3 --max-len 256 --qualities 2,11 --target wasm-gc` | 6/6 passed   |

This expands release-readiness coverage without changing Brotli encode/decode
implementation or the recorded codec target-perf baseline.

## 2026-05-29 — Fuzz Harness Stale-Lock Recovery

The decoder and encoder roundtrip fuzz runners now record the owner PID in
`tools/brotli/.harness-lock/pid`. A second active harness is still rejected,
but a lock left behind by an interrupted or crashed run is detected as stale,
removed, and reacquired.

Validation:

| Scenario                           | Command                                                                                                                  | Result                  |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ----------------------- |
| Stale lock recovery                | create `.harness-lock/pid` with dead PID `999999`, then run `nu tools/brotli/fuzz/run.nu --limit 1 --target native`      | 1/1 passed              |
| Active lock protection             | create `.harness-lock/pid` from a live `sleep` process, then run `nu tools/brotli/fuzz/run.nu --limit 1 --target native` | rejected with owner PID |
| Roundtrip harness normal lock path | `nu tools/brotli/fuzz/roundtrip.nu --count 2 --qualities 2,11 --target native --batch-size 2`                            | 4/4 passed              |

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

| Command                                                                                                                                                                            | Result                                                       |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `nu --ide-check 0 tools/brotli/release/validate.nu`                                                                                                                                | parsed successfully                                          |
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

| Command                       | Result                                                                       |
| ----------------------------- | ---------------------------------------------------------------------------- |
| `just --list`                 | lists `brotli-release`, `brotli-release-smoke`, and `brotli-release-package` |
| `just brotli-release-smoke`   | decoder fuzz corpus and encoder roundtrip fuzz passed                        |
| `just brotli-release-package` | `moon package` and `moon publish --dry-run` package verification passed      |

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

| Command                                      | Result                                                                     |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| `nu --ide-check 0 tools/brotli/fuzz/soak.nu` | parsed successfully                                                        |
| `just --list`                                | lists `brotli-fuzz-soak` and `brotli-fuzz-soak-smoke`                      |
| `just brotli-fuzz-soak-smoke`                | one decoder fuzz iteration and one encoder roundtrip fuzz iteration passed |

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

| Command                                                                                                                       | Result              |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| `nu --ide-check 0 tools/brotli/fuzz/gen-corpus.nu`                                                                            | parsed successfully |
| generate two corpora with `--count 12 --seed 12345` under separate `target/` directories and compare sorted SHA-256 manifests | identical           |
| `nu tools/brotli/fuzz/run.nu --corpus-dir target/brotli-fuzz-determinism-a --target native --batch-size 10`                   | 20/20 passed        |

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

| Command                                                                                                                                                                                                                   | Result                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `nu --ide-check 0 tools/brotli/release/validate.nu`                                                                                                                                                                       | parsed successfully                                                                  |
| `just --list`                                                                                                                                                                                                             | lists `brotli-release-generated-fuzz`                                                |
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

| Step                                       | Result | Elapsed ms |
| ------------------------------------------ | ------ | ---------- |
| generate deterministic decoder fuzz corpus | pass   | 210.55     |
| decoder fuzz corpus                        | pass   | 90,822.64  |
| encoder roundtrip fuzz                     | pass   | 14,357.89  |

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

| Phase                  | Iterations | Result |
| ---------------------- | ---------- | ------ |
| decoder fuzz           | 3          | pass   |
| encoder roundtrip fuzz | 3          | pass   |

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

| Command                               | Result                                                                                        |
| ------------------------------------- | --------------------------------------------------------------------------------------------- |
| `just brotli-release-candidate-smoke` | release smoke, generated-corpus smoke, and soak smoke passed                                  |
| `just brotli-release-candidate`       | full practical gate, generated deterministic corpus gate, and bounded full-corpus soak passed |

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

| Command                                                                                          | Result                                                                                                       |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json`   | q10/q11 remain 38,713 bytes versus Google 35,624/35,164                                                      |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`    | 8/8 encoder roundtrips passed                                                                                |
| `moon fmt && moon check --target all && moon test --target all && moon info && git diff --check` | all-target check passed; 469 tests passed on wasm, wasm-gc, js, and native; generated interface check passed |

## 2026-05-30 — Large Single-Copy Periodic Fast Path

Inputs up to 256 KiB now try the existing single-copy periodic detector before
falling into the chunked standard encoder. For high-diversity periodic prefixes
the encoder exact-costs the existing single compressed block against a split
form: a stored prefix meta-block followed by a copy-only compressed meta-block.
This avoids paying a full 256-symbol literal Huffman tree for the prefix.

The motivating broad-corpus sample is `periodic-allbytes-200k.bin`, a 200 KiB
cycle over all 256 byte values. The output remains externally decodable and
the Silesia 128 KiB q2/q5/q9 sizes are unchanged.

Periodic 200 KiB ratio, before -> after:

| Quality | Before bytes | After bytes | Google bytes | After overhead |
| ------- | ------------ | ----------- | ------------ | -------------- |
| q2      | 350          | 301         | 293          | +2.73%         |
| q3      | 350          | 272         | 281          | -3.20%         |
| q4      | 350          | 272         | 260          | +4.62%         |
| q5      | 350          | 272         | 260          | +4.62%         |
| q6      | 350          | 272         | 260          | +4.62%         |
| q7      | 350          | 272         | 260          | +4.62%         |
| q8      | 350          | 272         | 260          | +4.62%         |
| q9      | 350          | 272         | 259          | +5.02%         |

Periodic 200 KiB encode target-perf, before -> after:

| Quality | Target  | Before ms/op | After ms/op | Before bytes | After bytes |
| ------- | ------- | ------------ | ----------- | ------------ | ----------- |
| q2      | wasm-gc | 121.193      | 113.285     | 350          | 301         |
| q2      | native  | 91.339       | 73.513      | 350          | 301         |
| q9      | wasm-gc | 212.056      | 116.976     | 350          | 272         |
| q9      | native  | 666.810      | 72.173      | 350          | 272         |

Representative decode target-perf on the Google q9 periodic stream is
unchanged by this encoder-only change: wasm-gc 57.084 ms/op and native
`cc-o0` 86.281 ms/op, both versus Google 40.694 ms/op.

Silesia 128 KiB spot checks after the change:

| Quality | MoonBit bytes | Google bytes | Overhead | wasm-gc ms/op | native ms/op |
| ------- | ------------- | ------------ | -------- | ------------- | ------------ |
| q2      | 46,509        | 44,794       | +3.83%   | 120.632       | 142.666      |
| q5      | 40,328        | 40,515       | -0.46%   | not rerun     | not rerun    |
| q9      | 39,081        | 39,695       | -1.55%   | 195.853       | 380.678      |

Validation:

| Command                                                                                                             | Result                                                                  |
| ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `moon test --target native --filter '*large 256-byte periodic*'`                                                    | passed; covers >64 KiB periodic q2/q9 roundtrip and compact output      |
| `nu tools/brotli/bench/ratio.nu target/brotli-encode/periodic-allbytes-200k.bin --qualities 2,3,4,5,6,7,8,9 --json` | q2 improves from 350 to 301 bytes; q3..q9 improve from 350 to 272 bytes |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 2,5,9 --json`                      | q2/q5/q9 Silesia sizes unchanged                                        |

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

| Command                                                                                        | Result                                                                                                                   |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `moon test --target native --filter '*bounded shortest-path*'`                                 | passed; the bounded candidate writes a decodable final meta-block and q10 public roundtrip passes                        |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                            |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |
| `moon check --target all && moon test --target all`                                            | all-target check passed; 461 tests passed on wasm, wasm-gc, js, and native                                               |

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

| Command                                                                                        | Result                                                                                                                   |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `moon test --target native --filter '*bounded shortest-path*'`                                 | passed; 2/2 tests cover bounded command roundtrip and multiple previous-match enumeration                                |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                            |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged |
| `moon check --target all`                                                                      | passed                                                                                                                   |

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

| Command                                                                                        | Result                                                                                                                         |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `moon test --target native --filter '*bounded shortest-path*'`                                 | passed; 3/3 tests cover bounded command roundtrip, multiple previous-match enumeration, and recent-distance copy-cost modeling |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                                  |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged       |

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

| Command                                                                                        | Result                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*bounded shortest-path*'`                                 | passed; 4/4 tests cover bounded command roundtrip, multiple previous-match enumeration, recent-distance copy-cost modeling, and two-state beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                                                            |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged                                 |

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

| Command                                                                                        | Result                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*bounded shortest-path*'`                                 | passed; 5/5 tests cover bounded command roundtrip, multiple-match enumeration, recent-distance costs, cost-model histograms, and two-state beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                                                             |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged                                  |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-30 — q10/q11 Bounded Suffix-Tree Match Source

The q10/q11 bounded shortest-path seed now has a second match provider: a
bounded suffix binary tree built over earlier positions in the current
meta-block. The tree is deliberately capped by the existing match-check budget
and remains a small-input seed for the full P4 suffix-tree/Zopfli backend.
Suffix-tree matches are offered into the same two-state beam and still go
through exact meta-block costing before selection.

Validation:

| Command                                                                                        | Result                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*bounded*'`                                               | passed; 6/6 tests cover bounded command roundtrip, hash-chain multi-match enumeration, suffix-tree match enumeration, recent-distance costs, cost-model histograms, and beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                                                                                          |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged                                                               |

`target-perf.nu` was not rerun for this increment per maintainer instruction.

## 2026-05-30 — q10/q11 Bounded Match Transition Cleanup

The q10/q11 bounded shortest-path seed now sends hash-chain and suffix-tree
matches through one shared bounded-copy transition helper. This is a
behavior-preserving P4 seed cleanup: both match providers still offer the same
minimum, half-length, and full-length copy candidates into the two-state beam,
with recent-distance-cache updates and exact-cost final meta-block selection
unchanged.

Validation:

| Command                                                                                        | Result                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*bounded*'`                                               | passed; 6/6 tests cover bounded command roundtrip, hash-chain multi-match enumeration, suffix-tree match enumeration, recent-distance costs, cost-model histograms, and beam retention |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 10,11 --target native`  | 8/8 encoder roundtrips passed                                                                                                                                                          |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 10,11 --json` | q10/q11 remain 38,713 bytes; Google q10/q11 are 35,624/35,164 bytes, keeping the documented P4 ratio exception unchanged                                                               |

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

| Command                                                                                                                                                      | Result                                                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `moon test --target native --filter 'brotli_sync splits LZ77 command blocks by command histograms'`                                                          | passed; synthetic command-skew candidate beats the weighted single-command-tree writer and round-trips through `unbrotli_sync` |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`                                                                 | q5 40,328 bytes vs Google 40,515 (-0.46%); q9 39,081 bytes vs Google 39,695 (-1.55%)                                           |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 5 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q5 output 22,336 bytes vs Google 22,271; wasm-gc/native min encode 81.122/52.656 ms                                            |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q9 output 21,514 bytes vs Google 22,063; wasm-gc/native min encode 77.966/45.555 ms                                            |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`                                                                | 12/12 encoder roundtrips passed                                                                                                |
| `moon check --target all && moon test --target all && moon info`                                                                                             | all-target check passed; 459 tests passed on wasm, wasm-gc, js, and native; public interface generation unchanged              |

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

| Command                                                                                                                                                      | Result                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter 'brotli_sync splits LZ77 distance blocks by distance histograms'`                                                        | passed; synthetic distance-skew candidate beats the weighted single-distance-tree writer and round-trips through `unbrotli_sync` |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`                                                                 | q5 40,328 bytes vs Google 40,515 (-0.46%); q9 39,081 bytes vs Google 39,695 (-1.55%)                                             |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 5 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q5 output 22,336 bytes vs Google 22,271; wasm-gc/native min encode 82.182/53.730 ms                                              |
| `nu tools/brotli/bench/target-perf.nu target/brotli-bench/silesia-64k.bin --mode encode --quality 9 --targets wasm-gc,native --repeats 3 --samples 3 --json` | q9 output 21,514 bytes vs Google 22,063; wasm-gc/native min encode 79.780/47.608 ms                                              |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native`                                                                | 12/12 encoder roundtrips passed                                                                                                  |
| `moon check --target all && moon test --target all && moon info`                                                                                             | all-target check passed; 460 tests passed on wasm, wasm-gc, js, and native; public interface generation unchanged                |

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

| Command                                                                                       | Result                                                                                                |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*splits LZ77*blocks*'`                                   | passed; 4/4 tests cover literal, command, distance, and combined command+distance block split writers |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed                                                                       |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`  | q5 remains 40,328 bytes versus Google 40,515; q9 remains 39,081 bytes versus Google 39,695            |

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

| Command                                                                                       | Result                                                                                                        |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*splits LZ77*blocks*'`                                   | passed; 5/5 tests cover literal, command, distance, literal+command, and command+distance block split writers |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed                                                                               |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`  | q5 remains 40,328 bytes versus Google 40,515; q9 remains 39,081 bytes versus Google 39,695                    |

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

| Command                                                                                       | Result                                                                                                                          |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `moon test --target native --filter '*splits LZ77*blocks*'`                                   | passed; 6/6 tests cover literal, command, distance, literal+command, literal+distance, and command+distance block split writers |
| `nu tools/brotli/fuzz/roundtrip.nu --count 4 --max-len 512 --qualities 4,5,9 --target native` | 12/12 encoder roundtrips passed                                                                                                 |
| `nu tools/brotli/bench/ratio.nu target/brotli-bench/silesia-128k.bin --qualities 5,9 --json`  | q5 remains 40,328 bytes versus Google 40,515; q9 remains 39,081 bytes versus Google 39,695                                      |

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

| Command                                                                                                                                                                                                     | Result                                                 |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `nu --ide-check 0 tools/brotli/fuzz/soak.nu`                                                                                                                                                                | parsed successfully                                    |
| `nu tools/brotli/fuzz/soak.nu --log target/brotli-fuzz-soak-append-test/soak.jsonl --duration-min 0 --max-iterations 1 --decoder-limit 1 --roundtrip-count 1 --roundtrip-max-len 8 --roundtrip-qualities 2` | clean run wrote two iteration-1 rows                   |
| same command with `--append-log --max-iterations 2`                                                                                                                                                         | appended two iteration-2 rows, leaving four total rows |

This is release-validation tooling only; it does not change Brotli
encode/decode behavior or the recorded codec target-perf baseline.

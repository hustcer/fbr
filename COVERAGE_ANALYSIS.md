# fbr Coverage Analysis

Generated: `Mon Jun  1 18:02:42 2026`

Coverage source: `moon coverage analyze -- -f summary`

Generated temporary main packages such as `src/brotli_*_main/` are excluded from the totals.

## Summary

| Metric                     |  Value |
| -------------------------- | -----: |
| Coverage                   | 81.68% |
| Covered lines              |   3178 |
| Total instrumented lines   |   3891 |
| Uncovered lines            |    713 |
| Files in report            |     25 |
| Files with uncovered lines |     25 |
| Packages in report         |      4 |

## Packages

| Package  | Covered | Total | Uncovered | Coverage |
| -------- | ------: | ----: | --------: | -------: |
| `root`   |       2 |     4 |         2 |    50.0% |
| `common` |     172 |   276 |       104 |   62.32% |
| `decode` |     383 |   524 |       141 |   73.09% |
| `encode` |    2621 |  3087 |       466 |    84.9% |

## Files

| File                          | Package  | Covered | Total | Uncovered | Coverage |
| ----------------------------- | -------- | ------: | ----: | --------: | -------: |
| `encode/encode.mbt`           | `encode` |    2143 |  2519 |       376 |   85.07% |
| `encode/encode_dict.mbt`      | `encode` |     237 |   284 |        47 |   83.45% |
| `decode/decode.mbt`           | `decode` |     105 |   151 |        46 |   69.54% |
| `common/error.mbt`            | `common` |      16 |    47 |        31 |   34.04% |
| `common/transform.mbt`        | `common` |      17 |    44 |        27 |   38.64% |
| `common/huffman.mbt`          | `common` |      89 |   111 |        22 |   80.18% |
| `encode/huffman_tree.mbt`     | `encode` |      63 |    83 |        20 |    75.9% |
| `decode/huffman_decode.mbt`   | `decode` |      72 |    92 |        20 |   78.26% |
| `encode/encode_hash.mbt`      | `encode` |     130 |   149 |        19 |   87.25% |
| `decode/block.mbt`            | `decode` |      31 |    48 |        17 |   64.58% |
| `decode/command_decode.mbt`   | `decode` |      54 |    69 |        15 |   78.26% |
| `common/distance.mbt`         | `common` |      14 |    27 |        13 |   51.85% |
| `decode/bit_reader.mbt`       | `decode` |      41 |    53 |        12 |   77.36% |
| `decode/transform_copy.mbt`   | `decode` |      15 |    25 |        10 |    60.0% |
| `decode/context_decode.mbt`   | `decode` |      37 |    47 |        10 |   78.72% |
| `decode/dictionary_copy.mbt`  | `decode` |       6 |    14 |         8 |   42.86% |
| `common/bits.mbt`             | `common` |      14 |    19 |         5 |   73.68% |
| `encode/suffix_tree.mbt`      | `encode` |      39 |    42 |         3 |   92.86% |
| `fbr.mbt`                     | `root`   |       2 |     4 |         2 |    50.0% |
| `decode/distance_decode.mbt`  | `decode` |      13 |    15 |         2 |   86.67% |
| `common/format_constants.mbt` | `common` |       2 |     4 |         2 |    50.0% |
| `common/context.mbt`          | `common` |       6 |     8 |         2 |    75.0% |
| `common/command.mbt`          | `common` |      14 |    16 |         2 |    87.5% |
| `encode/stream.mbt`           | `encode` |       9 |    10 |         1 |    90.0% |
| `decode/stream.mbt`           | `decode` |       9 |    10 |         1 |    90.0% |

## Key Findings

Files with the most uncovered lines:

- `encode/encode.mbt`: 376 uncovered lines, 85.07% covered
- `encode/encode_dict.mbt`: 47 uncovered lines, 83.45% covered
- `decode/decode.mbt`: 46 uncovered lines, 69.54% covered
- `common/error.mbt`: 31 uncovered lines, 34.04% covered
- `common/transform.mbt`: 27 uncovered lines, 38.64% covered

Lowest file coverage:

- `common/error.mbt`: 34.04% covered 16/47
- `common/transform.mbt`: 38.64% covered 17/44
- `decode/dictionary_copy.mbt`: 42.86% covered 6/14
- `fbr.mbt`: 50.0% covered 2/4
- `common/format_constants.mbt`: 50.0% covered 2/4

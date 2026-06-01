# fbr Coverage Analysis

Generated: `Mon Jun  1 18:41:00 2026`

Coverage source: `moon coverage analyze -- -f summary`

Generated temporary main packages such as `src/brotli_*_main/` are excluded from the totals.

## Summary

| Metric                     |  Value |
| -------------------------- | -----: |
| Coverage                   | 90.58% |
| Covered lines              |   3482 |
| Total instrumented lines   |   3844 |
| Uncovered lines            |    362 |
| Files in report            |     24 |
| Files with uncovered lines |     24 |
| Packages in report         |      4 |

## Packages

| Package  | Covered | Total | Uncovered | Coverage |
| -------- | ------: | ----: | --------: | -------: |
| `root`   |       2 |     4 |         2 |    50.0% |
| `decode` |     462 |   524 |        62 |   88.17% |
| `encode` |    2809 |  3087 |       278 |   90.99% |
| `common` |     209 |   229 |        20 |   91.27% |

## Files

| File                          | Package  | Covered | Total | Uncovered | Coverage |
| ----------------------------- | -------- | ------: | ----: | --------: | -------: |
| `encode/encode.mbt`           | `encode` |    2287 |  2519 |       232 |   90.79% |
| `encode/encode_dict.mbt`      | `encode` |     252 |   284 |        32 |   88.73% |
| `decode/command_decode.mbt`   | `decode` |      56 |    69 |        13 |   81.16% |
| `decode/huffman_decode.mbt`   | `decode` |      82 |    92 |        10 |   89.13% |
| `encode/encode_hash.mbt`      | `encode` |     140 |   149 |         9 |   93.96% |
| `decode/decode.mbt`           | `decode` |     142 |   151 |         9 |   94.04% |
| `decode/block.mbt`            | `decode` |      39 |    48 |         9 |   81.25% |
| `decode/transform_copy.mbt`   | `decode` |      19 |    25 |         6 |    76.0% |
| `decode/dictionary_copy.mbt`  | `decode` |       8 |    14 |         6 |   57.14% |
| `common/distance.mbt`         | `common` |      22 |    27 |         5 |   81.48% |
| `decode/context_decode.mbt`   | `decode` |      43 |    47 |         4 |   91.49% |
| `common/huffman.mbt`          | `common` |     107 |   111 |         4 |    96.4% |
| `common/bits.mbt`             | `common` |      16 |    19 |         3 |   84.21% |
| `fbr.mbt`                     | `root`   |       2 |     4 |         2 |    50.0% |
| `encode/suffix_tree.mbt`      | `encode` |      40 |    42 |         2 |   95.24% |
| `encode/huffman_tree.mbt`     | `encode` |      81 |    83 |         2 |   97.59% |
| `decode/distance_decode.mbt`  | `decode` |      13 |    15 |         2 |   86.67% |
| `decode/bit_reader.mbt`       | `decode` |      51 |    53 |         2 |   96.23% |
| `common/transform.mbt`        | `common` |      42 |    44 |         2 |   95.45% |
| `common/format_constants.mbt` | `common` |       2 |     4 |         2 |    50.0% |
| `common/context.mbt`          | `common` |       6 |     8 |         2 |    75.0% |
| `common/command.mbt`          | `common` |      14 |    16 |         2 |    87.5% |
| `encode/stream.mbt`           | `encode` |       9 |    10 |         1 |    90.0% |
| `decode/stream.mbt`           | `decode` |       9 |    10 |         1 |    90.0% |

## Key Findings

Files with the most uncovered lines:

- `encode/encode.mbt`: 232 uncovered lines, 90.79% covered
- `encode/encode_dict.mbt`: 32 uncovered lines, 88.73% covered
- `decode/command_decode.mbt`: 13 uncovered lines, 81.16% covered
- `decode/huffman_decode.mbt`: 10 uncovered lines, 89.13% covered
- `encode/encode_hash.mbt`: 9 uncovered lines, 93.96% covered

Lowest file coverage:

- `fbr.mbt`: 50.0% covered 2/4
- `common/format_constants.mbt`: 50.0% covered 2/4
- `decode/dictionary_copy.mbt`: 57.14% covered 8/14
- `common/context.mbt`: 75.0% covered 6/8
- `decode/transform_copy.mbt`: 76.0% covered 19/25

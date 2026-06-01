# Tools Agent Guide

These instructions apply to files under `tools/`.

## Audience And Defaults

This directory contains developer automation, mostly Nushell scripts. Prefer
stable `just` recipes when they exist, and call the underlying `nu` scripts
only when you need flags that the recipe does not expose.

Run tools from the repository root. Use repo-relative paths in examples and
docs.

## Nushell Style

- Keep scripts idiomatic Nushell: typed parameters, structured records/tables,
  and pipeline transforms over ad hoc string parsing.
- Use `parse`, `from json`, `to json`, `lines`, tables, and records instead of
  shell text scraping when structured data is available.
- Preserve existing output modes. Human output should be readable by default;
  agent-oriented or CI output should use `--json` when practical.
- Validate new or edited scripts with `nu -c 'source path/to/script.nu'` when
  sourcing is safe. For runnable scripts, also run the smallest safe smoke
  command.

## Brotli Harness Rules

Brotli scripts under `tools/` may generate temporary MoonBit files and
share `tools/.harness-lock`.

- Do not run conformance, fuzz, roundtrip, soak, or `target-perf` jobs in
  parallel unless the script explicitly supports it.
- Prefer existing wrappers in `tools/bench/target-perf.nu` for encode
  and decode timing so benchmark shape stays consistent.
- For performance comparisons, use same-time comparison scripts:
  `tools/bench/decode-compare.nu` for decode and
  `tools/bench/encode-compare.nu` for encode.
- Use `--json --quiet` for agent consumption, logs, and follow-up analysis.
  Use default table output for human-facing reports.

## Validation Choices

Match validation scope to the change:

- Docs-only changes: no full codec gate required; check formatting by reading
  the rendered Markdown source and run no-op command validation only if useful.
- Nushell script changes: parse with `nu -c 'source ...'` and run a minimal
  smoke command.
- Codec behavior changes: run focused `moon test` plus relevant Brotli tools
  such as `just conformance`, `just roundtrip`, `just ratio`, `just size`, or
  `just release-smoke`.
- Performance-sensitive changes: run `just encode-compare` or
  `just decode-compare`, or a smaller direct script matrix while iterating.

## Scratch Output

Keep generated corpora, benchmark runs, and build artifacts out of git. Use
`target/` for scratch output when adding scripts. Do not check in `_build/`,
`target/`, generated fuzz corpora, or local benchmark run directories.

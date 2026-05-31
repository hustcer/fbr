# Repository Guidelines

## Project Structure & Module Organization

This repository is a pure MoonBit Brotli encoder/decoder module named `hustcer/fbr`.
Source lives under `src/`; each directory is a MoonBit package with its own
`moon.pkg`:

- `src/common/`: shared Brotli constants, tables, dictionary, errors, and bit helpers.
- `src/decode/`: decoder implementation and decode stream API.
- `src/encode/`: encoder implementation, hash/tree helpers, and encode stream API.
- `src/tests/`: black-box integration tests and Brotli fixture files.
- `docs/`: benchmark reports, package rationale, and release notes.
- `tools/brotli/`: Nushell validation, fuzzing, size, and benchmark scripts.

Generated API summaries are checked in as `pkg.generated.mbti`; refresh them with
`moon info` when public APIs change.

## Build, Test, and Development Commands

Use `just` targets when possible:

- `just b`: run `moon build --target all`.
- `just lint`: run `moon check --target all`.
- `just test`: run `moon test --target all`.
- `just fmt`: run `moon info` and `moon fmt`.
- `just size` or `just size js,wasm-gc`: verify encode/decode package split artifacts.
- `just release-smoke`: quick practical release gate.
- `just release`: full validation gate, including conformance, ratio, fuzz, size,
  and packaging checks.

## Coding Style & Naming Conventions

Write idiomatic MoonBit. Keep files focused by package responsibility, and separate
top-level declarations with `///|`. Function and variable names are lowercase
snake_case, public types use PascalCase, and imports use module paths from
`moon.pkg`, not file names. Run `moon fmt` before submitting changes.

## Testing Guidelines

Place black-box tests in `*_test.mbt` and package white-box tests in `*_wbtest.mbt`.
Use `src/tests/brotli_fixtures/` for checked-in `.br` inputs and expected output
fixtures. For focused work, run `moon test src/decode` or `moon test src/tests`;
before handoff, run `just test` and `just lint`. Codec or performance-sensitive
changes should also run the relevant `just conformance`, `just roundtrip`,
`just size`, or `just release-smoke` gate.

## Commit & Pull Request Guidelines

Recent commits use short, imperative, capitalized subjects, for example
`Reduce q4 Brotli output size by 2%`. Keep commits scoped to one change. Pull
requests should describe the affected package/API, list validation commands run,
link related issues, and include benchmark or artifact size notes when compression
ratio, speed, or package split behavior changes.

## Security & Configuration Tips

Do not commit generated corpora, local benchmark scratch files, or build outputs
from `_build/` and `target/`. Keep release fixtures deterministic, and prefer the
existing Nushell scripts under `tools/brotli/` for validation rather than ad hoc
local commands.

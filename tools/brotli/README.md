# Brotli Tools

These helpers support the Brotli implementation work. Run them from the
repository root.

## Fixture Generator

```bash
nu tools/brotli/gen-fixtures.nu
```

Regenerates `src/brotli_fixture_wbtest.mbt` and copies the selected upstream
fixtures into `src/tests/brotli_fixtures/`.

## Conformance Harness

```bash
nu tools/brotli/conformance/run.nu
nu tools/brotli/conformance/run.nu --fixture monkey
```

Runs the upstream corpus at `/Users/hustcer/iWork/refs/brotli/tests/testdata`
through `unbrotli_sync`. The harness writes a temporary
`src/brotli_conformance_wbtest.mbt`, runs one native MoonBit test per fixture,
then removes the temporary file.

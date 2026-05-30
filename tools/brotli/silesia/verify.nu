#!/usr/bin/env nu

# Legacy JS file-IO verifier for large acceptance artifacts. Keep performance
# measurements on target-perf.nu so wasm-gc/native stay the default signal.

const default_compressed = "target/brotli-silesia/silesia-100m.bin.br"
const default_expected = "target/brotli-silesia/silesia-100m.bin"
const generated_test = "_build/js/debug/test/decode/decode.whitebox_test.js"
const temp_dir = "target/brotli-silesia"
const temp_runner = "target/brotli-silesia/verify-generated.js"

def main [
  compressed: string = $default_compressed
  expected: string = $default_expected
  --max-output-size: int # Override the expected-size output cap.
]: nothing -> nothing {
  if not ($compressed | path exists) {
    print --stderr $"Missing compressed Brotli input: ($compressed)"
    exit 1
  }
  if not ($expected | path exists) {
    print --stderr $"Missing expected output: ($expected)"
    exit 1
  }

  let build = (moon test --target js --filter "brotli fixture empty" | complete)
  if $build.exit_code != 0 {
    print --stderr $build.stdout
    print --stderr $build.stderr
    exit $build.exit_code
  }

  mkdir $temp_dir
  let expected_size = (ls $expected | get size.0 | into int)
  let output_cap = ($max_output_size | default $expected_size)
  let compressed_abs = ($compressed | path expand)
  let expected_abs = ($expected | path expand)
  let generated_abs = ($generated_test | path expand)

  let compressed_json = ($compressed_abs | to json --raw)
  let expected_json = ($expected_abs | to json --raw)
  let generated_json = ($generated_abs | to json --raw)
  let runner = (
    [
      "const fs = require('fs');"
      "const crypto = require('crypto');"
      "const vm = require('vm');"
      $"const compressedPath = ($compressed_json);"
      $"const expectedPath = ($expected_json);"
      $"const generatedPath = ($generated_json);"
      "let src = fs.readFileSync(generatedPath, 'utf8');"
      "const idx = src.indexOf('\\n(() => {\\n  const test_params');"
      "if (idx < 0) { throw new Error('MoonBit JS test-runner marker not found'); }"
      "src = src.slice(0, idx);"
      "src += \"\\n(() => {\\n\" +"
      "  \"  const fs = require('fs');\\n\" +"
      "  \"  const crypto = require('crypto');\\n\" +"
      "  \"  const compressed = fs.readFileSync(\" + JSON.stringify(compressedPath) + \");\\n\" +"
      "  \"  const expected = fs.readFileSync(\" + JSON.stringify(expectedPath) + \");\\n\" +"
      ("  \"  const opts = new _M0TP37hustcer3fbr6decode15UnbrotliOptions(undefined, " + ($output_cap | into string) + ", compressed.length + 1);\\n\" +")
      "  \"  const result = _M0FP37hustcer3fbr6decode22unbrotli__sync_2einner(compressed, opts);\\n\" +"
      "  \"  if (result.$tag !== 1) { console.error('decode failed', result._0); process.exit(1); }\\n\" +"
      "  \"  const out = Buffer.from(result._0);\\n\" +"
      "  \"  const sha = crypto.createHash('sha256').update(out).digest('hex');\\n\" +"
      "  \"  const expectedSha = crypto.createHash('sha256').update(expected).digest('hex');\\n\" +"
      "  \"  console.log(JSON.stringify({purpose: 'file-io-verification', moonbit_backend: 'legacy-js', decoded_size: out.length, sha256: sha, expected_size: expected.length, expected_sha256: expectedSha}));\\n\" +"
      "  \"  if (out.length !== expected.length || sha !== expectedSha) { process.exit(1); }\\n\" +"
      "  \"})();\\n\";"
      "vm.runInNewContext(src, {require, console, process, Buffer, Uint8Array, exports: {}, module: {exports: {}}}, {filename: 'fbr.decode.whitebox_test.silesia.js'});"
    ]
    | str join (char newline)
  )

  $runner | save --force $temp_runner
  let run = (node $temp_runner | complete)
  rm --force $temp_runner
  print $run.stdout
  if $run.exit_code != 0 {
    print --stderr $run.stderr
    exit $run.exit_code
  }
}

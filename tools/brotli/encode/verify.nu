#!/usr/bin/env nu

const generated_test = "_build/js/debug/test/fzip.whitebox_test.js"
const temp_dir = "target/brotli-encode"
const temp_runner = "target/brotli-encode/verify-generated.js"

def main [
  input: string
  --quality (-q): int = 1
  --window-bits: int = 22
]: nothing -> nothing {
  if not ($input | path exists) {
    print --stderr $"Missing input file: ($input)"
    exit 1
  }

  let build = (moon test --target js --filter "brotli_sync q0 encodes empty stream" | complete)
  if $build.exit_code != 0 {
    print --stderr $build.stdout
    print --stderr $build.stderr
    exit $build.exit_code
  }

  mkdir $temp_dir
  let input_abs = ($input | path expand)
  let encoded = (
    $temp_dir
    | path join $"(($input | path basename)).q($quality).br"
    | path expand
  )
  let decoded = $"($encoded).decoded"
  let generated_abs = ($generated_test | path expand)

  let input_json = ($input_abs | to json --raw)
  let encoded_json = ($encoded | to json --raw)
  let generated_json = ($generated_abs | to json --raw)
  let runner = (
    [
      "const fs = require('fs');"
      "const crypto = require('crypto');"
      "const vm = require('vm');"
      $"const inputPath = ($input_json);"
      $"const encodedPath = ($encoded_json);"
      $"const generatedPath = ($generated_json);"
      $"const quality = ($quality);"
      $"const windowBits = ($window_bits);"
      "let src = fs.readFileSync(generatedPath, 'utf8');"
      "const idx = src.indexOf('\\n(() => {\\n  const test_params');"
      "if (idx < 0) { throw new Error('MoonBit JS test-runner marker not found'); }"
      "src = src.slice(0, idx);"
      "src += \"\\n(() => {\\n\" +"
      "  \"  const fs = require('fs');\\n\" +"
      "  \"  const crypto = require('crypto');\\n\" +"
      "  \"  const input = fs.readFileSync(\" + JSON.stringify(inputPath) + \");\\n\" +"
      "  \"  const opts = new _M0TP27hustcer4fzip13BrotliOptions(\" + quality + \", \" + windowBits + \");\\n\" +"
      "  \"  const result = _M0FP27hustcer4fzip20brotli__sync_2einner(input, opts);\\n\" +"
      "  \"  if (result.$tag !== 1) { console.error('encode failed', result._0); process.exit(1); }\\n\" +"
      "  \"  const out = Buffer.from(result._0);\\n\" +"
      "  \"  fs.writeFileSync(\" + JSON.stringify(encodedPath) + \", out);\\n\" +"
      "  \"  console.log(JSON.stringify({input_size: input.length, encoded_size: out.length, encoded_sha256: crypto.createHash('sha256').update(out).digest('hex')}));\\n\" +"
      "  \"})();\\n\";"
      "vm.runInNewContext(src, {require, console, process, Buffer, Uint8Array, exports: {}, module: {exports: {}}}, {filename: 'fzip.whitebox_test.encode.js'});"
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

  let decode = (bash -lc 'brotli -d --stdout "$1" > "$2"' _ $encoded $decoded | complete)
  if $decode.exit_code != 0 {
    print --stderr $decode.stderr
    exit $decode.exit_code
  }
  let same = (cmp $decoded $input_abs | complete)
  if $same.exit_code != 0 {
    print --stderr $same.stderr
    exit $same.exit_code
  }
  let decoded_sha = (open --raw $decoded | hash sha256)
  let input_sha = (open --raw $input_abs | hash sha256)
  rm --force $decoded
  print (
    {
      external_decoder: "brotli",
      quality: $quality,
      decoded_sha256: $decoded_sha,
      input_sha256: $input_sha,
      encoded: $encoded,
    } | to json --raw
  )
}

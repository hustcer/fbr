#!/usr/bin/env nu

const temp_test = "src/brotli_target_perf_wbtest.mbt"
const bench_dir = "target/brotli-bench"

def parse-csv-ints [text: string]: nothing -> list<int> {
  $text | split row "," | each {|value| $value | str trim | into int }
}

def parse-csv-strings [text: string]: nothing -> list<string> {
  $text | split row "," | each {|value| $value | str trim }
}

def parse-first-json-line [text: string]: nothing -> record {
  $text
  | lines
  | where {|line| ($line | str trim) != "" }
  | first
  | from json
}

def make-temp-test [
  mode: string
  input: string
  quality: int
  repeats: int
  expected_total: int
  max_output_size: int
]: nothing -> nothing {
  let input_abs = ($input | path expand)
  let node_code = '
const fs = require("fs");
const [inputPath, mode, qualityText, repeatsText, expectedTotalText, maxOutputText, outPath] = process.argv.slice(1);
const data = fs.readFileSync(inputPath);
const quality = Number(qualityText);
const repeats = Number(repeatsText);
const expectedTotal = Number(expectedTotalText);
const maxOutput = Number(maxOutputText);
const rows = [];
for (let i = 0; i < data.length; i += 16) {
  rows.push("  " + Array.from(data.slice(i, i + 16), b =>
    "0x" + b.toString(16).toUpperCase().padStart(2, "0")
  ).join(", "));
}
const literal = rows.join(",\n");
let body;
if (mode === "decode") {
  body = `    let decoded = unbrotli_sync(
      input,
      opts={ out: None, max_output_size: ${maxOutput}, max_input_size: input.length() + 1 },
    )
    total += decoded.length()`;
} else if (mode === "encode") {
  body = `    let encoded = brotli_sync(
      input,
      opts={ quality: ${quality}, window_bits: 22, max_input_size: input.length() + 1 },
    )
    total += encoded.length()`;
} else {
  throw new Error("unsupported mode: " + mode);
}
const content = `///|
test "brotli target perf generated" {
  let input : FixedArray[Byte] = [
${literal}
  ]
  let mut total = 0
  for _ in 0..<${repeats} {
${body}
  }
  inspect(total, content="${expectedTotal}")
}
`;
fs.writeFileSync(outPath, content);
'
  node -e $node_code $input_abs $mode ($quality | into string) ($repeats | into string) ($expected_total | into string) ($max_output_size | into string) $temp_test
}

def run-target [
  target: string
  repeats: int
  samples: int
]: nothing -> record {
  let filter = "brotli target perf generated"
  let warmup = (moon test --target $target --filter $filter | complete)
  if $warmup.exit_code != 0 {
    print --stderr $warmup.stdout
    print --stderr $warmup.stderr
    exit $warmup.exit_code
  }
  mut times = []
  for _ in 0..<$samples {
    let started = date now
    let run = (moon test --target $target --filter $filter | complete)
    let elapsed = ((date now) - $started | into int) / 1_000_000
    if $run.exit_code != 0 {
      print --stderr $run.stdout
      print --stderr $run.stderr
      exit $run.exit_code
    }
    $times = ($times | append $elapsed)
  }
  {
    target: $target,
    total_min_ms: ($times | math min),
    total_avg_ms: ($times | math avg),
    per_op_min_ms: (($times | math min) / $repeats),
    per_op_avg_ms: (($times | math avg) / $repeats),
    samples_ms: $times,
  }
}

def google-decode [
  compressed: string
  repeats: int
  samples: int
]: nothing -> record {
  let compressed_abs = ($compressed | path expand)
  mut times = []
  for _ in 0..<$samples {
    let started = date now
    let run = (
      bash -lc 'for i in $(seq 1 "$1"); do brotli -d -c "$2" > /dev/null || exit 1; done' _ ($repeats | into string) $compressed_abs
      | complete
    )
    let elapsed = ((date now) - $started | into int) / 1_000_000
    if $run.exit_code != 0 {
      print --stderr $run.stderr
      exit $run.exit_code
    }
    $times = ($times | append $elapsed)
  }
  {
    target: "google",
    total_min_ms: ($times | math min),
    total_avg_ms: ($times | math avg),
    per_op_min_ms: (($times | math min) / $repeats),
    per_op_avg_ms: (($times | math avg) / $repeats),
    samples_ms: $times,
  }
}

def google-encode [
  input: string
  quality: int
  repeats: int
  samples: int
]: nothing -> record {
  mkdir $bench_dir
  let input_abs = ($input | path expand)
  let out = (
    $bench_dir
    | path join $"(($input | path basename)).google.q($quality).br"
    | path expand
  )
  let size_run = (bash -lc 'brotli -q "$1" -c "$2" > "$3"' _ ($quality | into string) $input_abs $out | complete)
  if $size_run.exit_code != 0 {
    print --stderr $size_run.stderr
    exit $size_run.exit_code
  }
  mut times = []
  for _ in 0..<$samples {
    let started = date now
    let run = (
      bash -lc 'for i in $(seq 1 "$1"); do brotli -q "$2" -c "$3" > /dev/null || exit 1; done' _ ($repeats | into string) ($quality | into string) $input_abs
      | complete
    )
    let elapsed = ((date now) - $started | into int) / 1_000_000
    if $run.exit_code != 0 {
      print --stderr $run.stderr
      exit $run.exit_code
    }
    $times = ($times | append $elapsed)
  }
  {
    target: "google",
    encoded_size: (ls $out | get size.0 | into int),
    total_min_ms: ($times | math min),
    total_avg_ms: ($times | math avg),
    per_op_min_ms: (($times | math min) / $repeats),
    per_op_avg_ms: (($times | math avg) / $repeats),
    samples_ms: $times,
  }
}

def moonbit-encoded-size [
  input: string
  quality: int
]: nothing -> record {
  let run = (nu tools/brotli/encode/verify.nu $input --quality $quality | complete)
  if $run.exit_code != 0 {
    print --stderr $run.stdout
    print --stderr $run.stderr
    exit $run.exit_code
  }
  parse-first-json-line $run.stdout
}

def main [
  input: string
  --mode (-m): string = "decode" # decode or encode
  --expected (-e): string = "" # Required for decode: uncompressed expected file
  --quality (-q): int = 11 # Used for encode
  --targets (-t): string = "wasm-gc,native"
  --repeats (-r): int = 10
  --samples (-s): int = 5
  --json
]: nothing -> nothing {
  if $mode != "decode" and $mode != "encode" {
    print --stderr $"Unsupported mode: ($mode)"
    exit 1
  }
  if not ($input | path exists) {
    print --stderr $"Missing benchmark input: ($input)"
    exit 1
  }
  if $mode == "decode" and (($expected | str trim) == "" or not ($expected | path exists)) {
    print --stderr "Decode mode requires --expected <uncompressed-file>"
    exit 1
  }

  let targets = parse-csv-strings $targets
  let input_size = (ls $input | get size.0 | into int)
  mut rows = []

  if $mode == "decode" {
    let decoded_size = (ls $expected | get size.0 | into int)
    let expected_total = $decoded_size * $repeats
    make-temp-test decode $input 0 $repeats $expected_total $decoded_size
    let google = google-decode $input $repeats $samples
    for target in $targets {
      let measured = run-target $target $repeats $samples
      $rows = ($rows | append {
        mode: "decode",
        target: $target,
        input_bytes: $input_size,
        decoded_bytes: $decoded_size,
        target_min_ms: $measured.per_op_min_ms,
        target_avg_ms: $measured.per_op_avg_ms,
        google_min_ms: $google.per_op_min_ms,
        google_avg_ms: $google.per_op_avg_ms,
        slowdown_min: ($measured.per_op_min_ms / $google.per_op_min_ms),
        slowdown_avg: ($measured.per_op_avg_ms / $google.per_op_avg_ms),
      })
    }
  } else {
    let moon = moonbit-encoded-size $input $quality
    let google = google-encode $input $quality $repeats $samples
    let expected_total = $moon.encoded_size * $repeats
    make-temp-test encode $input $quality $repeats $expected_total 0
    for target in $targets {
      let measured = run-target $target $repeats $samples
      $rows = ($rows | append {
        mode: "encode",
        target: $target,
        quality: $quality,
        input_bytes: $input_size,
        moonbit_size: $moon.encoded_size,
        google_size: $google.encoded_size,
        size_overhead: (($moon.encoded_size - $google.encoded_size) / $google.encoded_size),
        target_min_ms: $measured.per_op_min_ms,
        target_avg_ms: $measured.per_op_avg_ms,
        google_min_ms: $google.per_op_min_ms,
        google_avg_ms: $google.per_op_avg_ms,
        slowdown_min: ($measured.per_op_min_ms / $google.per_op_min_ms),
        slowdown_avg: ($measured.per_op_avg_ms / $google.per_op_avg_ms),
      })
    }
  }

  rm --force $temp_test
  if $json {
    print ($rows | to json --raw)
  } else {
    print ($rows | table)
  }
}

#!/usr/bin/env nu

const default_output = "docs/brotli_release_report.md"
const default_work_dir = "docs/current-bench"
const default_encode_inputs = "target/brotli-bench/silesia-64k.bin,target/brotli-bench/silesia-128k.bin"
const default_decode_input = "target/brotli-bench/silesia-1m.bin"
const default_qualities = "0,1,2,3,4,5,6,7,8,9,10,11"

def parse-csv-ints [text: string]: nothing -> list<int> {
  $text | split row "," | each {|value| $value | str trim | into int }
}

def parse-csv-strings [text: string]: nothing -> list<string> {
  $text | split row "," | each {|value| $value | str trim }
}

def parse-first-json-line [text: string]: nothing -> any {
  $text
  | lines
  | where {|line| ($line | str trim) != "" }
  | first
  | from json
}

def require-command [name: string]: nothing -> nothing {
  if (which $name | is-empty) {
    print --stderr $"Missing required command: ($name)"
    exit 1
  }
}

def require-file [path: string]: nothing -> nothing {
  if not ($path | path exists) {
    print --stderr $"Missing benchmark input: ($path)"
    exit 1
  }
}

def run-or-exit [name: string, action: closure]: nothing -> record {
  print $"==> ($name)"
  let result = do $action
  if $result.exit_code != 0 {
    print --stderr $result.stdout
    print --stderr $result.stderr
    print --stderr $"Benchmark step failed: ($name)"
    exit $result.exit_code
  }
  $result
}

def append-jsonl [path: string, rows: list<any>]: nothing -> nothing {
  let text = (
    $rows
    | each {|row| $row | to json --raw }
    | str join (char newline)
  )
  if ($text | str length) > 0 {
    ($text + (char newline)) | save --append $path
  }
}

def file-size [path: string]: nothing -> int {
  ls $path | get size.0 | into int
}

def file-sha256 [path: string]: nothing -> string {
  open --raw $path | hash sha256
}

def format-int [value: int]: nothing -> string {
  let text = $value | into string
  $text
  | split chars
  | reverse
  | chunks 3
  | each {|chunk| $chunk | reverse | str join }
  | reverse
  | str join ","
}

def format-float [value: float, precision: int = 3]: nothing -> string {
  $value | math round --precision $precision | into string
}

def format-percent [value: float]: nothing -> string {
  let percent = $value * 100
  let text = format-float $percent 2
  if $percent > 0 {
    $"+($text)%"
  } else {
    $"($text)%"
  }
}

def format-slowdown [value: float]: nothing -> string {
  $"(format-float $value 2)x"
}

def input-label [path: string]: nothing -> string {
  $path | path basename | str replace ".bin" ""
}

def markdown-table [
  headers: list<string>
  rows: list<list<string>>
]: nothing -> list<string> {
  let header = $"| ($headers | str join ' | ') |"
  let separator = $"| ($headers | each { '---' } | str join ' | ') |"
  let body = $rows | each {|row| $"| ($row | str join ' | ') |" }
  [$header $separator] | append $body
}

def run-encode-benchmark [
  input: string
  quality: int
  targets: string
  repeats: int
  samples: int
]: nothing -> list<record> {
  let result = run-or-exit $"encode (input-label $input) q($quality)" {
    nu tools/brotli/bench/target-perf.nu $input --mode encode --quality $quality --targets $targets --repeats $repeats --samples $samples --json
    | complete
  }
  parse-first-json-line $result.stdout
  | each {|row|
    $row
    | insert input $input
    | insert input_label (input-label $input)
  }
}

def google-encode-for-decode [
  input: string
  quality: int
  out_dir: string
]: nothing -> string {
  mkdir $out_dir
  let out = $out_dir | path join $"((input-label $input)).q($quality).br"
  run-or-exit $"google encode decode input q($quality)" {
    bash -lc 'brotli -q "$1" -f -c "$2" > "$3"' _ ($quality | into string) $input $out
    | complete
  } | ignore
  $out
}

def run-decode-benchmark [
  expected: string
  quality: int
  targets: string
  repeats: int
  samples: int
  google_dir: string
]: nothing -> list<record> {
  let compressed = google-encode-for-decode $expected $quality $google_dir
  let result = run-or-exit $"decode Google q($quality)" {
    nu tools/brotli/bench/target-perf.nu $compressed --mode decode --expected $expected --targets $targets --repeats $repeats --samples $samples --json
    | complete
  }
  parse-first-json-line $result.stdout
  | each {|row|
    $row
    | insert input $compressed
    | insert input_label $"Google q($quality)"
    | insert google_quality $quality
  }
}

def env-table [
  date: string
  repeats: int
  samples: int
  targets: string
]: nothing -> list<string> {
  let moon_version = moon version | lines | first
  let brotli_version = brotli --version | str trim
  markdown-table [Item Value] [
    [Date $date]
    [MoonBit $"`($moon_version)`"]
    ["Google Brotli CLI" $"`($brotli_version)`"]
    ["MoonBit profile" "release, via `tools/brotli/bench/target-perf.nu`"]
    ["MoonBit targets" $"`($targets)`"]
    ["Timing shape" $"`--repeats ($repeats) --samples ($samples)`; tables report per-operation min and avg"]
  ]
}

def inputs-table [paths: list<string>]: nothing -> list<string> {
  let rows = (
    $paths
    | uniq
    | each {|path|
      [
        $"`($path)`"
        (format-int (file-size $path))
        $"`(file-sha256 $path)`"
      ]
    }
  )
  markdown-table [File Bytes SHA-256] $rows
}

def raw-files-table [paths: list<string>]: nothing -> list<string> {
  let rows = (
    $paths
    | where {|path| $path | path exists }
    | each {|path| [$"`($path)`" $"`(file-sha256 $path)`"] }
  )
  markdown-table [File SHA-256] $rows
}

def encode-table [
  rows: list<record>
  label: string
]: nothing -> list<string> {
  let table_rows = (
    $rows
    | where input_label == $label
    | sort-by quality target
    | each {|row|
      [
        $"q($row.quality)"
        $row.target
        $row.native_cc
        (format-int $row.moonbit_size)
        (format-int $row.google_size)
        (format-percent $row.size_overhead)
        (format-float $row.target_min_ms)
        (format-float $row.target_avg_ms)
        (format-float $row.google_min_ms)
        (format-float $row.google_avg_ms)
        (format-slowdown $row.slowdown_min)
      ]
    }
  )
  markdown-table [
    Quality
    Target
    "Native CC"
    "MoonBit bytes"
    "Google bytes"
    "Size overhead"
    "MoonBit min ms"
    "MoonBit avg ms"
    "Google min ms"
    "Google avg ms"
    "Slowdown min"
  ] $table_rows
}

def decode-table [rows: list<record>]: nothing -> list<string> {
  let table_rows = (
    $rows
    | sort-by google_quality target
    | each {|row|
      [
        $"q($row.google_quality)"
        $row.target
        $row.native_cc
        (format-int $row.input_bytes)
        (format-int $row.decoded_bytes)
        (format-float $row.target_min_ms)
        (format-float $row.target_avg_ms)
        (format-float $row.google_min_ms)
        (format-float $row.google_avg_ms)
        (format-slowdown $row.slowdown_min)
      ]
    }
  )
  markdown-table [
    "Google quality"
    Target
    "Native CC"
    "Compressed bytes"
    "Decoded bytes"
    "MoonBit min ms"
    "MoonBit avg ms"
    "Google min ms"
    "Google avg ms"
    "Slowdown min"
  ] $table_rows
}

def render-report [
  output: string
  encode_rows: list<record>
  decode_rows: list<record>
  encode_inputs: list<string>
  decode_input: string
  raw_files: list<string>
  repeats: int
  samples: int
  targets: string
]: nothing -> nothing {
  let date = date now | format date "%Y-%m-%d"
  let input_paths = $encode_inputs | append $decode_input
  let decode_label = input-label $decode_input
  let encode_sections = (
    $encode_inputs
    | each {|input|
      let label = input-label $input
      [
        $"## Encode, ($label)"
        ""
      ]
      | append (encode-table $encode_rows $label)
      | append [""]
    }
    | flatten
  )
  let lines = (
    [
      "# Brotli Release Readiness Report"
      ""
      $"Date: ($date)"
      ""
      "This report is generated by `just bench`. It summarizes the current release-build Brotli benchmark results against the Google Brotli CLI."
      ""
      "The benchmark entry point is the reproducible way to regenerate these results."
      ""
      "## Executive Summary"
      ""
      "- Brotli decode and encode entry points are benchmarked through the release `target-perf` harness."
      "- Encode tables include compressed size and time. Decode tables measure decoding Google-produced `.br` streams and report time only, with compressed size shown for context."
      "- q0 and q1 currently emit valid stored streams and are not intended to match Google Brotli's low-quality compression ratio."
      "- q10 and q11 remain valid but larger than Google output in the current high-quality range."
      ""
      "## Environment"
      ""
    ]
    | append (env-table $date $repeats $samples $targets)
    | append [
      ""
      "## Inputs"
      ""
    ]
    | append (inputs-table $input_paths)
    | append [
      ""
      "Raw result files from this run:"
      ""
    ]
    | append (raw-files-table $raw_files)
    | append [
      ""
    ]
    | append $encode_sections
    | append [
      $"## Decode, ($decode_label) Google Streams"
      ""
      $"Each input stream in this table was produced by Google `brotli -q <quality>` from `($decode_input)`."
      ""
    ]
    | append (decode-table $decode_rows)
    | append [
      ""
      "## Notes"
      ""
      "- Timing is command-harness timing, not an isolated in-process library microbenchmark."
      "- Use the same `just bench` entry point when comparing future changes."
      ""
    ]
  )
  $lines | str join (char newline) | save --force $output
}

def main [
  --output (-o): string = $default_output
  --work-dir: string = $default_work_dir
  --encode-inputs: string = $default_encode_inputs
  --decode-input: string = $default_decode_input
  --qualities (-q): string = $default_qualities
  --targets (-t): string = "wasm-gc,native"
  --repeats (-r): int = 3
  --samples (-s): int = 3
]: nothing -> nothing {
  require-command moon
  require-command brotli
  require-command node

  let encode_input_list = parse-csv-strings $encode_inputs
  let quality_values = parse-csv-ints $qualities
  for input in $encode_input_list {
    require-file $input
  }
  require-file $decode_input

  mkdir $work_dir
  let encode_jsonl = $work_dir | path join "encode.jsonl"
  let decode_jsonl = $work_dir | path join "decode.jsonl"
  let google_dir = $work_dir | path join "google-1m"
  rm --force $encode_jsonl
  rm --force $decode_jsonl

  mut encode_rows = []
  for input in $encode_input_list {
    for quality in $quality_values {
      let rows = run-encode-benchmark $input $quality $targets $repeats $samples
      append-jsonl $encode_jsonl $rows
      $encode_rows = $encode_rows | append $rows
    }
  }

  mut decode_rows = []
  for quality in $quality_values {
    let rows = run-decode-benchmark $decode_input $quality $targets $repeats $samples $google_dir
    append-jsonl $decode_jsonl $rows
    $decode_rows = $decode_rows | append $rows
  }

  render-report $output $encode_rows $decode_rows $encode_input_list $decode_input [$encode_jsonl $decode_jsonl] $repeats $samples $targets
  print $"Wrote ($output)"
}

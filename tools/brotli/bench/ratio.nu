#!/usr/bin/env nu

const bench_dir = "target/brotli-bench"

def parse-first-json-line [text: string]: nothing -> record {
  $text
  | lines
  | where {|line| ($line | str trim) != "" }
  | first
  | from json
}

def google-encode [
  input: string
  quality: int
]: nothing -> record {
  mkdir $bench_dir
  let input_abs = ($input | path expand)
  let out = (
    $bench_dir
    | path join $"(($input | path basename)).google.q($quality).br"
    | path expand
  )
  let run = (bash -lc 'brotli -q "$1" -c "$2" > "$3"' _ ($quality | into string) $input_abs $out | complete)
  if $run.exit_code != 0 {
    print --stderr $run.stderr
    exit $run.exit_code
  }
  let input_size = (ls $input_abs | get size.0 | into int)
  let encoded_size = (ls $out | get size.0 | into int)
  {
    encoder: "google",
    quality: $quality,
    input_size: $input_size,
    encoded_size: $encoded_size,
    ratio: ($input_size / $encoded_size),
    encoded: $out,
  }
}

def moonbit-encode [
  input: string
  quality: int
]: nothing -> record {
  let run = (nu tools/brotli/encode/verify.nu $input --quality $quality | complete)
  if $run.exit_code != 0 {
    print --stderr $run.stdout
    print --stderr $run.stderr
    exit $run.exit_code
  }
  let encoded = parse-first-json-line $run.stdout
  {
    encoder: "moonbit",
    quality: $quality,
    input_size: $encoded.input_size,
    encoded_size: $encoded.encoded_size,
    ratio: ($encoded.input_size / $encoded.encoded_size),
    encoded_sha256: $encoded.encoded_sha256,
  }
}

def main [
  input: string
  --qualities (-q): string = "0,1,2,9,10,11"
]: nothing -> nothing {
  if not ($input | path exists) {
    print --stderr $"Missing benchmark input: ($input)"
    exit 1
  }

  let quality_values = (
    $qualities
    | split row ","
    | each {|value| $value | str trim | into int }
  )

  mut rows = []
  for quality in $quality_values {
    let moon = moonbit-encode $input $quality
    let google = google-encode $input $quality
    let overhead = (($moon.encoded_size - $google.encoded_size) / $google.encoded_size)
    $rows = ($rows | append {
      quality: $quality,
      moonbit_size: $moon.encoded_size,
      google_size: $google.encoded_size,
      moonbit_ratio: $moon.ratio,
      google_ratio: $google.ratio,
      size_overhead: $overhead,
      moonbit_sha256: $moon.encoded_sha256,
      google_encoded: $google.encoded,
    })
  }

  print ($rows | table)
}

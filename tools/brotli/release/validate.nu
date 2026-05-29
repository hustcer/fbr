#!/usr/bin/env nu

const default_silesia_2m = "target/brotli-bench/silesia-2m.bin"
const default_silesia_1m = "target/brotli-bench/silesia-1m.bin"

def elapsed-ms [started: datetime]: nothing -> int {
  (date now) - $started | into int | $in / 1_000_000
}

def run-step [name: string, action: closure]: nothing -> record {
  print $"==> ($name)"
  let started = date now
  let result = do $action
  let elapsed = elapsed-ms $started
  if $result.exit_code != 0 {
    print --stderr $result.stdout
    print --stderr $result.stderr
    print --stderr $"Release validation failed at: ($name)"
    exit $result.exit_code
  }
  {step: $name, ok: true, elapsed_ms: $elapsed}
}

def require-file [path: string]: nothing -> nothing {
  if not ($path | path exists) {
    print --stderr $"Missing release validation input: ($path)"
    exit 1
  }
}

def append-step [results: list<record>, name: string, action: closure]: nothing -> list<record> {
  $results | append (run-step $name $action)
}

def main [
  --silesia-2m: string = $default_silesia_2m
  --silesia-1m: string = $default_silesia_1m
  --decoder-fuzz-limit: int = 0
  --decoder-fuzz-target: string = "native"
  --roundtrip-count: int = 12
  --roundtrip-max-len: int = 2048
  --roundtrip-qualities: string = "0,1,2,9,11"
  --roundtrip-target: string = "native"
  --skip-moon
  --skip-ratio
  --skip-fuzz
]: nothing -> nothing {
  require-file $silesia_2m
  require-file $silesia_1m

  mut results = []

  if not $skip_moon {
    $results = append-step $results "moon fmt" { moon fmt | complete }
    $results = append-step $results "moon check --target all" { moon check --target all | complete }
    $results = append-step $results "moon test --target all" { moon test --target all | complete }
    $results = append-step $results "moon info" { moon info | complete }
    $results = append-step $results "git diff --check" { git diff --check | complete }
  }

  $results = append-step $results "Brotli conformance corpus" {
    nu tools/brotli/conformance/run.nu | complete
  }

  if not $skip_ratio {
    for quality in [0 1] {
      $results = append-step $results $"q($quality) 2MiB external decode" {
        nu tools/brotli/encode/verify.nu $silesia_2m --quality $quality | complete
      }
    }

    $results = append-step $results "q2..q9 2MiB ratio and external decode" {
      nu tools/brotli/bench/ratio.nu $silesia_2m --qualities 2,3,4,5,6,7,8,9 --json | complete
    }
    $results = append-step $results "q10..q11 1MiB ratio-exception decode" {
      nu tools/brotli/bench/ratio.nu $silesia_1m --qualities 10,11 --json | complete
    }
  }

  if not $skip_fuzz {
    let decoder_fuzz_args = if $decoder_fuzz_limit > 0 {
      [
        "tools/brotli/fuzz/run.nu"
        "--limit"
        ($decoder_fuzz_limit | into string)
        "--target"
        $decoder_fuzz_target
      ]
    } else {
      ["tools/brotli/fuzz/run.nu" "--target" $decoder_fuzz_target]
    }
    $results = append-step $results "decoder fuzz corpus" {
      nu ...$decoder_fuzz_args | complete
    }

    let roundtrip_args = [
      "tools/brotli/fuzz/roundtrip.nu"
      "--count"
      ($roundtrip_count | into string)
      "--max-len"
      ($roundtrip_max_len | into string)
      "--qualities"
      $roundtrip_qualities
      "--target"
      $roundtrip_target
    ]
    $results = append-step $results "encoder roundtrip fuzz" {
      nu ...$roundtrip_args | complete
    }
  }

  print ""
  print "Brotli release validation passed:"
  print ($results | table)
}

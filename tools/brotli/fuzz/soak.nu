#!/usr/bin/env nu

const default_log = "target/brotli-fuzz-soak/soak.jsonl"

def elapsed-ms [started: datetime]: nothing -> int {
  (date now) - $started | into int | $in / 1_000_000
}

def append-log [path: string, row: record]: nothing -> nothing {
  mkdir ($path | path dirname)
  ($row | to json --raw) + (char newline) | save --append $path
}

def logged-max-iteration [path: string]: nothing -> int {
  if not ($path | path exists) {
    return 0
  }
  # Long soaks may be resumed from a partially written JSONL log. Ignore
  # malformed or unrelated rows so one bad line does not discard useful
  # progress evidence.
  let iterations = (
    open --raw $path
    | lines
    | where {|line| ($line | str trim | str length) > 0 }
    | each {|line|
      try {
        $line | from json
      } catch {
        null
      }
    }
    | each {|row|
      if $row == null or ($row.iteration? | default null) == null {
        null
      } else {
        try {
          $row.iteration | into int
        } catch {
          null
        }
      }
    }
    | where {|iteration| $iteration != null }
  )
  if ($iterations | length) == 0 {
    0
  } else {
    $iterations | math max
  }
}

def run-phase [name: string, iteration: int, args: list<string>, log_path: string]: nothing -> record {
  print $"==> iteration ($iteration) ($name)"
  let started = date now
  let result = (nu ...$args | complete)
  let row = {
    phase: $name
    iteration: $iteration
    ok: ($result.exit_code == 0)
    exit_code: $result.exit_code
    elapsed_ms: (elapsed-ms $started)
    finished_at: ((date now) | format date "%+")
  }
  append-log $log_path $row
  if $result.exit_code != 0 {
    print --stderr $result.stdout
    print --stderr $result.stderr
    print --stderr $"Brotli fuzz soak failed at iteration ($iteration), phase ($name)."
    exit $result.exit_code
  }
  $row
}

def should-stop [
  started: datetime
  iteration: int
  duration_min: int
  min_iterations: int
  max_iterations: int
]: nothing -> bool {
  let enough_iterations = $iteration >= $min_iterations
  let hit_max = $max_iterations > 0 and $iteration >= $max_iterations
  let hit_duration = $duration_min <= 0 or (elapsed-ms $started) >= ($duration_min * 60 * 1000)
  $enough_iterations and ($hit_max or $hit_duration)
}

def main [
  --duration-min: int = 1440
  --min-iterations: int = 1
  --max-iterations: int = 0
  --decoder-limit: int = 0
  --decoder-target: string = "native"
  --roundtrip-count: int = 12
  --roundtrip-max-len: int = 2048
  --roundtrip-qualities: string = "0,1,2,9,11"
  --roundtrip-target: string = "native"
  --log: string = $default_log
  --append-log
]: nothing -> nothing {
  if $duration_min < 0 {
    print --stderr "Duration minutes must be zero or greater."
    exit 1
  }
  if $min_iterations <= 0 {
    print --stderr "Minimum iterations must be greater than zero."
    exit 1
  }
  if $max_iterations < 0 {
    print --stderr "Maximum iterations must be zero or greater."
    exit 1
  }

  let started = date now
  let log_path = ($log | path expand)
  mkdir ($log_path | path dirname)
  # Default runs start with a clean evidence log. Append mode is explicit so
  # segmented long soaks can continue iteration numbering without hiding stale
  # rows in ordinary local validation.
  let start_iteration = if $append_log {
    logged-max-iteration $log_path
  } else {
    rm --force $log_path
    0
  }

  mut iteration = $start_iteration
  mut results = []
  loop {
    $iteration += 1
    let decoder_args = if $decoder_limit > 0 {
      [
        "tools/brotli/fuzz/run.nu"
        "--limit"
        ($decoder_limit | into string)
        "--target"
        $decoder_target
      ]
    } else {
      ["tools/brotli/fuzz/run.nu" "--target" $decoder_target]
    }
    let decoder = run-phase "decoder fuzz" $iteration $decoder_args $log_path
    $results = ($results | append $decoder)

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
    let roundtrip = run-phase "encoder roundtrip fuzz" $iteration $roundtrip_args $log_path
    $results = ($results | append $roundtrip)

    if (should-stop $started $iteration $duration_min $min_iterations $max_iterations) {
      break
    }
  }

  print ""
  print $"Brotli fuzz soak passed; log: ($log_path)"
  print ($results | table)
}

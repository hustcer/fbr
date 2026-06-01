#!/usr/bin/env nu
# Same-time encode benchmark comparison.
#
# Compares encode speed and encoded size of the trial (current working tree,
# including uncommitted changes) against a baseline git ref. Measurements are
# INTERLEAVED so slow machine drift (thermal throttling, background load) is
# less likely to hide a small optimization or regression.
#
# It reuses `tools/bench/target-perf.nu` for the actual measurement, so
# the timing shape (release build, per-op min over repeats x samples) matches
# the documented benchmark methodology. The baseline is built in a throwaway
# git worktree pinned to the resolved ref; the trial is measured in the repo
# you invoke this from.
#
# Output is designed for both humans and agents:
#   * default  -> an aligned comparison table + verdict banner
#   * --json   -> a single machine-readable JSON object
#
# Examples:
#   nu tools/bench/encode-compare.nu
#   nu tools/bench/encode-compare.nu --base HEAD --qualities 2,4,9,11
#   nu tools/bench/encode-compare.nu --inputs target/brotli-bench/silesia-1m.bin --rounds 1 --json
#
# The default matrix follows the release benchmark encode matrix: two practical
# Silesia slices across q0..q11 on wasm-gc and native. That covers stored/fast
# modes, the daily q2..q9 ratio-sensitive range, and high-quality q10/q11.

const perf_script = "tools/bench/target-perf.nu"
const legacy_perf_script = "tools/brotli/bench/target-perf.nu"
const default_inputs = "target/brotli-bench/silesia-64k.bin,target/brotli-bench/silesia-128k.bin"

# Parse a comma-separated list into trimmed, non-empty strings.
def parse-csv [text: string]: nothing -> list<string> {
  $text | split row "," | each {|v| $v | str trim } | where {|v| $v != "" }
}

# Parse comma-separated qualities into ints.
def parse-qualities [text: string]: nothing -> list<int> {
  parse-csv $text | each {|v| $v | into int }
}

# Format a percentage with an explicit sign (e.g. "+1.23%", "-2.40%").
def fmt-pct [v: float]: nothing -> string {
  let rounded = ($v | math round --precision 3)
  if $rounded > 0 { $"+($rounded)%" } else { $"($rounded)%" }
}

# Format an integer with thousands separators.
def fmt-int [value: int]: nothing -> string {
  $value
  | into string
  | split chars
  | reverse
  | chunks 3
  | each {|chunk| $chunk | reverse | str join }
  | reverse
  | str join ","
}

def input-label [path: string]: nothing -> string {
  $path | path basename | str replace ".bin" ""
}

# Run target-perf.nu (encode mode) in `dir` for one input/quality and return
# the parsed JSON rows (one per target). `input` must be absolute so the
# baseline worktree can read the main tree's benchmark files.
def measure-one [
  dir: string
  input: string
  quality: int
  targets: string
  repeats: int
  samples: int
]: nothing -> list<any> {
  let script = if ($dir | path join $perf_script | path exists) {
    $perf_script
  } else {
    $legacy_perf_script
  }
  let out = do {
    cd $dir
    ^nu $script $input --mode encode --quality $quality --targets $targets --repeats $repeats --samples $samples --json
    | complete
  }
  if $out.exit_code != 0 {
    print -e $"target-perf.nu failed in ($dir):"
    print -e $out.stdout
    print -e $out.stderr
    exit 1
  }
  $out.stdout | lines | where {|l| ($l | str trim) | str starts-with "[" } | last | from json
}

# Resolve (creating if needed) a baseline worktree pinned to `sha`. The main
# tree's `.mooncakes` is symlinked in so `moon` can resolve dependencies. The
# path is canonicalized with `path expand` so the registration check matches
# what `git worktree list` reports (e.g. /tmp -> /private/tmp on macOS).
def ensure-baseline-worktree [sha: string, repo_root: string]: nothing -> string {
  let path = ($"/tmp/fbr-encode-cmp-($sha | str substring 0..<12)" | path expand)
  ^git worktree prune
  let registered = (
    ^git worktree list | complete | get stdout | lines
    | any {|l| ($l | split row " " | first | path expand) == $path }
  )
  if not $registered {
    if ($path | path exists) { rm --recursive --force $path }
    let add = (^git worktree add --detach $path $sha | complete)
    if $add.exit_code != 0 {
      print -e $add.stderr
      exit 1
    }
  }
  let mooncakes = ($path | path join ".mooncakes")
  if not ($mooncakes | path exists) {
    ^ln -s ($repo_root | path join ".mooncakes") $mooncakes
  }
  $path
}

# Compare the working tree's encode speed and encoded size against a baseline
# git ref.
def main [
  --base: string = "HEAD"               # baseline git ref to compare the working tree against
  --inputs: string = $default_inputs     # comma-separated uncompressed inputs to encode
  --qualities: string = "0,1,2,3,4,5,6,7,8,9,10,11" # comma-separated Brotli qualities
  --targets: string = "wasm-gc,native"  # comma-separated MoonBit targets
  --repeats: int = 3                     # encode loop iterations per timed sample
  --samples: int = 3                     # timed samples per measurement; the min is kept
  --rounds: int = 2                      # interleaved rounds; the min across rounds is used
  --tolerance: float = 0.0               # per-target speed regression allowance, in percent
  --size-tolerance: float = 0.0          # per-input/quality encoded-size growth allowance, in percent
  --cleanup                              # remove the baseline worktree when done
  --json                                 # emit a single JSON object instead of a table
  --quiet                                # suppress progress lines on stderr
]: nothing -> nothing {
  let repo_root = (pwd)
  let input_list = parse-csv $inputs | each {|p| $p | path expand }
  let quals = parse-qualities $qualities
  let target_list = parse-csv $targets
  let base_sha = (^git rev-parse $base | complete | get stdout | str trim)
  if ($base_sha | is-empty) {
    print -e $"Cannot resolve git ref: ($base)"
    exit 1
  }
  for input in $input_list {
    if not ($input | path exists) {
      print -e $"Missing input: ($input)"
      exit 1
    }
  }

  let base_dir = (ensure-baseline-worktree $base_sha $repo_root)
  if not $quiet {
    print -e $"baseline ref ($base) -> ($base_sha | str substring 0..<12) at ($base_dir)"
  }

  # Collect one {input, quality, target, trial_ms, base_ms, trial_size,
  # base_size} sample per round.
  mut sample_rows = []
  for round in 0..<$rounds {
    for input in $input_list {
      for q in $quals {
        if not $quiet {
          print -e $"round (($round + 1))/($rounds)  (input-label $input)  q($q)  measuring trial + base..."
        }
        # Swap order each round so any monotonic drift hits both sides evenly.
        let pair = if ($round mod 2) == 0 {
          let t = (measure-one $repo_root $input $q $targets $repeats $samples)
          { t: $t, b: (measure-one $base_dir $input $q $targets $repeats $samples) }
        } else {
          let b = (measure-one $base_dir $input $q $targets $repeats $samples)
          { t: (measure-one $repo_root $input $q $targets $repeats $samples), b: $b }
        }
        let round_rows = $target_list | each {|tgt|
          let t_row = ($pair.t | where {|r| $r.target == $tgt } | first)
          let b_row = ($pair.b | where {|r| $r.target == $tgt } | first)
          {
            input: $input,
            input_label: (input-label $input),
            input_bytes: $t_row.input_bytes,
            quality: $q,
            target: $tgt,
            native_cc: $t_row.native_cc,
            trial_ms: $t_row.target_min_ms,
            base_ms: $b_row.target_min_ms,
            trial_size: $t_row.moonbit_size,
            base_size: $b_row.moonbit_size,
            google_size: $t_row.google_size,
            trial_google_overhead_pct: ($t_row.size_overhead * 100.0),
            base_google_overhead_pct: ($b_row.size_overhead * 100.0),
          }
        }
        $sample_rows = ($sample_rows | append $round_rows)
      }
    }
  }

  # Aggregate: keep the min across rounds per (input, quality, target), while
  # retaining encoded-size data for the same scenario.
  let collected = $sample_rows
  let rows = $input_list | each {|input|
    $quals | each {|q|
      $target_list | each {|tgt|
        let sel = ($collected | where {|r| $r.input == $input and $r.quality == $q and $r.target == $tgt })
        let b_ms = ($sel.base_ms | math min)
        let t_ms = ($sel.trial_ms | math min)
        let first = ($sel | first)
        let speed_delta_pct = ((($t_ms - $b_ms) / $b_ms) * 100.0)
        let size_delta_pct = ((($first.trial_size - $first.base_size) / $first.base_size) * 100.0)
        {
          input: $input,
          input_label: $first.input_label,
          input_bytes: $first.input_bytes,
          quality: $q,
          target: $tgt,
          native_cc: $first.native_cc,
          base_min_ms: ($b_ms | math round --precision 4),
          trial_min_ms: ($t_ms | math round --precision 4),
          time_delta_pct: ($speed_delta_pct | math round --precision 3),
          speedup_pct: ((0.0 - $speed_delta_pct) | math round --precision 3),
          base_bytes: $first.base_size,
          trial_bytes: $first.trial_size,
          size_delta_bytes: ($first.trial_size - $first.base_size),
          size_delta_pct: ($size_delta_pct | math round --precision 3),
          google_bytes: $first.google_size,
          base_google_overhead_pct: ($first.base_google_overhead_pct | math round --precision 3),
          trial_google_overhead_pct: ($first.trial_google_overhead_pct | math round --precision 3),
        }
      }
    } | flatten
  } | flatten

  # Size is target-independent, so aggregate it once per (input, quality).
  let size_rows = $input_list | each {|input|
    $quals | each {|q|
      $rows | where {|r| $r.input == $input and $r.quality == $q } | first | select input input_label input_bytes quality base_bytes trial_bytes size_delta_bytes size_delta_pct google_bytes base_google_overhead_pct trial_google_overhead_pct
    }
  } | flatten

  let base_time_sum = ($rows | get base_min_ms | math sum)
  let trial_time_sum = ($rows | get trial_min_ms | math sum)
  let agg_time_delta = ((($trial_time_sum - $base_time_sum) / $base_time_sum) * 100.0 | math round --precision 3)
  let base_size_sum = ($size_rows | get base_bytes | math sum)
  let trial_size_sum = ($size_rows | get trial_bytes | math sum)
  let agg_size_delta = ((($trial_size_sum - $base_size_sum) / $base_size_sum) * 100.0 | math round --precision 3)
  let speed_regressed = ($rows | where {|r| $r.time_delta_pct > $tolerance })
  let size_grew = ($size_rows | where {|r| $r.size_delta_pct > $size_tolerance })
  let pass_strict = (($speed_regressed | is-empty) and ($size_grew | is-empty))

  if $cleanup {
    ^git worktree remove --force $base_dir | complete | ignore
  }

  if $json {
    {
      base_ref: $base,
      base_sha: $base_sha,
      inputs: $input_list,
      qualities: $quals,
      targets: $target_list,
      repeats: $repeats,
      samples: $samples,
      rounds: $rounds,
      tolerance_pct: $tolerance,
      size_tolerance_pct: $size_tolerance,
      rows: $rows,
      size_rows: $size_rows,
      aggregate: {
        base_sum_ms: ($base_time_sum | math round --precision 4),
        trial_sum_ms: ($trial_time_sum | math round --precision 4),
        time_delta_pct: $agg_time_delta,
        speedup_pct: ((0.0 - $agg_time_delta) | math round --precision 3),
        base_sum_bytes: $base_size_sum,
        trial_sum_bytes: $trial_size_sum,
        size_delta_bytes: ($trial_size_sum - $base_size_sum),
        size_delta_pct: $agg_size_delta,
      },
      verdict: {
        pass_strict: $pass_strict,
        speed_regressed_rows: ($speed_regressed | select input_label quality target time_delta_pct speedup_pct),
        size_grew_rows: ($size_grew | select input_label quality size_delta_pct size_delta_bytes),
      },
    } | to json --raw | print
    return
  }

  # Human-friendly table + verdict banner.
  print $"Encode benchmark: trial \(working tree\) vs base \(($base) @ ($base_sha | str substring 0..<12)\)"
  print $"inputs: ($inputs)  qualities: ($qualities)  targets: ($targets)"
  print $"repeats: ($repeats)  samples: ($samples)  rounds: ($rounds)  speed tolerance: ($tolerance)%  size tolerance: ($size_tolerance)%"
  print ""
  print (
    $rows | each {|r| {
      input: $r.input_label,
      q: $"q($r.quality)",
      target: $r.target,
      "base ms": $r.base_min_ms,
      "trial ms": $r.trial_min_ms,
      speedup: (fmt-pct $r.speedup_pct),
      "base bytes": (fmt-int $r.base_bytes),
      "trial bytes": (fmt-int $r.trial_bytes),
      "size delta": (fmt-pct $r.size_delta_pct),
      "vs google": (fmt-pct $r.trial_google_overhead_pct),
      result: (if $r.time_delta_pct <= $tolerance and $r.size_delta_pct <= $size_tolerance { "ok" } else { "CHECK" }),
    } } | table --width 180
  )
  print ""
  print $"aggregate speed \(sum of per-op min rows\): base ($base_time_sum | math round --precision 3) ms  trial ($trial_time_sum | math round --precision 3) ms  speedup (fmt-pct (0.0 - $agg_time_delta))"
  print $"aggregate size \(one row per input/quality\): base (fmt-int $base_size_sum) bytes  trial (fmt-int $trial_size_sum) bytes  delta (fmt-pct $agg_size_delta)"
  print ""
  if $pass_strict {
    print $"VERDICT: PASS - trial is within speed and size tolerances on all rows."
  } else {
    let speed_names = ($speed_regressed | each {|r| $"($r.input_label)/q($r.quality)/($r.target) time (fmt-pct $r.time_delta_pct)" } | str join ", ")
    let size_names = ($size_grew | each {|r| $"($r.input_label)/q($r.quality) size (fmt-pct $r.size_delta_pct)" } | str join ", ")
    if not ($speed_regressed | is-empty) {
      print $"SPEED REGRESSIONS: (($speed_regressed | length))/(($rows | length)) rows: ($speed_names)"
    }
    if not ($size_grew | is-empty) {
      print $"SIZE GROWTH: (($size_grew | length))/(($size_rows | length)) scenarios: ($size_names)"
    }
    print "VERDICT: FAIL - at least one speed or size guardrail was exceeded."
  }
}

#!/usr/bin/env nu
# Same-time decode benchmark comparison.
#
# Compares the decode speed of the *trial* (current working tree, including
# uncommitted changes) against a *baseline* git ref, running the two builds
# INTERLEAVED so slow machine drift (thermal throttling, background load)
# cancels out instead of masking a small (1-3%) optimization. This is the
# rigorous way to screen a decode change against the project guardrail without
# being fooled by between-run machine noise.
#
# It reuses `tools/brotli/bench/target-perf.nu` for the actual measurement, so
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
#   nu tools/brotli/bench/decode-compare.nu
#   nu tools/brotli/bench/decode-compare.nu --base HEAD --qualities 0,5,9,11
#   nu tools/brotli/bench/decode-compare.nu --rounds 3 --json
#
# Guardrail (matches the .planning decode policy): an optimization is accepted
# only if the trial is at least as fast as the baseline on EVERY (quality,
# target) row. `pass_strict` reports exactly that, allowing a per-row
# `--tolerance` (percent) to absorb residual noise.

const perf_script = "tools/brotli/bench/target-perf.nu"
const default_input_dir = "target/brotli-current-bench/google-1m"
const default_expected = "target/brotli-bench/silesia-1m.bin"

# Parse a comma-separated list into trimmed, non-empty strings.
def parse-csv [text: string]: nothing -> list<string> {
  $text | split row "," | each {|v| $v | str trim } | where {|v| $v != "" }
}

# Format a percentage with an explicit sign (e.g. "+1.23%", "-2.40%").
def fmt-pct [v: float]: nothing -> string {
  if $v > 0 { $"+($v)%" } else { $"($v)%" }
}

# Run target-perf.nu (decode mode) in `dir` for one quality and return the
# parsed JSON rows (one per target). `input`/`expected` must be absolute so the
# baseline worktree can read the main tree's benchmark files.
def measure-one [
  dir: string
  input: string
  expected: string
  targets: string
  repeats: int
  samples: int
]: nothing -> list<any> {
  let out = do {
    cd $dir
    ^nu $perf_script $input --mode decode --expected $expected --targets $targets --repeats $repeats --samples $samples --json
    | complete
  }
  if $out.exit_code != 0 {
    print -e $"target-perf.nu failed in ($dir):"
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
  let path = ($"/tmp/fbr-decode-cmp-($sha | str substring 0..<12)" | path expand)
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

# Compare the working tree's decode speed against a baseline git ref.
def main [
  --base: string = "HEAD"               # baseline git ref to compare the working tree against
  --qualities: string = "0,5,9,11"      # comma-separated Google qualities to screen
  --targets: string = "wasm-gc,native"  # comma-separated MoonBit targets
  --repeats: int = 5                     # decode loop iterations per timed sample
  --samples: int = 3                     # timed samples per measurement; the min is kept
  --rounds: int = 2                      # interleaved rounds; the min across rounds is used
  --tolerance: float = 0.0               # per-row regression allowance, in percent
  --input-dir: string = ""              # dir with silesia-1m.q<q>.br (default: target/brotli-current-bench/google-1m)
  --expected: string = ""               # uncompressed reference file (default: target/brotli-bench/silesia-1m.bin)
  --cleanup                              # remove the baseline worktree when done
  --json                                 # emit a single JSON object instead of a table
  --quiet                                # suppress progress lines on stderr
]: nothing -> nothing {
  let repo_root = (pwd)
  let dir_in = (if ($input_dir | str trim) == "" { $default_input_dir } else { $input_dir } | path expand)
  let expected = (if ($expected | str trim) == "" { $default_expected } else { $expected } | path expand)
  if not ($expected | path exists) {
    print -e $"Missing reference file: ($expected)"
    exit 1
  }
  let quals = parse-csv $qualities
  let target_list = parse-csv $targets
  let base_sha = (^git rev-parse $base | complete | get stdout | str trim)
  if ($base_sha | is-empty) {
    print -e $"Cannot resolve git ref: ($base)"
    exit 1
  }
  let base_dir = (ensure-baseline-worktree $base_sha $repo_root)
  if not $quiet {
    print -e $"baseline ref ($base) -> ($base_sha | str substring 0..<12) at ($base_dir)"
  }

  # Collect one {quality, target, trial_ms, base_ms} sample per round.
  mut sample_rows = []
  for round in 0..<$rounds {
    for q in $quals {
      let input = ($dir_in | path join $"silesia-1m.q($q).br")
      if not ($input | path exists) {
        print -e $"Missing input: ($input)"
        exit 1
      }
      if not $quiet {
        print -e $"round (($round + 1))/($rounds)  q($q)  measuring trial + base..."
      }
      # Swap order each round so any monotonic drift hits both sides evenly.
      let pair = if ($round mod 2) == 0 {
        let t = (measure-one $repo_root $input $expected $targets $repeats $samples)
        { t: $t, b: (measure-one $base_dir $input $expected $targets $repeats $samples) }
      } else {
        let b = (measure-one $base_dir $input $expected $targets $repeats $samples)
        { t: (measure-one $repo_root $input $expected $targets $repeats $samples), b: $b }
      }
      let round_rows = $target_list | each {|tgt|
        {
          quality: $"q($q)",
          target: $tgt,
          trial_ms: ($pair.t | where {|r| $r.target == $tgt } | first | get target_min_ms),
          base_ms: ($pair.b | where {|r| $r.target == $tgt } | first | get target_min_ms),
        }
      }
      $sample_rows = ($sample_rows | append $round_rows)
    }
  }

  # Aggregate: keep the min across rounds per (quality, target).
  let collected = $sample_rows
  let rows = $quals | each {|q|
    $target_list | each {|tgt|
      let sel = ($collected | where {|r| $r.quality == $"q($q)" and $r.target == $tgt })
      let b = ($sel.base_ms | math min)
      let t = ($sel.trial_ms | math min)
      {
        quality: $"q($q)",
        target: $tgt,
        base_min_ms: ($b | math round --precision 4),
        trial_min_ms: ($t | math round --precision 4),
        delta_pct: ((($t - $b) / $b) * 100.0 | math round --precision 3),
      }
    }
  } | flatten

  let base_sum = ($rows | get base_min_ms | math sum)
  let trial_sum = ($rows | get trial_min_ms | math sum)
  let agg_delta = ((($trial_sum - $base_sum) / $base_sum) * 100.0 | math round --precision 3)
  let regressed = ($rows | where {|r| $r.delta_pct > $tolerance })
  let pass_strict = ($regressed | is-empty)

  if $cleanup {
    ^git worktree remove --force $base_dir | complete | ignore
  }

  if $json {
    {
      base_ref: $base,
      base_sha: $base_sha,
      qualities: $quals,
      targets: $target_list,
      repeats: $repeats,
      samples: $samples,
      rounds: $rounds,
      tolerance_pct: $tolerance,
      rows: $rows,
      aggregate: {
        base_sum_ms: ($base_sum | math round --precision 4),
        trial_sum_ms: ($trial_sum | math round --precision 4),
        delta_pct: $agg_delta,
      },
      verdict: {
        pass_strict: $pass_strict,
        regressed_rows: ($regressed | select quality target delta_pct),
      },
    } | to json --raw | print
    return
  }

  # Human-friendly table + verdict banner.
  print $"Decode benchmark: trial \(working tree\) vs base \(($base) @ ($base_sha | str substring 0..<12)\)"
  print $"qualities: ($qualities)  targets: ($targets)  repeats: ($repeats)  samples: ($samples)  rounds: ($rounds)  tolerance: ($tolerance)%"
  print ""
  print (
    $rows | each {|r| {
      quality: $r.quality,
      target: $r.target,
      "base ms": $r.base_min_ms,
      "trial ms": $r.trial_min_ms,
      delta: (fmt-pct $r.delta_pct),
      result: (if $r.delta_pct <= $tolerance { "faster" } else { "SLOWER" }),
    } } | table
  )
  print ""
  print $"aggregate \(sum of per-op min\): base ($base_sum | math round --precision 3) ms  trial ($trial_sum | math round --precision 3) ms  \((fmt-pct $agg_delta)\)"
  print ""
  if $pass_strict {
    print $"VERDICT: PASS — trial is at least as fast on all (($rows | length)) rows \(tolerance ($tolerance)%\)."
  } else {
    let names = ($regressed | each {|r| $"($r.quality)/($r.target) (fmt-pct $r.delta_pct)" } | str join ", ")
    print $"VERDICT: FAIL — regressed on (($regressed | length))/(($rows | length)) rows: ($names)"
  }
}

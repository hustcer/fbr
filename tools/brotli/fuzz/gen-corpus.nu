#!/usr/bin/env nu

const fixture_dir = "src/tests/brotli_fixtures"
const corpus_dir = "tools/brotli/fuzz/corpus"

def mutate-truncate [data: binary, keep: int]: nothing -> binary {
  if $keep <= 0 {
    bytes build
  } else {
    $data | bytes at 0..<$keep
  }
}

def mutate-append [data: binary, extra_len: int]: nothing -> binary {
  [$data (random binary $extra_len)] | bytes collect
}

def mutate-delete-middle [
  data: binary
  start: int
  delete_len: int
]: nothing -> binary {
  let len = ($data | bytes length)
  let end = [$len ($start + $delete_len)] | math min
  [
    ($data | bytes at 0..<$start)
    ($data | bytes at $end..)
  ] | bytes collect
}

def main [
  --count (-n): int = 1000
]: nothing -> nothing {
  mkdir $corpus_dir
  let seeds = glob ($fixture_dir | path join "*.br") | sort

  if ($seeds | length) == 0 {
    print --stderr $"No Brotli fixture seeds found in ($fixture_dir)."
    exit 1
  }

  for seed in $seeds {
    cp --force $seed ($corpus_dir | path join ($seed | path basename))
  }

  for i in 0..<$count {
    let seed = ($seeds | get ($i mod ($seeds | length)))
    let data = (open --raw $seed | into binary)
    let len = ($data | bytes length)
    let mutation = $i mod 3
    let mutated = if $mutation == 0 {
      let keep = if $len == 0 { 0 } else { random int 0..<$len }
      mutate-truncate $data $keep
    } else if $mutation == 1 {
      mutate-append $data (random int 1..=8)
    } else {
      let start = if $len == 0 { 0 } else { random int 0..<$len }
      mutate-delete-middle $data $start (random int 1..=8)
    }
    $mutated | save --force ($corpus_dir | path join $"mutation_($i).mut")
  }

  print $"Wrote (($seeds | length) + $count) Brotli fuzz inputs to ($corpus_dir)."
}

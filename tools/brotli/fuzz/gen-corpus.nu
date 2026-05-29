#!/usr/bin/env nu

const fixture_dir = "src/tests/brotli_fixtures"
const corpus_dir = "tools/brotli/fuzz/corpus"

def next-seed [seed: int]: nothing -> int {
  (($seed * 1_664_525 + 1_013_904_223) mod 4_294_967_296)
}

def next-value [seed: int, upper: int]: nothing -> record {
  let next = next-seed $seed
  {
    seed: $next
    value: ($next mod $upper)
  }
}

def bounded-value [seed: int, upper: int]: nothing -> record {
  if $upper <= 0 {
    {
      seed: $seed
      value: 0
    }
  } else {
    next-value $seed $upper
  }
}

def random-bytes [seed: int, len: int]: nothing -> record {
  if $len <= 0 {
    {
      seed: $seed
      data: (bytes build)
    }
  } else {
    let rows = (
      0..<$len
      | generate {|_, current|
        let next = next-seed $current
        {
          out: {
            seed: $next
            byte: ($next mod 256)
          }
          next: $next
        }
      } $seed
    )
    {
      seed: ($rows | last | get seed)
      data: (bytes build ...($rows | get byte))
    }
  }
}

def mutate-truncate [data: binary, keep: int]: nothing -> binary {
  if $keep <= 0 {
    bytes build
  } else {
    $data | bytes at 0..<$keep
  }
}

def mutate-append [data: binary, extra: binary]: nothing -> binary {
  [$data $extra] | bytes collect
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

def mutation-row [i: int, seeds: list<string>, current_seed: int]: nothing -> record {
  let source = ($seeds | get ($i mod ($seeds | length)))
  let data = (open --raw $source | into binary)
  let len = ($data | bytes length)
  let mutation = $i mod 3
  let mutated = if $mutation == 0 {
    let keep = bounded-value $current_seed $len
    {
      seed: $keep.seed
      data: (mutate-truncate $data $keep.value)
    }
  } else if $mutation == 1 {
    let extra_len = next-value $current_seed 8
    let extra = random-bytes $extra_len.seed ($extra_len.value + 1)
    {
      seed: $extra.seed
      data: (mutate-append $data $extra.data)
    }
  } else {
    let start = bounded-value $current_seed $len
    let delete_len = next-value $start.seed 8
    {
      seed: $delete_len.seed
      data: (mutate-delete-middle $data $start.value ($delete_len.value + 1))
    }
  }
  {
    index: $i
    seed: $mutated.seed
    data: $mutated.data
  }
}

def main [
  --count (-n): int = 1000
  --seed (-s): int = 1
  --corpus-dir (-c): string = $corpus_dir
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

  0..<$count
  | generate {|i, current_seed|
    let row = mutation-row $i $seeds $current_seed
    {
      out: $row
      next: $row.seed
    }
  } $seed
  | each {|row|
    $row.data | save --force ($corpus_dir | path join $"mutation_($row.index).mut")
  }
  | ignore

  print $"Wrote (($seeds | length) + $count) Brotli fuzz inputs to ($corpus_dir)."
}

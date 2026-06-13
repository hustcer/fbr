///|
priv struct BrotliHashConfig {
  table_size : Int
  table_mask : Int
  hash_bytes : Int
  max_match_checks : Int
  max_match_length : Int
  min_match_length : Int
  max_distance_cache_codes : Int
  lazy_lookahead : Int
  scan_step : Int
  max_commands : Int
  max_input_length : Int
  min_copy_ratio_percent : Int
  require_dense_match_density : Bool
  density_sample_step : Int
  density_required_numerator : Int
  density_required_denominator : Int
}

///|
priv struct BrotliHashMatchCandidate {
  length : Int
  distance : Int
}

///|
fn brotli_hash_config_for_quality(quality : Int) -> BrotliHashConfig {
  {
    table_size: 32768,
    table_mask: 32767,
    hash_bytes: 3,
    max_match_checks: 4,
    max_match_length: 4096,
    min_match_length: 4,
    max_distance_cache_codes: @common.brotli_num_distance_short_codes,
    lazy_lookahead: brotli_greedy_lazy_lookahead_for_quality(quality, 3),
    scan_step: 1,
    max_commands: 1200,
    max_input_length: 1048576,
    min_copy_ratio_percent: 0,
    require_dense_match_density: true,
    density_sample_step: 256,
    density_required_numerator: 9,
    density_required_denominator: 10,
  }
}

///|
fn brotli_natural_hash_config_for_quality(quality : Int) -> BrotliHashConfig {
  let max_distance_cache_codes = if quality <= 2 {
    0
  } else {
    @common.brotli_num_distance_short_codes
  }
  {
    table_size: 32768,
    table_mask: 32767,
    hash_bytes: 3,
    max_match_checks: if quality == 0 {
      3
    } else if quality == 1 {
      4
    } else {
      8
    },
    max_match_length: 16384,
    min_match_length: if quality == 0 {
      8
    } else if quality == 1 {
      10
    } else {
      10
    },
    max_distance_cache_codes,
    lazy_lookahead: if quality <= 2 {
      1
    } else {
      brotli_greedy_lazy_lookahead_for_quality(quality, 3)
    },
    scan_step: 1,
    max_commands: 52000,
    max_input_length: if quality <= 9 {
      2097152
    } else {
      1048576
    },
    min_copy_ratio_percent: 12,
    require_dense_match_density: false,
    density_sample_step: 256,
    density_required_numerator: 9,
    density_required_denominator: 10,
  }
}

///|
fn brotli_high_quality_hash_config_for_quality(
  quality : Int,
) -> BrotliHashConfig {
  // q10/q11: deeper search (256 checks, 131,072-entry table) to spend the
  // high-quality CPU budget on more candidate matches.
  // q9: 32 checks at 32,768-entry table.
  let table_size = if quality >= 10 { 131072 } else { 32768 }
  let table_mask = table_size - 1
  let max_match_checks = if quality >= 10 {
    256
  } else if quality >= 9 {
    32
  } else {
    4
  }
  let min_match_length = if quality >= 9 { 5 } else { 6 }
  let max_commands = if quality >= 10 {
    600000
  } else if quality >= 9 {
    300000
  } else {
    150000
  }
  let lazy_lookahead = 3
  {
    table_size,
    table_mask,
    hash_bytes: 3,
    max_match_checks,
    max_match_length: 16384,
    min_match_length,
    max_distance_cache_codes: @common.brotli_num_distance_short_codes,
    lazy_lookahead,
    scan_step: 1,
    max_commands,
    max_input_length: if quality == 9 {
      2097152
    } else {
      1048576
    },
    min_copy_ratio_percent: 12,
    require_dense_match_density: false,
    density_sample_step: 256,
    density_required_numerator: 9,
    density_required_denominator: 10,
  }
}

///|
fn brotli_intermediate_hash_config_for_quality(
  quality : Int,
) -> BrotliHashConfig {
  let max_match_checks = if quality <= 4 {
    8
  } else if quality <= 6 {
    16
  } else {
    32
  }
  let max_commands = if quality <= 4 {
    100000
  } else if quality <= 6 {
    180000
  } else {
    240000
  }
  {
    table_size: 32768,
    table_mask: 32767,
    hash_bytes: 3,
    max_match_checks,
    max_match_length: 16384,
    min_match_length: if quality <= 4 {
      6
    } else {
      5
    },
    max_distance_cache_codes: @common.brotli_num_distance_short_codes,
    lazy_lookahead: brotli_greedy_lazy_lookahead_for_quality(quality, 3),
    scan_step: 1,
    max_commands,
    max_input_length: 2097152,
    min_copy_ratio_percent: 12,
    require_dense_match_density: false,
    density_sample_step: 256,
    density_required_numerator: 9,
    density_required_denominator: 10,
  }
}

///|
fn brotli_four_byte_hash_config(config : BrotliHashConfig) -> BrotliHashConfig {
  {
    table_size: config.table_size,
    table_mask: config.table_mask,
    hash_bytes: 4,
    max_match_checks: config.max_match_checks,
    max_match_length: config.max_match_length,
    min_match_length: config.min_match_length,
    max_distance_cache_codes: config.max_distance_cache_codes,
    lazy_lookahead: config.lazy_lookahead,
    scan_step: config.scan_step,
    max_commands: config.max_commands,
    max_input_length: config.max_input_length,
    min_copy_ratio_percent: config.min_copy_ratio_percent,
    require_dense_match_density: config.require_dense_match_density,
    density_sample_step: config.density_sample_step,
    density_required_numerator: config.density_required_numerator,
    density_required_denominator: config.density_required_denominator,
  }
}

///|
fn brotli_greedy_lazy_lookahead_for_quality(
  quality : Int,
  default_lookahead : Int,
) -> Int {
  if quality >= 4 && quality <= 8 {
    0
  } else {
    default_lookahead
  }
}

///|
fn brotli_hash_max_input_length(config : BrotliHashConfig) -> Int {
  config.max_input_length
}

///|
fn brotli_effective_max_commands(
  config : BrotliHashConfig,
  data_length : Int,
) -> Int {
  // q2..q8 keep their historical command budgets for <=1 MiB chunks. Larger
  // P3 chunks scale the budget with input length so the candidate does not
  // fall back to stored output just because two formerly separate chunks are
  // costed together.
  if config.max_input_length > 1048576 &&
    config.max_commands < 300000 &&
    data_length > 1048576 {
    config.max_commands * ((data_length + 1048575) / 1048576)
  } else {
    config.max_commands
  }
}

///|
fn brotli_count_unique_literals_up_to(
  data : FixedArray[Byte],
  limit : Int,
) -> Int {
  let seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
  let mut count = 0
  for i in 0..<data.length() {
    let value = data[i].to_int()
    if !seen[value] {
      seen[value] = true
      count += 1
      if count > limit {
        return count
      }
    }
  }
  count
}

///|
fn brotli_has_compressible_match_density(
  data : FixedArray[Byte],
  config : BrotliHashConfig,
) -> Bool {
  if !config.require_dense_match_density {
    return true
  }
  if data.length() < 64 {
    return true
  }
  if brotli_count_unique_literals_up_to(data, 16) <= 16 {
    return true
  }
  let table = FixedArray::make(config.table_size, -1)
  let mut matched_positions = 0
  let step = config.density_sample_step
  let threshold = data.length() *
    config.density_required_numerator /
    (step * config.density_required_denominator)
  let mut position = 0
  while position < data.length() - 3 {
    let hash = brotli_match_hash(data, position, config)
    let candidate = table[hash]
    table[hash] = position
    if candidate >= 0 &&
      data[position] == data[candidate] &&
      data[position + 1] == data[candidate + 1] &&
      data[position + 2] == data[candidate + 2] &&
      data[position + 3] == data[candidate + 3] {
      matched_positions += 1
      if matched_positions >= threshold {
        return true
      }
    }
    position += step
  }
  false
}

///|
fn brotli_match_hash(
  data : FixedArray[Byte],
  position : Int,
  config : BrotliHashConfig,
) -> Int {
  if position + 2 >= data.length() ||
    (config.hash_bytes >= 4 && position + 3 >= data.length()) {
    0
  } else if config.hash_bytes >= 4 {
    (
      (data[position].to_int() * 257) ^
      (data[position + 1].to_int() * 131) ^
      (data[position + 2].to_int() * 17) ^
      data[position + 3].to_int()
    ) &
    config.table_mask
  } else {
    (
      (data[position].to_int() * 257) ^
      (data[position + 1].to_int() * 17) ^
      data[position + 2].to_int()
    ) &
    config.table_mask
  }
}

///|
fn brotli_previous_match_positions(
  data : FixedArray[Byte],
  config : BrotliHashConfig,
) -> FixedArray[Int] {
  let len = data.length()
  let previous = FixedArray::make(len, -1)
  let table = FixedArray::make(config.table_size, -1)
  let hash_bytes = if config.hash_bytes >= 4 { 4 } else { 3 }
  if len < hash_bytes {
    return previous
  }
  let table_mask = config.table_mask
  let end = len - hash_bytes + 1
  if hash_bytes >= 4 {
    for position in 0..<end {
      let hash = (
          (data[position].to_int() * 257) ^
          (data[position + 1].to_int() * 131) ^
          (data[position + 2].to_int() * 17) ^
          data[position + 3].to_int()
        ) &
        table_mask
      previous[position] = table[hash]
      table[hash] = position
    }
  } else {
    for position in 0..<end {
      let hash = (
          (data[position].to_int() * 257) ^
          (data[position + 1].to_int() * 17) ^
          data[position + 2].to_int()
        ) &
        table_mask
      previous[position] = table[hash]
      table[hash] = position
    }
  }
  previous
}

///|
/// Index/delta pairs for Brotli's recent-distance short codes 0..15.
/// `(base_index, delta)`: distance = `distance_cache[base_index] + delta`.
/// Mirrors the if-else chain in `brotli_distance_cache_candidate`.
let brotli_distance_cache_lookup : FixedArray[Int] = [
  0, 0, // code 0: cache[0]
   1, 0, // code 1: cache[1]
   2, 0, // code 2: cache[2]
   3, 0, // code 3: cache[3]
   0, -1, // code 4: cache[0] - 1
   0, 1, // code 5: cache[0] + 1
   0, -2, // code 6
   0, 2, // code 7
   0, -3, // code 8
   0, 3, // code 9
   1, -1, // code 10
   1, 1, // code 11
   1, -2, // code 12
   1, 2, // code 13
   1, -3, // code 14
   1, 3, // code 15
]

///|
fn brotli_distance_cache_candidate(
  distance_cache : FixedArray[Int],
  code : Int,
) -> Int {
  let base_index = brotli_distance_cache_lookup[code * 2]
  let delta = brotli_distance_cache_lookup[code * 2 + 1]
  distance_cache[base_index] + delta
}

///|
fn brotli_record_bounded_hash_match(
  matches : Array[BrotliHashMatchCandidate],
  length : Int,
  distance : Int,
  min_match_length : Int,
) -> Unit {
  if length < min_match_length || distance <= 0 {
    return
  }
  for i in 0..<matches.length() {
    if matches[i].distance == distance {
      if length > matches[i].length {
        matches[i] = { length, distance }
      }
      return
    }
  }
  matches.push({ length, distance })
}

///|
fn brotli_bounded_previous_hash_matches_with_cache(
  data : FixedArray[Byte],
  previous : FixedArray[Int],
  position : Int,
  config : BrotliHashConfig,
  distance_cache : FixedArray[Int],
) -> Array[BrotliHashMatchCandidate] {
  let matches : Array[BrotliHashMatchCandidate] = []
  let len = data.length()
  let hash_bytes = if config.hash_bytes >= 4 { 4 } else { 3 }
  if position + hash_bytes > len {
    return matches
  }
  let max_match_length = config.max_match_length
  let b0 = data[position]
  let b1 = data[position + 1]
  let b2 = data[position + 2]
  let b3 = if hash_bytes >= 4 { data[position + 3] } else { b'\x00' }
  let max_cache_codes = config.max_distance_cache_codes
  for code in 0..<max_cache_codes {
    let distance = brotli_distance_cache_candidate(distance_cache, code)
    if distance > 0 && distance <= position {
      let candidate = position - distance
      let match_ok = if hash_bytes >= 4 {
        data[candidate] == b0 &&
        data[candidate + 1] == b1 &&
        data[candidate + 2] == b2 &&
        data[candidate + 3] == b3
      } else {
        data[candidate] == b0 &&
        data[candidate + 1] == b1 &&
        data[candidate + 2] == b2
      }
      if match_ok {
        let mut length = hash_bytes
        while length < max_match_length &&
              position + length < len &&
              data[position + length] == data[candidate + length] {
          length += 1
        }
        brotli_record_bounded_hash_match(
          matches,
          length,
          distance,
          config.min_match_length,
        )
      }
    }
  }
  let max_match_checks = config.max_match_checks
  let mut candidate = if position < previous.length() {
    previous[position]
  } else {
    -1
  }
  let mut checked = 0
  while candidate >= 0 && checked < max_match_checks {
    let match_ok = if hash_bytes >= 4 {
      data[candidate] == b0 &&
      data[candidate + 1] == b1 &&
      data[candidate + 2] == b2 &&
      data[candidate + 3] == b3
    } else {
      data[candidate] == b0 &&
      data[candidate + 1] == b1 &&
      data[candidate + 2] == b2
    }
    if match_ok {
      let mut length = hash_bytes
      while length < max_match_length &&
            position + length < len &&
            data[position + length] == data[candidate + length] {
        length += 1
      }
      brotli_record_bounded_hash_match(
        matches,
        length,
        position - candidate,
        config.min_match_length,
      )
    }
    candidate = previous[candidate]
    checked += 1
  }
  matches
}

///|
fn brotli_longest_previous_hash_match_with_cache(
  data : FixedArray[Byte],
  previous : FixedArray[Int],
  position : Int,
  config : BrotliHashConfig,
  distance_cache : FixedArray[Int],
) -> (Int, Int) {
  let len = data.length()
  if position + 3 >= len {
    return (0, 0)
  }
  let max_match_length = config.max_match_length
  let b0 = data[position]
  let b1 = data[position + 1]
  let b2 = data[position + 2]
  let b3 = data[position + 3]
  let mut best_length = 0
  let mut best_distance = 0
  let mut best_from_distance_cache = false
  let distance_cache_replacement_margin = if config.max_match_checks >= 256 {
    1
  } else {
    0
  }
  // Inlined distance-cache probes
  let max_cache_codes = config.max_distance_cache_codes
  for code in 0..<max_cache_codes {
    let distance = brotli_distance_cache_candidate(distance_cache, code)
    if distance > 0 && distance <= position {
      let candidate = position - distance
      if data[candidate] == b0 &&
        data[candidate + 1] == b1 &&
        data[candidate + 2] == b2 &&
        data[candidate + 3] == b3 {
        let mut length = 4
        while length < max_match_length &&
              position + length < len &&
              data[position + length] == data[candidate + length] {
          length += 1
        }
        if length > best_length {
          best_length = length
          best_distance = distance
          best_from_distance_cache = true
        }
      }
    }
  }
  // Inlined hash-chain probes
  let max_match_checks = config.max_match_checks
  let mut candidate = if position < previous.length() {
    previous[position]
  } else {
    -1
  }
  let mut checked = 0
  while candidate >= 0 && checked < max_match_checks {
    // Boundary-byte pre-check: a candidate can only beat the incumbent if its
    // common prefix with `position` is at least `best_length + 1` bytes, which
    // requires the byte at offset `best_length` to match. If it differs the
    // prefix cannot reach that offset, so the candidate's length is
    // <= best_length regardless of the earlier bytes; skipping it never
    // changes the selected match. This one comparison rejects most chain
    // candidates without the 4-byte prefix test or the byte-by-byte extension.
    // Once `position + best_length` runs past the data end no remaining
    // candidate can extend beyond `best_length`, so the walk can stop.
    if best_length > 0 {
      if position + best_length >= len {
        break
      }
      if data[candidate + best_length] != data[position + best_length] {
        candidate = previous[candidate]
        checked += 1
        continue
      }
    }
    if data[candidate] == b0 &&
      data[candidate + 1] == b1 &&
      data[candidate + 2] == b2 &&
      data[candidate + 3] == b3 {
      let mut length = 4
      while length < max_match_length &&
            position + length < len &&
            data[position + length] == data[candidate + length] {
        length += 1
      }
      if length > best_length &&
        (
          !best_from_distance_cache ||
          length > best_length + distance_cache_replacement_margin
        ) {
        best_length = length
        best_distance = position - candidate
        best_from_distance_cache = false
      }
    }
    candidate = previous[candidate]
    checked += 1
  }
  (best_length, best_distance)
}

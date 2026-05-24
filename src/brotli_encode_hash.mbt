///|
priv struct BrotliHashConfig {
  table_size : Int
  table_mask : Int
  hash_bytes : Int
  max_match_checks : Int
  max_match_length : Int
  min_match_length : Int
  scan_step : Int
  max_commands : Int
  min_copy_ratio_percent : Int
  require_dense_match_density : Bool
  density_sample_step : Int
  density_required_numerator : Int
  density_required_denominator : Int
}

///|
fn brotli_hash_config_for_quality(_quality : Int) -> BrotliHashConfig {
  {
    table_size: 32768,
    table_mask: 32767,
    hash_bytes: 3,
    max_match_checks: 4,
    max_match_length: 4096,
    min_match_length: 4,
    scan_step: 1,
    max_commands: 1200,
    min_copy_ratio_percent: 0,
    require_dense_match_density: true,
    density_sample_step: 256,
    density_required_numerator: 9,
    density_required_denominator: 10,
  }
}

///|
fn brotli_natural_hash_config_for_quality(_quality : Int) -> BrotliHashConfig {
  {
    table_size: 32768,
    table_mask: 32767,
    hash_bytes: 3,
    max_match_checks: 8,
    max_match_length: 16384,
    min_match_length: 16,
    scan_step: 1,
    max_commands: 19200,
    min_copy_ratio_percent: 12,
    require_dense_match_density: false,
    density_sample_step: 256,
    density_required_numerator: 9,
    density_required_denominator: 10,
  }
}

///|
fn brotli_high_quality_hash_config_for_quality(
  _quality : Int,
) -> BrotliHashConfig {
  {
    table_size: 32768,
    table_mask: 32767,
    hash_bytes: 3,
    max_match_checks: 4,
    max_match_length: 16384,
    min_match_length: 12,
    scan_step: 1,
    max_commands: 25600,
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
    scan_step: config.scan_step,
    max_commands: config.max_commands,
    min_copy_ratio_percent: config.min_copy_ratio_percent,
    require_dense_match_density: config.require_dense_match_density,
    density_sample_step: config.density_sample_step,
    density_required_numerator: config.density_required_numerator,
    density_required_denominator: config.density_required_denominator,
  }
}

///|
fn brotli_count_unique_literals_up_to(
  data : FixedArray[Byte],
  limit : Int,
) -> Int {
  let seen = FixedArray::make(brotli_num_literal_symbols, false)
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
  let previous = FixedArray::make(data.length(), -1)
  let table = FixedArray::make(config.table_size, -1)
  let hash_bytes = if config.hash_bytes >= 4 { 4 } else { 3 }
  if data.length() < hash_bytes {
    return previous
  }
  for position in 0..<(data.length() - hash_bytes + 1) {
    let hash = brotli_match_hash(data, position, config)
    previous[position] = table[hash]
    table[hash] = position
  }
  previous
}

///|
fn brotli_longest_previous_hash_match(
  data : FixedArray[Byte],
  previous : FixedArray[Int],
  position : Int,
  config : BrotliHashConfig,
) -> (Int, Int) {
  if position + 3 >= data.length() {
    return (0, 0)
  }
  let mut best_length = 0
  let mut best_distance = 0
  let mut candidate = if position < previous.length() {
    previous[position]
  } else {
    -1
  }
  let mut checked = 0
  while candidate >= 0 && checked < config.max_match_checks {
    let distance = position - candidate
    let has_min_match = data[position] == data[candidate] &&
      data[position + 1] == data[candidate + 1] &&
      data[position + 2] == data[candidate + 2] &&
      data[position + 3] == data[candidate + 3]
    if has_min_match {
      let mut length = 4
      while length < config.max_match_length &&
            position + length < data.length() &&
            data[position + length] == data[candidate + length] {
        length += 1
      }
      if length > best_length {
        best_length = length
        best_distance = distance
      }
    }
    candidate = previous[candidate]
    checked += 1
  }
  (best_length, best_distance)
}

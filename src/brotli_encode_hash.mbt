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
fn brotli_has_compressible_match_density(data : FixedArray[Byte]) -> Bool {
  if data.length() < 64 {
    return true
  }
  if brotli_count_unique_literals_up_to(data, 16) <= 16 {
    return true
  }
  let table = FixedArray::make(4096, -1)
  let mut matched_positions = 0
  let step = 256
  let threshold = data.length() * 9 / (step * 10)
  let mut position = 0
  while position < data.length() - 3 {
    let hash = brotli_match_hash(data, position)
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
fn brotli_match_hash(data : FixedArray[Byte], position : Int) -> Int {
  if position + 2 >= data.length() {
    0
  } else {
    (
      (data[position].to_int() * 257) ^
      (data[position + 1].to_int() * 17) ^
      data[position + 2].to_int()
    ) &
    4095
  }
}

///|
fn brotli_previous_match_positions(data : FixedArray[Byte]) -> FixedArray[Int] {
  let previous = FixedArray::make(data.length(), -1)
  let table = FixedArray::make(4096, -1)
  if data.length() < 3 {
    return previous
  }
  for position in 0..<(data.length() - 2) {
    let hash = brotli_match_hash(data, position)
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
  while candidate >= 0 && checked < 4 {
    let distance = position - candidate
    let has_min_match = data[position] == data[candidate] &&
      data[position + 1] == data[candidate + 1] &&
      data[position + 2] == data[candidate + 2] &&
      data[position + 3] == data[candidate + 3]
    if has_min_match {
      let mut length = 4
      while length < 4096 &&
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

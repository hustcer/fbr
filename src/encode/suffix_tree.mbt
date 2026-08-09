///|
fn brotli_suffix_tree_compare(
  data : FixedArray[Byte],
  left_pos : Int,
  right_pos : Int,
  max_match_length : Int,
) -> (Int, Int) {
  let len = data.length()
  let mut matched = 0
  while matched < max_match_length &&
        left_pos + matched < len &&
        right_pos + matched < len &&
        data[left_pos + matched] == data[right_pos + matched] {
    matched += 1
  }
  if matched >= max_match_length {
    return (matched, 0)
  }
  let left_index = left_pos + matched
  let right_index = right_pos + matched
  if left_index >= len && right_index >= len {
    (matched, 0)
  } else if left_index >= len {
    (matched, -1)
  } else if right_index >= len {
    (matched, 1)
  } else if data[left_index].to_int() < data[right_index].to_int() {
    (matched, -1)
  } else {
    (matched, 1)
  }
}

///|
fn brotli_bounded_suffix_tree_insert(
  data : FixedArray[Byte],
  left_child : FixedArray[Int],
  right_child : FixedArray[Int],
  root : Int,
  position : Int,
  config : BrotliHashConfig,
) -> Int {
  if root < 0 {
    return position
  }
  let mut node = root
  let mut checks = 0
  let max_insert_checks = config.max_match_checks * 2
  while checks < max_insert_checks {
    let (_, compare) = brotli_suffix_tree_compare(
      data,
      position,
      node,
      config.max_match_length,
    )
    if compare < 0 {
      if left_child[node] < 0 {
        left_child[node] = position
        return root
      }
      node = left_child[node]
    } else {
      if right_child[node] < 0 {
        right_child[node] = position
        return root
      }
      node = right_child[node]
    }
    checks += 1
  }
  root
}

///|
fn brotli_bounded_suffix_tree_collect_matches(
  data : FixedArray[Byte],
  left_child : FixedArray[Int],
  right_child : FixedArray[Int],
  root : Int,
  position : Int,
  config : BrotliHashConfig,
  lengths : Array[Int],
  distances : Array[Int],
  start : Int,
) -> Unit {
  let mut node = root
  let mut checks = 0
  while node >= 0 && checks < config.max_match_checks {
    let (match_length, compare) = brotli_suffix_tree_compare(
      data,
      position,
      node,
      config.max_match_length,
    )
    brotli_record_flat_hash_match(
      lengths,
      distances,
      start,
      match_length,
      position - node,
      config.min_match_length,
    )
    if compare < 0 {
      node = left_child[node]
    } else if compare > 0 {
      node = right_child[node]
    } else {
      return
    }
    checks += 1
  }
}

///|
/// Compressed-sparse-row match table. The candidates for position `i` live at
/// `lengths[offsets[i]:offsets[i + 1]]` and the parallel slice of `distances`.
///
/// The DP visits every position of the input, so a per-position
/// `Array[BrotliHashMatchCandidate]` would allocate one array object per byte
/// (plus one struct per candidate). Three flat buffers keep the object count
/// constant regardless of input length.
priv struct BrotliSuffixMatchTable {
  offsets : FixedArray[Int]
  lengths : Array[Int]
  distances : Array[Int]
}

///|
fn brotli_bounded_suffix_tree_match_table(
  data : FixedArray[Byte],
  config : BrotliHashConfig,
) -> BrotliSuffixMatchTable {
  let len = data.length()
  let offsets = FixedArray::make(len + 1, 0)
  let lengths : Array[Int] = []
  let distances : Array[Int] = []
  let left_child = FixedArray::make(len, -1)
  let right_child = FixedArray::make(len, -1)
  let mut root = -1
  for position in 0..<len {
    let start = lengths.length()
    offsets[position] = start
    if root >= 0 {
      brotli_bounded_suffix_tree_collect_matches(
        data, left_child, right_child, root, position, config, lengths, distances,
        start,
      )
    }
    root = brotli_bounded_suffix_tree_insert(
      data, left_child, right_child, root, position, config,
    )
  }
  offsets[len] = lengths.length()
  { offsets, lengths, distances }
}

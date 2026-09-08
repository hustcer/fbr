///|
test "hash and cache matches enforce the inclusive backward window boundary" {
  let position = 1200
  let config3 = brotli_natural_hash_config_for_quality(3, window_bits=10)
  for config in [config3, brotli_four_byte_hash_config(config3)] {
    for copy_length in 6..<=9 {
      for distance in [1008, 1009] {
        let candidate = position - distance
        let data = FixedArray::make(position + copy_length + 1, b'\xff')
        for i in 0..<copy_length {
          data[candidate + i] = (i + 1).to_byte()
          data[position + i] = data[candidate + i]
        }
        data[position + copy_length] = b'\x00'
        // Exercise the chain and the cache independently, so either path
        // forgetting the window constraint fails this test.
        for from_cache in [false, true] {
          let previous = FixedArray::make(data.length(), -1)
          let cache = FixedArray::make(4, if from_cache { distance } else { 0 })
          if !from_cache {
            previous[position] = candidate
          }
          let (length, found_distance) = brotli_longest_previous_hash_match_with_cache(
            data, previous, position, config, cache,
          )
          let lengths : Array[Int] = []
          let distances : Array[Int] = []
          brotli_bounded_previous_hash_matches_flat(
            data, previous, position, config, cache, lengths, distances,
          )
          if distance == 1008 {
            assert_eq(length, copy_length)
            assert_eq(found_distance, distance)
            assert_eq(lengths.length(), 1)
            assert_eq(lengths[0], copy_length)
            assert_eq(distances[0], distance)
          } else {
            assert_eq(length, 0)
            assert_eq(found_distance, 0)
            assert_eq(lengths.length(), 0)
          }
        }
      }
    }
  }
}

///|
test "suffix matches skip expired equal roots and retain in-window descendants" {
  let config = brotli_bounded_shortest_path_config(
    brotli_four_byte_hash_config(
      brotli_high_quality_hash_config_for_quality(11, window_bits=10),
    ),
  )
  // Identical suffix prefixes compare equal at the match-length bound.
  // The tree puts newer equal suffixes on the right of the expired root.
  let position = 1200
  let data = FixedArray::make(position + config.max_match_length, b'a')
  let left_child = FixedArray::make(data.length(), -1)
  let right_child = FixedArray::make(data.length(), -1)
  let root = 0
  right_child[root] = position - 1008
  let lengths : Array[Int] = []
  let distances : Array[Int] = []
  brotli_bounded_suffix_tree_collect_matches(
    data, left_child, right_child, root, position, config, lengths, distances, 0,
  )
  assert_eq(lengths.length(), 1)
  assert_eq(lengths[0], config.max_match_length)
  assert_eq(distances[0], 1008)
}

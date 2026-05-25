///|
priv struct BrotliDictionaryEncodeIndex {
  table : FixedArray[Int]
  next : FixedArray[Int]
  lengths : FixedArray[Int]
  output_lengths : FixedArray[Int]
  word_indices : FixedArray[Int]
  transforms : FixedArray[Int]
}

///|
let brotli_dictionary_encode_hash_size : Int = 32768

///|
let brotli_dictionary_encode_hash_mask : Int = 32767

///|
fn brotli_dictionary_identity_word_total() -> Int {
  let mut total = 0
  for
    length in brotli_dictionary_min_word_length..<=brotli_dictionary_max_word_length {
    let bits = brotli_dictionary_size_bits_by_length[length]
    if bits > 0 {
      total += 1 << bits
    }
  }
  total
}

///|
fn brotli_dictionary_encode_entry_capacity() -> Int {
  brotli_dictionary_identity_word_total() *
  (
    brotli_dictionary_same_length_transform_count() +
    brotli_dictionary_extra_transform_count()
  )
}

///|
fn brotli_dictionary_hash_update(hash : Int, value : Int) -> Int {
  ((hash << 5) - hash + value) & 0x7fffffff
}

///|
fn brotli_dictionary_hash_data(
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Int {
  let mut hash = brotli_dictionary_hash_update(17, length)
  for i in 0..<length {
    hash = brotli_dictionary_hash_update(hash, data[offset + i].to_int())
  }
  hash & brotli_dictionary_encode_hash_mask
}

///|
fn brotli_dictionary_word_offset(length : Int, word_index : Int) -> Int {
  brotli_dictionary_offsets_by_length[length] + word_index * length
}

///|
fn brotli_dictionary_word_byte_at(
  length : Int,
  word_index : Int,
  byte_index : Int,
) -> Byte {
  brotli_dictionary_data[brotli_dictionary_word_offset(length, word_index) +
  byte_index]
}

///|
fn brotli_dictionary_transformed_byte(
  value : Byte,
  transform_type : Int,
  byte_index : Int,
) -> Byte {
  if transform_type == brotli_transform_uppercase_all ||
    (transform_type == brotli_transform_uppercase_first && byte_index == 0) {
    brotli_ascii_upper(value)
  } else {
    value
  }
}

///|
fn brotli_dictionary_transform_type(transform_index : Int) -> Int {
  brotli_transform_triplets[transform_index * 3 + 1]
}

///|
fn brotli_dictionary_transform_prefix_length(transform_index : Int) -> Int {
  let prefix_id = brotli_transform_triplets[transform_index * 3]
  brotli_transform_prefix_suffix[brotli_transform_prefix_suffix_map[prefix_id]].to_int()
}

///|
fn brotli_dictionary_transform_suffix_length(transform_index : Int) -> Int {
  let suffix_id = brotli_transform_triplets[transform_index * 3 + 2]
  brotli_transform_prefix_suffix[brotli_transform_prefix_suffix_map[suffix_id]].to_int()
}

///|
let brotli_dictionary_extra_transforms : FixedArray[Int] = [
  1, 4, 10, 12, 16, 25, 28, 38, 46, 47, 49, 60,
]

///|
fn brotli_dictionary_same_length_transform(transform_index : Int) -> Bool {
  let transform_type = brotli_dictionary_transform_type(transform_index)
  (
    transform_type == brotli_transform_identity ||
    transform_type == brotli_transform_uppercase_first ||
    transform_type == brotli_transform_uppercase_all
  ) &&
  brotli_dictionary_transform_prefix_length(transform_index) == 0 &&
  brotli_dictionary_transform_suffix_length(transform_index) == 0
}

///|
fn brotli_dictionary_extra_transform_count() -> Int {
  brotli_dictionary_extra_transforms.length()
}

///|
fn brotli_dictionary_selected_extra_transform(transform_index : Int) -> Bool {
  for i in 0..<brotli_dictionary_extra_transforms.length() {
    if brotli_dictionary_extra_transforms[i] == transform_index {
      return true
    }
  }
  false
}

///|
fn brotli_dictionary_same_length_transform_count() -> Int {
  let mut count = 0
  for transform_index in 0..<brotli_transform_count() {
    if brotli_dictionary_same_length_transform(transform_index) {
      count += 1
    }
  }
  count
}

///|
fn brotli_dictionary_word_has_ascii_lower(
  length : Int,
  word_index : Int,
) -> Bool {
  for i in 0..<length {
    let value = brotli_dictionary_word_byte_at(length, word_index, i).to_int()
    if value >= 97 && value <= 122 {
      return true
    }
  }
  false
}

///|
fn brotli_dictionary_word_is_ascii(length : Int, word_index : Int) -> Bool {
  for i in 0..<length {
    if brotli_dictionary_word_byte_at(length, word_index, i).to_int() >= 128 {
      return false
    }
  }
  true
}

///|
fn brotli_dictionary_transform_source_start(transform_type : Int) -> Int {
  if transform_type >= brotli_transform_omit_first_1 &&
    transform_type <= brotli_transform_omit_first_9 {
    transform_type - (brotli_transform_omit_first_1 - 1)
  } else {
    0
  }
}

///|
fn brotli_dictionary_transform_source_length(
  length : Int,
  transform_type : Int,
) -> Int {
  if transform_type <= brotli_transform_omit_last_9 {
    length - transform_type
  } else if transform_type >= brotli_transform_omit_first_1 &&
    transform_type <= brotli_transform_omit_first_9 {
    length - (transform_type - (brotli_transform_omit_first_1 - 1))
  } else {
    length
  }
}

///|
fn brotli_dictionary_transform_output_length(
  length : Int,
  transform_index : Int,
) -> Int {
  let transform_type = brotli_dictionary_transform_type(transform_index)
  if transform_type == brotli_transform_shift_first ||
    transform_type == brotli_transform_shift_all {
    return -1
  }
  if transform_type > brotli_transform_omit_last_9 &&
    transform_type < brotli_transform_uppercase_first {
    return -1
  }
  if transform_type > brotli_transform_uppercase_all &&
    transform_type < brotli_transform_omit_first_1 {
    return -1
  }
  if transform_type > brotli_transform_omit_first_9 {
    return -1
  }
  let source_length = brotli_dictionary_transform_source_length(
    length, transform_type,
  )
  if source_length < 0 {
    return -1
  }
  brotli_dictionary_transform_prefix_length(transform_index) +
  source_length +
  brotli_dictionary_transform_suffix_length(transform_index)
}

///|
fn brotli_dictionary_transform_string_byte(
  string_id : Int,
  byte_index : Int,
) -> Byte {
  brotli_transform_prefix_suffix[brotli_transform_prefix_suffix_map[string_id] +
  1 +
  byte_index]
}

///|
fn brotli_dictionary_transform_output_byte(
  length : Int,
  word_index : Int,
  transform_index : Int,
  output_index : Int,
) -> Byte {
  let triplet_offset = transform_index * 3
  let prefix_id = brotli_transform_triplets[triplet_offset]
  let transform_type = brotli_transform_triplets[triplet_offset + 1]
  let suffix_id = brotli_transform_triplets[triplet_offset + 2]
  let prefix_length = brotli_dictionary_transform_prefix_length(transform_index)
  if output_index < prefix_length {
    return brotli_dictionary_transform_string_byte(prefix_id, output_index)
  }
  let source_start = brotli_dictionary_transform_source_start(transform_type)
  let source_length = brotli_dictionary_transform_source_length(
    length, transform_type,
  )
  let source_index = output_index - prefix_length
  if source_index < source_length {
    return brotli_dictionary_transformed_byte(
      brotli_dictionary_word_byte_at(
        length,
        word_index,
        source_start + source_index,
      ),
      transform_type,
      source_index,
    )
  }
  brotli_dictionary_transform_string_byte(
    suffix_id,
    source_index - source_length,
  )
}

///|
fn brotli_dictionary_transform_allowed(
  length : Int,
  word_index : Int,
  transform_index : Int,
) -> Bool {
  if !brotli_dictionary_same_length_transform(transform_index) &&
    !brotli_dictionary_selected_extra_transform(transform_index) {
    return false
  }
  if brotli_dictionary_transform_output_length(length, transform_index) <
    brotli_dictionary_min_word_length {
    return false
  }
  let transform_type = brotli_dictionary_transform_type(transform_index)
  if transform_type == brotli_transform_identity {
    true
  } else if transform_type == brotli_transform_uppercase_first {
    let first = brotli_dictionary_word_byte_at(length, word_index, 0).to_int()
    first >= 97 && first <= 122
  } else if transform_type == brotli_transform_uppercase_all {
    brotli_dictionary_word_is_ascii(length, word_index) &&
    brotli_dictionary_word_has_ascii_lower(length, word_index)
  } else if transform_type <= brotli_transform_omit_last_9 ||
    (
      transform_type >= brotli_transform_omit_first_1 &&
      transform_type <= brotli_transform_omit_first_9
    ) {
    true
  } else {
    false
  }
}

///|
fn brotli_dictionary_hash_word(
  length : Int,
  word_index : Int,
  transform_index : Int,
) -> Int {
  let output_length = brotli_dictionary_transform_output_length(
    length, transform_index,
  )
  let mut hash = brotli_dictionary_hash_update(17, output_length)
  for i in 0..<output_length {
    hash = brotli_dictionary_hash_update(
      hash,
      brotli_dictionary_transform_output_byte(
        length, word_index, transform_index, i,
      ).to_int(),
    )
  }
  hash & brotli_dictionary_encode_hash_mask
}

///|
fn brotli_add_dictionary_encode_entry(
  index : BrotliDictionaryEncodeIndex,
  entry : Int,
  length : Int,
  word_index : Int,
  transform_index : Int,
) -> Int {
  brotli_add_dictionary_encode_entry_with_min_output(
    index, entry, length, word_index, transform_index, brotli_dictionary_min_word_length,
  )
}

///|
fn brotli_add_dictionary_encode_entry_with_min_output(
  index : BrotliDictionaryEncodeIndex,
  entry : Int,
  length : Int,
  word_index : Int,
  transform_index : Int,
  min_output_length : Int,
) -> Int {
  let output_length = brotli_dictionary_transform_output_length(
    length, transform_index,
  )
  if output_length < min_output_length {
    return entry
  }
  if !brotli_dictionary_transform_allowed(length, word_index, transform_index) {
    return entry
  }
  let hash = brotli_dictionary_hash_word(length, word_index, transform_index)
  index.lengths[entry] = length
  index.output_lengths[entry] = output_length
  index.word_indices[entry] = word_index
  index.transforms[entry] = transform_index
  index.next[entry] = index.table[hash]
  index.table[hash] = entry
  entry + 1
}

///|
fn brotli_build_dictionary_encode_index() -> BrotliDictionaryEncodeIndex {
  let total = brotli_dictionary_encode_entry_capacity()
  let table = FixedArray::make(brotli_dictionary_encode_hash_size, -1)
  let next = FixedArray::make(total, -1)
  let lengths = FixedArray::make(total, 0)
  let output_lengths = FixedArray::make(total, 0)
  let word_indices = FixedArray::make(total, 0)
  let transforms = FixedArray::make(total, 0)
  let index = { table, next, lengths, output_lengths, word_indices, transforms }
  let mut entry = 0
  for
    length in brotli_dictionary_min_word_length..<=brotli_dictionary_max_word_length {
    let bits = brotli_dictionary_size_bits_by_length[length]
    if bits > 0 {
      let word_count = 1 << bits
      for word_index in 0..<word_count {
        for transform_index in 0..<brotli_transform_count() {
          entry = brotli_add_dictionary_encode_entry(
            index, entry, length, word_index, transform_index,
          )
        }
      }
    }
  }
  ignore(entry)
  index
}

///|
fn brotli_build_dictionary_encode_index_min_output(
  min_output_length : Int,
) -> BrotliDictionaryEncodeIndex {
  let total = brotli_dictionary_encode_entry_capacity()
  let table = FixedArray::make(brotli_dictionary_encode_hash_size, -1)
  let next = FixedArray::make(total, -1)
  let lengths = FixedArray::make(total, 0)
  let output_lengths = FixedArray::make(total, 0)
  let word_indices = FixedArray::make(total, 0)
  let transforms = FixedArray::make(total, 0)
  let index = { table, next, lengths, output_lengths, word_indices, transforms }
  let mut entry = 0
  for
    length in brotli_dictionary_min_word_length..<=brotli_dictionary_max_word_length {
    let bits = brotli_dictionary_size_bits_by_length[length]
    if bits > 0 {
      let word_count = 1 << bits
      for word_index in 0..<word_count {
        entry = brotli_add_dictionary_encode_entry_with_min_output(
          index, entry, length, word_index, 0, min_output_length,
        )
      }
    }
  }
  ignore(entry)
  index
}

///|
fn brotli_dictionary_word_byte(value : Byte) -> Bool {
  let code = value.to_int()
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122)
}

///|
fn brotli_dictionary_word_matches(
  data : FixedArray[Byte],
  position : Int,
  length : Int,
  output_length : Int,
  word_index : Int,
  transform_index : Int,
) -> Bool {
  for i in 0..<output_length {
    let expected = brotli_dictionary_transform_output_byte(
      length, word_index, transform_index, i,
    )
    if data[position + i] != expected {
      return false
    }
  }
  true
}

///|
fn brotli_encoder_max_distance(output_len : Int, window_bits : Int) -> Int {
  let cap = (1 << window_bits) - brotli_window_gap
  if output_len < cap {
    output_len
  } else {
    cap
  }
}

///|
fn brotli_find_identity_dictionary_match(
  index : BrotliDictionaryEncodeIndex,
  data : FixedArray[Byte],
  position : Int,
  global_position : Int,
  window_bits : Int,
) -> (Int, Int, Int)? {
  if position > 0 && brotli_dictionary_word_byte(data[position - 1]) {
    return None
  }
  let max_length = if data.length() - position <
    brotli_dictionary_max_word_length {
    data.length() - position
  } else {
    brotli_dictionary_max_word_length
  }
  let mut output_length = max_length
  while output_length >= brotli_dictionary_min_word_length {
    let output_ends_word = brotli_dictionary_word_byte(
      data[position + output_length - 1],
    )
    if position + output_length == data.length() ||
      !output_ends_word ||
      !brotli_dictionary_word_byte(data[position + output_length]) {
      let hash = brotli_dictionary_hash_data(data, position, output_length)
      let mut entry = index.table[hash]
      while entry >= 0 {
        let length = index.lengths[entry]
        if index.output_lengths[entry] == output_length &&
          brotli_dictionary_word_matches(
            data,
            position,
            length,
            output_length,
            index.word_indices[entry],
            index.transforms[entry],
          ) {
          let max_distance = brotli_encoder_max_distance(
            global_position, window_bits,
          )
          let word_count = 1 << brotli_dictionary_size_bits_by_length[length]
          let distance = max_distance +
            1 +
            index.word_indices[entry] +
            index.transforms[entry] * word_count
          return Some((length, output_length, distance))
        }
        entry = index.next[entry]
      }
    }
    output_length -= 1
  }
  None
}

///|
fn brotli_build_identity_dictionary_commands(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  base_offset : Int,
  window_bits : Int,
) -> Array[BrotliEncodeCommand]? {
  if data.length() < brotli_dictionary_min_word_length || data.length() > 4096 {
    return None
  }
  if base_offset != 0 {
    return None
  }
  let index = brotli_build_dictionary_encode_index()
  let commands : Array[BrotliEncodeCommand] = []
  let mut literal_start = 0
  let mut position = 0
  while position < data.length() {
    match
      brotli_find_identity_dictionary_match(
        index,
        data,
        position,
        base_offset + position,
        window_bits,
      ) {
      Some((length, output_length, distance)) => {
        let insert_length = position - literal_start
        let command_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_dictionary_encode_command(
          literal_start, insert_length, length, output_length, distance,
        )
        match command_result {
          Ok(command) => commands.push(command)
          Err(_) => return None
        }
        if commands.length() > hash_config.max_commands {
          return None
        }
        position += output_length
        literal_start = position
      }
      None => position += 1
    }
  }
  if commands.length() == 0 {
    return None
  }
  if literal_start < data.length() {
    let final_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command(
      literal_start,
      data.length() - literal_start,
      0,
      0,
      false,
    )
    match final_result {
      Ok(command) => commands.push(command)
      Err(_) => return None
    }
  }
  Some(commands)
}

///|
fn brotli_build_mixed_dictionary_lz77_commands(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  base_offset : Int,
  window_bits : Int,
) -> Array[BrotliEncodeCommand]? {
  if data.length() < 8192 || data.length() > 1048576 {
    return None
  }
  if !brotli_has_compressible_match_density(data, hash_config) {
    return None
  }
  let index = brotli_build_dictionary_encode_index_min_output(8)
  let commands : Array[BrotliEncodeCommand] = []
  let previous = brotli_previous_match_positions(data, hash_config)
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  let mut literal_start = 0
  let mut position = 0
  let mut used_dictionary = false
  while position < data.length() {
    let (match_length, distance) = brotli_longest_previous_hash_match_with_cache(
      data, previous, position, hash_config, distance_cache,
    )
    if match_length < 22 &&
      brotli_dictionary_word_byte(data[position]) &&
      (position == 0 || !brotli_dictionary_word_byte(data[position - 1])) {
      match
        brotli_find_identity_dictionary_match(
          index,
          data,
          position,
          base_offset + position,
          window_bits,
        ) {
        Some((word_length, output_length, dictionary_distance)) =>
          if output_length >= 8 && output_length >= match_length + 2 {
            let insert_length = position - literal_start
            let command_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_dictionary_encode_command(
              literal_start, insert_length, word_length, output_length, dictionary_distance,
            )
            match command_result {
              Ok(command) => commands.push(command)
              Err(_) => return None
            }
            used_dictionary = true
            if commands.length() > hash_config.max_commands {
              return None
            }
            position += output_length
            literal_start = position
            continue
          }
        None => ()
      }
    }
    if match_length >= hash_config.min_match_length {
      let lookahead = hash_config.lazy_lookahead
      if lookahead > 0 {
        let mut k = 1
        let mut skip = 0
        while k <= lookahead && position + k < data.length() {
          let (next_length, _) = brotli_longest_previous_hash_match_with_cache(
            data,
            previous,
            position + k,
            hash_config,
            distance_cache,
          )
          if next_length > match_length {
            skip = k
            break
          }
          k += 1
        }
        if skip > 0 {
          position += skip
          continue
        }
      }
      let insert_length = position - literal_start
      let distance_code = brotli_compute_distance_code(
        distance, position, distance_cache,
      )
      let command = match
        brotli_try_make_encode_command_with_distance_code(
          literal_start, insert_length, match_length, distance, distance_code,
        ) {
        Some(command) => command
        None =>
          match
            brotli_try_make_encode_command_with_distance_mode(
              literal_start, insert_length, match_length, distance, true, true,
            ) {
            Some(command) => command
            None => return None
          }
      }
      commands.push(command)
      brotli_update_distance_cache(distance_cache, distance, distance_code)
      if commands.length() > hash_config.max_commands {
        return None
      }
      position += match_length
      literal_start = position
    } else {
      position += hash_config.scan_step
    }
  }
  if !used_dictionary || commands.length() == 0 {
    return None
  }
  if literal_start < data.length() {
    let final_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command(
      literal_start,
      data.length() - literal_start,
      0,
      0,
      false,
    )
    match final_result {
      Ok(command) => commands.push(command)
      Err(_) => return None
    }
  }
  let copy_bytes = brotli_commands_copy_bytes(commands)
  if copy_bytes * 100 < data.length() * hash_config.min_copy_ratio_percent {
    return None
  }
  Some(commands)
}

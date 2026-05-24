///|
priv struct BrotliDictionaryEncodeIndex {
  table : FixedArray[Int]
  next : FixedArray[Int]
  lengths : FixedArray[Int]
  word_indices : FixedArray[Int]
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
fn brotli_dictionary_hash_word(length : Int, word_index : Int) -> Int {
  let offset = brotli_dictionary_offsets_by_length[length] + word_index * length
  let mut hash = brotli_dictionary_hash_update(17, length)
  for i in 0..<length {
    hash = brotli_dictionary_hash_update(
      hash,
      brotli_dictionary_data[offset + i].to_int(),
    )
  }
  hash & brotli_dictionary_encode_hash_mask
}

///|
fn brotli_build_dictionary_encode_index() -> BrotliDictionaryEncodeIndex {
  let total = brotli_dictionary_identity_word_total()
  let table = FixedArray::make(brotli_dictionary_encode_hash_size, -1)
  let next = FixedArray::make(total, -1)
  let lengths = FixedArray::make(total, 0)
  let word_indices = FixedArray::make(total, 0)
  let mut entry = 0
  for
    length in brotli_dictionary_min_word_length..<=brotli_dictionary_max_word_length {
    let bits = brotli_dictionary_size_bits_by_length[length]
    if bits > 0 {
      let word_count = 1 << bits
      for word_index in 0..<word_count {
        let hash = brotli_dictionary_hash_word(length, word_index)
        lengths[entry] = length
        word_indices[entry] = word_index
        next[entry] = table[hash]
        table[hash] = entry
        entry += 1
      }
    }
  }
  ignore(entry)
  { table, next, lengths, word_indices }
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
  word_index : Int,
) -> Bool {
  let offset = brotli_dictionary_offsets_by_length[length] + word_index * length
  for i in 0..<length {
    if data[position + i] != brotli_dictionary_data[offset + i] {
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
) -> (Int, Int)? {
  if position > 0 && brotli_dictionary_word_byte(data[position - 1]) {
    return None
  }
  let max_length = if data.length() - position <
    brotli_dictionary_max_word_length {
    data.length() - position
  } else {
    brotli_dictionary_max_word_length
  }
  let mut length = max_length
  while length >= brotli_dictionary_min_word_length {
    if position + length == data.length() ||
      !brotli_dictionary_word_byte(data[position + length]) {
      let hash = brotli_dictionary_hash_data(data, position, length)
      let mut entry = index.table[hash]
      while entry >= 0 {
        if index.lengths[entry] == length &&
          brotli_dictionary_word_matches(
            data,
            position,
            length,
            index.word_indices[entry],
          ) {
          let max_distance = brotli_encoder_max_distance(
            global_position, window_bits,
          )
          let distance = max_distance + 1 + index.word_indices[entry]
          return Some((length, distance))
        }
        entry = index.next[entry]
      }
    }
    length -= 1
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
      Some((length, distance)) => {
        let insert_length = position - literal_start
        let command_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command(
          literal_start, insert_length, length, distance, true,
        )
        match command_result {
          Ok(command) => commands.push(command)
          Err(_) => return None
        }
        if commands.length() > hash_config.max_commands {
          return None
        }
        position += length
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

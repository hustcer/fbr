///|
priv struct BrotliDictionaryEncodeIndex {
  table : FixedArray[Int]
  next : FixedArray[Int]
  lengths : FixedArray[Int]
  output_lengths : FixedArray[Int]
  word_indices : FixedArray[Int]
  transforms : FixedArray[Int]
  /// Start of each entry's transformed output bytes in `output_pool`.
  output_offsets : FixedArray[Int]
  /// Every entry's transformed output bytes, materialized once at build
  /// time so match verification is a flat byte compare instead of
  /// re-running the per-byte transform machinery.
  output_pool : FixedArray[Byte]
}

///|
/// Growable variant used while building an index: entries append their
/// transformed output bytes to `pool`, which is frozen into the final
/// index's `output_pool`.
priv struct BrotliDictionaryIndexBuilder {
  table : FixedArray[Int]
  next : FixedArray[Int]
  lengths : FixedArray[Int]
  output_lengths : FixedArray[Int]
  word_indices : FixedArray[Int]
  transforms : FixedArray[Int]
  output_offsets : FixedArray[Int]
  pool : Array[Byte]
}

///|
fn brotli_dictionary_index_builder_new(
  total : Int,
) -> BrotliDictionaryIndexBuilder {
  {
    table: FixedArray::make(brotli_dictionary_encode_hash_size, -1),
    next: FixedArray::make(total, -1),
    lengths: FixedArray::make(total, 0),
    output_lengths: FixedArray::make(total, 0),
    word_indices: FixedArray::make(total, 0),
    transforms: FixedArray::make(total, 0),
    output_offsets: FixedArray::make(total, 0),
    pool: [],
  }
}

///|
fn brotli_dictionary_index_builder_finish(
  builder : BrotliDictionaryIndexBuilder,
) -> BrotliDictionaryEncodeIndex {
  {
    table: builder.table,
    next: builder.next,
    lengths: builder.lengths,
    output_lengths: builder.output_lengths,
    word_indices: builder.word_indices,
    transforms: builder.transforms,
    output_offsets: builder.output_offsets,
    output_pool: FixedArray::from_array(builder.pool),
  }
}

///|
let brotli_dictionary_encode_hash_size : Int = 32768

///|
let brotli_dictionary_encode_hash_mask : Int = 32767

///|
fn brotli_dictionary_identity_word_total() -> Int {
  let mut total = 0
  for
    length in @common.brotli_dictionary_min_word_length..<=@common.brotli_dictionary_max_word_length {
    let bits = @common.brotli_dictionary_size_bits_by_length[length]
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
fn brotli_dictionary_mixed_encode_entry_capacity() -> Int {
  brotli_dictionary_identity_word_total() *
  (
    brotli_dictionary_same_length_transform_count() +
    brotli_dictionary_mixed_extra_transforms.length()
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
  @common.brotli_dictionary_offsets_by_length[length] + word_index * length
}

///|
fn brotli_dictionary_word_byte_at(
  length : Int,
  word_index : Int,
  byte_index : Int,
) -> Byte {
  @common.brotli_dictionary_data[brotli_dictionary_word_offset(
    length, word_index,
  ) +
  byte_index]
}

///|
fn brotli_dictionary_transformed_byte(
  value : Byte,
  transform_type : Int,
  byte_index : Int,
) -> Byte {
  if transform_type == @common.brotli_transform_uppercase_all ||
    (
      transform_type == @common.brotli_transform_uppercase_first &&
      byte_index == 0
    ) {
    @common.brotli_ascii_upper(value)
  } else {
    value
  }
}

///|
fn brotli_dictionary_transform_type(transform_index : Int) -> Int {
  @common.brotli_transform_triplets[transform_index * 3 + 1]
}

///|
fn brotli_dictionary_transform_prefix_length(transform_index : Int) -> Int {
  let prefix_id = @common.brotli_transform_triplets[transform_index * 3]
  @common.brotli_transform_prefix_suffix[@common.brotli_transform_prefix_suffix_map[prefix_id]].to_int()
}

///|
fn brotli_dictionary_transform_suffix_length(transform_index : Int) -> Int {
  let suffix_id = @common.brotli_transform_triplets[transform_index * 3 + 2]
  @common.brotli_transform_prefix_suffix[@common.brotli_transform_prefix_suffix_map[suffix_id]].to_int()
}

///|
let brotli_dictionary_extra_transforms : FixedArray[Int] = [
  1, 4, 10, 12, 16, 25, 28, 38, 46, 47, 49, 60,
]

///|
let brotli_dictionary_same_length_transforms : FixedArray[Int] = [0, 9, 44]

///|
let brotli_dictionary_mixed_extra_transforms : FixedArray[Int] = [1, 4]

///|
fn brotli_dictionary_same_length_transform(transform_index : Int) -> Bool {
  let transform_type = brotli_dictionary_transform_type(transform_index)
  (
    transform_type == @common.brotli_transform_identity ||
    transform_type == @common.brotli_transform_uppercase_first ||
    transform_type == @common.brotli_transform_uppercase_all
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
  for transform_index in 0..<@common.brotli_transform_count() {
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
  if transform_type >= @common.brotli_transform_omit_first_1 &&
    transform_type <= @common.brotli_transform_omit_first_9 {
    transform_type - (@common.brotli_transform_omit_first_1 - 1)
  } else {
    0
  }
}

///|
fn brotli_dictionary_transform_source_length(
  length : Int,
  transform_type : Int,
) -> Int {
  if transform_type <= @common.brotli_transform_omit_last_9 {
    length - transform_type
  } else if transform_type >= @common.brotli_transform_omit_first_1 &&
    transform_type <= @common.brotli_transform_omit_first_9 {
    length - (transform_type - (@common.brotli_transform_omit_first_1 - 1))
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
  if transform_type == @common.brotli_transform_shift_first ||
    transform_type == @common.brotli_transform_shift_all {
    return -1
  }
  if transform_type > @common.brotli_transform_omit_last_9 &&
    transform_type < @common.brotli_transform_uppercase_first {
    return -1
  }
  if transform_type > @common.brotli_transform_uppercase_all &&
    transform_type < @common.brotli_transform_omit_first_1 {
    return -1
  }
  if transform_type > @common.brotli_transform_omit_first_9 {
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
  @common.brotli_transform_prefix_suffix[@common.brotli_transform_prefix_suffix_map[string_id] +
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
  let prefix_id = @common.brotli_transform_triplets[triplet_offset]
  let transform_type = @common.brotli_transform_triplets[triplet_offset + 1]
  let suffix_id = @common.brotli_transform_triplets[triplet_offset + 2]
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
    @common.brotli_dictionary_min_word_length {
    return false
  }
  let transform_type = brotli_dictionary_transform_type(transform_index)
  if transform_type == @common.brotli_transform_identity {
    true
  } else if transform_type == @common.brotli_transform_uppercase_first {
    let first = brotli_dictionary_word_byte_at(length, word_index, 0).to_int()
    first >= 97 && first <= 122
  } else if transform_type == @common.brotli_transform_uppercase_all {
    brotli_dictionary_word_is_ascii(length, word_index) &&
    brotli_dictionary_word_has_ascii_lower(length, word_index)
  } else if transform_type <= @common.brotli_transform_omit_last_9 ||
    (
      transform_type >= @common.brotli_transform_omit_first_1 &&
      transform_type <= @common.brotli_transform_omit_first_9
    ) {
    true
  } else {
    false
  }
}

///|
fn brotli_add_dictionary_encode_entry(
  builder : BrotliDictionaryIndexBuilder,
  entry : Int,
  length : Int,
  word_index : Int,
  transform_index : Int,
) -> Int {
  brotli_add_dictionary_encode_entry_with_min_output(
    builder, entry, length, word_index, transform_index, @common.brotli_dictionary_min_word_length,
  )
}

///|
fn brotli_add_dictionary_encode_entry_with_min_output(
  builder : BrotliDictionaryIndexBuilder,
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
  // Materialize the transformed output bytes once, feeding the entry hash
  // and the shared verification pool in the same pass.
  let offset = builder.pool.length()
  let mut hash = brotli_dictionary_hash_update(17, output_length)
  for i in 0..<output_length {
    let value = brotli_dictionary_transform_output_byte(
      length, word_index, transform_index, i,
    )
    hash = brotli_dictionary_hash_update(hash, value.to_int())
    builder.pool.push(value)
  }
  let hash = hash & brotli_dictionary_encode_hash_mask
  builder.lengths[entry] = length
  builder.output_lengths[entry] = output_length
  builder.word_indices[entry] = word_index
  builder.transforms[entry] = transform_index
  builder.output_offsets[entry] = offset
  builder.next[entry] = builder.table[hash]
  builder.table[hash] = entry
  entry + 1
}

///|
fn brotli_build_dictionary_encode_index() -> BrotliDictionaryEncodeIndex {
  let total = brotli_dictionary_encode_entry_capacity()
  let builder = brotli_dictionary_index_builder_new(total)
  let mut entry = 0
  for
    length in @common.brotli_dictionary_min_word_length..<=@common.brotli_dictionary_max_word_length {
    let bits = @common.brotli_dictionary_size_bits_by_length[length]
    if bits > 0 {
      let word_count = 1 << bits
      for word_index in 0..<word_count {
        for transform_index in 0..<@common.brotli_transform_count() {
          entry = brotli_add_dictionary_encode_entry(
            builder, entry, length, word_index, transform_index,
          )
        }
      }
    }
  }
  ignore(entry)
  brotli_dictionary_index_builder_finish(builder)
}

///|
fn brotli_build_dictionary_encode_index_min_output(
  min_output_length : Int,
) -> BrotliDictionaryEncodeIndex {
  let total = brotli_dictionary_mixed_encode_entry_capacity()
  let builder = brotli_dictionary_index_builder_new(total)
  let mut entry = 0
  for
    length in @common.brotli_dictionary_min_word_length..<=@common.brotli_dictionary_max_word_length {
    let bits = @common.brotli_dictionary_size_bits_by_length[length]
    if bits > 0 {
      let word_count = 1 << bits
      for word_index in 0..<word_count {
        for i in 0..<brotli_dictionary_same_length_transforms.length() {
          entry = brotli_add_dictionary_encode_entry_with_min_output(
            builder,
            entry,
            length,
            word_index,
            brotli_dictionary_same_length_transforms[i],
            min_output_length,
          )
        }
        for i in 0..<brotli_dictionary_mixed_extra_transforms.length() {
          entry = brotli_add_dictionary_encode_entry_with_min_output(
            builder,
            entry,
            length,
            word_index,
            brotli_dictionary_mixed_extra_transforms[i],
            min_output_length,
          )
        }
      }
    }
  }
  ignore(entry)
  brotli_dictionary_index_builder_finish(builder)
}

///|
/// Process-lifetime cache for the two dictionary encode indexes. Both are
/// pure functions of the static Brotli dictionary tables, so a cached
/// value is never stale; caching mirrors Google Brotli's compile-time
/// static dictionary hash and removes the dominant per-call cost of the
/// dictionary candidates (rebuilding ~200k transform entries).
priv struct BrotliDictionaryIndexCache {
  mut identity : BrotliDictionaryEncodeIndex?
  mut mixed_min8 : BrotliDictionaryEncodeIndex?
}

///|
let brotli_dictionary_index_cache : BrotliDictionaryIndexCache = {
  identity: None,
  mixed_min8: None,
}

///|
fn brotli_identity_dictionary_encode_index() -> BrotliDictionaryEncodeIndex {
  match brotli_dictionary_index_cache.identity {
    Some(index) => index
    None => {
      let index = brotli_build_dictionary_encode_index()
      brotli_dictionary_index_cache.identity = Some(index)
      index
    }
  }
}

///|
fn brotli_mixed_dictionary_encode_index_min8() -> BrotliDictionaryEncodeIndex {
  match brotli_dictionary_index_cache.mixed_min8 {
    Some(index) => index
    None => {
      let index = brotli_build_dictionary_encode_index_min_output(8)
      brotli_dictionary_index_cache.mixed_min8 = Some(index)
      index
    }
  }
}

///|
fn brotli_dictionary_word_byte(value : Byte) -> Bool {
  let code = value.to_int()
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122)
}

///|
fn brotli_mixed_dictionary_may_pay(data : FixedArray[Byte]) -> Bool {
  if data.length() < 8192 {
    return false
  }
  let required = if data.length() < 65536 { 4 } else { data.length() / 16384 }
  let mut candidates = 0
  let mut position = 0
  while position < data.length() {
    if brotli_dictionary_word_byte(data[position]) &&
      (position == 0 || !brotli_dictionary_word_byte(data[position - 1])) {
      let mut length = 0
      while position + length < data.length() &&
            brotli_dictionary_word_byte(data[position + length]) {
        length += 1
      }
      if length >= 7 {
        candidates += 1
        if candidates >= required {
          return true
        }
      }
      position += length
    } else {
      position += 1
    }
  }
  false
}

///|
/// Compares input bytes at `position` against one index entry's
/// materialized output bytes. Equivalent to re-deriving each byte through
/// the transform machinery, but a flat pool compare.
fn brotli_dictionary_entry_matches(
  index : BrotliDictionaryEncodeIndex,
  entry : Int,
  data : FixedArray[Byte],
  position : Int,
) -> Bool {
  let offset = index.output_offsets[entry]
  let output_length = index.output_lengths[entry]
  for i in 0..<output_length {
    if data[position + i] != index.output_pool[offset + i] {
      return false
    }
  }
  true
}

///|
fn brotli_encoder_max_distance(output_len : Int, window_bits : Int) -> Int {
  let cap = (1 << window_bits) - @common.brotli_window_gap
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
    @common.brotli_dictionary_max_word_length {
    data.length() - position
  } else {
    @common.brotli_dictionary_max_word_length
  }
  let mut output_length = max_length
  while output_length >= @common.brotli_dictionary_min_word_length {
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
          brotli_dictionary_entry_matches(index, entry, data, position) {
          let max_distance = brotli_encoder_max_distance(
            global_position, window_bits,
          )
          let word_count = 1 <<
            @common.brotli_dictionary_size_bits_by_length[length]
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
  if data.length() < @common.brotli_dictionary_min_word_length ||
    data.length() > 4096 {
    return None
  }
  if base_offset != 0 {
    return None
  }
  let index = brotli_identity_dictionary_encode_index()
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
        match
          brotli_try_optional(() => {
            brotli_make_dictionary_encode_command(
              literal_start, insert_length, length, output_length, distance,
            )
          }) {
          Some(command) => commands.push(command)
          None => return None
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
    match
      brotli_try_optional(() => {
        brotli_make_encode_command(
          literal_start,
          data.length() - literal_start,
          0,
          0,
          false,
        )
      }) {
      Some(command) => commands.push(command)
      None => return None
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
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  brotli_build_mixed_dictionary_lz77_commands_with_distance_cache(
    data, hash_config, base_offset, window_bits, distance_cache,
  )
}

///|
fn brotli_build_mixed_dictionary_lz77_command_candidate(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  base_offset : Int,
  window_bits : Int,
  distance_cache : FixedArray[Int],
) -> BrotliCommandCandidate? {
  // Dictionary copies do not update Brotli's recent-distance ring, but the
  // interleaved LZ77 copies do. Preserve that terminal state for the selected
  // chunk candidate.
  let chunk_cache = brotli_copy_distance_cache(distance_cache)
  match
    brotli_build_mixed_dictionary_lz77_commands_with_distance_cache(
      data, hash_config, base_offset, window_bits, chunk_cache,
    ) {
    Some(commands) => Some({ commands, distance_cache: chunk_cache })
    None => None
  }
}

///|
fn brotli_build_mixed_dictionary_lz77_commands_with_distance_cache(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  base_offset : Int,
  window_bits : Int,
  distance_cache : FixedArray[Int],
) -> Array[BrotliEncodeCommand]? {
  if data.length() < 8192 ||
    data.length() > brotli_hash_max_input_length(hash_config) {
    return None
  }
  if !brotli_has_compressible_match_density(data, hash_config) {
    return None
  }
  let index = brotli_mixed_dictionary_encode_index_min8()
  let commands : Array[BrotliEncodeCommand] = []
  let max_commands = brotli_effective_max_commands(hash_config, data.length())
  let previous = brotli_previous_match_positions(data, hash_config)
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
            match
              brotli_try_optional(() => {
                brotli_make_dictionary_encode_command(
                  literal_start, insert_length, word_length, output_length, dictionary_distance,
                )
              }) {
              Some(command) => commands.push(command)
              None => return None
            }
            used_dictionary = true
            if commands.length() > max_commands {
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
      let mut emitted_distance_code = distance_code
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
            Some(command) => {
              // Keep the carried cache aligned with the actual stream when a
              // short-code attempt has to fall back to an explicit distance.
              emitted_distance_code = command.distance_prefix.symbol
              command
            }
            None => return None
          }
      }
      commands.push(command)
      brotli_update_distance_cache(
        distance_cache, distance, emitted_distance_code,
      )
      if commands.length() > max_commands {
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
    match
      brotli_try_optional(() => {
        brotli_make_encode_command(
          literal_start,
          data.length() - literal_start,
          0,
          0,
          false,
        )
      }) {
      Some(command) => commands.push(command)
      None => return None
    }
  }
  let copy_bytes = brotli_commands_copy_bytes(commands)
  if copy_bytes * 100 < data.length() * hash_config.min_copy_ratio_percent {
    return None
  }
  Some(commands)
}

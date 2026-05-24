///|
priv struct BrotliBitWriter {
  buf : FixedArray[Byte]
  mut bit_pos : Int
}

///|
priv struct BrotliCommandPrefix {
  symbol : Int
  insert_extra : Int
  copy_extra : Int
  insert_extra_bits : Int
  copy_extra_bits : Int
}

///|
priv struct BrotliSingleCopyMatch {
  insert_length : Int
  copy_length : Int
  distance : Int
  literal_symbols : FixedArray[Int]
  literal_symbol_count : Int
}

///|
priv struct BrotliLiteralSet {
  symbols : FixedArray[Int]
  count : Int
}

///|
priv struct BrotliHuffmanSpec {
  symbols : FixedArray[Int]
  count : Int
  code_lengths : FixedArray[Byte]
  alphabet_size_max : Int
  alphabet_size_limit : Int
  simple : Bool
}

///|
priv struct BrotliEncodeCommand {
  insert_start : Int
  insert_length : Int
  has_copy : Bool
  command : BrotliCommandPrefix
  distance_prefix : BrotliCommandPrefix
}

///|
fn BrotliBitWriter::new(capacity : Int) -> BrotliBitWriter {
  { buf: FixedArray::make(capacity, b'\x00'), bit_pos: 0 }
}

///|
fn BrotliBitWriter::write_bits(
  self : BrotliBitWriter,
  count : Int,
  value : Int,
) -> Unit {
  let mut remaining = count
  let mut value = value
  while remaining > 0 {
    let byte_index = self.bit_pos / 8
    let bit_index = self.bit_pos & 7
    let space = 8 - bit_index
    let take = if remaining < space { remaining } else { space }
    let mask = (1 << take) - 1
    let part = value & mask
    self.buf[byte_index] = (self.buf[byte_index].to_int() | (part << bit_index)).to_byte()
    self.bit_pos += take
    value = value >> take
    remaining -= take
  }
}

///|
fn BrotliBitWriter::align_to_byte(self : BrotliBitWriter) -> Unit {
  let extra = self.bit_pos & 7
  if extra != 0 {
    self.bit_pos += 8 - extra
  }
}

///|
fn BrotliBitWriter::write_bytes(
  self : BrotliBitWriter,
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  self.align_to_byte()
  let byte_offset = self.bit_pos / 8
  data.blit_to(self.buf, len=length, src_offset=offset, dst_offset=byte_offset)
  self.bit_pos += length * 8
}

///|
fn BrotliBitWriter::write_from_bits(
  self : BrotliBitWriter,
  data : FixedArray[Byte],
  bit_count : Int,
) -> Unit {
  for pos in 0..<bit_count {
    let bit = (data[pos / 8].to_int() >> (pos & 7)) & 1
    self.write_bits(1, bit)
  }
}

///|
fn BrotliBitWriter::finish(self : BrotliBitWriter) -> FixedArray[Byte] {
  trim_buf(self.buf, shft(self.bit_pos))
}

///|
fn brotli_encode_window_bits(
  writer : BrotliBitWriter,
  window_bits : Int,
) -> Unit raise FzipError {
  brotli_validate_window_bits(window_bits)
  if window_bits == 16 {
    writer.write_bits(1, 0)
  } else if window_bits == 17 {
    writer.write_bits(1, 1)
    writer.write_bits(3, 0)
    writer.write_bits(3, 0)
  } else if window_bits >= 18 && window_bits <= 24 {
    writer.write_bits(1, 1)
    writer.write_bits(3, window_bits - 17)
  } else if window_bits == 10 {
    writer.write_bits(1, 1)
    writer.write_bits(3, 0)
    writer.write_bits(3, 2)
  } else {
    writer.write_bits(1, 1)
    writer.write_bits(3, 0)
    writer.write_bits(3, window_bits - 8)
  }
}

///|
fn brotli_metablock_mnibbles(length : Int) -> Int {
  if length <= 1 << 16 {
    0
  } else if length <= 1 << 20 {
    1
  } else {
    2
  }
}

///|
fn brotli_write_length_nibbles(
  writer : BrotliBitWriter,
  length : Int,
  mnibbles : Int,
) -> Unit {
  let encoded = length - 1
  for i in 0..<(mnibbles + 4) {
    writer.write_bits(4, (encoded >> (i * 4)) & 0xf)
  }
}

///|
fn brotli_write_metablock_header(
  writer : BrotliBitWriter,
  length : Int,
  is_last : Bool,
  is_uncompressed : Bool,
) -> Unit {
  let mnibbles = brotli_metablock_mnibbles(length)
  writer.write_bits(1, if is_last { 1 } else { 0 })
  if is_last {
    writer.write_bits(1, 0) // not empty
  }
  writer.write_bits(2, mnibbles)
  brotli_write_length_nibbles(writer, length, mnibbles)
  if !is_last {
    writer.write_bits(1, if is_uncompressed { 1 } else { 0 })
  }
}

///|
fn brotli_write_uncompressed_metablock(
  writer : BrotliBitWriter,
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  brotli_write_metablock_header(writer, length, false, true)
  writer.write_bytes(data, offset, length)
}

///|
fn brotli_write_final_empty_metablock(writer : BrotliBitWriter) -> Unit {
  writer.write_bits(1, 1) // ISLAST
  writer.write_bits(1, 1) // ISLASTEMPTY
}

///|
fn brotli_encoded_capacity(input_len : Int) -> Int {
  let blocks = if input_len == 0 {
    0
  } else {
    (input_len + brotli_max_metablock_bytes - 1) / brotli_max_metablock_bytes
  }
  input_len + 8 + blocks * 8
}

///|
fn brotli_write_simple_one_symbol_huffman(
  writer : BrotliBitWriter,
  symbol : Int,
  symbol_bits : Int,
) -> Unit {
  writer.write_bits(2, 1) // simple Huffman marker
  writer.write_bits(2, 0) // one symbol
  writer.write_bits(symbol_bits, symbol)
}

///|
fn brotli_write_simple_huffman(
  writer : BrotliBitWriter,
  symbols : FixedArray[Int],
  count : Int,
  symbol_bits : Int,
) -> Unit {
  writer.write_bits(2, 1) // simple Huffman marker
  writer.write_bits(2, count - 1)
  for i in 0..<count {
    writer.write_bits(symbol_bits, symbols[i])
  }
  if count == 4 {
    writer.write_bits(1, 0)
  }
}

///|
fn brotli_next_power_of_two(value : Int) -> Int {
  let mut power = 1
  while power < value {
    power *= 2
  }
  power
}

///|
fn brotli_contains_symbol(
  symbols : FixedArray[Int],
  count : Int,
  symbol : Int,
) -> Bool {
  for i in 0..<count {
    if symbols[i] == symbol {
      return true
    }
  }
  false
}

///|
fn brotli_make_huffman_spec(
  symbols : FixedArray[Int],
  count : Int,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
) -> BrotliHuffmanSpec raise FzipError {
  if count <= 0 || count > alphabet_size_limit {
    raise fzip_err(BrotliInvalidHuffman, msg="invalid encoder alphabet")
  }
  let code_lengths = FixedArray::make(alphabet_size_limit, b'\x00')
  if count <= 4 {
    return {
      symbols,
      count,
      code_lengths,
      alphabet_size_max,
      alphabet_size_limit,
      simple: true,
    }
  }
  let padded_count = brotli_next_power_of_two(count)
  if padded_count > alphabet_size_limit {
    raise fzip_err(BrotliInvalidHuffman, msg="encoder alphabet too large")
  }
  let bits = brotli_log2_floor_plus_one(padded_count) - 1
  for i in 0..<count {
    code_lengths[symbols[i]] = bits.to_byte()
  }
  let padded_symbols = FixedArray::make(padded_count, 0)
  for i in 0..<count {
    padded_symbols[i] = symbols[i]
  }
  let mut written = count
  let mut candidate = 0
  while written < padded_count {
    if !brotli_contains_symbol(symbols, count, candidate) {
      padded_symbols[written] = candidate
      code_lengths[candidate] = bits.to_byte()
      written += 1
    }
    candidate += 1
  }
  {
    symbols: padded_symbols,
    count: padded_count,
    code_lengths,
    alphabet_size_max,
    alphabet_size_limit,
    simple: false,
  }
}

///|
fn brotli_make_weighted_huffman_spec(
  symbols : FixedArray[Int],
  count : Int,
  frequencies : FixedArray[Int],
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
) -> BrotliHuffmanSpec raise FzipError {
  if count <= 4 || count > 16 {
    return brotli_make_huffman_spec(
      symbols, count, alphabet_size_max, alphabet_size_limit,
    )
  }
  let node_count = count * 2 - 1
  let weights = FixedArray::make(node_count, 0)
  let parents = FixedArray::make(node_count, -1)
  let min_symbols = FixedArray::make(node_count, 0)
  for i in 0..<count {
    let symbol = symbols[i]
    let frequency = frequencies[symbol]
    weights[i] = if frequency <= 0 { 1 } else { frequency }
    min_symbols[i] = symbol
  }
  for node in count..<node_count {
    let mut first = -1
    let mut second = -1
    for candidate in 0..<node {
      if parents[candidate] == -1 {
        if first == -1 ||
          weights[candidate] < weights[first] ||
          (
            weights[candidate] == weights[first] &&
            min_symbols[candidate] < min_symbols[first]
          ) {
          second = first
          first = candidate
        } else if second == -1 ||
          weights[candidate] < weights[second] ||
          (
            weights[candidate] == weights[second] &&
            min_symbols[candidate] < min_symbols[second]
          ) {
          second = candidate
        }
      }
    }
    if first < 0 || second < 0 {
      raise fzip_err(BrotliInvalidHuffman, msg="invalid weighted tree")
    }
    parents[first] = node
    parents[second] = node
    weights[node] = weights[first] + weights[second]
    min_symbols[node] = if min_symbols[first] < min_symbols[second] {
      min_symbols[first]
    } else {
      min_symbols[second]
    }
  }
  let code_lengths = FixedArray::make(alphabet_size_limit, b'\x00')
  for i in 0..<count {
    let mut depth = 0
    let mut node = i
    while parents[node] >= 0 {
      depth += 1
      node = parents[node]
    }
    if depth <= 0 || depth > brotli_huffman_max_code_length {
      return brotli_make_huffman_spec(
        symbols, count, alphabet_size_max, alphabet_size_limit,
      )
    }
    code_lengths[symbols[i]] = depth.to_byte()
  }
  {
    symbols,
    count,
    code_lengths,
    alphabet_size_max,
    alphabet_size_limit,
    simple: false,
  }
}

///|
fn brotli_find_fixed_prefix_payload(value : Int) -> (Int, Int) raise FzipError {
  for i in 0..<brotli_code_length_prefix_value.length() {
    if brotli_code_length_prefix_value[i] == value {
      let bits = brotli_code_length_prefix_length[i]
      return (bits, i & ((1 << bits) - 1))
    }
  }
  raise fzip_err(BrotliInvalidHuffman, msg="missing fixed prefix payload")
}

///|
fn brotli_huffman_payload_from_lengths(
  code_lengths : FixedArray[Byte],
  alphabet_size : Int,
  target : Int,
) -> BrotliCommandPrefix raise FzipError {
  if target < 0 || target >= alphabet_size {
    raise fzip_err(BrotliInvalidHuffman, msg="target outside alphabet")
  }
  let count = FixedArray::make(brotli_huffman_max_code_length + 1, 0)
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len > 0 {
      count[len] += 1
    }
  }
  let next_code = FixedArray::make(brotli_huffman_max_code_length + 1, 0)
  let mut code = 0
  for bits in 1..<=brotli_huffman_max_code_length {
    code = (code + count[bits - 1]) << 1
    next_code[bits] = code
  }
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len != 0 {
      let reversed = brotli_reverse_bits(next_code[len], len)
      next_code[len] += 1
      if symbol == target {
        return {
          symbol: target,
          insert_extra: reversed,
          copy_extra: 0,
          insert_extra_bits: len,
          copy_extra_bits: 0,
        }
      }
    }
  }
  raise fzip_err(BrotliInvalidHuffman, msg="target has no Huffman code")
}

///|
fn brotli_write_complex_huffman(
  writer : BrotliBitWriter,
  spec : BrotliHuffmanSpec,
) -> Unit raise FzipError {
  writer.write_bits(2, 0) // complex Huffman marker, skip 0
  let code_length_symbols = FixedArray::make(brotli_num_code_length_codes, 0)
  let mut code_length_count = brotli_add_unique_symbol(
    code_length_symbols, 0, 0,
  )
  for i in 0..<spec.alphabet_size_limit {
    let length = spec.code_lengths[i].to_int()
    if length != 0 {
      code_length_count = brotli_add_unique_symbol(
        code_length_symbols, code_length_count, length,
      )
    }
  }
  let padded_count = brotli_next_power_of_two(code_length_count)
  if padded_count > brotli_num_code_length_codes {
    raise fzip_err(BrotliInvalidHuffman, msg="code-length alphabet too large")
  }
  let bits = brotli_log2_floor_plus_one(padded_count) - 1
  let code_length_code_lengths = FixedArray::make(
    brotli_num_code_length_codes, b'\x00',
  )
  for i in 0..<code_length_count {
    code_length_code_lengths[code_length_symbols[i]] = bits.to_byte()
  }
  let mut written = code_length_count
  let mut candidate = 0
  while written < padded_count {
    if !brotli_contains_symbol(
        code_length_symbols, code_length_count, candidate,
      ) {
      code_length_symbols[written] = candidate
      code_length_code_lengths[candidate] = bits.to_byte()
      written += 1
    }
    candidate += 1
  }
  let mut space = 32
  for i in 0..<brotli_code_length_code_order.length() {
    let symbol = brotli_code_length_code_order[i]
    let value = code_length_code_lengths[symbol].to_int()
    let (payload_bits, payload) = brotli_find_fixed_prefix_payload(value)
    writer.write_bits(payload_bits, payload)
    if value != 0 {
      space -= 32 >> value
      if space == 0 {
        break
      }
    }
  }
  let mut last_nonzero = 0
  for i in 0..<spec.alphabet_size_limit {
    if spec.code_lengths[i] != b'\x00' {
      last_nonzero = i
    }
  }
  for symbol in 0..<=last_nonzero {
    let payload = brotli_huffman_payload_from_lengths(
      code_length_code_lengths,
      brotli_num_code_length_codes,
      spec.code_lengths[symbol].to_int(),
    )
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
}

///|
fn brotli_write_huffman_spec(
  writer : BrotliBitWriter,
  spec : BrotliHuffmanSpec,
) -> Unit raise FzipError {
  if spec.simple {
    let symbol_bits = brotli_log2_floor_plus_one(spec.alphabet_size_max - 1)
    brotli_write_simple_huffman(writer, spec.symbols, spec.count, symbol_bits)
  } else {
    brotli_write_complex_huffman(writer, spec)
  }
}

///|
fn brotli_simple_huffman_payload(
  symbols : FixedArray[Int],
  count : Int,
  target : Int,
) -> BrotliCommandPrefix raise FzipError {
  let table = brotli_build_simple_huffman_table(
    symbols,
    count - 1,
    brotli_huffman_table_bits,
  )
  for index in 0..<(1 << brotli_huffman_table_bits) {
    let entry = table[index]
    if entry.value == target {
      let mask = if entry.bits == 0 { 0 } else { (1 << entry.bits) - 1 }
      return {
        symbol: target,
        insert_extra: index & mask,
        copy_extra: 0,
        insert_extra_bits: entry.bits,
        copy_extra_bits: 0,
      }
    }
  }
  raise fzip_err(BrotliInvalidHuffman, msg="symbol missing from simple tree")
}

///|
fn brotli_huffman_spec_payload(
  spec : BrotliHuffmanSpec,
  target : Int,
) -> BrotliCommandPrefix raise FzipError {
  if spec.simple {
    brotli_simple_huffman_payload(spec.symbols, spec.count, target)
  } else {
    brotli_huffman_payload_from_lengths(
      spec.code_lengths,
      spec.alphabet_size_limit,
      target,
    )
  }
}

///|
fn brotli_collect_unique_literals(
  data : FixedArray[Byte],
  length : Int,
) -> BrotliLiteralSet? {
  let symbols = FixedArray::make(brotli_num_literal_symbols, 0)
  let mut count = 0
  for i in 0..<length {
    let value = data[i].to_int()
    let mut found = false
    for k in 0..<count {
      if symbols[k] == value {
        found = true
      }
    }
    if !found {
      if count == symbols.length() {
        return None
      }
      symbols[count] = value
      count += 1
    }
  }
  Some({ symbols, count })
}

///|
fn brotli_suffix_is_copy(
  data : FixedArray[Byte],
  insert_length : Int,
  distance : Int,
) -> Bool {
  for i in insert_length..<data.length() {
    if data[i] != data[i - distance] {
      return false
    }
  }
  true
}

///|
fn brotli_find_single_copy_match(
  data : FixedArray[Byte],
) -> BrotliSingleCopyMatch? {
  if data.length() < 3 {
    return None
  }
  let max_insert = if data.length() - 2 < 256 { data.length() - 2 } else { 256 }
  for insert_length in 1..<=max_insert {
    match brotli_collect_unique_literals(data, insert_length) {
      Some(literals) =>
        for distance in 1..<=insert_length {
          if brotli_suffix_is_copy(data, insert_length, distance) {
            return Some({
              insert_length,
              copy_length: data.length() - insert_length,
              distance,
              literal_symbols: literals.symbols,
              literal_symbol_count: literals.count,
            })
          }
        }
      None => ()
    }
  }
  None
}

///|
fn brotli_distance_prefix_for_distance(
  distance : Int,
) -> BrotliCommandPrefix raise FzipError {
  for
    code in brotli_num_distance_short_codes..<brotli_distance_alphabet_size(
      0, 0, 24,
    ) {
    let extra_bits = brotli_distance_extra_bits(code, 0, 0)
    let offset = brotli_distance_offset(code, 0, 0)
    let extra = distance - offset
    if extra >= 0 && extra < 1 << extra_bits {
      return {
        symbol: code,
        insert_extra: extra,
        copy_extra: 0,
        insert_extra_bits: extra_bits,
        copy_extra_bits: 0,
      }
    }
  }
  raise fzip_err(BrotliInvalidDistance, msg="no Brotli distance prefix")
}

///|
fn brotli_add_unique_symbol(
  symbols : FixedArray[Int],
  count : Int,
  symbol : Int,
) -> Int {
  for i in 0..<count {
    if symbols[i] == symbol {
      return count
    }
  }
  if count >= symbols.length() {
    return count + 1
  }
  symbols[count] = symbol
  count + 1
}

///|
fn brotli_find_command_prefix(
  insert_length : Int,
  copy_length : Int,
  explicit_distance : Bool,
) -> BrotliCommandPrefix raise FzipError {
  for symbol in 0..<brotli_num_command_symbols {
    let info = brotli_command_info(symbol)
    let distance_ok = if explicit_distance {
      info.distance_code < 0
    } else {
      info.distance_code >= 0
    }
    if distance_ok &&
      insert_length >= info.insert_len_offset &&
      copy_length >= info.copy_len_offset {
      let insert_extra = insert_length - info.insert_len_offset
      let copy_extra = copy_length - info.copy_len_offset
      if insert_extra < 1 << info.insert_len_extra_bits &&
        copy_extra < 1 << info.copy_len_extra_bits {
        return {
          symbol,
          insert_extra,
          copy_extra,
          insert_extra_bits: info.insert_len_extra_bits,
          copy_extra_bits: info.copy_len_extra_bits,
        }
      }
    }
  }
  raise fzip_err(BrotliInvalidMetablock, msg="no Brotli command prefix")
}

///|
fn brotli_make_encode_command(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  has_copy : Bool,
) -> BrotliEncodeCommand raise FzipError {
  let command = if has_copy {
    brotli_find_command_prefix(insert_length, copy_length, true)
  } else {
    brotli_find_command_prefix(insert_length, 2, false)
  }
  let distance_prefix = if has_copy {
    brotli_distance_prefix_for_distance(distance)
  } else {
    brotli_distance_prefix_for_distance(1)
  }
  { insert_start, insert_length, has_copy, command, distance_prefix }
}

///|
fn brotli_build_simple_lz77_commands(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
) -> Array[BrotliEncodeCommand]? {
  if data.length() < 8 || data.length() > 65536 {
    return None
  }
  if !brotli_has_compressible_match_density(data, hash_config) {
    return None
  }
  match brotli_collect_unique_literals(data, data.length()) {
    Some(_) => ()
    None => return None
  }
  let commands : Array[BrotliEncodeCommand] = []
  let previous = brotli_previous_match_positions(data, hash_config)
  let mut literal_start = 0
  let mut position = 0
  while position < data.length() {
    let (match_length, distance) = brotli_longest_previous_hash_match(
      data, previous, position, hash_config,
    )
    if match_length >= 4 {
      let insert_length = position - literal_start
      let command_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command(
        literal_start, insert_length, match_length, distance, true,
      )
      match command_result {
        Ok(command) => commands.push(command)
        Err(_) => return None
      }
      if commands.length() > 1200 {
        return None
      }
      position += match_length
      literal_start = position
    } else {
      position += 1
    }
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
  if commands.length() == 0 {
    return None
  }
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  let mut has_copy = false
  for i in 0..<commands.length() {
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      commands[i].command.symbol,
    )
    if command_count > brotli_num_command_symbols {
      return None
    }
    if commands[i].has_copy {
      has_copy = true
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        commands[i].distance_prefix.symbol,
      )
      if distance_count > distance_symbols.length() {
        return None
      }
    }
  }
  if !has_copy {
    return None
  }
  Some(commands)
}

///|
fn brotli_encode_single_copy_match(
  data : FixedArray[Byte],
  opts : BrotliOptions,
  match_ : BrotliSingleCopyMatch,
) -> FixedArray[Byte] raise FzipError {
  let command = brotli_find_command_prefix(
    match_.insert_length,
    match_.copy_length,
    true,
  )
  let distance = brotli_distance_prefix_for_distance(match_.distance)
  let literal_spec = brotli_make_huffman_spec(
    match_.literal_symbols,
    match_.literal_symbol_count,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let writer = BrotliBitWriter::new(128 + match_.insert_length * 4)
  brotli_encode_window_bits(writer, opts.window_bits)
  brotli_write_metablock_header(writer, data.length(), true, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 literal context mode
  writer.write_bits(1, 0) // literal context map has one tree
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, literal_spec)
  brotli_write_simple_one_symbol_huffman(writer, command.symbol, 10)
  brotli_write_simple_one_symbol_huffman(writer, distance.symbol, 6)
  writer.write_bits(command.insert_extra_bits, command.insert_extra)
  writer.write_bits(command.copy_extra_bits, command.copy_extra)
  for i in 0..<match_.insert_length {
    let payload = brotli_huffman_spec_payload(literal_spec, data[i].to_int())
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(distance.insert_extra_bits, distance.insert_extra)
  writer.finish()
}

///|
fn brotli_write_simple_lz77_metablock(
  writer : BrotliBitWriter,
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
  weighted : Bool,
) -> Unit raise FzipError {
  let literals = match brotli_collect_unique_literals(data, data.length()) {
    Some(literals) => literals
    None =>
      raise fzip_err(BrotliInvalidMetablock, msg="too many literal symbols")
  }
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let literal_frequencies = FixedArray::make(brotli_num_literal_symbols, 0)
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  for i in 0..<data.length() {
    literal_frequencies[data[i].to_int()] += 1
  }
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    command_frequencies[commands[i].command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      commands[i].command.symbol,
    )
    if commands[i].has_copy {
      distance_frequencies[commands[i].distance_prefix.symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        commands[i].distance_prefix.symbol,
      )
    }
  }
  let literal_spec = if weighted {
    brotli_make_weighted_huffman_spec(
      literals.symbols,
      literals.count,
      literal_frequencies,
      brotli_num_literal_symbols,
      brotli_num_literal_symbols,
    )
  } else {
    brotli_make_huffman_spec(
      literals.symbols,
      literals.count,
      brotli_num_literal_symbols,
      brotli_num_literal_symbols,
    )
  }
  let command_spec = if weighted {
    brotli_make_weighted_huffman_spec(
      command_symbols, command_count, command_frequencies, brotli_num_command_symbols,
      brotli_num_command_symbols,
    )
  } else {
    brotli_make_huffman_spec(
      command_symbols, command_count, brotli_num_command_symbols, brotli_num_command_symbols,
    )
  }
  let distance_spec = if weighted {
    brotli_make_weighted_huffman_spec(
      distance_symbols,
      distance_count,
      distance_frequencies,
      brotli_distance_alphabet_size(0, 0, 24),
      brotli_distance_alphabet_size(0, 0, 24),
    )
  } else {
    brotli_make_huffman_spec(
      distance_symbols,
      distance_count,
      brotli_distance_alphabet_size(0, 0, 24),
      brotli_distance_alphabet_size(0, 0, 24),
    )
  }
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 literal context mode
  writer.write_bits(1, 0) // literal context map has one tree
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, literal_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = brotli_huffman_spec_payload(
      command_spec,
      command.command.symbol,
    )
    writer.write_bits(
      command_payload.insert_extra_bits,
      command_payload.insert_extra,
    )
    writer.write_bits(
      command.command.insert_extra_bits,
      command.command.insert_extra,
    )
    writer.write_bits(
      command.command.copy_extra_bits,
      command.command.copy_extra,
    )
    for j in 0..<command.insert_length {
      let literal = data[command.insert_start + j].to_int()
      let literal_payload = brotli_huffman_spec_payload(literal_spec, literal)
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if command.has_copy {
      let distance_payload = brotli_huffman_spec_payload(
        distance_spec,
        command.distance_prefix.symbol,
      )
      writer.write_bits(
        distance_payload.insert_extra_bits,
        distance_payload.insert_extra,
      )
      writer.write_bits(
        command.distance_prefix.insert_extra_bits,
        command.distance_prefix.insert_extra,
      )
    }
  }
}

///|
fn brotli_encode_simple_lz77(
  data : FixedArray[Byte],
  opts : BrotliOptions,
  commands : Array[BrotliEncodeCommand],
) -> FixedArray[Byte] raise FzipError {
  let weighted = BrotliBitWriter::new(
    128 + data.length() * 4 + commands.length() * 8,
  )
  brotli_encode_window_bits(weighted, opts.window_bits)
  brotli_write_simple_lz77_metablock(weighted, data, commands, true, true)
  let fixed = BrotliBitWriter::new(
    128 + data.length() * 4 + commands.length() * 8,
  )
  brotli_encode_window_bits(fixed, opts.window_bits)
  brotli_write_simple_lz77_metablock(fixed, data, commands, true, false)
  if weighted.bit_pos < fixed.bit_pos {
    weighted.finish()
  } else {
    fixed.finish()
  }
}

///|
fn brotli_encode_uncompressed(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise FzipError {
  let writer = BrotliBitWriter::new(brotli_encoded_capacity(data.length()))
  brotli_encode_window_bits(writer, opts.window_bits)
  let mut offset = 0
  while offset < data.length() {
    let remaining = data.length() - offset
    let length = if remaining > brotli_max_metablock_bytes {
      brotli_max_metablock_bytes
    } else {
      remaining
    }
    brotli_write_uncompressed_metablock(writer, data, offset, length)
    offset += length
  }
  brotli_write_final_empty_metablock(writer)
  writer.finish()
}

///|
fn brotli_try_compressed_chunk(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
) -> BrotliBitWriter? raise FzipError {
  match brotli_build_simple_lz77_commands(data, hash_config) {
    Some(commands) => {
      let fixed = BrotliBitWriter::new(
        128 + data.length() * 4 + commands.length() * 8,
      )
      brotli_write_simple_lz77_metablock(fixed, data, commands, false, false)
      let weighted = BrotliBitWriter::new(
        128 + data.length() * 4 + commands.length() * 8,
      )
      brotli_write_simple_lz77_metablock(weighted, data, commands, false, true)
      if weighted.bit_pos < fixed.bit_pos {
        Some(weighted)
      } else {
        Some(fixed)
      }
    }
    None => None
  }
}

///|
fn brotli_encode_chunked_standard(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise FzipError {
  let chunk_size = 65535
  let chunk_count = (data.length() + chunk_size - 1) / chunk_size
  let writer = BrotliBitWriter::new(data.length() + 8 + chunk_count * 16)
  brotli_encode_window_bits(writer, opts.window_bits)
  let hash_config = brotli_hash_config_for_quality(opts.quality)
  let mut offset = 0
  while offset < data.length() {
    let remaining = data.length() - offset
    let length = if remaining > chunk_size { chunk_size } else { remaining }
    let chunk = slc(data, offset, e=offset + length)
    match brotli_try_compressed_chunk(chunk, hash_config) {
      Some(compressed) =>
        if shft(compressed.bit_pos) < length + 16 {
          writer.write_from_bits(compressed.buf, compressed.bit_pos)
        } else {
          brotli_write_uncompressed_metablock(writer, data, offset, length)
        }
      None => brotli_write_uncompressed_metablock(writer, data, offset, length)
    }
    offset += length
  }
  brotli_write_final_empty_metablock(writer)
  writer.finish()
}

///|
fn brotli_encode_standard(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise FzipError {
  if data.length() > 65536 {
    return brotli_encode_chunked_standard(data, opts)
  }
  let hash_config = brotli_hash_config_for_quality(opts.quality)
  if data.length() <= brotli_max_metablock_bytes {
    match brotli_find_single_copy_match(data) {
      Some(match_) => return brotli_encode_single_copy_match(data, opts, match_)
      None => ()
    }
    match brotli_build_simple_lz77_commands(data, hash_config) {
      Some(commands) => return brotli_encode_simple_lz77(data, opts, commands)
      None => ()
    }
  }
  brotli_encode_uncompressed(data, opts)
}

///|
fn brotli_validate_options(opts : BrotliOptions) -> Unit raise FzipError {
  if opts.quality < 0 || opts.quality > 11 {
    raise fzip_err(InvalidZipData, msg="Brotli quality must be 0..=11")
  }
  brotli_validate_window_bits(opts.window_bits)
}

///|
/// Compress bytes into a Brotli stream.
///
/// The current encoder backend supports Brotli quality levels 0 through 11. It
/// emits valid uncompressed meta-blocks with a final empty terminator, which
/// prioritizes interoperability and decoder round-trip correctness while the
/// higher-ratio search and entropy-coding work is built.
pub fn brotli_sync(
  data : FixedArray[Byte],
  opts? : BrotliOptions = BrotliOptions::default(),
) -> FixedArray[Byte] raise FzipError {
  brotli_validate_options(opts)
  match opts.quality {
    0 | 1 => brotli_encode_uncompressed(data, opts)
    2..=11 => brotli_encode_standard(data, opts)
    _ => raise fzip_err(InvalidZipData, msg="Brotli quality must be 0..=11")
  }
}

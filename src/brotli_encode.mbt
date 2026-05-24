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
fn brotli_collect_unique_literals(
  data : FixedArray[Byte],
  length : Int,
) -> BrotliLiteralSet? {
  let symbols = FixedArray::make(4, 0)
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
      if count == 4 {
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
fn brotli_longest_previous_match(
  data : FixedArray[Byte],
  position : Int,
) -> (Int, Int) {
  let mut best_length = 0
  let mut best_distance = 0
  let max_distance = if position < 256 { position } else { 256 }
  for distance in 1..<=max_distance {
    let mut length = 0
    while length < 6 &&
          position + length < data.length() &&
          data[position + length] == data[position + length - distance] {
      length += 1
    }
    if length > best_length {
      best_length = length
      best_distance = distance
    }
  }
  (best_length, best_distance)
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
) -> Array[BrotliEncodeCommand]? raise FzipError {
  if data.length() < 8 || data.length() > 65536 {
    return None
  }
  match brotli_collect_unique_literals(data, data.length()) {
    Some(_) => ()
    None => return None
  }
  let commands : Array[BrotliEncodeCommand] = []
  let mut literal_start = 0
  let mut position = 0
  while position < data.length() {
    let (match_length, distance) = brotli_longest_previous_match(data, position)
    if match_length >= 4 {
      let insert_length = position - literal_start
      commands.push(
        brotli_make_encode_command(
          literal_start, insert_length, match_length, distance, true,
        ),
      )
      position += match_length
      literal_start = position
    } else {
      position += 1
    }
  }
  if literal_start < data.length() {
    commands.push(
      brotli_make_encode_command(
        literal_start,
        data.length() - literal_start,
        0,
        0,
        false,
      ),
    )
  }
  if commands.length() == 0 {
    return None
  }
  let command_symbols = FixedArray::make(4, 0)
  let distance_symbols = FixedArray::make(4, 0)
  let mut command_count = 0
  let mut distance_count = 0
  let mut has_copy = false
  for i in 0..<commands.length() {
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      commands[i].command.symbol,
    )
    if command_count > 4 {
      return None
    }
    if commands[i].has_copy {
      has_copy = true
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        commands[i].distance_prefix.symbol,
      )
      if distance_count > 4 {
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
  brotli_write_simple_huffman(
    writer,
    match_.literal_symbols,
    match_.literal_symbol_count,
    8,
  )
  brotli_write_simple_one_symbol_huffman(writer, command.symbol, 10)
  brotli_write_simple_one_symbol_huffman(writer, distance.symbol, 6)
  writer.write_bits(command.insert_extra_bits, command.insert_extra)
  writer.write_bits(command.copy_extra_bits, command.copy_extra)
  for i in 0..<match_.insert_length {
    let payload = brotli_simple_huffman_payload(
      match_.literal_symbols,
      match_.literal_symbol_count,
      data[i].to_int(),
    )
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(distance.insert_extra_bits, distance.insert_extra)
  writer.finish()
}

///|
fn brotli_encode_simple_lz77(
  data : FixedArray[Byte],
  opts : BrotliOptions,
  commands : Array[BrotliEncodeCommand],
) -> FixedArray[Byte] raise FzipError {
  let literals = match brotli_collect_unique_literals(data, data.length()) {
    Some(literals) => literals
    None =>
      raise fzip_err(BrotliInvalidMetablock, msg="too many literal symbols")
  }
  let command_symbols = FixedArray::make(4, 0)
  let distance_symbols = FixedArray::make(4, 0)
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      commands[i].command.symbol,
    )
    if commands[i].has_copy {
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        commands[i].distance_prefix.symbol,
      )
    }
  }
  let writer = BrotliBitWriter::new(
    128 + data.length() * 4 + commands.length() * 8,
  )
  brotli_encode_window_bits(writer, opts.window_bits)
  brotli_write_metablock_header(writer, data.length(), true, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 literal context mode
  writer.write_bits(1, 0) // literal context map has one tree
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_simple_huffman(writer, literals.symbols, literals.count, 8)
  brotli_write_simple_huffman(writer, command_symbols, command_count, 10)
  brotli_write_simple_huffman(writer, distance_symbols, distance_count, 6)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = brotli_simple_huffman_payload(
      command_symbols,
      command_count,
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
      let literal_payload = brotli_simple_huffman_payload(
        literals.symbols,
        literals.count,
        literal,
      )
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if command.has_copy {
      let distance_payload = brotli_simple_huffman_payload(
        distance_symbols,
        distance_count,
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
  writer.finish()
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
fn brotli_encode_standard(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise FzipError {
  if data.length() <= brotli_max_metablock_bytes {
    match brotli_find_single_copy_match(data) {
      Some(match_) => return brotli_encode_single_copy_match(data, opts, match_)
      None => ()
    }
    match brotli_build_simple_lz77_commands(data) {
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

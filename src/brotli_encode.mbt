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
  copy_length : Int
  output_length : Int
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
  let bit_pos = self.bit_pos
  let bit_index = bit_pos & 7
  let space_in_byte = 8 - bit_index
  // Fast path: fits in the current byte.
  if count <= space_in_byte {
    let byte_index = bit_pos >> 3
    self.buf[byte_index] = (self.buf[byte_index].to_int() |
    ((value & ((1 << count) - 1)) << bit_index)).to_byte()
    self.bit_pos = bit_pos + count
    return
  }
  // Slow path: bits span multiple bytes.
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
  let mut pos = 0
  // Fast path: when the destination is byte-aligned, blit whole bytes
  // directly into the output buffer; only the trailing < 8 bits fall
  // back to per-bit writes.
  if (self.bit_pos & 7) == 0 && bit_count >= 8 {
    let full_bytes = bit_count >> 3
    let byte_offset = self.bit_pos >> 3
    data.blit_to(self.buf, len=full_bytes, src_offset=0, dst_offset=byte_offset)
    self.bit_pos += full_bytes * 8
    pos = full_bytes * 8
  }
  // Push remaining whole bytes at unaligned destinations through the
  // bit-spanning write_bits slow path eight bits at a time to skip the
  // per-bit dispatch.
  while pos + 8 <= bit_count {
    let bit_offset = pos & 7
    let byte_index = pos >> 3
    let low = data[byte_index].to_int() >> bit_offset
    let high = if bit_offset != 0 {
      data[byte_index + 1].to_int() << (8 - bit_offset)
    } else {
      0
    }
    self.write_bits(8, (low | high) & 0xff)
    pos += 8
  }
  while pos < bit_count {
    let bit = (data[pos / 8].to_int() >> (pos & 7)) & 1
    self.write_bits(1, bit)
    pos += 1
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
fn brotli_write_var_len_uint8(writer : BrotliBitWriter, value : Int) -> Unit {
  if value == 0 {
    writer.write_bits(1, 0)
  } else if value == 1 {
    writer.write_bits(1, 1)
    writer.write_bits(3, 0)
  } else {
    let mut bits = 1
    while bits < 8 && value >= 1 << (bits + 1) {
      bits += 1
    }
    writer.write_bits(1, 1)
    writer.write_bits(3, bits)
    writer.write_bits(bits, value - (1 << bits))
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
  if count <= 4 {
    return brotli_make_huffman_spec(
      symbols, count, alphabet_size_max, alphabet_size_limit,
    )
  }
  if count > 16 {
    let (tree_lengths, _) = h_tree(frequencies, brotli_huffman_max_code_length)
    if tree_lengths.length() == 0 {
      return brotli_make_huffman_spec(
        symbols, count, alphabet_size_max, alphabet_size_limit,
      )
    }
    let code_lengths = FixedArray::make(alphabet_size_limit, b'\x00')
    for i in 0..<tree_lengths.length() {
      code_lengths[i] = tree_lengths[i]
    }
    return {
      symbols,
      count,
      code_lengths,
      alphabet_size_max,
      alphabet_size_limit,
      simple: false,
    }
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
fn brotli_complex_huffman_last_nonzero(spec : BrotliHuffmanSpec) -> Int {
  let mut last_nonzero = 0
  for i in 0..<spec.alphabet_size_limit {
    if spec.code_lengths[i] != b'\x00' {
      last_nonzero = i
    }
  }
  last_nonzero
}

///|
fn brotli_add_complex_code_length_symbols(
  spec : BrotliHuffmanSpec,
  code_length_symbols : FixedArray[Int],
  count : Int,
  last_nonzero : Int,
) -> Int {
  let mut count = count
  let mut symbol = 0
  while symbol <= last_nonzero {
    let length = spec.code_lengths[symbol].to_int()
    if length == 0 {
      let mut run = 1
      while symbol + run <= last_nonzero &&
            spec.code_lengths[symbol + run] == b'\x00' {
        run += 1
      }
      if run >= 3 {
        count = brotli_add_unique_symbol(
          code_length_symbols, count, brotli_repeat_zero_code_length,
        )
        let remainder = if run > 10 { 1 } else { run % 10 }
        if remainder == 1 || remainder == 2 {
          count = brotli_add_unique_symbol(code_length_symbols, count, 0)
        }
      } else {
        count = brotli_add_unique_symbol(code_length_symbols, count, 0)
      }
      symbol += run
    } else {
      let mut run = 1
      while symbol + run <= last_nonzero &&
            spec.code_lengths[symbol + run].to_int() == length {
        run += 1
      }
      count = brotli_add_unique_symbol(code_length_symbols, count, length)
      if run >= 4 {
        count = brotli_add_unique_symbol(
          code_length_symbols, count, brotli_repeat_previous_code_length,
        )
      }
      symbol += run
    }
  }
  count
}

///|
fn brotli_write_complex_code_lengths(
  writer : BrotliBitWriter,
  spec : BrotliHuffmanSpec,
  code_length_code_lengths : FixedArray[Byte],
  last_nonzero : Int,
) -> Unit raise FzipError {
  let mut symbol = 0
  while symbol <= last_nonzero {
    let length = spec.code_lengths[symbol].to_int()
    if length == 0 {
      let mut run = 1
      while symbol + run <= last_nonzero &&
            spec.code_lengths[symbol + run] == b'\x00' {
        run += 1
      }
      let run_length = run
      while run > 10 {
        let payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, brotli_num_code_length_codes, brotli_repeat_zero_code_length,
        )
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        writer.write_bits(3, 7)
        run -= 10
        let zero_payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, brotli_num_code_length_codes, 0,
        )
        writer.write_bits(
          zero_payload.insert_extra_bits,
          zero_payload.insert_extra,
        )
        run -= 1
      }
      if run >= 3 {
        let payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, brotli_num_code_length_codes, brotli_repeat_zero_code_length,
        )
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        writer.write_bits(3, run - 3)
        run = 0
      }
      while run > 0 {
        let payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, brotli_num_code_length_codes, 0,
        )
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        run -= 1
      }
      symbol += run_length
    } else {
      let mut run = 1
      while symbol + run <= last_nonzero &&
            spec.code_lengths[symbol + run].to_int() == length {
        run += 1
      }
      let run_length = run
      let payload = brotli_huffman_payload_from_lengths(
        code_length_code_lengths, brotli_num_code_length_codes, length,
      )
      writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
      run -= 1
      while run > 6 {
        let repeat_payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, brotli_num_code_length_codes, brotli_repeat_previous_code_length,
        )
        writer.write_bits(
          repeat_payload.insert_extra_bits,
          repeat_payload.insert_extra,
        )
        writer.write_bits(2, 3)
        run -= 6
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        run -= 1
      }
      if run >= 3 {
        let repeat_payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, brotli_num_code_length_codes, brotli_repeat_previous_code_length,
        )
        writer.write_bits(
          repeat_payload.insert_extra_bits,
          repeat_payload.insert_extra,
        )
        writer.write_bits(2, run - 3)
        run = 0
      }
      while run > 0 {
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        run -= 1
      }
      symbol += run_length
    }
  }
}

///|
fn brotli_write_complex_huffman(
  writer : BrotliBitWriter,
  spec : BrotliHuffmanSpec,
) -> Unit raise FzipError {
  writer.write_bits(2, 0) // complex Huffman marker, skip 0
  let last_nonzero = brotli_complex_huffman_last_nonzero(spec)
  let code_length_symbols = FixedArray::make(brotli_num_code_length_codes, 0)
  let mut code_length_count = brotli_add_unique_symbol(
    code_length_symbols, 0, 0,
  )
  code_length_count = brotli_add_complex_code_length_symbols(
    spec, code_length_symbols, code_length_count, last_nonzero,
  )
  let code_length_code_lengths = FixedArray::make(
    brotli_num_code_length_codes, b'\x00',
  )
  let padded_count = brotli_next_power_of_two(code_length_count)
  if padded_count <= brotli_num_code_length_codes {
    let bits = brotli_log2_floor_plus_one(padded_count) - 1
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
  } else {
    let frequencies = FixedArray::make(brotli_num_code_length_codes, 0)
    for i in 0..<code_length_count {
      frequencies[code_length_symbols[i]] += 1
    }
    let (tree_lengths, _) = h_tree(frequencies, 5)
    if tree_lengths.length() == 0 {
      raise fzip_err(BrotliInvalidHuffman, msg="code-length alphabet too large")
    }
    for i in 0..<tree_lengths.length() {
      code_length_code_lengths[i] = tree_lengths[i]
    }
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
  brotli_write_complex_code_lengths(
    writer, spec, code_length_code_lengths, last_nonzero,
  )
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
fn brotli_huffman_payload_table(
  spec : BrotliHuffmanSpec,
) -> FixedArray[BrotliCommandPrefix] raise FzipError {
  let empty_payload = {
    symbol: -1,
    insert_extra: 0,
    copy_extra: 0,
    insert_extra_bits: 0,
    copy_extra_bits: 0,
  }
  let payloads = FixedArray::make(spec.alphabet_size_limit, empty_payload)
  if spec.simple {
    for i in 0..<spec.count {
      let symbol = spec.symbols[i]
      payloads[symbol] = brotli_simple_huffman_payload(
        spec.symbols,
        spec.count,
        symbol,
      )
    }
    return payloads
  }
  let count = FixedArray::make(brotli_huffman_max_code_length + 1, 0)
  for symbol in 0..<spec.alphabet_size_limit {
    let len = spec.code_lengths[symbol].to_int()
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
  for symbol in 0..<spec.alphabet_size_limit {
    let len = spec.code_lengths[symbol].to_int()
    if len != 0 {
      let reversed = brotli_reverse_bits(next_code[len], len)
      next_code[len] += 1
      payloads[symbol] = {
        symbol,
        insert_extra: reversed,
        copy_extra: 0,
        insert_extra_bits: len,
        copy_extra_bits: 0,
      }
    }
  }
  payloads
}

///|
fn brotli_collect_unique_literals(
  data : FixedArray[Byte],
  length : Int,
) -> BrotliLiteralSet? {
  let symbols = FixedArray::make(brotli_num_literal_symbols, 0)
  let seen = FixedArray::make(brotli_num_literal_symbols, false)
  let mut count = 0
  for i in 0..<length {
    let value = data[i].to_int()
    if !seen[value] {
      seen[value] = true
      symbols[count] = value
      count += 1
    }
  }
  Some({ symbols, count })
}

///|
fn brotli_collect_unique_literals_range(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> BrotliLiteralSet? {
  let symbols = FixedArray::make(brotli_num_literal_symbols, 0)
  let seen = FixedArray::make(brotli_num_literal_symbols, false)
  let mut count = 0
  for i in start..<end {
    let value = data[i].to_int()
    if !seen[value] {
      seen[value] = true
      symbols[count] = value
      count += 1
    }
  }
  if count == 0 {
    None
  } else {
    Some({ symbols, count })
  }
}

///|
fn brotli_literal_frequencies_range(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> FixedArray[Int] {
  let frequencies = FixedArray::make(brotli_num_literal_symbols, 0)
  for i in start..<end {
    frequencies[data[i].to_int()] += 1
  }
  frequencies
}

///|
fn brotli_split_literal_saving_bits_with_single(
  data : FixedArray[Byte],
  split : Int,
  single_bits : Int,
) -> Int {
  if split <= 0 || split >= data.length() {
    return 0
  }
  let first_frequencies = brotli_literal_frequencies_range(data, 0, split)
  let second_frequencies = brotli_literal_frequencies_range(
    data,
    split,
    data.length(),
  )
  let (first_lengths, _) = h_tree(
    first_frequencies, brotli_huffman_max_code_length,
  )
  let (second_lengths, _) = h_tree(
    second_frequencies, brotli_huffman_max_code_length,
  )
  if first_lengths.length() == 0 || second_lengths.length() == 0 {
    return 0
  }
  let split_bits = clen(first_frequencies, first_lengths) +
    clen(second_frequencies, second_lengths)
  single_bits - split_bits
}

///|
fn brotli_best_split_literal_point(data : FixedArray[Byte]) -> Int {
  let all_frequencies = brotli_literal_frequencies_range(data, 0, data.length())
  let (all_lengths, _) = h_tree(all_frequencies, brotli_huffman_max_code_length)
  if all_lengths.length() == 0 {
    return 0
  }
  let single_bits = clen(all_frequencies, all_lengths)
  let split_points = [
    data.length() / 4,
    data.length() / 2,
    data.length() * 3 / 4,
  ]
  let mut best_split = 0
  let mut best_saving = 384
  for i in 0..<split_points.length() {
    let saving = brotli_split_literal_saving_bits_with_single(
      data,
      split_points[i],
      single_bits,
    )
    if saving > best_saving {
      best_saving = saving
      best_split = split_points[i]
    }
  }
  best_split
}

///|

///|
fn brotli_command_literal_count(commands : Array[BrotliEncodeCommand]) -> Int {
  let mut count = 0
  for i in 0..<commands.length() {
    count += commands[i].insert_length
  }
  count
}

///|
fn brotli_collect_command_literals_range(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  start : Int,
  end : Int,
) -> BrotliLiteralSet? {
  let symbols = FixedArray::make(brotli_num_literal_symbols, 0)
  let seen = FixedArray::make(brotli_num_literal_symbols, false)
  let mut count = 0
  let mut literal_index = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      if literal_index >= start && literal_index < end {
        let literal = data[command.insert_start + j].to_int()
        if !seen[literal] {
          seen[literal] = true
          symbols[count] = literal
          count += 1
        }
      }
      literal_index += 1
    }
  }
  if count == 0 {
    None
  } else {
    Some({ symbols, count })
  }
}

///|
fn brotli_command_literal_frequencies_range(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  start : Int,
  end : Int,
) -> FixedArray[Int] {
  let frequencies = FixedArray::make(brotli_num_literal_symbols, 0)
  let mut literal_index = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      if literal_index >= start && literal_index < end {
        frequencies[data[command.insert_start + j].to_int()] += 1
      }
      literal_index += 1
    }
  }
  frequencies
}

///|
fn brotli_command_literal_utf8_context_tree(
  data : FixedArray[Byte],
  position : Int,
) -> Int raise FzipError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    0
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else {
    0
  }
  brotli_utf8_context_tree(
    brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_command_literal_utf8_context_tree4(
  data : FixedArray[Byte],
  position : Int,
) -> Int raise FzipError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    0
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else {
    0
  }
  brotli_utf8_context_tree4(
    brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_command_literal_utf8_context_tree8(
  data : FixedArray[Byte],
  position : Int,
) -> Int raise FzipError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    0
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else {
    0
  }
  brotli_utf8_context_tree8(
    brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_command_literal_utf8_context_tree16(
  data : FixedArray[Byte],
  position : Int,
) -> Int raise FzipError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    0
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else {
    0
  }
  brotli_utf8_context_tree16(
    brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_collect_command_literals_and_frequencies_by_utf8_context16(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise FzipError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(16, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<16 {
    symbols.push(FixedArray::make(brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree16(data, position)
      let literal = data[position].to_int()
      if !seen[tree][literal] {
        seen[tree][literal] = true
        symbols[tree][counts[tree]] = literal
        counts[tree] += 1
      }
      frequencies[tree][literal] += 1
    }
  }
  let literal_sets : Array[BrotliLiteralSet] = []
  for tree in 0..<16 {
    if counts[tree] == 0 {
      return None
    }
    literal_sets.push({ symbols: symbols[tree], count: counts[tree] })
  }
  Some((literal_sets, frequencies))
}

///|
fn brotli_collect_command_literals_and_frequencies_by_utf8_context8(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise FzipError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(8, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<8 {
    symbols.push(FixedArray::make(brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree8(data, position)
      let literal = data[position].to_int()
      if !seen[tree][literal] {
        seen[tree][literal] = true
        symbols[tree][counts[tree]] = literal
        counts[tree] += 1
      }
      frequencies[tree][literal] += 1
    }
  }
  let literal_sets : Array[BrotliLiteralSet] = []
  for tree in 0..<8 {
    if counts[tree] == 0 {
      return None
    }
    literal_sets.push({ symbols: symbols[tree], count: counts[tree] })
  }
  Some((literal_sets, frequencies))
}

///|
fn brotli_collect_command_literals_and_frequencies_by_utf8_context4(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise FzipError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(4, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<4 {
    symbols.push(FixedArray::make(brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree4(data, position)
      let literal = data[position].to_int()
      if !seen[tree][literal] {
        seen[tree][literal] = true
        symbols[tree][counts[tree]] = literal
        counts[tree] += 1
      }
      frequencies[tree][literal] += 1
    }
  }
  let literal_sets : Array[BrotliLiteralSet] = []
  for tree in 0..<4 {
    if counts[tree] == 0 {
      return None
    }
    literal_sets.push({ symbols: symbols[tree], count: counts[tree] })
  }
  Some((literal_sets, frequencies))
}

///|
fn brotli_collect_command_literals_and_frequencies_by_utf8_context(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise FzipError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(2, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<2 {
    symbols.push(FixedArray::make(brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree(data, position)
      let literal = data[position].to_int()
      if !seen[tree][literal] {
        seen[tree][literal] = true
        symbols[tree][counts[tree]] = literal
        counts[tree] += 1
      }
      frequencies[tree][literal] += 1
    }
  }
  let literal_sets : Array[BrotliLiteralSet] = []
  for tree in 0..<2 {
    if counts[tree] == 0 {
      return None
    }
    literal_sets.push({ symbols: symbols[tree], count: counts[tree] })
  }
  Some((literal_sets, frequencies))
}

///|
fn brotli_two_tree_saving(
  first_frequencies : FixedArray[Int],
  second_frequencies : FixedArray[Int],
  single_bits : Int,
) -> Int {
  let (first_lengths, _) = h_tree(
    first_frequencies, brotli_huffman_max_code_length,
  )
  let (second_lengths, _) = h_tree(
    second_frequencies, brotli_huffman_max_code_length,
  )
  if first_lengths.length() == 0 || second_lengths.length() == 0 {
    return 0
  }
  single_bits -
  (
    clen(first_frequencies, first_lengths) +
    clen(second_frequencies, second_lengths)
  )
}

///|
/// Snapshot literal frequencies at each `split_points` boundary in one
/// command-stream pass. Returns a flat `(split_count + 1) × alphabet` table:
/// row `i` is the cumulative frequency up to `split_points[i]`, and the last
/// row is the total frequency over `0 .. literal_count`. Assumes
/// `split_points` is sorted ascending with values in `(0, literal_count)`.
fn brotli_split_literal_freq_snapshots(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  split_points : FixedArray[Int],
  literal_count : Int,
) -> FixedArray[Int] {
  let alphabet = brotli_num_literal_symbols
  let rows = split_points.length() + 1
  let snapshots = FixedArray::make(rows * alphabet, 0)
  let frequencies = FixedArray::make(alphabet, 0)
  let mut literal_index = 0
  let mut next_split_idx = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    let start = command.insert_start
    let insert_length = command.insert_length
    for j in 0..<insert_length {
      while next_split_idx < split_points.length() &&
            literal_index == split_points[next_split_idx] {
        let row_offset = next_split_idx * alphabet
        for k in 0..<alphabet {
          snapshots[row_offset + k] = frequencies[k]
        }
        next_split_idx += 1
      }
      frequencies[data[start + j].to_int()] += 1
      literal_index += 1
    }
  }
  while next_split_idx < split_points.length() &&
        literal_index >= split_points[next_split_idx] {
    let row_offset = next_split_idx * alphabet
    for k in 0..<alphabet {
      snapshots[row_offset + k] = frequencies[k]
    }
    next_split_idx += 1
  }
  let total_offset = split_points.length() * alphabet
  for k in 0..<alphabet {
    snapshots[total_offset + k] = frequencies[k]
  }
  ignore(literal_count)
  snapshots
}

///|
fn brotli_best_command_literal_split_point(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
) -> Int {
  let literal_count = brotli_command_literal_count(commands)
  if literal_count < 2048 {
    return 0
  }
  // Try three evenly spaced split points (1/4, 1/2, 3/4); broader candidate
  // sets (eighths) did not pay for themselves on Silesia.
  let split_points : FixedArray[Int] = [
    literal_count / 4,
    literal_count / 2,
    literal_count * 3 / 4,
  ]
  // Build cumulative frequency snapshots at each split boundary in a single
  // pass instead of rescanning literals per candidate.
  let snapshots = brotli_split_literal_freq_snapshots(
    data, commands, split_points, literal_count,
  )
  let alphabet = brotli_num_literal_symbols
  let total_offset = split_points.length() * alphabet
  let all_frequencies = FixedArray::make(alphabet, 0)
  for k in 0..<alphabet {
    all_frequencies[k] = snapshots[total_offset + k]
  }
  let (all_lengths, _) = h_tree(all_frequencies, brotli_huffman_max_code_length)
  if all_lengths.length() == 0 {
    return 0
  }
  let single_bits = clen(all_frequencies, all_lengths)
  let mut best_split = 0
  let mut best_saving = 384
  let first_frequencies = FixedArray::make(alphabet, 0)
  let second_frequencies = FixedArray::make(alphabet, 0)
  for i in 0..<split_points.length() {
    let split = split_points[i]
    if split <= 0 || split >= literal_count {
      continue
    }
    let row_offset = i * alphabet
    for k in 0..<alphabet {
      first_frequencies[k] = snapshots[row_offset + k]
      second_frequencies[k] = all_frequencies[k] - first_frequencies[k]
    }
    let saving = brotli_two_tree_saving(
      first_frequencies, second_frequencies, single_bits,
    )
    if saving > best_saving {
      best_saving = saving
      best_split = split
    }
  }
  best_split
}

///|
fn brotli_commands_copy_bytes(commands : Array[BrotliEncodeCommand]) -> Int {
  let mut total = 0
  for i in 0..<commands.length() {
    if commands[i].has_copy {
      ignore(commands[i].copy_length)
      total += commands[i].output_length
    }
  }
  total
}

///|
fn brotli_command_uses_distance_symbol(command : BrotliEncodeCommand) -> Bool {
  // Equivalent to: command.has_copy &&
  //   brotli_command_info(command.command.symbol).distance_code < 0
  // distance_code is < 0 iff cell_index (symbol >> 6) >= 2, i.e. symbol >= 128.
  // Avoids the per-command brotli_prefix_offset linear sums when only the
  // distance-vs-implicit flag is needed.
  command.has_copy && command.command.symbol >= 128
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
fn brotli_distance_prefix_for_code(
  distance_code : Int,
) -> BrotliCommandPrefix raise FzipError {
  if distance_code < 0 {
    raise fzip_err(BrotliInvalidDistance, msg="negative Brotli distance code")
  }
  if distance_code < brotli_num_distance_short_codes {
    return {
      symbol: distance_code,
      insert_extra: 0,
      copy_extra: 0,
      insert_extra_bits: 0,
      copy_extra_bits: 0,
    }
  }
  brotli_distance_prefix_for_distance(
    distance_code - brotli_num_distance_short_codes + 1,
  )
}

///|
fn brotli_compute_distance_code(
  distance : Int,
  max_distance : Int,
  distance_cache : FixedArray[Int],
) -> Int {
  if distance <= max_distance {
    let distance_plus_3 = distance + 3
    let offset0 = distance_plus_3 - distance_cache[0]
    let offset1 = distance_plus_3 - distance_cache[1]
    if distance == distance_cache[0] {
      return 0
    } else if distance == distance_cache[1] {
      return 1
    } else if offset0 >= 0 && offset0 < 7 {
      return (0x9750468 >> (4 * offset0)) & 0xf
    } else if offset1 >= 0 && offset1 < 7 {
      return (0xfdb1ace >> (4 * offset1)) & 0xf
    } else if distance == distance_cache[2] {
      return 2
    } else if distance == distance_cache[3] {
      return 3
    }
  }
  distance + brotli_num_distance_short_codes - 1
}

///|
fn brotli_update_distance_cache(
  distance_cache : FixedArray[Int],
  distance : Int,
  distance_code : Int,
) -> Unit {
  if distance_code > 0 {
    distance_cache[3] = distance_cache[2]
    distance_cache[2] = distance_cache[1]
    distance_cache[1] = distance_cache[0]
    distance_cache[0] = distance
  }
}

///|
fn brotli_copy_distance_cache(
  distance_cache : FixedArray[Int],
) -> FixedArray[Int] {
  [distance_cache[0], distance_cache[1], distance_cache[2], distance_cache[3]]
}

///|
fn brotli_commit_distance_cache(
  target : FixedArray[Int],
  source : FixedArray[Int],
) -> Unit {
  target[0] = source[0]
  target[1] = source[1]
  target[2] = source[2]
  target[3] = source[3]
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
fn brotli_find_insert_only_command_prefix(
  insert_length : Int,
) -> BrotliCommandPrefix raise FzipError {
  for symbol in 0..<brotli_num_command_symbols {
    let info = brotli_command_info(symbol)
    if insert_length >= info.insert_len_offset {
      let insert_extra = insert_length - info.insert_len_offset
      if insert_extra < 1 << info.insert_len_extra_bits &&
        2 >= info.copy_len_offset &&
        2 - info.copy_len_offset < 1 << info.copy_len_extra_bits {
        return {
          symbol,
          insert_extra,
          copy_extra: 2 - info.copy_len_offset,
          insert_extra_bits: info.insert_len_extra_bits,
          copy_extra_bits: info.copy_len_extra_bits,
        }
      }
    }
  }
  raise fzip_err(
    BrotliInvalidMetablock,
    msg="no Brotli insert-only command prefix",
  )
}

///|
fn brotli_make_encode_command_with_distance_mode(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  has_copy : Bool,
  explicit_distance : Bool,
) -> BrotliEncodeCommand raise FzipError {
  let command = if has_copy {
    brotli_find_command_prefix(insert_length, copy_length, explicit_distance)
  } else {
    brotli_find_insert_only_command_prefix(insert_length)
  }
  let distance_prefix = if has_copy && explicit_distance {
    brotli_distance_prefix_for_distance(distance)
  } else {
    brotli_distance_prefix_for_distance(1)
  }
  {
    insert_start,
    insert_length,
    copy_length,
    output_length: copy_length,
    has_copy,
    command,
    distance_prefix,
  }
}

///|
fn brotli_make_encode_command_with_distance_code(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  distance_code : Int,
) -> BrotliEncodeCommand raise FzipError {
  if distance_code == 0 {
    return brotli_make_encode_command_with_distance_mode(
      insert_start, insert_length, copy_length, distance, true, false,
    )
  }
  let command = brotli_find_command_prefix(insert_length, copy_length, true)
  {
    insert_start,
    insert_length,
    copy_length,
    output_length: copy_length,
    has_copy: true,
    command,
    distance_prefix: brotli_distance_prefix_for_code(distance_code),
  }
}

///|
fn brotli_try_make_encode_command_with_distance_code(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  distance_code : Int,
) -> BrotliEncodeCommand? {
  let result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command_with_distance_code(
    insert_start, insert_length, copy_length, distance, distance_code,
  )
  match result {
    Ok(command) => Some(command)
    Err(_) => None
  }
}

///|
fn brotli_try_make_encode_command_with_distance_mode(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  has_copy : Bool,
  explicit_distance : Bool,
) -> BrotliEncodeCommand? {
  let result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command_with_distance_mode(
    insert_start, insert_length, copy_length, distance, has_copy, explicit_distance,
  )
  match result {
    Ok(command) => Some(command)
    Err(_) => None
  }
}

///|
fn brotli_make_encode_command(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  has_copy : Bool,
) -> BrotliEncodeCommand raise FzipError {
  brotli_make_encode_command_with_distance_mode(
    insert_start, insert_length, copy_length, distance, has_copy, true,
  )
}

///|
fn brotli_make_dictionary_encode_command(
  insert_start : Int,
  insert_length : Int,
  word_length : Int,
  output_length : Int,
  distance : Int,
) -> BrotliEncodeCommand raise FzipError {
  let command = brotli_find_command_prefix(insert_length, word_length, true)
  {
    insert_start,
    insert_length,
    copy_length: word_length,
    output_length,
    has_copy: true,
    command,
    distance_prefix: brotli_distance_prefix_for_distance(distance),
  }
}

///|
fn brotli_literal_only_may_beat_stored(data : FixedArray[Byte]) -> Bool {
  if data.length() == 0 {
    return false
  }
  if brotli_count_unique_literals_up_to(data, 64) <= 64 {
    return true
  }
  let frequencies = FixedArray::make(brotli_num_literal_symbols, 0)
  for i in 0..<data.length() {
    frequencies[data[i].to_int()] += 1
  }
  let (code_lengths, _) = h_tree(frequencies, brotli_huffman_max_code_length)
  if code_lengths.length() == 0 {
    return false
  }
  let mut literal_bits = 0
  for symbol in 0..<code_lengths.length() {
    literal_bits += frequencies[symbol] * code_lengths[symbol].to_int()
  }
  // Leave room for the meta-block, context maps, command/distance trees, and
  // literal-tree description before spending time writing the candidate.
  literal_bits + 1024 < data.length() * 8
}

///|
fn brotli_build_literal_only_command(
  data : FixedArray[Byte],
) -> Array[BrotliEncodeCommand]? {
  if data.length() == 0 || data.length() > 65536 {
    return None
  }
  if !brotli_literal_only_may_beat_stored(data) {
    return None
  }
  let command_result : Result[BrotliEncodeCommand, FzipError] = try? brotli_make_encode_command(
    0,
    data.length(),
    0,
    0,
    false,
  )
  match command_result {
    Ok(command) => Some([command])
    Err(_) => None
  }
}

///|
fn brotli_block_length_prefix(
  length : Int,
) -> BrotliCommandPrefix raise FzipError {
  for symbol in 0..<brotli_num_block_length_symbols {
    let extra_bits = brotli_block_length_extra_bits[symbol]
    let extra = length - brotli_block_length_bases[symbol]
    if extra >= 0 && extra < 1 << extra_bits {
      return {
        symbol,
        insert_extra: extra,
        copy_extra: 0,
        insert_extra_bits: extra_bits,
        copy_extra_bits: 0,
      }
    }
  }
  raise fzip_err(BrotliInvalidMetablock, msg="invalid Brotli block length")
}

///|
fn brotli_write_two_literal_block_header(
  writer : BrotliBitWriter,
  first_length : Int,
  second_length : Int,
) -> (BrotliHuffmanSpec, BrotliCommandPrefix, BrotliCommandPrefix) raise FzipError {
  let first_prefix = brotli_block_length_prefix(first_length)
  let second_prefix = brotli_block_length_prefix(second_length)
  let length_symbols = FixedArray::make(brotli_num_block_length_symbols, 0)
  let mut length_count = 0
  length_count = brotli_add_unique_symbol(
    length_symbols,
    length_count,
    first_prefix.symbol,
  )
  length_count = brotli_add_unique_symbol(
    length_symbols,
    length_count,
    second_prefix.symbol,
  )
  let length_spec = brotli_make_huffman_spec(
    length_symbols, length_count, brotli_num_block_length_symbols, brotli_num_block_length_symbols,
  )
  brotli_write_var_len_uint8(writer, 1) // two literal block types
  brotli_write_simple_one_symbol_huffman(writer, 1, 2)
  brotli_write_huffman_spec(writer, length_spec)
  let length_payloads = brotli_huffman_payload_table(length_spec)
  let first_payload = length_payloads[first_prefix.symbol]
  writer.write_bits(first_payload.insert_extra_bits, first_payload.insert_extra)
  writer.write_bits(first_prefix.insert_extra_bits, first_prefix.insert_extra)
  (length_spec, first_prefix, second_prefix)
}

///|
fn brotli_write_trivial_two_tree_context_map(
  writer : BrotliBitWriter,
) -> Unit raise FzipError {
  brotli_write_var_len_uint8(writer, 1) // two literal trees
  writer.write_bits(1, 1) // use RLEMAX
  writer.write_bits(4, brotli_literal_context_bits - 2)
  let symbols : FixedArray[Int] = [0, 5, 6]
  let frequencies = FixedArray::make(7, 0)
  frequencies[0] = 1
  frequencies[5] = 2
  frequencies[6] = 1
  let spec = brotli_make_weighted_huffman_spec(symbols, 3, frequencies, 7, 7)
  brotli_write_huffman_spec(writer, spec)
  let payloads = brotli_huffman_payload_table(spec)
  let zero_payload = payloads[0]
  writer.write_bits(zero_payload.insert_extra_bits, zero_payload.insert_extra)
  let repeat_payload = payloads[5]
  writer.write_bits(
    repeat_payload.insert_extra_bits,
    repeat_payload.insert_extra,
  )
  writer.write_bits(5, 31)
  let one_payload = payloads[6]
  writer.write_bits(one_payload.insert_extra_bits, one_payload.insert_extra)
  writer.write_bits(
    repeat_payload.insert_extra_bits,
    repeat_payload.insert_extra,
  )
  writer.write_bits(5, 31)
  writer.write_bits(1, 1) // apply inverse move-to-front
}

///|
fn brotli_utf8_context_tree(context : Int) -> Int {
  if context >= 56 {
    1
  } else {
    0
  }
}

///|
fn brotli_utf8_context_tree4(context : Int) -> Int {
  if context >= 56 {
    3
  } else if context <= 11 {
    0
  } else if context >= 44 {
    2
  } else {
    1
  }
}

///|
fn brotli_utf8_context_tree8(context : Int) -> Int {
  if context <= 5 {
    0
  } else if context <= 11 {
    1
  } else if context <= 23 {
    2
  } else if context <= 35 {
    3
  } else if context <= 43 {
    4
  } else if context <= 55 {
    5
  } else if context <= 59 {
    6
  } else {
    7
  }
}

///|
fn brotli_utf8_context_tree16(context : Int) -> Int {
  context / 4
}

///|
fn brotli_write_utf8_context_map(
  writer : BrotliBitWriter,
) -> Unit raise FzipError {
  brotli_write_var_len_uint8(writer, 1) // two literal trees
  writer.write_bits(1, 0) // no RLE prefix
  let symbols : FixedArray[Int] = [0, 1]
  let spec = brotli_make_huffman_spec(symbols, 2, 2, 2)
  brotli_write_huffman_spec(writer, spec)
  let payloads = brotli_huffman_payload_table(spec)
  for context in 0..<64 {
    let tree = brotli_utf8_context_tree(context)
    let payload = payloads[tree]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(1, 0) // no inverse move-to-front
}

///|
fn brotli_write_utf8_context_map4(
  writer : BrotliBitWriter,
) -> Unit raise FzipError {
  brotli_write_var_len_uint8(writer, 3) // four literal trees
  writer.write_bits(1, 0) // no RLE prefix
  let symbols : FixedArray[Int] = [0, 1, 2, 3]
  let spec = brotli_make_huffman_spec(symbols, 4, 4, 4)
  brotli_write_huffman_spec(writer, spec)
  let payloads = brotli_huffman_payload_table(spec)
  for context in 0..<64 {
    let tree = brotli_utf8_context_tree4(context)
    let payload = payloads[tree]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(1, 0) // no inverse move-to-front
}

///|
fn brotli_write_utf8_context_map8(
  writer : BrotliBitWriter,
) -> Unit raise FzipError {
  brotli_write_var_len_uint8(writer, 7) // eight literal trees
  writer.write_bits(1, 0) // no RLE prefix
  let symbols : FixedArray[Int] = [0, 1, 2, 3, 4, 5, 6, 7]
  let spec = brotli_make_huffman_spec(symbols, 8, 8, 8)
  brotli_write_huffman_spec(writer, spec)
  let payloads = brotli_huffman_payload_table(spec)
  for context in 0..<64 {
    let tree = brotli_utf8_context_tree8(context)
    let payload = payloads[tree]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(1, 0) // no inverse move-to-front
}

///|
fn brotli_write_utf8_context_map16(
  writer : BrotliBitWriter,
) -> Unit raise FzipError {
  brotli_write_var_len_uint8(writer, 15) // sixteen literal trees
  writer.write_bits(1, 0) // no RLE prefix
  let symbols : FixedArray[Int] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  ]
  let spec = brotli_make_huffman_spec(symbols, 16, 16, 16)
  brotli_write_huffman_spec(writer, spec)
  let payloads = brotli_huffman_payload_table(spec)
  for context in 0..<64 {
    let tree = brotli_utf8_context_tree16(context)
    let payload = payloads[tree]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(1, 0) // no inverse move-to-front
}

///|
fn brotli_write_split_literal_only_metablock(
  data : FixedArray[Byte],
  split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise FzipError {
  if split <= 0 || split >= data.length() {
    return None
  }
  let first_literals = match
    brotli_collect_unique_literals_range(data, 0, split) {
    Some(literals) => literals
    None => return None
  }
  let second_literals = match
    brotli_collect_unique_literals_range(data, split, data.length()) {
    Some(literals) => literals
    None => return None
  }
  let command = match brotli_build_literal_only_command(data) {
    Some(commands) => commands[0]
    None => return None
  }
  let first_frequencies = brotli_literal_frequencies_range(data, 0, split)
  let second_frequencies = brotli_literal_frequencies_range(
    data,
    split,
    data.length(),
  )
  let first_spec = brotli_make_weighted_huffman_spec(
    first_literals.symbols,
    first_literals.count,
    first_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let command_symbols : FixedArray[Int] = [command.command.symbol]
  let command_spec = brotli_make_huffman_spec(
    command_symbols, 1, brotli_num_command_symbols, brotli_num_command_symbols,
  )
  let distance_symbols : FixedArray[Int] = [0]
  let distance_spec = brotli_make_huffman_spec(
    distance_symbols,
    1,
    brotli_distance_alphabet_size(0, 0, 24),
    brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(256 + data.length() * 4)
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  let (length_spec, _, second_prefix) = brotli_write_two_literal_block_header(
    writer,
    split,
    data.length() - split,
  )
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 1
  brotli_write_trivial_two_tree_context_map(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, first_spec)
  brotli_write_huffman_spec(writer, second_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let first_payloads = brotli_huffman_payload_table(first_spec)
  let second_payloads = brotli_huffman_payload_table(second_spec)
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let length_payloads = brotli_huffman_payload_table(length_spec)
  let command_payload = command_payloads[command.command.symbol]
  writer.write_bits(
    command_payload.insert_extra_bits,
    command_payload.insert_extra,
  )
  writer.write_bits(
    command.command.insert_extra_bits,
    command.command.insert_extra,
  )
  writer.write_bits(command.command.copy_extra_bits, command.command.copy_extra)
  for i in 0..<split {
    let payload = first_payloads[data[i].to_int()]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  writer.write_bits(type_payload.insert_extra_bits, type_payload.insert_extra)
  let second_length_payload = length_payloads[second_prefix.symbol]
  writer.write_bits(
    second_length_payload.insert_extra_bits,
    second_length_payload.insert_extra,
  )
  writer.write_bits(second_prefix.insert_extra_bits, second_prefix.insert_extra)
  for i in split..<data.length() {
    let payload = second_payloads[data[i].to_int()]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  Some(writer)
}

///|
fn brotli_try_split_literal_only_metablock(
  data : FixedArray[Byte],
  is_last : Bool,
  best : BrotliBitWriter?,
) -> BrotliBitWriter? raise FzipError {
  if data.length() < 2048 || data.length() > 65536 {
    return best
  }
  if !brotli_literal_only_may_beat_stored(data) {
    return best
  }
  let split = brotli_best_split_literal_point(data)
  let mut best = best
  if split > 0 {
    match brotli_write_split_literal_only_metablock(data, split, is_last) {
      Some(candidate) =>
        match best {
          Some(current) =>
            if candidate.bit_pos < current.bit_pos {
              best = Some(candidate)
            }
          None => best = Some(candidate)
        }
      None => ()
    }
  }
  best
}

///|
fn brotli_build_simple_lz77_commands(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
) -> Array[BrotliEncodeCommand]? {
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  brotli_build_simple_lz77_commands_with_distance_cache(
    data, hash_config, distance_cache,
  )
}

///|
fn brotli_build_simple_lz77_commands_with_distance_cache(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  distance_cache : FixedArray[Int],
) -> Array[BrotliEncodeCommand]? {
  if data.length() < 8 || data.length() > 1048576 {
    return None
  }
  if !brotli_has_compressible_match_density(data, hash_config) {
    return None
  }
  let commands : Array[BrotliEncodeCommand] = []
  let previous = brotli_previous_match_positions(data, hash_config)
  let mut literal_start = 0
  let mut position = 0
  while position < data.length() {
    let (match_length, distance) = brotli_longest_previous_hash_match_with_cache(
      data, previous, position, hash_config, distance_cache,
    )
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
  let copy_bytes = brotli_commands_copy_bytes(commands)
  if copy_bytes * 100 < data.length() * hash_config.min_copy_ratio_percent {
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
      if brotli_command_uses_distance_symbol(commands[i]) {
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
  // Single-pass literal collection + frequency tally.
  let literal_symbols = FixedArray::make(brotli_num_literal_symbols, 0)
  let literal_seen = FixedArray::make(brotli_num_literal_symbols, false)
  let literal_frequencies = FixedArray::make(brotli_num_literal_symbols, 0)
  let mut literal_count = 0
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  let commands_len = commands.length()
  for i in 0..<commands_len {
    let command = commands[i]
    let insert_start = command.insert_start
    let insert_length = command.insert_length
    for j in 0..<insert_length {
      let literal = data[insert_start + j].to_int()
      literal_frequencies[literal] += 1
      if !literal_seen[literal] {
        literal_seen[literal] = true
        literal_symbols[literal_count] = literal
        literal_count += 1
      }
    }
    let cmd_symbol = command.command.symbol
    command_frequencies[cmd_symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols, command_count, cmd_symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      let dist_symbol = command.distance_prefix.symbol
      distance_frequencies[dist_symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols, distance_count, dist_symbol,
      )
    }
  }
  if literal_count == 0 {
    literal_symbols[0] = 0
    literal_count = 1
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let literal_spec = if weighted {
    brotli_make_weighted_huffman_spec(
      literal_symbols, literal_count, literal_frequencies, brotli_num_literal_symbols,
      brotli_num_literal_symbols,
    )
  } else {
    brotli_make_huffman_spec(
      literal_symbols, literal_count, brotli_num_literal_symbols, brotli_num_literal_symbols,
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
  let literal_payloads = brotli_huffman_payload_table(literal_spec)
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = command_payloads[command.command.symbol]
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
      let literal_payload = literal_payloads[literal]
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_payload = distance_payloads[command.distance_prefix.symbol]
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
fn brotli_write_split_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise FzipError {
  let literal_count = brotli_command_literal_count(commands)
  if split <= 0 || split >= literal_count {
    return None
  }
  let mut has_copy = false
  for i in 0..<commands.length() {
    if commands[i].has_copy {
      has_copy = true
      break
    }
  }
  if !has_copy {
    return None
  }
  let first_literals = match
    brotli_collect_command_literals_range(data, commands, 0, split) {
    Some(literals) => literals
    None => return None
  }
  let second_literals = match
    brotli_collect_command_literals_range(data, commands, split, literal_count) {
    Some(literals) => literals
    None => return None
  }
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_frequencies = brotli_command_literal_frequencies_range(
    data, commands, 0, split,
  )
  let second_frequencies = brotli_command_literal_frequencies_range(
    data, commands, split, literal_count,
  )
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      distance_frequencies[command.distance_prefix.symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        command.distance_prefix.symbol,
      )
    }
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let first_spec = brotli_make_weighted_huffman_spec(
    first_literals.symbols,
    first_literals.count,
    first_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, brotli_num_command_symbols,
    brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    brotli_distance_alphabet_size(0, 0, 24),
    brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  let (length_spec, _, second_prefix) = brotli_write_two_literal_block_header(
    writer,
    split,
    literal_count - split,
  )
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 1
  brotli_write_trivial_two_tree_context_map(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, first_spec)
  brotli_write_huffman_spec(writer, second_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let first_payloads = brotli_huffman_payload_table(first_spec)
  let second_payloads = brotli_huffman_payload_table(second_spec)
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  let length_payloads = brotli_huffman_payload_table(length_spec)
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  let second_length_payload = length_payloads[second_prefix.symbol]
  let mut literal_index = 0
  let mut switched = false
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = command_payloads[command.command.symbol]
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
      if !switched && literal_index == split {
        writer.write_bits(
          type_payload.insert_extra_bits,
          type_payload.insert_extra,
        )
        writer.write_bits(
          second_length_payload.insert_extra_bits,
          second_length_payload.insert_extra,
        )
        writer.write_bits(
          second_prefix.insert_extra_bits,
          second_prefix.insert_extra,
        )
        switched = true
      }
      let literal = data[command.insert_start + j].to_int()
      let literal_payload = if literal_index < split {
        first_payloads[literal]
      } else {
        second_payloads[literal]
      }
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
      literal_index += 1
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_payload = distance_payloads[command.distance_prefix.symbol]
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
  Some(writer)
}

///|
fn brotli_write_context_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
) -> BrotliBitWriter? raise FzipError {
  let (literal_sets, literal_frequencies_array) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context(
      data, commands,
    ) {
    Some(result) => result
    None => return None
  }
  let first_literals = literal_sets[0]
  let second_literals = literal_sets[1]
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_frequencies = literal_frequencies_array[0]
  let second_frequencies = literal_frequencies_array[1]
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      distance_frequencies[command.distance_prefix.symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        command.distance_prefix.symbol,
      )
    }
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let first_spec = brotli_make_weighted_huffman_spec(
    first_literals.symbols,
    first_literals.count,
    first_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, brotli_num_command_symbols,
    brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    brotli_distance_alphabet_size(0, 0, 24),
    brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 2) // UTF-8 literal context mode
  brotli_write_utf8_context_map(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, first_spec)
  brotli_write_huffman_spec(writer, second_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let first_payloads = brotli_huffman_payload_table(first_spec)
  let second_payloads = brotli_huffman_payload_table(second_spec)
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = command_payloads[command.command.symbol]
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
      let position = command.insert_start + j
      let literal = data[position].to_int()
      let tree = brotli_command_literal_utf8_context_tree(data, position)
      let literal_payload = if tree == 0 {
        first_payloads[literal]
      } else {
        second_payloads[literal]
      }
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_payload = distance_payloads[command.distance_prefix.symbol]
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
  Some(writer)
}

///|
fn brotli_write_context4_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
) -> BrotliBitWriter? raise FzipError {
  let (literal_sets, literal_frequencies_array) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context4(
      data, commands,
    ) {
    Some(result) => result
    None => return None
  }
  let first_literals = literal_sets[0]
  let second_literals = literal_sets[1]
  let third_literals = literal_sets[2]
  let fourth_literals = literal_sets[3]
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_frequencies = literal_frequencies_array[0]
  let second_frequencies = literal_frequencies_array[1]
  let third_frequencies = literal_frequencies_array[2]
  let fourth_frequencies = literal_frequencies_array[3]
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      distance_frequencies[command.distance_prefix.symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        command.distance_prefix.symbol,
      )
    }
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let first_spec = brotli_make_weighted_huffman_spec(
    first_literals.symbols,
    first_literals.count,
    first_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let third_spec = brotli_make_weighted_huffman_spec(
    third_literals.symbols,
    third_literals.count,
    third_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let fourth_spec = brotli_make_weighted_huffman_spec(
    fourth_literals.symbols,
    fourth_literals.count,
    fourth_frequencies,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, brotli_num_command_symbols,
    brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    brotli_distance_alphabet_size(0, 0, 24),
    brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 2) // UTF-8 literal context mode
  brotli_write_utf8_context_map4(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, first_spec)
  brotli_write_huffman_spec(writer, second_spec)
  brotli_write_huffman_spec(writer, third_spec)
  brotli_write_huffman_spec(writer, fourth_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let first_payloads = brotli_huffman_payload_table(first_spec)
  let second_payloads = brotli_huffman_payload_table(second_spec)
  let third_payloads = brotli_huffman_payload_table(third_spec)
  let fourth_payloads = brotli_huffman_payload_table(fourth_spec)
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = command_payloads[command.command.symbol]
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
      let position = command.insert_start + j
      let literal = data[position].to_int()
      let tree = brotli_command_literal_utf8_context_tree4(data, position)
      let literal_payload = if tree == 0 {
        first_payloads[literal]
      } else if tree == 1 {
        second_payloads[literal]
      } else if tree == 2 {
        third_payloads[literal]
      } else {
        fourth_payloads[literal]
      }
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_payload = distance_payloads[command.distance_prefix.symbol]
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
  Some(writer)
}

///|
fn brotli_write_context8_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
) -> BrotliBitWriter? raise FzipError {
  let (literal_sets, literal_frequencies) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context8(
      data, commands,
    ) {
    Some(result) => result
    None => return None
  }
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      distance_frequencies[command.distance_prefix.symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        command.distance_prefix.symbol,
      )
    }
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let literal_specs : Array[BrotliHuffmanSpec] = []
  for tree in 0..<8 {
    let literals = literal_sets[tree]
    literal_specs.push(
      brotli_make_weighted_huffman_spec(
        literals.symbols,
        literals.count,
        literal_frequencies[tree],
        brotli_num_literal_symbols,
        brotli_num_literal_symbols,
      ),
    )
  }
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, brotli_num_command_symbols,
    brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    brotli_distance_alphabet_size(0, 0, 24),
    brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 2) // UTF-8 literal context mode
  brotli_write_utf8_context_map8(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  for tree in 0..<8 {
    brotli_write_huffman_spec(writer, literal_specs[tree])
  }
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let literal_payloads : Array[FixedArray[BrotliCommandPrefix]] = []
  for tree in 0..<8 {
    literal_payloads.push(brotli_huffman_payload_table(literal_specs[tree]))
  }
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = command_payloads[command.command.symbol]
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
      let position = command.insert_start + j
      let literal = data[position].to_int()
      let tree = brotli_command_literal_utf8_context_tree8(data, position)
      let literal_payload = literal_payloads[tree][literal]
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_payload = distance_payloads[command.distance_prefix.symbol]
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
  Some(writer)
}

///|
fn brotli_write_context16_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
) -> BrotliBitWriter? raise FzipError {
  let (literal_sets, literal_frequencies) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context16(
      data, commands,
    ) {
    Some(result) => result
    None => return None
  }
  let command_symbols = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(brotli_num_command_symbols, 0)
  let distance_frequencies = FixedArray::make(
    brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      distance_frequencies[command.distance_prefix.symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols,
        distance_count,
        command.distance_prefix.symbol,
      )
    }
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let literal_specs : Array[BrotliHuffmanSpec] = []
  for tree in 0..<16 {
    let literals = literal_sets[tree]
    literal_specs.push(
      brotli_make_weighted_huffman_spec(
        literals.symbols,
        literals.count,
        literal_frequencies[tree],
        brotli_num_literal_symbols,
        brotli_num_literal_symbols,
      ),
    )
  }
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, brotli_num_command_symbols,
    brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    brotli_distance_alphabet_size(0, 0, 24),
    brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 2) // UTF-8 literal context mode
  brotli_write_utf8_context_map16(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  for tree in 0..<16 {
    brotli_write_huffman_spec(writer, literal_specs[tree])
  }
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let literal_payloads : Array[FixedArray[BrotliCommandPrefix]] = []
  for tree in 0..<16 {
    literal_payloads.push(brotli_huffman_payload_table(literal_specs[tree]))
  }
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_payload = command_payloads[command.command.symbol]
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
      let position = command.insert_start + j
      let literal = data[position].to_int()
      let tree = brotli_command_literal_utf8_context_tree16(data, position)
      let literal_payload = literal_payloads[tree][literal]
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_payload = distance_payloads[command.distance_prefix.symbol]
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
  Some(writer)
}

///|
fn brotli_write_best_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
  quality : Int,
) -> BrotliBitWriter raise FzipError {
  if quality <= 2 && data.length() >= 524288 {
    if commands.length() != 1 || commands[0].has_copy {
      match brotli_write_context16_lz77_metablock(data, commands, is_last) {
        Some(candidate) => return candidate
        None => ()
      }
    }
  }
  let weighted = BrotliBitWriter::new(
    128 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, data, commands, is_last, true)
  if commands.length() == 1 &&
    !commands[0].has_copy &&
    brotli_count_unique_literals_up_to(data, 16) > 16 {
    return weighted
  }
  if quality <= 2 && data.length() >= 262144 {
    return weighted
  }
  let mut best = weighted
  if quality <= 2 && data.length() >= 8192 {
    let split = brotli_best_command_literal_split_point(data, commands)
    if split > 0 {
      match brotli_write_split_lz77_metablock(data, commands, split, is_last) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
    }
    match brotli_write_context16_lz77_metablock(data, commands, is_last) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
    return best
  }
  // Fixed (un-weighted) Huffman and 2-tree context candidates almost never
  // beat the weighted single-tree or richer context candidates on inputs
  // large enough to reach this path: weighted has the same structure with
  // better code-length costs, and the 2-tree context map's metadata
  // overhead outweighs the literal savings versus context4/8/16. Skip
  // them at quality >= 3 to remove two full per-command writer passes
  // (verified zero size change on silesia-128k q9/q11).
  if quality < 3 {
    let fixed = BrotliBitWriter::new(
      128 + data.length() * 4 + commands.length() * 8,
    )
    brotli_write_simple_lz77_metablock(fixed, data, commands, is_last, false)
    if fixed.bit_pos < best.bit_pos {
      best = fixed
    }
  }
  let split = brotli_best_command_literal_split_point(data, commands)
  if split > 0 {
    match brotli_write_split_lz77_metablock(data, commands, split, is_last) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
  }
  if quality < 3 {
    match brotli_write_context_lz77_metablock(data, commands, is_last) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
  }
  match brotli_write_context4_lz77_metablock(data, commands, is_last) {
    Some(candidate) => if candidate.bit_pos < best.bit_pos { best = candidate }
    None => ()
  }
  match brotli_write_context8_lz77_metablock(data, commands, is_last) {
    Some(candidate) => if candidate.bit_pos < best.bit_pos { best = candidate }
    None => ()
  }
  match brotli_write_context16_lz77_metablock(data, commands, is_last) {
    Some(candidate) => if candidate.bit_pos < best.bit_pos { best = candidate }
    None => ()
  }
  best
}

///|
fn brotli_try_compressed_commands(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand]?,
  is_last : Bool,
  best : BrotliBitWriter?,
  quality : Int,
) -> BrotliBitWriter? raise FzipError {
  match commands {
    Some(commands) => {
      let candidate = brotli_write_best_lz77_metablock(
        data, commands, is_last, quality,
      )
      match best {
        Some(best) =>
          if candidate.bit_pos < best.bit_pos {
            Some(candidate)
          } else {
            Some(best)
          }
        None => Some(candidate)
      }
    }
    None => best
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
  is_last : Bool,
  base_offset : Int,
  window_bits : Int,
  quality : Int,
  distance_cache : FixedArray[Int],
) -> BrotliBitWriter? raise FzipError {
  if quality <= 2 && data.length() >= 8192 {
    let natural_config = brotli_natural_hash_config_for_quality(quality)
    let chunk_cache = brotli_copy_distance_cache(distance_cache)
    let commands = brotli_build_simple_lz77_commands_with_distance_cache(
      data, natural_config, chunk_cache,
    )
    let candidate = brotli_try_compressed_commands(
      data,
      commands,
      is_last,
      None,
      quality,
    )
    match candidate {
      Some(_) => brotli_commit_distance_cache(distance_cache, chunk_cache)
      None => ()
    }
    return candidate
  }
  let match_commands = brotli_build_simple_lz77_commands(data, hash_config)
  let best = brotli_try_compressed_commands(
    data,
    match_commands,
    is_last,
    None,
    quality,
  )
  let best = brotli_try_compressed_commands(
    data,
    brotli_build_literal_only_command(data),
    is_last,
    best,
    quality,
  )
  let best = brotli_try_split_literal_only_metablock(data, is_last, best)
  let best = brotli_try_compressed_commands(
    data,
    brotli_build_identity_dictionary_commands(
      data, hash_config, base_offset, window_bits,
    ),
    is_last,
    best,
    quality,
  )
  if quality >= 2 && data.length() >= 8192 {
    if quality >= 9 {
      let hq_config = brotli_high_quality_hash_config_for_quality(quality)
      if quality >= 10 {
        return brotli_try_compressed_commands(
          data,
          brotli_build_simple_lz77_commands(
            data,
            brotli_four_byte_hash_config(hq_config),
          ),
          is_last,
          best,
          quality,
        )
      }
      let best = brotli_try_compressed_commands(
        data,
        brotli_build_simple_lz77_commands(data, hq_config),
        is_last,
        best,
        quality,
      )
      brotli_try_compressed_commands(
        data,
        brotli_build_simple_lz77_commands(
          data,
          brotli_four_byte_hash_config(hq_config),
        ),
        is_last,
        best,
        quality,
      )
    } else {
      let natural_config = brotli_natural_hash_config_for_quality(quality)
      let best = brotli_try_compressed_commands(
        data,
        brotli_build_simple_lz77_commands(data, natural_config),
        is_last,
        best,
        quality,
      )
      brotli_try_compressed_commands(
        data,
        brotli_build_simple_lz77_commands(
          data,
          brotli_four_byte_hash_config(natural_config),
        ),
        is_last,
        best,
        quality,
      )
    }
  } else {
    best
  }
}

///|
fn brotli_encode_chunked_standard(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise FzipError {
  let chunk_size = 1048576
  let chunk_count = (data.length() + chunk_size - 1) / chunk_size
  let writer = BrotliBitWriter::new(data.length() + 8 + chunk_count * 16)
  brotli_encode_window_bits(writer, opts.window_bits)
  let hash_config = brotli_hash_config_for_quality(opts.quality)
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  let mut offset = 0
  let mut wrote_last = false
  while offset < data.length() {
    let remaining = data.length() - offset
    let length = if remaining > chunk_size { chunk_size } else { remaining }
    let chunk = slc(data, offset, e=offset + length)
    let is_last = offset + length == data.length()
    let previous_distance_cache = brotli_copy_distance_cache(distance_cache)
    match
      brotli_try_compressed_chunk(
        chunk,
        hash_config,
        is_last,
        offset,
        opts.window_bits,
        opts.quality,
        distance_cache,
      ) {
      Some(compressed) =>
        if shft(compressed.bit_pos) + 1 < length + 16 {
          writer.write_from_bits(compressed.buf, compressed.bit_pos)
          if is_last {
            wrote_last = true
          }
        } else {
          brotli_commit_distance_cache(distance_cache, previous_distance_cache)
          brotli_write_uncompressed_metablock(writer, data, offset, length)
        }
      None => {
        brotli_commit_distance_cache(distance_cache, previous_distance_cache)
        brotli_write_uncompressed_metablock(writer, data, offset, length)
      }
    }
    offset += length
  }
  if !wrote_last {
    brotli_write_final_empty_metablock(writer)
  }
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
    let mut best : BrotliBitWriter? = None
    best = brotli_try_compressed_commands(
      data,
      brotli_build_simple_lz77_commands(data, hash_config),
      true,
      best,
      opts.quality,
    )
    best = brotli_try_compressed_commands(
      data,
      brotli_build_literal_only_command(data),
      true,
      best,
      opts.quality,
    )
    best = brotli_try_split_literal_only_metablock(data, true, best)
    best = brotli_try_compressed_commands(
      data,
      brotli_build_identity_dictionary_commands(
        data,
        hash_config,
        0,
        opts.window_bits,
      ),
      true,
      best,
      opts.quality,
    )
    if data.length() >= 8192 {
      if opts.quality >= 9 {
        let hq_config = brotli_high_quality_hash_config_for_quality(
          opts.quality,
        )
        if opts.quality >= 10 {
          best = brotli_try_compressed_commands(
            data,
            brotli_build_simple_lz77_commands(
              data,
              brotli_four_byte_hash_config(hq_config),
            ),
            true,
            best,
            opts.quality,
          )
        } else {
          best = brotli_try_compressed_commands(
            data,
            brotli_build_simple_lz77_commands(data, hq_config),
            true,
            best,
            opts.quality,
          )
          best = brotli_try_compressed_commands(
            data,
            brotli_build_simple_lz77_commands(
              data,
              brotli_four_byte_hash_config(hq_config),
            ),
            true,
            best,
            opts.quality,
          )
        }
      } else {
        let natural_config = brotli_natural_hash_config_for_quality(
          opts.quality,
        )
        best = brotli_try_compressed_commands(
          data,
          brotli_build_simple_lz77_commands(data, natural_config),
          true,
          best,
          opts.quality,
        )
        best = brotli_try_compressed_commands(
          data,
          brotli_build_simple_lz77_commands(
            data,
            brotli_four_byte_hash_config(natural_config),
          ),
          true,
          best,
          opts.quality,
        )
      }
    }
    match best {
      Some(compressed) => {
        let uncompressed = brotli_encode_uncompressed(data, opts)
        let compressed_size = shft(compressed.bit_pos) + 1
        if compressed_size < uncompressed.length() {
          let writer = BrotliBitWriter::new(
            8 + compressed_size + data.length() / 8,
          )
          brotli_encode_window_bits(writer, opts.window_bits)
          writer.write_from_bits(compressed.buf, compressed.bit_pos)
          return writer.finish()
        }
      }
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
  if opts.max_input_size < 0 {
    raise fzip_err(InvalidZipData, msg="Brotli max_input_size must be >= 0")
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
  if data.length() > opts.max_input_size {
    raise fzip_err(InvalidZipData, msg="input exceeds max_input_size")
  }
  if opts.quality >= 10 && data.length() > 256 * 1024 * 1024 {
    raise fzip_err(
      InvalidZipData,
      msg="Brotli q10/q11 input exceeds 256 MiB safety cap",
    )
  }
  match opts.quality {
    0 | 1 => brotli_encode_uncompressed(data, opts)
    2..=11 => brotli_encode_standard(data, opts)
    _ => raise fzip_err(InvalidZipData, msg="Brotli quality must be 0..=11")
  }
}

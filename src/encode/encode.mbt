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
priv struct BrotliCommandCandidate {
  commands : Array[BrotliEncodeCommand]
  distance_cache : FixedArray[Int]
}

///|
priv struct BrotliCompressedChunk {
  writer : BrotliBitWriter
  distance_cache : FixedArray[Int]
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
  @common.trim_buf(self.buf, @common.shft(self.bit_pos))
}

///|
fn brotli_encode_window_bits(
  writer : BrotliBitWriter,
  window_bits : Int,
) -> Unit raise @common.FbrError {
  @common.brotli_validate_window_bits(window_bits)
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
    (input_len + @common.brotli_max_metablock_bytes - 1) /
    @common.brotli_max_metablock_bytes
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
) -> BrotliHuffmanSpec raise @common.FbrError {
  if count <= 0 || count > alphabet_size_limit {
    raise @common.fbr_err(
      @common.BrotliInvalidHuffman,
      msg="invalid encoder alphabet",
    )
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
    raise @common.fbr_err(
      @common.BrotliInvalidHuffman,
      msg="encoder alphabet too large",
    )
  }
  let bits = @common.brotli_log2_floor_plus_one(padded_count) - 1
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
) -> BrotliHuffmanSpec raise @common.FbrError {
  if count <= 4 {
    return brotli_make_huffman_spec(
      symbols, count, alphabet_size_max, alphabet_size_limit,
    )
  }
  if count > 16 {
    let (tree_lengths, _) = h_tree(
      frequencies, @common.brotli_huffman_max_code_length,
    )
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
      raise @common.fbr_err(
        @common.BrotliInvalidHuffman,
        msg="invalid weighted tree",
      )
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
    if depth <= 0 || depth > @common.brotli_huffman_max_code_length {
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
fn brotli_find_fixed_prefix_payload(
  value : Int,
) -> (Int, Int) raise @common.FbrError {
  for i in 0..<@common.brotli_code_length_prefix_value.length() {
    if @common.brotli_code_length_prefix_value[i] == value {
      let bits = @common.brotli_code_length_prefix_length[i]
      return (bits, i & ((1 << bits) - 1))
    }
  }
  raise @common.fbr_err(
    @common.BrotliInvalidHuffman,
    msg="missing fixed prefix payload",
  )
}

///|
fn brotli_huffman_payload_from_lengths(
  code_lengths : FixedArray[Byte],
  alphabet_size : Int,
  target : Int,
) -> BrotliCommandPrefix raise @common.FbrError {
  if target < 0 || target >= alphabet_size {
    raise @common.fbr_err(
      @common.BrotliInvalidHuffman,
      msg="target outside alphabet",
    )
  }
  let count = FixedArray::make(@common.brotli_huffman_max_code_length + 1, 0)
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len > 0 {
      count[len] += 1
    }
  }
  let next_code = FixedArray::make(
    @common.brotli_huffman_max_code_length + 1,
    0,
  )
  let mut code = 0
  for bits in 1..<=@common.brotli_huffman_max_code_length {
    code = (code + count[bits - 1]) << 1
    next_code[bits] = code
  }
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len != 0 {
      let reversed = @common.brotli_reverse_bits(next_code[len], len)
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
  raise @common.fbr_err(
    @common.BrotliInvalidHuffman,
    msg="target has no Huffman code",
  )
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
          code_length_symbols, count, @common.brotli_repeat_zero_code_length,
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
          code_length_symbols, count, @common.brotli_repeat_previous_code_length,
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
) -> Unit raise @common.FbrError {
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
          code_length_code_lengths, @common.brotli_num_code_length_codes, @common.brotli_repeat_zero_code_length,
        )
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        writer.write_bits(3, 7)
        run -= 10
        let zero_payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, @common.brotli_num_code_length_codes, 0,
        )
        writer.write_bits(
          zero_payload.insert_extra_bits,
          zero_payload.insert_extra,
        )
        run -= 1
      }
      if run >= 3 {
        let payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, @common.brotli_num_code_length_codes, @common.brotli_repeat_zero_code_length,
        )
        writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
        writer.write_bits(3, run - 3)
        run = 0
      }
      while run > 0 {
        let payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, @common.brotli_num_code_length_codes, 0,
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
        code_length_code_lengths, @common.brotli_num_code_length_codes, length,
      )
      writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
      run -= 1
      while run > 6 {
        let repeat_payload = brotli_huffman_payload_from_lengths(
          code_length_code_lengths, @common.brotli_num_code_length_codes, @common.brotli_repeat_previous_code_length,
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
          code_length_code_lengths, @common.brotli_num_code_length_codes, @common.brotli_repeat_previous_code_length,
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
) -> Unit raise @common.FbrError {
  writer.write_bits(2, 0) // complex Huffman marker, skip 0
  let last_nonzero = brotli_complex_huffman_last_nonzero(spec)
  let code_length_symbols = FixedArray::make(
    @common.brotli_num_code_length_codes, 0,
  )
  let mut code_length_count = brotli_add_unique_symbol(
    code_length_symbols, 0, 0,
  )
  code_length_count = brotli_add_complex_code_length_symbols(
    spec, code_length_symbols, code_length_count, last_nonzero,
  )
  let code_length_code_lengths = FixedArray::make(
    @common.brotli_num_code_length_codes, b'\x00',
  )
  let padded_count = brotli_next_power_of_two(code_length_count)
  if padded_count <= @common.brotli_num_code_length_codes {
    let bits = @common.brotli_log2_floor_plus_one(padded_count) - 1
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
    let frequencies = FixedArray::make(@common.brotli_num_code_length_codes, 0)
    for i in 0..<code_length_count {
      frequencies[code_length_symbols[i]] += 1
    }
    let (tree_lengths, _) = h_tree(frequencies, 5)
    if tree_lengths.length() == 0 {
      raise @common.fbr_err(
        @common.BrotliInvalidHuffman,
        msg="code-length alphabet too large",
      )
    }
    for i in 0..<tree_lengths.length() {
      code_length_code_lengths[i] = tree_lengths[i]
    }
  }
  let mut space = 32
  for i in 0..<@common.brotli_code_length_code_order.length() {
    let symbol = @common.brotli_code_length_code_order[i]
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
) -> Unit raise @common.FbrError {
  if spec.simple {
    let symbol_bits = @common.brotli_log2_floor_plus_one(
      spec.alphabet_size_max - 1,
    )
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
) -> BrotliCommandPrefix raise @common.FbrError {
  let table = @common.brotli_build_simple_huffman_table(
    symbols,
    count - 1,
    @common.brotli_huffman_table_bits,
  )
  for index in 0..<(1 << @common.brotli_huffman_table_bits) {
    let entry = table[index]
    let entry_bits = @common.brotli_huffman_code_bits(entry)
    if @common.brotli_huffman_code_value(entry) == target {
      let mask = if entry_bits == 0 { 0 } else { (1 << entry_bits) - 1 }
      return {
        symbol: target,
        insert_extra: index & mask,
        copy_extra: 0,
        insert_extra_bits: entry_bits,
        copy_extra_bits: 0,
      }
    }
  }
  raise @common.fbr_err(
    @common.BrotliInvalidHuffman,
    msg="symbol missing from simple tree",
  )
}

///|
fn brotli_huffman_spec_payload(
  spec : BrotliHuffmanSpec,
  target : Int,
) -> BrotliCommandPrefix raise @common.FbrError {
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
) -> FixedArray[BrotliCommandPrefix] raise @common.FbrError {
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
  let count = FixedArray::make(@common.brotli_huffman_max_code_length + 1, 0)
  for symbol in 0..<spec.alphabet_size_limit {
    let len = spec.code_lengths[symbol].to_int()
    if len > 0 {
      count[len] += 1
    }
  }
  let next_code = FixedArray::make(
    @common.brotli_huffman_max_code_length + 1,
    0,
  )
  let mut code = 0
  for bits in 1..<=@common.brotli_huffman_max_code_length {
    code = (code + count[bits - 1]) << 1
    next_code[bits] = code
  }
  for symbol in 0..<spec.alphabet_size_limit {
    let len = spec.code_lengths[symbol].to_int()
    if len != 0 {
      let reversed = @common.brotli_reverse_bits(next_code[len], len)
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
  let symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
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
  let symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
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
  let frequencies = FixedArray::make(@common.brotli_num_literal_symbols, 0)
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
    first_frequencies, @common.brotli_huffman_max_code_length,
  )
  let (second_lengths, _) = h_tree(
    second_frequencies, @common.brotli_huffman_max_code_length,
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
  let (all_lengths, _) = h_tree(
    all_frequencies, @common.brotli_huffman_max_code_length,
  )
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
  let symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
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
  let frequencies = FixedArray::make(@common.brotli_num_literal_symbols, 0)
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> Int raise @common.FbrError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    initial_previous_byte_1
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else if position == 1 {
    initial_previous_byte_1
  } else {
    initial_previous_byte_2
  }
  brotli_utf8_context_tree(
    @common.brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_command_literal_utf8_context_tree4(
  data : FixedArray[Byte],
  position : Int,
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> Int raise @common.FbrError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    initial_previous_byte_1
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else if position == 1 {
    initial_previous_byte_1
  } else {
    initial_previous_byte_2
  }
  brotli_utf8_context_tree4(
    @common.brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_command_literal_utf8_context_tree8(
  data : FixedArray[Byte],
  position : Int,
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> Int raise @common.FbrError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    initial_previous_byte_1
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else if position == 1 {
    initial_previous_byte_1
  } else {
    initial_previous_byte_2
  }
  brotli_utf8_context_tree8(
    @common.brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_command_literal_utf8_context_tree16(
  data : FixedArray[Byte],
  position : Int,
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> Int raise @common.FbrError {
  let previous_byte_1 = if position > 0 {
    data[position - 1].to_int()
  } else {
    initial_previous_byte_1
  }
  let previous_byte_2 = if position > 1 {
    data[position - 2].to_int()
  } else if position == 1 {
    initial_previous_byte_1
  } else {
    initial_previous_byte_2
  }
  brotli_utf8_context_tree16(
    @common.brotli_literal_context_id(2, previous_byte_1, previous_byte_2),
  )
}

///|
fn brotli_collect_command_literals_and_frequencies_by_utf8_context16(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise @common.FbrError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(16, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<16 {
    symbols.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(@common.brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree16(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise @common.FbrError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(8, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<8 {
    symbols.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(@common.brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree8(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise @common.FbrError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(4, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<4 {
    symbols.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(@common.brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree4(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> (Array[BrotliLiteralSet], Array[FixedArray[Int]])? raise @common.FbrError {
  let symbols : Array[FixedArray[Int]] = []
  let seen : Array[FixedArray[Bool]] = []
  let counts = FixedArray::make(2, 0)
  let frequencies : Array[FixedArray[Int]] = []
  for _ in 0..<2 {
    symbols.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
    seen.push(FixedArray::make(@common.brotli_num_literal_symbols, false))
    frequencies.push(FixedArray::make(@common.brotli_num_literal_symbols, 0))
  }
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let position = command.insert_start + j
      let tree = brotli_command_literal_utf8_context_tree(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
    first_frequencies, @common.brotli_huffman_max_code_length,
  )
  let (second_lengths, _) = h_tree(
    second_frequencies, @common.brotli_huffman_max_code_length,
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
  let alphabet = @common.brotli_num_literal_symbols
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
  let alphabet = @common.brotli_num_literal_symbols
  let total_offset = split_points.length() * alphabet
  let all_frequencies = FixedArray::make(alphabet, 0)
  for k in 0..<alphabet {
    all_frequencies[k] = snapshots[total_offset + k]
  }
  let (all_lengths, _) = h_tree(
    all_frequencies, @common.brotli_huffman_max_code_length,
  )
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
/// Snapshot command-symbol frequencies at candidate block boundaries. Row `i`
/// is the cumulative frequency before `split_points[i]`; the final row is the
/// complete command stream.
fn brotli_split_command_freq_snapshots(
  commands : Array[BrotliEncodeCommand],
  split_points : FixedArray[Int],
) -> FixedArray[Int] {
  let alphabet = @common.brotli_num_command_symbols
  let rows = split_points.length() + 1
  let snapshots = FixedArray::make(rows * alphabet, 0)
  let frequencies = FixedArray::make(alphabet, 0)
  let mut next_split_idx = 0
  for i in 0..<commands.length() {
    while next_split_idx < split_points.length() &&
          i == split_points[next_split_idx] {
      let row_offset = next_split_idx * alphabet
      for k in 0..<alphabet {
        snapshots[row_offset + k] = frequencies[k]
      }
      next_split_idx += 1
    }
    frequencies[commands[i].command.symbol] += 1
  }
  while next_split_idx < split_points.length() &&
        commands.length() >= split_points[next_split_idx] {
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
  snapshots
}

///|
fn brotli_histogram_payload_bits(frequencies : FixedArray[Int]) -> Int {
  let mut nonzero = 0
  for i in 0..<frequencies.length() {
    if frequencies[i] > 0 {
      nonzero += 1
      if nonzero > 1 {
        break
      }
    }
  }
  if nonzero <= 1 {
    return 0
  }
  let (lengths, _) = h_tree(frequencies, @common.brotli_huffman_max_code_length)
  if lengths.length() == 0 {
    0
  } else {
    clen(frequencies, lengths)
  }
}

///|
fn brotli_best_command_block_split_point(
  commands : Array[BrotliEncodeCommand],
) -> Int {
  if commands.length() < 64 {
    return 0
  }
  let split_points : FixedArray[Int] = [
    commands.length() / 4,
    commands.length() / 2,
    commands.length() * 3 / 4,
  ]
  let snapshots = brotli_split_command_freq_snapshots(commands, split_points)
  let alphabet = @common.brotli_num_command_symbols
  let total_offset = split_points.length() * alphabet
  let all_frequencies = FixedArray::make(alphabet, 0)
  for k in 0..<alphabet {
    all_frequencies[k] = snapshots[total_offset + k]
  }
  let single_bits = brotli_histogram_payload_bits(all_frequencies)
  let mut best_split = 0
  let mut best_saving = 384
  let first_frequencies = FixedArray::make(alphabet, 0)
  let second_frequencies = FixedArray::make(alphabet, 0)
  for i in 0..<split_points.length() {
    let split = split_points[i]
    if split <= 0 || split >= commands.length() {
      continue
    }
    let row_offset = i * alphabet
    for k in 0..<alphabet {
      first_frequencies[k] = snapshots[row_offset + k]
      second_frequencies[k] = all_frequencies[k] - first_frequencies[k]
    }
    let saving = single_bits -
      (
        brotli_histogram_payload_bits(first_frequencies) +
        brotli_histogram_payload_bits(second_frequencies)
      )
    if saving > best_saving {
      best_saving = saving
      best_split = split
    }
  }
  best_split
}

///|
fn brotli_command_distance_symbol_count(
  commands : Array[BrotliEncodeCommand],
) -> Int {
  let mut count = 0
  for i in 0..<commands.length() {
    if brotli_command_uses_distance_symbol(commands[i]) {
      count += 1
    }
  }
  count
}

///|
/// Snapshot explicit-distance frequencies at candidate distance-block
/// boundaries. Split points count only commands that actually read a distance
/// symbol; recent-distance short-code commands do not consume distance blocks.
fn brotli_split_distance_freq_snapshots(
  commands : Array[BrotliEncodeCommand],
  split_points : FixedArray[Int],
  distance_count : Int,
) -> FixedArray[Int] {
  let alphabet = @common.brotli_distance_alphabet_size(0, 0, 24)
  let rows = split_points.length() + 1
  let snapshots = FixedArray::make(rows * alphabet, 0)
  let frequencies = FixedArray::make(alphabet, 0)
  let mut next_split_idx = 0
  let mut distance_index = 0
  for i in 0..<commands.length() {
    if !brotli_command_uses_distance_symbol(commands[i]) {
      continue
    }
    while next_split_idx < split_points.length() &&
          distance_index == split_points[next_split_idx] {
      let row_offset = next_split_idx * alphabet
      for k in 0..<alphabet {
        snapshots[row_offset + k] = frequencies[k]
      }
      next_split_idx += 1
    }
    frequencies[commands[i].distance_prefix.symbol] += 1
    distance_index += 1
  }
  while next_split_idx < split_points.length() &&
        distance_count >= split_points[next_split_idx] {
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
  snapshots
}

///|
fn brotli_best_distance_block_split_point(
  commands : Array[BrotliEncodeCommand],
) -> Int {
  let distance_count = brotli_command_distance_symbol_count(commands)
  if distance_count < 64 {
    return 0
  }
  let split_points : FixedArray[Int] = [
    distance_count / 4,
    distance_count / 2,
    distance_count * 3 / 4,
  ]
  let snapshots = brotli_split_distance_freq_snapshots(
    commands, split_points, distance_count,
  )
  let alphabet = @common.brotli_distance_alphabet_size(0, 0, 24)
  let total_offset = split_points.length() * alphabet
  let all_frequencies = FixedArray::make(alphabet, 0)
  for k in 0..<alphabet {
    all_frequencies[k] = snapshots[total_offset + k]
  }
  let single_bits = brotli_histogram_payload_bits(all_frequencies)
  let mut best_split = 0
  let mut best_saving = 384
  let first_frequencies = FixedArray::make(alphabet, 0)
  let second_frequencies = FixedArray::make(alphabet, 0)
  for i in 0..<split_points.length() {
    let split = split_points[i]
    if split <= 0 || split >= distance_count {
      continue
    }
    let row_offset = i * alphabet
    for k in 0..<alphabet {
      first_frequencies[k] = snapshots[row_offset + k]
      second_frequencies[k] = all_frequencies[k] - first_frequencies[k]
    }
    let saving = single_bits -
      (
        brotli_histogram_payload_bits(first_frequencies) +
        brotli_histogram_payload_bits(second_frequencies)
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
  //   @common.brotli_command_info(command.command.symbol).distance_code < 0
  // distance_code is < 0 iff cell_index (symbol >> 6) >= 2, i.e. symbol >= 128.
  // Avoids the per-command @common.brotli_prefix_offset linear sums when only the
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
) -> BrotliCommandPrefix raise @common.FbrError {
  if distance <= 0 {
    raise @common.fbr_err(
      @common.BrotliInvalidDistance,
      msg="invalid Brotli distance",
    )
  }
  let extra_bits = @common.brotli_log2_floor_plus_one(distance + 3) - 2
  let split = 3 << extra_bits
  let half = if distance + 4 <= split { 0 } else { 1 }
  let offset = if half == 0 { (2 << extra_bits) - 3 } else { split - 3 }
  let symbol = @common.brotli_num_distance_short_codes +
    (extra_bits - 1) * 2 +
    half
  if symbol < @common.brotli_num_distance_short_codes ||
    symbol >= @common.brotli_distance_alphabet_size(0, 0, 24) {
    raise @common.fbr_err(
      @common.BrotliInvalidDistance,
      msg="no Brotli distance prefix",
    )
  }
  {
    symbol,
    insert_extra: distance - offset,
    copy_extra: 0,
    insert_extra_bits: extra_bits,
    copy_extra_bits: 0,
  }
}

///|
fn brotli_distance_prefix_for_code(
  distance_code : Int,
) -> BrotliCommandPrefix raise @common.FbrError {
  if distance_code < 0 {
    raise @common.fbr_err(
      @common.BrotliInvalidDistance,
      msg="negative Brotli distance code",
    )
  }
  if distance_code < @common.brotli_num_distance_short_codes {
    return {
      symbol: distance_code,
      insert_extra: 0,
      copy_extra: 0,
      insert_extra_bits: 0,
      copy_extra_bits: 0,
    }
  }
  brotli_distance_prefix_for_distance(
    distance_code - @common.brotli_num_distance_short_codes + 1,
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
  distance + @common.brotli_num_distance_short_codes - 1
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
let brotli_command_prefix_code_count = 24

///|
fn brotli_command_prefix_table_index(
  mode : Int,
  insert_code : Int,
  copy_code : Int,
) -> Int {
  (mode * brotli_command_prefix_code_count + insert_code) *
  brotli_command_prefix_code_count +
  copy_code
}

///|
let brotli_command_prefix_table : FixedArray[Int] = {
  let code_count = brotli_command_prefix_code_count
  let table = FixedArray::make(3 * code_count * code_count, -1)
  for symbol in 0..<@common.brotli_num_command_symbols {
    let cell_index = symbol >> 6
    let cell_pos = @common.brotli_command_cell_pos[cell_index]
    let copy_code = ((cell_pos << 3) & 0x18) + (symbol & 0x7)
    let insert_code = (cell_pos & 0x18) + ((symbol >> 3) & 0x7)
    let mode = if cell_index >= 2 { 1 } else { 0 }
    let index = brotli_command_prefix_table_index(mode, insert_code, copy_code)
    if table[index] < 0 {
      table[index] = symbol
    }
    let insert_only_index = brotli_command_prefix_table_index(
      2, insert_code, copy_code,
    )
    if table[insert_only_index] < 0 {
      table[insert_only_index] = symbol
    }
  }
  table
}

///|
fn brotli_prefix_code_for_length(
  extra_bits : FixedArray[Int],
  initial : Int,
  length : Int,
) -> (Int, Int, Int)? {
  let mut offset = initial
  for code in 0..<extra_bits.length() {
    let bits = extra_bits[code]
    let limit = offset + (1 << bits)
    if length >= offset && length < limit {
      return Some((code, bits, length - offset))
    }
    offset = limit
  }
  None
}

///|
fn brotli_command_prefix_for_mode(
  insert_length : Int,
  copy_length : Int,
  mode : Int,
) -> BrotliCommandPrefix raise @common.FbrError {
  match
    (
      brotli_prefix_code_for_length(
        @common.brotli_insert_length_extra_bits, 0, insert_length,
      ),
      brotli_prefix_code_for_length(
        @common.brotli_copy_length_extra_bits, 2, copy_length,
      ),
    ) {
    (
      Some((insert_code, insert_bits, insert_extra)),
      Some((copy_code, copy_bits, copy_extra)),
    ) => {
      let symbol = brotli_command_prefix_table[brotli_command_prefix_table_index(
          mode, insert_code, copy_code,
        )]
      if symbol >= 0 {
        return {
          symbol,
          insert_extra,
          copy_extra,
          insert_extra_bits: insert_bits,
          copy_extra_bits: copy_bits,
        }
      }
    }
    _ => ()
  }
  raise @common.fbr_err(
    @common.BrotliInvalidMetablock,
    msg="no Brotli command prefix",
  )
}

///|
fn brotli_find_command_prefix(
  insert_length : Int,
  copy_length : Int,
  explicit_distance : Bool,
) -> BrotliCommandPrefix raise @common.FbrError {
  brotli_command_prefix_for_mode(
    insert_length,
    copy_length,
    if explicit_distance {
      1
    } else {
      0
    },
  )
}

///|
fn brotli_find_insert_only_command_prefix(
  insert_length : Int,
) -> BrotliCommandPrefix raise @common.FbrError {
  brotli_command_prefix_for_mode(insert_length, 2, 2)
}

///|
fn brotli_make_encode_command_with_distance_mode(
  insert_start : Int,
  insert_length : Int,
  copy_length : Int,
  distance : Int,
  has_copy : Bool,
  explicit_distance : Bool,
) -> BrotliEncodeCommand raise @common.FbrError {
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
) -> BrotliEncodeCommand raise @common.FbrError {
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
  let result : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_encode_command_with_distance_code(
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
  let result : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_encode_command_with_distance_mode(
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
) -> BrotliEncodeCommand raise @common.FbrError {
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
) -> BrotliEncodeCommand raise @common.FbrError {
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
  let frequencies = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  for i in 0..<data.length() {
    frequencies[data[i].to_int()] += 1
  }
  let (code_lengths, _) = h_tree(
    frequencies, @common.brotli_huffman_max_code_length,
  )
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
  let command_result : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_encode_command(
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
) -> BrotliCommandPrefix raise @common.FbrError {
  for symbol in 0..<@common.brotli_num_block_length_symbols {
    let extra_bits = @common.brotli_block_length_extra_bits[symbol]
    let extra = length - @common.brotli_block_length_bases[symbol]
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
  raise @common.fbr_err(
    @common.BrotliInvalidMetablock,
    msg="invalid Brotli block length",
  )
}

///|
fn brotli_write_two_block_header(
  writer : BrotliBitWriter,
  first_length : Int,
  second_length : Int,
) -> (BrotliHuffmanSpec, BrotliCommandPrefix, BrotliCommandPrefix) raise @common.FbrError {
  let first_prefix = brotli_block_length_prefix(first_length)
  let second_prefix = brotli_block_length_prefix(second_length)
  let length_symbols = FixedArray::make(
    @common.brotli_num_block_length_symbols, 0,
  )
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
    length_symbols, length_count, @common.brotli_num_block_length_symbols, @common.brotli_num_block_length_symbols,
  )
  brotli_write_var_len_uint8(writer, 1) // two block types
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
) -> Unit raise @common.FbrError {
  brotli_write_var_len_uint8(writer, 1) // two literal trees
  writer.write_bits(1, 1) // use RLEMAX
  writer.write_bits(4, @common.brotli_literal_context_bits - 2)
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
fn brotli_write_trivial_two_distance_context_map(
  writer : BrotliBitWriter,
) -> Unit raise @common.FbrError {
  brotli_write_var_len_uint8(writer, 1) // two distance trees
  writer.write_bits(1, 0) // no RLE prefix
  let symbols : FixedArray[Int] = [0, 1]
  let spec = brotli_make_huffman_spec(symbols, 2, 2, 2)
  brotli_write_huffman_spec(writer, spec)
  let payloads = brotli_huffman_payload_table(spec)
  let contexts_per_block = 1 << @common.brotli_distance_context_bits
  for context in 0..<(contexts_per_block * 2) {
    let tree = if context < contexts_per_block { 0 } else { 1 }
    let payload = payloads[tree]
    writer.write_bits(payload.insert_extra_bits, payload.insert_extra)
  }
  writer.write_bits(1, 0) // no inverse move-to-front
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
) -> Unit raise @common.FbrError {
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
) -> Unit raise @common.FbrError {
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
) -> Unit raise @common.FbrError {
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
) -> Unit raise @common.FbrError {
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
) -> BrotliBitWriter? raise @common.FbrError {
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
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let command_symbols : FixedArray[Int] = [command.command.symbol]
  let command_spec = brotli_make_huffman_spec(
    command_symbols, 1, @common.brotli_num_command_symbols, @common.brotli_num_command_symbols,
  )
  let distance_symbols : FixedArray[Int] = [0]
  let distance_spec = brotli_make_huffman_spec(
    distance_symbols,
    1,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(256 + data.length() * 4)
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  let (length_spec, _, second_prefix) = brotli_write_two_block_header(
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
) -> BrotliBitWriter? raise @common.FbrError {
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
fn brotli_build_simple_lz77_command_candidate(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  distance_cache : FixedArray[Int],
) -> BrotliCommandCandidate? {
  // Every exact-costed chunk candidate must start from the decoder state that
  // exists before this meta-block. Only the winner's terminal cache is later
  // committed to the outer stream.
  let chunk_cache = brotli_copy_distance_cache(distance_cache)
  match
    brotli_build_simple_lz77_commands_with_distance_cache(
      data, hash_config, chunk_cache,
    ) {
    Some(commands) => Some({ commands, distance_cache: chunk_cache })
    None => None
  }
}

///|
fn brotli_wrap_command_candidate(
  commands : Array[BrotliEncodeCommand]?,
  distance_cache : FixedArray[Int],
) -> BrotliCommandCandidate? {
  match commands {
    Some(commands) =>
      Some({
        commands,
        distance_cache: brotli_copy_distance_cache(distance_cache),
      })
    None => None
  }
}

///|
fn brotli_build_simple_lz77_commands_with_distance_cache(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  distance_cache : FixedArray[Int],
) -> Array[BrotliEncodeCommand]? {
  if data.length() < 8 ||
    data.length() > brotli_hash_max_input_length(hash_config) {
    return None
  }
  if !brotli_has_compressible_match_density(data, hash_config) {
    return None
  }
  let commands : Array[BrotliEncodeCommand] = []
  let max_commands = brotli_effective_max_commands(hash_config, data.length())
  let previous = brotli_previous_match_positions(data, hash_config)
  let mut literal_start = 0
  let mut position = 0
  // Lazy-match carry-forward: when the lookahead defers to `position + skip`,
  // no command is emitted before we resume there, so `distance_cache` is
  // unchanged and the match `brotli_longest_previous_hash_match_with_cache`
  // already computed for that position is exactly what a fresh search would
  // return. Carry it forward instead of re-searching the deferred position.
  let mut have_carried = false
  let mut carried_length = 0
  let mut carried_distance = 0
  while position < data.length() {
    let (match_length, distance) = if have_carried {
      have_carried = false
      (carried_length, carried_distance)
    } else {
      brotli_longest_previous_hash_match_with_cache(
        data, previous, position, hash_config, distance_cache,
      )
    }
    if match_length >= hash_config.min_match_length {
      let lookahead = hash_config.lazy_lookahead
      if lookahead > 0 {
        let mut k = 1
        let mut skip = 0
        let mut skip_length = 0
        let mut skip_distance = 0
        while k <= lookahead && position + k < data.length() {
          let (next_length, next_distance) = brotli_longest_previous_hash_match_with_cache(
            data,
            previous,
            position + k,
            hash_config,
            distance_cache,
          )
          if next_length > match_length {
            skip = k
            skip_length = next_length
            skip_distance = next_distance
            break
          }
          k += 1
        }
        if skip > 0 {
          position += skip
          carried_length = skip_length
          carried_distance = skip_distance
          have_carried = true
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
              // The implicit distance-0 command family cannot represent every
              // insert/copy length. When we fall back to an explicit distance
              // symbol, advance the cache as the decoder will see it.
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
  if literal_start < data.length() {
    let final_result : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_encode_command(
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
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
    if command_count > @common.brotli_num_command_symbols {
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
priv struct BrotliBoundedShortestPathCostModel {
  literal_bits : FixedArray[Int]
  distance_bits : FixedArray[Int]
}

///|
fn brotli_bounded_shortest_path_bits_from_frequencies(
  frequencies : FixedArray[Int],
  default_bits : Int,
) -> FixedArray[Int] {
  let bits = FixedArray::make(frequencies.length(), default_bits)
  let mut nonzero = 0
  let mut only_symbol = 0
  for i in 0..<frequencies.length() {
    if frequencies[i] > 0 {
      nonzero += 1
      only_symbol = i
    }
  }
  if nonzero == 0 {
    return bits
  }
  if nonzero == 1 {
    bits[only_symbol] = 0
    return bits
  }
  let (lengths, _) = h_tree(frequencies, @common.brotli_huffman_max_code_length)
  if lengths.length() == 0 {
    return bits
  }
  for i in 0..<lengths.length() {
    if lengths[i].to_int() > 0 {
      bits[i] = lengths[i].to_int()
    }
  }
  bits
}

///|
fn brotli_bounded_shortest_path_default_cost_model() -> BrotliBoundedShortestPathCostModel {
  {
    literal_bits: FixedArray::make(@common.brotli_num_literal_symbols, 8),
    distance_bits: FixedArray::make(
      @common.brotli_distance_alphabet_size(0, 0, 24),
      6,
    ),
  }
}

///|
fn brotli_bounded_shortest_path_cost_model_from_commands(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
) -> BrotliBoundedShortestPathCostModel {
  let literal_frequencies = FixedArray::make(
    @common.brotli_num_literal_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      literal_frequencies[data[command.insert_start + j].to_int()] += 1
    }
    if brotli_command_uses_distance_symbol(command) {
      distance_frequencies[command.distance_prefix.symbol] += 1
    }
  }
  {
    literal_bits: brotli_bounded_shortest_path_bits_from_frequencies(
      literal_frequencies, 8,
    ),
    distance_bits: brotli_bounded_shortest_path_bits_from_frequencies(
      distance_frequencies, 6,
    ),
  }
}

///|
fn brotli_bounded_shortest_path_cost_model(
  data : FixedArray[Byte],
  config : BrotliHashConfig,
  distance_cache : FixedArray[Int],
) -> BrotliBoundedShortestPathCostModel {
  let greedy_cache = brotli_copy_distance_cache(distance_cache)
  match
    brotli_build_simple_lz77_commands_with_distance_cache(
      data, config, greedy_cache,
    ) {
    Some(commands) =>
      brotli_bounded_shortest_path_cost_model_from_commands(data, commands)
    None => brotli_bounded_shortest_path_default_cost_model()
  }
}

///|
fn brotli_bounded_shortest_path_copy_cost(
  length : Int,
  distance : Int,
  position : Int,
  distance_cache : FixedArray[Int],
  model : BrotliBoundedShortestPathCostModel,
) -> Int {
  // This is a parser heuristic, not the final cost. The chosen command list is
  // still written and compared by the exact meta-block writer before use.
  let distance_code = brotli_compute_distance_code(
    distance, position, distance_cache,
  )
  let distance_bits = if distance_code == 0 {
    0
  } else {
    match
      (
        try? brotli_distance_prefix_for_code(distance_code) :
        Result[BrotliCommandPrefix, @common.FbrError]) {
      Ok(prefix) =>
        model.distance_bits[prefix.symbol] + prefix.insert_extra_bits
      Err(_) => 24
    }
  }
  let length_extra_bits = match length {
    0..=10 => 0
    11..=14 => 1
    15..=18 => 2
    19..=26 => 3
    27..=38 => 4
    39..=54 => 5
    55..=70 => 6
    71..=102 => 7
    103..=134 => 8
    135..=198 => 9
    199..=326 => 10
    327..=582 => 11
    583..=1094 => 12
    1095..=2118 => 13
    _ => 14
  }
  8 + length_extra_bits + distance_bits
}

///|
fn brotli_bounded_shortest_path_config(
  config : BrotliHashConfig,
) -> BrotliHashConfig {
  {
    table_size: config.table_size,
    table_mask: config.table_mask,
    hash_bytes: config.hash_bytes,
    max_match_checks: if config.max_match_checks > 32 {
      32
    } else {
      config.max_match_checks
    },
    max_match_length: if config.max_match_length > 4096 {
      4096
    } else {
      config.max_match_length
    },
    min_match_length: config.min_match_length,
    max_distance_cache_codes: config.max_distance_cache_codes,
    lazy_lookahead: 0,
    scan_step: 1,
    max_commands: 12000,
    max_input_length: 32768,
    min_copy_ratio_percent: 8,
    require_dense_match_density: false,
    density_sample_step: config.density_sample_step,
    density_required_numerator: config.density_required_numerator,
    density_required_denominator: config.density_required_denominator,
  }
}

///|
let brotli_bounded_shortest_path_beam_width = 2

///|
fn brotli_bounded_shortest_path_state_index(position : Int, slot : Int) -> Int {
  position * brotli_bounded_shortest_path_beam_width + slot
}

///|
fn brotli_bounded_shortest_path_store_state(
  costs : FixedArray[Int],
  state_cache0 : FixedArray[Int],
  state_cache1 : FixedArray[Int],
  state_cache2 : FixedArray[Int],
  state_cache3 : FixedArray[Int],
  previous_position : FixedArray[Int],
  previous_slot : FixedArray[Int],
  choice_copy_length : FixedArray[Int],
  choice_copy_distance : FixedArray[Int],
  choice_copy_output_length : FixedArray[Int],
  index : Int,
  cost : Int,
  cache : FixedArray[Int],
  from_position : Int,
  from_slot : Int,
  copy_length : Int,
  copy_distance : Int,
  copy_output_length : Int,
) -> Unit {
  costs[index] = cost
  state_cache0[index] = cache[0]
  state_cache1[index] = cache[1]
  state_cache2[index] = cache[2]
  state_cache3[index] = cache[3]
  previous_position[index] = from_position
  previous_slot[index] = from_slot
  choice_copy_length[index] = copy_length
  choice_copy_distance[index] = copy_distance
  choice_copy_output_length[index] = copy_output_length
}

///|
fn brotli_bounded_shortest_path_offer_state(
  costs : FixedArray[Int],
  state_cache0 : FixedArray[Int],
  state_cache1 : FixedArray[Int],
  state_cache2 : FixedArray[Int],
  state_cache3 : FixedArray[Int],
  previous_position : FixedArray[Int],
  previous_slot : FixedArray[Int],
  choice_copy_length : FixedArray[Int],
  choice_copy_distance : FixedArray[Int],
  choice_copy_output_length : FixedArray[Int],
  position : Int,
  cost : Int,
  cache : FixedArray[Int],
  from_position : Int,
  from_slot : Int,
  copy_length : Int,
  copy_distance : Int,
  copy_output_length : Int,
) -> Unit {
  let first = brotli_bounded_shortest_path_state_index(position, 0)
  let second = brotli_bounded_shortest_path_state_index(position, 1)
  if cost < costs[first] {
    costs[second] = costs[first]
    state_cache0[second] = state_cache0[first]
    state_cache1[second] = state_cache1[first]
    state_cache2[second] = state_cache2[first]
    state_cache3[second] = state_cache3[first]
    previous_position[second] = previous_position[first]
    previous_slot[second] = previous_slot[first]
    choice_copy_length[second] = choice_copy_length[first]
    choice_copy_distance[second] = choice_copy_distance[first]
    choice_copy_output_length[second] = choice_copy_output_length[first]
    brotli_bounded_shortest_path_store_state(
      costs, state_cache0, state_cache1, state_cache2, state_cache3, previous_position,
      previous_slot, choice_copy_length, choice_copy_distance, choice_copy_output_length,
      first, cost, cache, from_position, from_slot, copy_length, copy_distance, copy_output_length,
    )
  } else if cost < costs[second] {
    brotli_bounded_shortest_path_store_state(
      costs, state_cache0, state_cache1, state_cache2, state_cache3, previous_position,
      previous_slot, choice_copy_length, choice_copy_distance, choice_copy_output_length,
      second, cost, cache, from_position, from_slot, copy_length, copy_distance,
      copy_output_length,
    )
  }
}

///|
fn brotli_bounded_shortest_path_offer_matches(
  matches : Array[BrotliHashMatchCandidate],
  len : Int,
  position : Int,
  slot : Int,
  base_cost : Int,
  current_cache : FixedArray[Int],
  config : BrotliHashConfig,
  cost_model : BrotliBoundedShortestPathCostModel,
  costs : FixedArray[Int],
  state_cache0 : FixedArray[Int],
  state_cache1 : FixedArray[Int],
  state_cache2 : FixedArray[Int],
  state_cache3 : FixedArray[Int],
  previous_position : FixedArray[Int],
  previous_slot : FixedArray[Int],
  choice_copy_length : FixedArray[Int],
  choice_copy_distance : FixedArray[Int],
  choice_copy_output_length : FixedArray[Int],
) -> Unit {
  for match_index in 0..<matches.length() {
    let match_ = matches[match_index]
    if match_.length < config.min_match_length {
      continue
    }
    // Keep the DP bounded: several previous matches per position, and only a
    // few representative copy lengths for each match. This grows the P4
    // candidate graph without taking on full Zopfli search cost.
    let bounded_lengths : FixedArray[Int] = [
      config.min_match_length,
      match_.length / 2,
      match_.length,
    ]
    for i in 0..<bounded_lengths.length() {
      let copy_length = bounded_lengths[i]
      if copy_length < config.min_match_length ||
        copy_length > match_.length ||
        position + copy_length > len {
        continue
      }
      let end = position + copy_length
      let copy_cost = base_cost +
        brotli_bounded_shortest_path_copy_cost(
          copy_length,
          match_.distance,
          position,
          current_cache,
          cost_model,
        )
      let next_cache = brotli_copy_distance_cache(current_cache)
      let distance_code = brotli_compute_distance_code(
        match_.distance,
        position,
        next_cache,
      )
      brotli_update_distance_cache(next_cache, match_.distance, distance_code)
      brotli_bounded_shortest_path_offer_state(
        costs,
        state_cache0,
        state_cache1,
        state_cache2,
        state_cache3,
        previous_position,
        previous_slot,
        choice_copy_length,
        choice_copy_distance,
        choice_copy_output_length,
        end,
        copy_cost,
        next_cache,
        position,
        slot,
        copy_length,
        match_.distance,
        0,
      )
    }
  }
}

///|
fn brotli_build_bounded_shortest_path_command_candidate(
  data : FixedArray[Byte],
  hash_config : BrotliHashConfig,
  base_offset : Int,
  window_bits : Int,
  distance_cache : FixedArray[Int],
) -> BrotliCommandCandidate? {
  let config = brotli_bounded_shortest_path_config(hash_config)
  if data.length() < config.min_match_length ||
    data.length() > config.max_input_length {
    return None
  }
  let len = data.length()
  let previous = brotli_previous_match_positions(data, config)
  let suffix_matches = brotli_bounded_suffix_tree_match_table(data, config)
  let index = brotli_build_dictionary_encode_index_min_output(8)
  let cost_model = brotli_bounded_shortest_path_cost_model(
    data, config, distance_cache,
  )
  let unreachable_cost = len * 16 + 1_000_000
  let state_count = (len + 1) * brotli_bounded_shortest_path_beam_width
  let costs = FixedArray::make(state_count, unreachable_cost)
  let state_cache0 = FixedArray::make(state_count, distance_cache[0])
  let state_cache1 = FixedArray::make(state_count, distance_cache[1])
  let state_cache2 = FixedArray::make(state_count, distance_cache[2])
  let state_cache3 = FixedArray::make(state_count, distance_cache[3])
  let previous_position = FixedArray::make(state_count, -1)
  let previous_slot = FixedArray::make(state_count, -1)
  let choice_copy_length = FixedArray::make(state_count, 0)
  let choice_copy_distance = FixedArray::make(state_count, 0)
  let choice_copy_output_length = FixedArray::make(state_count, 0)
  costs[brotli_bounded_shortest_path_state_index(0, 0)] = 0
  for position in 0..<len {
    for slot in 0..<brotli_bounded_shortest_path_beam_width {
      let state_index = brotli_bounded_shortest_path_state_index(position, slot)
      let base_cost = costs[state_index]
      if base_cost >= unreachable_cost {
        continue
      }
      let current_cache : FixedArray[Int] = [
        state_cache0[state_index],
        state_cache1[state_index],
        state_cache2[state_index],
        state_cache3[state_index],
      ]
      brotli_bounded_shortest_path_offer_state(
        costs,
        state_cache0,
        state_cache1,
        state_cache2,
        state_cache3,
        previous_position,
        previous_slot,
        choice_copy_length,
        choice_copy_distance,
        choice_copy_output_length,
        position + 1,
        base_cost + cost_model.literal_bits[data[position].to_int()],
        current_cache,
        position,
        slot,
        0,
        0,
        0,
      )
      let matches = brotli_bounded_previous_hash_matches_with_cache(
        data, previous, position, config, current_cache,
      )
      brotli_bounded_shortest_path_offer_matches(
        matches, len, position, slot, base_cost, current_cache, config, cost_model,
        costs, state_cache0, state_cache1, state_cache2, state_cache3, previous_position,
        previous_slot, choice_copy_length, choice_copy_distance, choice_copy_output_length,
      )
      brotli_bounded_shortest_path_offer_matches(
        suffix_matches[position],
        len,
        position,
        slot,
        base_cost,
        current_cache,
        config,
        cost_model,
        costs,
        state_cache0,
        state_cache1,
        state_cache2,
        state_cache3,
        previous_position,
        previous_slot,
        choice_copy_length,
        choice_copy_distance,
        choice_copy_output_length,
      )
      let is_word_start = brotli_dictionary_word_byte(data[position]) &&
        (position == 0 || !brotli_dictionary_word_byte(data[position - 1]))
      if is_word_start {
        match
          brotli_find_identity_dictionary_match(
            index,
            data,
            position,
            base_offset + position,
            window_bits,
          ) {
          Some((word_length, output_length, dictionary_distance)) =>
            if position + output_length <= len {
              let copy_cost = base_cost +
                brotli_bounded_shortest_path_copy_cost(
                  word_length, dictionary_distance, position, current_cache, cost_model,
                )
              brotli_bounded_shortest_path_offer_state(
                costs,
                state_cache0,
                state_cache1,
                state_cache2,
                state_cache3,
                previous_position,
                previous_slot,
                choice_copy_length,
                choice_copy_distance,
                choice_copy_output_length,
                position + output_length,
                copy_cost,
                current_cache,
                position,
                slot,
                word_length,
                dictionary_distance,
                output_length,
              )
            }
          None => ()
        }
      }
    }
  }
  let mut terminal_slot = 0
  let terminal0 = brotli_bounded_shortest_path_state_index(len, 0)
  let terminal1 = brotli_bounded_shortest_path_state_index(len, 1)
  if costs[terminal1] < costs[terminal0] {
    terminal_slot = 1
  }
  let terminal_index = brotli_bounded_shortest_path_state_index(
    len, terminal_slot,
  )
  if costs[terminal_index] >= unreachable_cost {
    return None
  }
  let segment_starts : Array[Int] = []
  let segment_lengths : Array[Int] = []
  let segment_distances : Array[Int] = []
  let segment_output_lengths : Array[Int] = []
  let mut position = len
  let mut slot = terminal_slot
  while position > 0 {
    let state_index = brotli_bounded_shortest_path_state_index(position, slot)
    let copy_length = choice_copy_length[state_index]
    let from_position = previous_position[state_index]
    let from_slot = previous_slot[state_index]
    if from_position < 0 || from_slot < 0 {
      return None
    }
    if copy_length > 0 {
      let start = from_position
      segment_starts.push(start)
      segment_lengths.push(copy_length)
      segment_distances.push(choice_copy_distance[state_index])
      segment_output_lengths.push(choice_copy_output_length[state_index])
    }
    position = from_position
    slot = from_slot
  }
  if segment_lengths.length() == 0 ||
    segment_lengths.length() > config.max_commands {
    return None
  }
  let commands : Array[BrotliEncodeCommand] = []
  let candidate_cache = brotli_copy_distance_cache(distance_cache)
  let mut literal_start = 0
  let mut copy_bytes = 0
  let mut index = segment_lengths.length()
  while index > 0 {
    index -= 1
    let copy_start = segment_starts[index]
    let copy_length = segment_lengths[index]
    let distance = segment_distances[index]
    let copy_output_length = segment_output_lengths[index]
    let insert_length = copy_start - literal_start
    let output_length = if copy_output_length > 0 {
      copy_output_length
    } else {
      copy_length
    }
    let command = if copy_output_length > 0 {
      let cmd_res : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_dictionary_encode_command(
        literal_start, insert_length, copy_length, output_length, distance,
      )
      match cmd_res {
        Ok(cmd) => cmd
        Err(_) => return None
      }
    } else {
      let distance_code = brotli_compute_distance_code(
        distance, copy_start, candidate_cache,
      )
      let mut emitted_distance_code = distance_code
      let cmd = match
        brotli_try_make_encode_command_with_distance_code(
          literal_start, insert_length, copy_length, distance, distance_code,
        ) {
        Some(command) => command
        None =>
          match
            brotli_try_make_encode_command_with_distance_mode(
              literal_start, insert_length, copy_length, distance, true, true,
            ) {
            Some(command) => {
              emitted_distance_code = command.distance_prefix.symbol
              command
            }
            None => return None
          }
      }
      brotli_update_distance_cache(
        candidate_cache, distance, emitted_distance_code,
      )
      cmd
    }
    commands.push(command)
    copy_bytes += output_length
    literal_start = copy_start + output_length
  }
  if literal_start < len {
    let final_result : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_encode_command(
      literal_start,
      len - literal_start,
      0,
      0,
      false,
    )
    match final_result {
      Ok(command) => commands.push(command)
      Err(_) => return None
    }
  }
  if copy_bytes * 100 < len * config.min_copy_ratio_percent {
    return None
  }
  Some({ commands, distance_cache: candidate_cache })
}

///|
fn brotli_encode_single_copy_match(
  data : FixedArray[Byte],
  opts : BrotliOptions,
  match_ : BrotliSingleCopyMatch,
) -> FixedArray[Byte] raise @common.FbrError {
  let command = brotli_find_command_prefix(
    match_.insert_length,
    match_.copy_length,
    true,
  )
  let distance = brotli_distance_prefix_for_distance(match_.distance)
  let literal_spec = brotli_make_huffman_spec(
    match_.literal_symbols,
    match_.literal_symbol_count,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
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
fn brotli_encode_prefix_stored_single_copy_match(
  data : FixedArray[Byte],
  opts : BrotliOptions,
  match_ : BrotliSingleCopyMatch,
) -> FixedArray[Byte]? raise @common.FbrError {
  if match_.insert_length <= 0 || match_.copy_length <= 0 {
    return None
  }
  let command_result : Result[BrotliEncodeCommand, @common.FbrError] = try? brotli_make_encode_command(
    0,
    0,
    match_.copy_length,
    match_.distance,
    true,
  )
  let command = match command_result {
    Ok(command) => command
    Err(_) => return None
  }
  let commands : Array[BrotliEncodeCommand] = []
  commands.push(command)
  let suffix = @common.slc(data, match_.insert_length, e=data.length())
  let body = BrotliBitWriter::new(
    128 + suffix.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(body, suffix, commands, true, true)
  let writer = BrotliBitWriter::new(data.length() + 32 + body.buf.length())
  brotli_encode_window_bits(writer, opts.window_bits)
  brotli_write_uncompressed_metablock(writer, data, 0, match_.insert_length)
  writer.write_from_bits(body.buf, body.bit_pos)
  Some(writer.finish())
}

///|
fn brotli_write_simple_lz77_metablock(
  writer : BrotliBitWriter,
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
  weighted : Bool,
) -> Unit raise @common.FbrError {
  // Single-pass literal collection + frequency tally.
  let literal_symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let literal_seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
  let literal_frequencies = FixedArray::make(
    @common.brotli_num_literal_symbols, 0,
  )
  let mut literal_count = 0
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
      literal_symbols, literal_count, literal_frequencies, @common.brotli_num_literal_symbols,
      @common.brotli_num_literal_symbols,
    )
  } else {
    brotli_make_huffman_spec(
      literal_symbols, literal_count, @common.brotli_num_literal_symbols, @common.brotli_num_literal_symbols,
    )
  }
  let command_spec = if weighted {
    brotli_make_weighted_huffman_spec(
      command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
      @common.brotli_num_command_symbols,
    )
  } else {
    brotli_make_huffman_spec(
      command_symbols, command_count, @common.brotli_num_command_symbols, @common.brotli_num_command_symbols,
    )
  }
  let distance_spec = if weighted {
    brotli_make_weighted_huffman_spec(
      distance_symbols,
      distance_count,
      distance_frequencies,
      @common.brotli_distance_alphabet_size(0, 0, 24),
      @common.brotli_distance_alphabet_size(0, 0, 24),
    )
  } else {
    brotli_make_huffman_spec(
      distance_symbols,
      distance_count,
      @common.brotli_distance_alphabet_size(0, 0, 24),
      @common.brotli_distance_alphabet_size(0, 0, 24),
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
) -> BrotliBitWriter? raise @common.FbrError {
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
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_frequencies = brotli_command_literal_frequencies_range(
    data, commands, 0, split,
  )
  let second_frequencies = brotli_command_literal_frequencies_range(
    data, commands, split, literal_count,
  )
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  let (length_spec, _, second_prefix) = brotli_write_two_block_header(
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
fn brotli_write_command_split_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise @common.FbrError {
  if split <= 0 || split >= commands.length() {
    return None
  }
  let literal_symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let literal_seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
  let literal_frequencies = FixedArray::make(
    @common.brotli_num_literal_symbols, 0,
  )
  let first_command_symbols = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let second_command_symbols = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let second_command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut literal_count = 0
  let mut first_command_count = 0
  let mut second_command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let literal = data[command.insert_start + j].to_int()
      literal_frequencies[literal] += 1
      if !literal_seen[literal] {
        literal_seen[literal] = true
        literal_symbols[literal_count] = literal
        literal_count += 1
      }
    }
    let command_symbol = command.command.symbol
    if i < split {
      first_command_frequencies[command_symbol] += 1
      first_command_count = brotli_add_unique_symbol(
        first_command_symbols, first_command_count, command_symbol,
      )
    } else {
      second_command_frequencies[command_symbol] += 1
      second_command_count = brotli_add_unique_symbol(
        second_command_symbols, second_command_count, command_symbol,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_symbol = command.distance_prefix.symbol
      distance_frequencies[distance_symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols, distance_count, distance_symbol,
      )
    }
  }
  if first_command_count == 0 || second_command_count == 0 {
    return None
  }
  if literal_count == 0 {
    literal_symbols[0] = 0
    literal_count = 1
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let literal_spec = brotli_make_weighted_huffman_spec(
    literal_symbols, literal_count, literal_frequencies, @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let first_command_spec = brotli_make_weighted_huffman_spec(
    first_command_symbols, first_command_count, first_command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let second_command_spec = brotli_make_weighted_huffman_spec(
    second_command_symbols, second_command_count, second_command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  let (length_spec, _, second_prefix) = brotli_write_two_block_header(
    writer,
    split,
    commands.length() - split,
  )
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 literal context mode
  writer.write_bits(1, 0) // literal context map has one tree
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, literal_spec)
  brotli_write_huffman_spec(writer, first_command_spec)
  brotli_write_huffman_spec(writer, second_command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let literal_payloads = brotli_huffman_payload_table(literal_spec)
  let first_command_payloads = brotli_huffman_payload_table(first_command_spec)
  let second_command_payloads = brotli_huffman_payload_table(
    second_command_spec,
  )
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  let length_payloads = brotli_huffman_payload_table(length_spec)
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  let second_length_payload = length_payloads[second_prefix.symbol]
  for i in 0..<commands.length() {
    let command = commands[i]
    if i == split {
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
    }
    let command_payload = if i < split {
      first_command_payloads[command.command.symbol]
    } else {
      second_command_payloads[command.command.symbol]
    }
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
  Some(writer)
}

///|
fn brotli_write_literal_command_split_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  literal_split : Int,
  command_split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise @common.FbrError {
  let literal_total = brotli_command_literal_count(commands)
  if literal_split <= 0 ||
    literal_split >= literal_total ||
    command_split <= 0 ||
    command_split >= commands.length() {
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
    brotli_collect_command_literals_range(data, commands, 0, literal_split) {
    Some(literals) => literals
    None => return None
  }
  let second_literals = match
    brotli_collect_command_literals_range(
      data, commands, literal_split, literal_total,
    ) {
    Some(literals) => literals
    None => return None
  }
  let first_literal_frequencies = brotli_command_literal_frequencies_range(
    data, commands, 0, literal_split,
  )
  let second_literal_frequencies = brotli_command_literal_frequencies_range(
    data, commands, literal_split, literal_total,
  )
  let first_command_symbols = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let second_command_symbols = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let second_command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut first_command_count = 0
  let mut second_command_count = 0
  let mut distance_count = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    let command_symbol = command.command.symbol
    if i < command_split {
      first_command_frequencies[command_symbol] += 1
      first_command_count = brotli_add_unique_symbol(
        first_command_symbols, first_command_count, command_symbol,
      )
    } else {
      second_command_frequencies[command_symbol] += 1
      second_command_count = brotli_add_unique_symbol(
        second_command_symbols, second_command_count, command_symbol,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_symbol = command.distance_prefix.symbol
      distance_frequencies[distance_symbol] += 1
      distance_count = brotli_add_unique_symbol(
        distance_symbols, distance_count, distance_symbol,
      )
    }
  }
  if first_command_count == 0 || second_command_count == 0 {
    return None
  }
  if distance_count == 0 {
    distance_symbols[0] = 0
    distance_count = 1
  }
  let first_literal_spec = brotli_make_weighted_huffman_spec(
    first_literals.symbols,
    first_literals.count,
    first_literal_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let second_literal_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_literal_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let first_command_spec = brotli_make_weighted_huffman_spec(
    first_command_symbols, first_command_count, first_command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let second_command_spec = brotli_make_weighted_huffman_spec(
    second_command_symbols, second_command_count, second_command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  let (literal_length_spec, _, literal_second_prefix) = brotli_write_two_block_header(
    writer,
    literal_split,
    literal_total - literal_split,
  )
  let (command_length_spec, _, command_second_prefix) = brotli_write_two_block_header(
    writer,
    command_split,
    commands.length() - command_split,
  )
  writer.write_bits(1, 0) // one distance block type
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 1
  brotli_write_trivial_two_tree_context_map(writer)
  writer.write_bits(1, 0) // distance context map has one tree
  brotli_write_huffman_spec(writer, first_literal_spec)
  brotli_write_huffman_spec(writer, second_literal_spec)
  brotli_write_huffman_spec(writer, first_command_spec)
  brotli_write_huffman_spec(writer, second_command_spec)
  brotli_write_huffman_spec(writer, distance_spec)
  let first_literal_payloads = brotli_huffman_payload_table(first_literal_spec)
  let second_literal_payloads = brotli_huffman_payload_table(
    second_literal_spec,
  )
  let first_command_payloads = brotli_huffman_payload_table(first_command_spec)
  let second_command_payloads = brotli_huffman_payload_table(
    second_command_spec,
  )
  let distance_payloads = brotli_huffman_payload_table(distance_spec)
  let literal_length_payloads = brotli_huffman_payload_table(
    literal_length_spec,
  )
  let command_length_payloads = brotli_huffman_payload_table(
    command_length_spec,
  )
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  let literal_second_length_payload = literal_length_payloads[literal_second_prefix.symbol]
  let command_second_length_payload = command_length_payloads[command_second_prefix.symbol]
  let mut literal_index = 0
  let mut literal_switched = false
  for i in 0..<commands.length() {
    let command = commands[i]
    if i == command_split {
      writer.write_bits(
        type_payload.insert_extra_bits,
        type_payload.insert_extra,
      )
      writer.write_bits(
        command_second_length_payload.insert_extra_bits,
        command_second_length_payload.insert_extra,
      )
      writer.write_bits(
        command_second_prefix.insert_extra_bits,
        command_second_prefix.insert_extra,
      )
    }
    let command_payload = if i < command_split {
      first_command_payloads[command.command.symbol]
    } else {
      second_command_payloads[command.command.symbol]
    }
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
      if !literal_switched && literal_index == literal_split {
        writer.write_bits(
          type_payload.insert_extra_bits,
          type_payload.insert_extra,
        )
        writer.write_bits(
          literal_second_length_payload.insert_extra_bits,
          literal_second_length_payload.insert_extra,
        )
        writer.write_bits(
          literal_second_prefix.insert_extra_bits,
          literal_second_prefix.insert_extra,
        )
        literal_switched = true
      }
      let literal = data[command.insert_start + j].to_int()
      let literal_payload = if literal_index < literal_split {
        first_literal_payloads[literal]
      } else {
        second_literal_payloads[literal]
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
fn brotli_write_distance_split_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise @common.FbrError {
  let total_distance_count = brotli_command_distance_symbol_count(commands)
  if split <= 0 || split >= total_distance_count {
    return None
  }
  let literal_symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let literal_seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
  let literal_frequencies = FixedArray::make(
    @common.brotli_num_literal_symbols, 0,
  )
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let first_distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let second_distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let first_distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let second_distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut literal_count = 0
  let mut command_count = 0
  let mut first_distance_count = 0
  let mut second_distance_count = 0
  let mut distance_index = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let literal = data[command.insert_start + j].to_int()
      literal_frequencies[literal] += 1
      if !literal_seen[literal] {
        literal_seen[literal] = true
        literal_symbols[literal_count] = literal
        literal_count += 1
      }
    }
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      let distance_symbol = command.distance_prefix.symbol
      if distance_index < split {
        first_distance_frequencies[distance_symbol] += 1
        first_distance_count = brotli_add_unique_symbol(
          first_distance_symbols, first_distance_count, distance_symbol,
        )
      } else {
        second_distance_frequencies[distance_symbol] += 1
        second_distance_count = brotli_add_unique_symbol(
          second_distance_symbols, second_distance_count, distance_symbol,
        )
      }
      distance_index += 1
    }
  }
  if first_distance_count == 0 || second_distance_count == 0 {
    return None
  }
  if literal_count == 0 {
    literal_symbols[0] = 0
    literal_count = 1
  }
  let literal_spec = brotli_make_weighted_huffman_spec(
    literal_symbols, literal_count, literal_frequencies, @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let first_distance_spec = brotli_make_weighted_huffman_spec(
    first_distance_symbols,
    first_distance_count,
    first_distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let second_distance_spec = brotli_make_weighted_huffman_spec(
    second_distance_symbols,
    second_distance_count,
    second_distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  writer.write_bits(1, 0) // one command block type
  let (length_spec, _, second_prefix) = brotli_write_two_block_header(
    writer,
    split,
    total_distance_count - split,
  )
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 literal context mode
  writer.write_bits(1, 0) // literal context map has one tree
  brotli_write_trivial_two_distance_context_map(writer)
  brotli_write_huffman_spec(writer, literal_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, first_distance_spec)
  brotli_write_huffman_spec(writer, second_distance_spec)
  let literal_payloads = brotli_huffman_payload_table(literal_spec)
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let first_distance_payloads = brotli_huffman_payload_table(
    first_distance_spec,
  )
  let second_distance_payloads = brotli_huffman_payload_table(
    second_distance_spec,
  )
  let length_payloads = brotli_huffman_payload_table(length_spec)
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  let second_length_payload = length_payloads[second_prefix.symbol]
  distance_index = 0
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
      if distance_index == split {
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
      }
      let distance_payload = if distance_index < split {
        first_distance_payloads[command.distance_prefix.symbol]
      } else {
        second_distance_payloads[command.distance_prefix.symbol]
      }
      writer.write_bits(
        distance_payload.insert_extra_bits,
        distance_payload.insert_extra,
      )
      writer.write_bits(
        command.distance_prefix.insert_extra_bits,
        command.distance_prefix.insert_extra,
      )
      distance_index += 1
    }
  }
  Some(writer)
}

///|
fn brotli_write_literal_distance_split_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  literal_split : Int,
  distance_split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise @common.FbrError {
  let literal_total = brotli_command_literal_count(commands)
  let total_distance_count = brotli_command_distance_symbol_count(commands)
  if literal_split <= 0 ||
    literal_split >= literal_total ||
    distance_split <= 0 ||
    distance_split >= total_distance_count {
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
    brotli_collect_command_literals_range(data, commands, 0, literal_split) {
    Some(literals) => literals
    None => return None
  }
  let second_literals = match
    brotli_collect_command_literals_range(
      data, commands, literal_split, literal_total,
    ) {
    Some(literals) => literals
    None => return None
  }
  let first_literal_frequencies = brotli_command_literal_frequencies_range(
    data, commands, 0, literal_split,
  )
  let second_literal_frequencies = brotli_command_literal_frequencies_range(
    data, commands, literal_split, literal_total,
  )
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let first_distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let second_distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let first_distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let second_distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut command_count = 0
  let mut first_distance_count = 0
  let mut second_distance_count = 0
  let mut distance_index = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    command_frequencies[command.command.symbol] += 1
    command_count = brotli_add_unique_symbol(
      command_symbols,
      command_count,
      command.command.symbol,
    )
    if brotli_command_uses_distance_symbol(command) {
      let distance_symbol = command.distance_prefix.symbol
      if distance_index < distance_split {
        first_distance_frequencies[distance_symbol] += 1
        first_distance_count = brotli_add_unique_symbol(
          first_distance_symbols, first_distance_count, distance_symbol,
        )
      } else {
        second_distance_frequencies[distance_symbol] += 1
        second_distance_count = brotli_add_unique_symbol(
          second_distance_symbols, second_distance_count, distance_symbol,
        )
      }
      distance_index += 1
    }
  }
  if first_distance_count == 0 || second_distance_count == 0 {
    return None
  }
  let first_literal_spec = brotli_make_weighted_huffman_spec(
    first_literals.symbols,
    first_literals.count,
    first_literal_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let second_literal_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_literal_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let first_distance_spec = brotli_make_weighted_huffman_spec(
    first_distance_symbols,
    first_distance_count,
    first_distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let second_distance_spec = brotli_make_weighted_huffman_spec(
    second_distance_symbols,
    second_distance_count,
    second_distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  let (literal_length_spec, _, literal_second_prefix) = brotli_write_two_block_header(
    writer,
    literal_split,
    literal_total - literal_split,
  )
  writer.write_bits(1, 0) // one command block type
  let (distance_length_spec, _, distance_second_prefix) = brotli_write_two_block_header(
    writer,
    distance_split,
    total_distance_count - distance_split,
  )
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 0
  writer.write_bits(2, 0) // LSB6 context mode for literal block 1
  brotli_write_trivial_two_tree_context_map(writer)
  brotli_write_trivial_two_distance_context_map(writer)
  brotli_write_huffman_spec(writer, first_literal_spec)
  brotli_write_huffman_spec(writer, second_literal_spec)
  brotli_write_huffman_spec(writer, command_spec)
  brotli_write_huffman_spec(writer, first_distance_spec)
  brotli_write_huffman_spec(writer, second_distance_spec)
  let first_literal_payloads = brotli_huffman_payload_table(first_literal_spec)
  let second_literal_payloads = brotli_huffman_payload_table(
    second_literal_spec,
  )
  let command_payloads = brotli_huffman_payload_table(command_spec)
  let first_distance_payloads = brotli_huffman_payload_table(
    first_distance_spec,
  )
  let second_distance_payloads = brotli_huffman_payload_table(
    second_distance_spec,
  )
  let literal_length_payloads = brotli_huffman_payload_table(
    literal_length_spec,
  )
  let distance_length_payloads = brotli_huffman_payload_table(
    distance_length_spec,
  )
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  let literal_second_length_payload = literal_length_payloads[literal_second_prefix.symbol]
  let distance_second_length_payload = distance_length_payloads[distance_second_prefix.symbol]
  let mut literal_index = 0
  let mut literal_switched = false
  distance_index = 0
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
      if !literal_switched && literal_index == literal_split {
        writer.write_bits(
          type_payload.insert_extra_bits,
          type_payload.insert_extra,
        )
        writer.write_bits(
          literal_second_length_payload.insert_extra_bits,
          literal_second_length_payload.insert_extra,
        )
        writer.write_bits(
          literal_second_prefix.insert_extra_bits,
          literal_second_prefix.insert_extra,
        )
        literal_switched = true
      }
      let literal = data[command.insert_start + j].to_int()
      let literal_payload = if literal_index < literal_split {
        first_literal_payloads[literal]
      } else {
        second_literal_payloads[literal]
      }
      writer.write_bits(
        literal_payload.insert_extra_bits,
        literal_payload.insert_extra,
      )
      literal_index += 1
    }
    if brotli_command_uses_distance_symbol(command) {
      if distance_index == distance_split {
        writer.write_bits(
          type_payload.insert_extra_bits,
          type_payload.insert_extra,
        )
        writer.write_bits(
          distance_second_length_payload.insert_extra_bits,
          distance_second_length_payload.insert_extra,
        )
        writer.write_bits(
          distance_second_prefix.insert_extra_bits,
          distance_second_prefix.insert_extra,
        )
      }
      let distance_payload = if distance_index < distance_split {
        first_distance_payloads[command.distance_prefix.symbol]
      } else {
        second_distance_payloads[command.distance_prefix.symbol]
      }
      writer.write_bits(
        distance_payload.insert_extra_bits,
        distance_payload.insert_extra,
      )
      writer.write_bits(
        command.distance_prefix.insert_extra_bits,
        command.distance_prefix.insert_extra,
      )
      distance_index += 1
    }
  }
  Some(writer)
}

///|
fn brotli_write_command_distance_split_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  command_split : Int,
  distance_split : Int,
  is_last : Bool,
) -> BrotliBitWriter? raise @common.FbrError {
  let total_distance_count = brotli_command_distance_symbol_count(commands)
  if command_split <= 0 ||
    command_split >= commands.length() ||
    distance_split <= 0 ||
    distance_split >= total_distance_count {
    return None
  }
  let literal_symbols = FixedArray::make(@common.brotli_num_literal_symbols, 0)
  let literal_seen = FixedArray::make(@common.brotli_num_literal_symbols, false)
  let literal_frequencies = FixedArray::make(
    @common.brotli_num_literal_symbols, 0,
  )
  let first_command_symbols = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let second_command_symbols = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let first_distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let second_distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let second_command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let first_distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let second_distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let mut literal_count = 0
  let mut first_command_count = 0
  let mut second_command_count = 0
  let mut first_distance_count = 0
  let mut second_distance_count = 0
  let mut distance_index = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    for j in 0..<command.insert_length {
      let literal = data[command.insert_start + j].to_int()
      literal_frequencies[literal] += 1
      if !literal_seen[literal] {
        literal_seen[literal] = true
        literal_symbols[literal_count] = literal
        literal_count += 1
      }
    }
    let command_symbol = command.command.symbol
    if i < command_split {
      first_command_frequencies[command_symbol] += 1
      first_command_count = brotli_add_unique_symbol(
        first_command_symbols, first_command_count, command_symbol,
      )
    } else {
      second_command_frequencies[command_symbol] += 1
      second_command_count = brotli_add_unique_symbol(
        second_command_symbols, second_command_count, command_symbol,
      )
    }
    if brotli_command_uses_distance_symbol(command) {
      let distance_symbol = command.distance_prefix.symbol
      if distance_index < distance_split {
        first_distance_frequencies[distance_symbol] += 1
        first_distance_count = brotli_add_unique_symbol(
          first_distance_symbols, first_distance_count, distance_symbol,
        )
      } else {
        second_distance_frequencies[distance_symbol] += 1
        second_distance_count = brotli_add_unique_symbol(
          second_distance_symbols, second_distance_count, distance_symbol,
        )
      }
      distance_index += 1
    }
  }
  if first_command_count == 0 ||
    second_command_count == 0 ||
    first_distance_count == 0 ||
    second_distance_count == 0 {
    return None
  }
  if literal_count == 0 {
    literal_symbols[0] = 0
    literal_count = 1
  }
  let literal_spec = brotli_make_weighted_huffman_spec(
    literal_symbols, literal_count, literal_frequencies, @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let first_command_spec = brotli_make_weighted_huffman_spec(
    first_command_symbols, first_command_count, first_command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let second_command_spec = brotli_make_weighted_huffman_spec(
    second_command_symbols, second_command_count, second_command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let first_distance_spec = brotli_make_weighted_huffman_spec(
    first_distance_symbols,
    first_distance_count,
    first_distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let second_distance_spec = brotli_make_weighted_huffman_spec(
    second_distance_symbols,
    second_distance_count,
    second_distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
  )
  let writer = BrotliBitWriter::new(
    256 + data.length() * 4 + commands.length() * 8,
  )
  brotli_write_metablock_header(writer, data.length(), is_last, false)
  writer.write_bits(1, 0) // one literal block type
  let (command_length_spec, _, command_second_prefix) = brotli_write_two_block_header(
    writer,
    command_split,
    commands.length() - command_split,
  )
  let (distance_length_spec, _, distance_second_prefix) = brotli_write_two_block_header(
    writer,
    distance_split,
    total_distance_count - distance_split,
  )
  writer.write_bits(6, 0) // NPOSTFIX = 0, NDIRECT = 0
  writer.write_bits(2, 0) // LSB6 literal context mode
  writer.write_bits(1, 0) // literal context map has one tree
  brotli_write_trivial_two_distance_context_map(writer)
  brotli_write_huffman_spec(writer, literal_spec)
  brotli_write_huffman_spec(writer, first_command_spec)
  brotli_write_huffman_spec(writer, second_command_spec)
  brotli_write_huffman_spec(writer, first_distance_spec)
  brotli_write_huffman_spec(writer, second_distance_spec)
  let literal_payloads = brotli_huffman_payload_table(literal_spec)
  let first_command_payloads = brotli_huffman_payload_table(first_command_spec)
  let second_command_payloads = brotli_huffman_payload_table(
    second_command_spec,
  )
  let first_distance_payloads = brotli_huffman_payload_table(
    first_distance_spec,
  )
  let second_distance_payloads = brotli_huffman_payload_table(
    second_distance_spec,
  )
  let command_length_payloads = brotli_huffman_payload_table(
    command_length_spec,
  )
  let distance_length_payloads = brotli_huffman_payload_table(
    distance_length_spec,
  )
  let type_symbols : FixedArray[Int] = [1]
  let type_payload = brotli_simple_huffman_payload(type_symbols, 1, 1)
  let command_second_length_payload = command_length_payloads[command_second_prefix.symbol]
  let distance_second_length_payload = distance_length_payloads[distance_second_prefix.symbol]
  distance_index = 0
  for i in 0..<commands.length() {
    let command = commands[i]
    if i == command_split {
      writer.write_bits(
        type_payload.insert_extra_bits,
        type_payload.insert_extra,
      )
      writer.write_bits(
        command_second_length_payload.insert_extra_bits,
        command_second_length_payload.insert_extra,
      )
      writer.write_bits(
        command_second_prefix.insert_extra_bits,
        command_second_prefix.insert_extra,
      )
    }
    let command_payload = if i < command_split {
      first_command_payloads[command.command.symbol]
    } else {
      second_command_payloads[command.command.symbol]
    }
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
      if distance_index == distance_split {
        writer.write_bits(
          type_payload.insert_extra_bits,
          type_payload.insert_extra,
        )
        writer.write_bits(
          distance_second_length_payload.insert_extra_bits,
          distance_second_length_payload.insert_extra,
        )
        writer.write_bits(
          distance_second_prefix.insert_extra_bits,
          distance_second_prefix.insert_extra,
        )
      }
      let distance_payload = if distance_index < distance_split {
        first_distance_payloads[command.distance_prefix.symbol]
      } else {
        second_distance_payloads[command.distance_prefix.symbol]
      }
      writer.write_bits(
        distance_payload.insert_extra_bits,
        distance_payload.insert_extra,
      )
      writer.write_bits(
        command.distance_prefix.insert_extra_bits,
        command.distance_prefix.insert_extra,
      )
      distance_index += 1
    }
  }
  Some(writer)
}

///|
fn brotli_write_context_lz77_metablock(
  data : FixedArray[Byte],
  commands : Array[BrotliEncodeCommand],
  is_last : Bool,
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliBitWriter? raise @common.FbrError {
  let (literal_sets, literal_frequencies_array) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context(
      data, commands, initial_previous_byte_1, initial_previous_byte_2,
    ) {
    Some(result) => result
    None => return None
  }
  let first_literals = literal_sets[0]
  let second_literals = literal_sets[1]
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_frequencies = literal_frequencies_array[0]
  let second_frequencies = literal_frequencies_array[1]
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
      let tree = brotli_command_literal_utf8_context_tree(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliBitWriter? raise @common.FbrError {
  let (literal_sets, literal_frequencies_array) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context4(
      data, commands, initial_previous_byte_1, initial_previous_byte_2,
    ) {
    Some(result) => result
    None => return None
  }
  let first_literals = literal_sets[0]
  let second_literals = literal_sets[1]
  let third_literals = literal_sets[2]
  let fourth_literals = literal_sets[3]
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let first_frequencies = literal_frequencies_array[0]
  let second_frequencies = literal_frequencies_array[1]
  let third_frequencies = literal_frequencies_array[2]
  let fourth_frequencies = literal_frequencies_array[3]
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let second_spec = brotli_make_weighted_huffman_spec(
    second_literals.symbols,
    second_literals.count,
    second_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let third_spec = brotli_make_weighted_huffman_spec(
    third_literals.symbols,
    third_literals.count,
    third_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let fourth_spec = brotli_make_weighted_huffman_spec(
    fourth_literals.symbols,
    fourth_literals.count,
    fourth_frequencies,
    @common.brotli_num_literal_symbols,
    @common.brotli_num_literal_symbols,
  )
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
      let tree = brotli_command_literal_utf8_context_tree4(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliBitWriter? raise @common.FbrError {
  let (literal_sets, literal_frequencies) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context8(
      data, commands, initial_previous_byte_1, initial_previous_byte_2,
    ) {
    Some(result) => result
    None => return None
  }
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
        @common.brotli_num_literal_symbols,
        @common.brotli_num_literal_symbols,
      ),
    )
  }
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
      let tree = brotli_command_literal_utf8_context_tree8(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliBitWriter? raise @common.FbrError {
  let (literal_sets, literal_frequencies) = match
    brotli_collect_command_literals_and_frequencies_by_utf8_context16(
      data, commands, initial_previous_byte_1, initial_previous_byte_2,
    ) {
    Some(result) => result
    None => return None
  }
  let command_symbols = FixedArray::make(@common.brotli_num_command_symbols, 0)
  let distance_symbols = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
    0,
  )
  let command_frequencies = FixedArray::make(
    @common.brotli_num_command_symbols, 0,
  )
  let distance_frequencies = FixedArray::make(
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
        @common.brotli_num_literal_symbols,
        @common.brotli_num_literal_symbols,
      ),
    )
  }
  let command_spec = brotli_make_weighted_huffman_spec(
    command_symbols, command_count, command_frequencies, @common.brotli_num_command_symbols,
    @common.brotli_num_command_symbols,
  )
  let distance_spec = brotli_make_weighted_huffman_spec(
    distance_symbols,
    distance_count,
    distance_frequencies,
    @common.brotli_distance_alphabet_size(0, 0, 24),
    @common.brotli_distance_alphabet_size(0, 0, 24),
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
      let tree = brotli_command_literal_utf8_context_tree16(
        data, position, initial_previous_byte_1, initial_previous_byte_2,
      )
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
  allow_contexts : Bool,
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliBitWriter raise @common.FbrError {
  if allow_contexts && quality <= 2 && data.length() >= 524288 {
    if commands.length() != 1 || commands[0].has_copy {
      match
        brotli_write_context16_lz77_metablock(
          data, commands, is_last, initial_previous_byte_1, initial_previous_byte_2,
        ) {
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
    if allow_contexts {
      match
        brotli_write_context16_lz77_metablock(
          data, commands, is_last, initial_previous_byte_1, initial_previous_byte_2,
        ) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
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
  if quality >= 4 {
    let command_split = brotli_best_command_block_split_point(commands)
    if split > 0 && command_split > 0 {
      match
        brotli_write_literal_command_split_lz77_metablock(
          data, commands, split, command_split, is_last,
        ) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
    }
    if command_split > 0 {
      match
        brotli_write_command_split_lz77_metablock(
          data, commands, command_split, is_last,
        ) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
    }
    let distance_split = brotli_best_distance_block_split_point(commands)
    if distance_split > 0 {
      match
        brotli_write_distance_split_lz77_metablock(
          data, commands, distance_split, is_last,
        ) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
    }
    if split > 0 && distance_split > 0 {
      match
        brotli_write_literal_distance_split_lz77_metablock(
          data, commands, split, distance_split, is_last,
        ) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
    }
    if command_split > 0 && distance_split > 0 {
      match
        brotli_write_command_distance_split_lz77_metablock(
          data, commands, command_split, distance_split, is_last,
        ) {
        Some(candidate) =>
          if candidate.bit_pos < best.bit_pos {
            best = candidate
          }
        None => ()
      }
    }
  }
  if allow_contexts && quality < 3 {
    match
      brotli_write_context_lz77_metablock(
        data, commands, is_last, initial_previous_byte_1, initial_previous_byte_2,
      ) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
  }
  if allow_contexts {
    match
      brotli_write_context4_lz77_metablock(
        data, commands, is_last, initial_previous_byte_1, initial_previous_byte_2,
      ) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
    match
      brotli_write_context8_lz77_metablock(
        data, commands, is_last, initial_previous_byte_1, initial_previous_byte_2,
      ) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
    match
      brotli_write_context16_lz77_metablock(
        data, commands, is_last, initial_previous_byte_1, initial_previous_byte_2,
      ) {
      Some(candidate) =>
        if candidate.bit_pos < best.bit_pos {
          best = candidate
        }
      None => ()
    }
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
) -> BrotliBitWriter? raise @common.FbrError {
  match commands {
    Some(commands) => {
      let candidate = brotli_write_best_lz77_metablock(
        data, commands, is_last, quality, true, 0, 0,
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
fn brotli_try_compressed_command_candidate(
  data : FixedArray[Byte],
  candidate : BrotliCommandCandidate?,
  is_last : Bool,
  best : BrotliCompressedChunk?,
  quality : Int,
  allow_contexts : Bool,
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliCompressedChunk? raise @common.FbrError {
  match candidate {
    Some(candidate) => {
      let writer = brotli_write_best_lz77_metablock(
        data,
        candidate.commands,
        is_last,
        quality,
        allow_contexts,
        initial_previous_byte_1,
        initial_previous_byte_2,
      )
      match best {
        Some(best) =>
          if writer.bit_pos < best.writer.bit_pos {
            Some({ writer, distance_cache: candidate.distance_cache })
          } else {
            Some(best)
          }
        None => Some({ writer, distance_cache: candidate.distance_cache })
      }
    }
    None => best
  }
}

///|
fn brotli_try_split_literal_only_chunk(
  data : FixedArray[Byte],
  is_last : Bool,
  best : BrotliCompressedChunk?,
  distance_cache : FixedArray[Int],
) -> BrotliCompressedChunk? raise @common.FbrError {
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
      Some(writer) =>
        match best {
          Some(current) =>
            if writer.bit_pos < current.writer.bit_pos {
              best = Some({
                writer,
                distance_cache: brotli_copy_distance_cache(distance_cache),
              })
            }
          None =>
            best = Some({
              writer,
              distance_cache: brotli_copy_distance_cache(distance_cache),
            })
        }
      None => ()
    }
  }
  best
}

///|
fn brotli_use_intermediate_four_byte_candidate(
  quality : Int,
  data_length : Int,
) -> Bool {
  (quality != 6 && quality != 7) || data_length > 65536
}

///|
fn brotli_use_natural_four_byte_candidate(
  quality : Int,
  _data_length : Int,
) -> Bool {
  quality != 5
}

///|
fn brotli_encode_uncompressed(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise @common.FbrError {
  let writer = BrotliBitWriter::new(brotli_encoded_capacity(data.length()))
  brotli_encode_window_bits(writer, opts.window_bits)
  let mut offset = 0
  while offset < data.length() {
    let remaining = data.length() - offset
    let length = if remaining > @common.brotli_max_metablock_bytes {
      @common.brotli_max_metablock_bytes
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
fn brotli_standard_chunk_size_for_quality(quality : Int) -> Int {
  // q2..q9 need larger P3 chunks so matches and literal-context statistics
  // can cross the previous 1 MiB boundary. Keep other standard modes unchanged
  // until their target-perf tradeoff has separate evidence.
  if quality >= 2 && quality <= 9 {
    2097152
  } else {
    1048576
  }
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
  initial_previous_byte_1 : Int,
  initial_previous_byte_2 : Int,
) -> BrotliCompressedChunk? raise @common.FbrError {
  // UTF-8 literal contexts depend on the two bytes before this meta-block; for
  // non-first chunks they come from the previous chunk, not from zero padding.
  let allow_contexts = true
  if quality <= 2 && data.length() >= 8192 {
    let natural_config = brotli_natural_hash_config_for_quality(quality)
    return brotli_try_compressed_command_candidate(
      data,
      brotli_build_simple_lz77_command_candidate(
        data, natural_config, distance_cache,
      ),
      is_last,
      None,
      quality,
      allow_contexts,
      initial_previous_byte_1,
      initial_previous_byte_2,
    )
  }
  let best = brotli_try_compressed_command_candidate(
    data,
    brotli_build_simple_lz77_command_candidate(
      data, hash_config, distance_cache,
    ),
    is_last,
    None,
    quality,
    allow_contexts,
    initial_previous_byte_1,
    initial_previous_byte_2,
  )
  let best = brotli_try_compressed_command_candidate(
    data,
    brotli_wrap_command_candidate(
      brotli_build_literal_only_command(data),
      distance_cache,
    ),
    is_last,
    best,
    quality,
    allow_contexts,
    initial_previous_byte_1,
    initial_previous_byte_2,
  )
  let best = brotli_try_split_literal_only_chunk(
    data, is_last, best, distance_cache,
  )
  let best = brotli_try_compressed_command_candidate(
    data,
    brotli_wrap_command_candidate(
      brotli_build_identity_dictionary_commands(
        data, hash_config, base_offset, window_bits,
      ),
      distance_cache,
    ),
    is_last,
    best,
    quality,
    allow_contexts,
    initial_previous_byte_1,
    initial_previous_byte_2,
  )
  if quality >= 2 && data.length() >= 8192 {
    if quality >= 9 {
      let hq_config = brotli_high_quality_hash_config_for_quality(quality)
      if quality >= 10 {
        let hq_config = brotli_four_byte_hash_config(hq_config)
        let best = brotli_try_compressed_command_candidate(
          data,
          brotli_build_bounded_shortest_path_command_candidate(
            data, hq_config, base_offset, window_bits, distance_cache,
          ),
          is_last,
          best,
          quality,
          allow_contexts,
          initial_previous_byte_1,
          initial_previous_byte_2,
        )
        let mixed_candidate = brotli_build_mixed_dictionary_lz77_command_candidate(
          data, hq_config, base_offset, window_bits, distance_cache,
        )
        match mixed_candidate {
          Some(_) =>
            return brotli_try_compressed_command_candidate(
              data, mixed_candidate, is_last, best, quality, allow_contexts, initial_previous_byte_1,
              initial_previous_byte_2,
            )
          None =>
            return brotli_try_compressed_command_candidate(
              data,
              brotli_build_simple_lz77_command_candidate(
                data, hq_config, distance_cache,
              ),
              is_last,
              best,
              quality,
              allow_contexts,
              initial_previous_byte_1,
              initial_previous_byte_2,
            )
        }
      }
      let best = brotli_try_compressed_command_candidate(
        data,
        brotli_build_simple_lz77_command_candidate(
          data, hq_config, distance_cache,
        ),
        is_last,
        best,
        quality,
        allow_contexts,
        initial_previous_byte_1,
        initial_previous_byte_2,
      )
      let hq_config_4 = brotli_four_byte_hash_config(hq_config)
      if brotli_mixed_dictionary_may_pay(data) {
        let mixed = brotli_try_compressed_command_candidate(
          data,
          brotli_build_mixed_dictionary_lz77_command_candidate(
            data, hq_config_4, base_offset, window_bits, distance_cache,
          ),
          is_last,
          best,
          quality,
          allow_contexts,
          initial_previous_byte_1,
          initial_previous_byte_2,
        )
        match (best, mixed) {
          (Some(before), Some(after)) =>
            if after.writer.bit_pos < before.writer.bit_pos {
              mixed
            } else {
              brotli_try_compressed_command_candidate(
                data,
                brotli_build_simple_lz77_command_candidate(
                  data, hq_config_4, distance_cache,
                ),
                is_last,
                mixed,
                quality,
                allow_contexts,
                initial_previous_byte_1,
                initial_previous_byte_2,
              )
            }
          (_, _) => mixed
        }
      } else {
        brotli_try_compressed_command_candidate(
          data,
          brotli_build_simple_lz77_command_candidate(
            data, hq_config_4, distance_cache,
          ),
          is_last,
          best,
          quality,
          allow_contexts,
          initial_previous_byte_1,
          initial_previous_byte_2,
        )
      }
    } else {
      let natural_config = brotli_natural_hash_config_for_quality(quality)
      let best = brotli_try_compressed_command_candidate(
        data,
        brotli_build_simple_lz77_command_candidate(
          data, natural_config, distance_cache,
        ),
        is_last,
        best,
        quality,
        allow_contexts,
        initial_previous_byte_1,
        initial_previous_byte_2,
      )
      let best = brotli_try_compressed_command_candidate(
        data,
        if brotli_use_natural_four_byte_candidate(quality, data.length()) {
          brotli_build_simple_lz77_command_candidate(
            data,
            brotli_four_byte_hash_config(natural_config),
            distance_cache,
          )
        } else {
          None
        },
        is_last,
        best,
        quality,
        allow_contexts,
        initial_previous_byte_1,
        initial_previous_byte_2,
      )
      if quality >= 4 {
        let intermediate_config = brotli_intermediate_hash_config_for_quality(
          quality,
        )
        let best = brotli_try_compressed_command_candidate(
          data,
          brotli_build_simple_lz77_command_candidate(
            data, intermediate_config, distance_cache,
          ),
          is_last,
          best,
          quality,
          allow_contexts,
          initial_previous_byte_1,
          initial_previous_byte_2,
        )
        if brotli_use_intermediate_four_byte_candidate(quality, data.length()) {
          brotli_try_compressed_command_candidate(
            data,
            brotli_build_simple_lz77_command_candidate(
              data,
              brotli_four_byte_hash_config(intermediate_config),
              distance_cache,
            ),
            is_last,
            best,
            quality,
            allow_contexts,
            initial_previous_byte_1,
            initial_previous_byte_2,
          )
        } else {
          best
        }
      } else {
        best
      }
    }
  } else {
    best
  }
}

///|
fn brotli_encode_chunked_standard(
  data : FixedArray[Byte],
  opts : BrotliOptions,
) -> FixedArray[Byte] raise @common.FbrError {
  let chunk_size = brotli_standard_chunk_size_for_quality(opts.quality)
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
    let chunk = @common.slc(data, offset, e=offset + length)
    let is_last = offset + length == data.length()
    let previous_distance_cache = brotli_copy_distance_cache(distance_cache)
    let initial_previous_byte_1 = if offset > 0 {
      data[offset - 1].to_int()
    } else {
      0
    }
    let initial_previous_byte_2 = if offset > 1 {
      data[offset - 2].to_int()
    } else {
      0
    }
    match
      brotli_try_compressed_chunk(
        chunk,
        hash_config,
        is_last,
        offset,
        opts.window_bits,
        opts.quality,
        distance_cache,
        initial_previous_byte_1,
        initial_previous_byte_2,
      ) {
      Some(compressed) =>
        if @common.shft(compressed.writer.bit_pos) + 1 < length + 16 {
          writer.write_from_bits(
            compressed.writer.buf,
            compressed.writer.bit_pos,
          )
          brotli_commit_distance_cache(
            distance_cache,
            compressed.distance_cache,
          )
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
) -> FixedArray[Byte] raise @common.FbrError {
  if data.length() <= 262144 {
    match brotli_find_single_copy_match(data) {
      Some(match_) => {
        let compressed = brotli_encode_single_copy_match(data, opts, match_)
        if opts.quality <= 2 {
          return compressed
        }
        match
          brotli_encode_prefix_stored_single_copy_match(data, opts, match_) {
          Some(split) =>
            if split.length() < compressed.length() {
              return split
            } else {
              return compressed
            }
          None => return compressed
        }
      }
      None => ()
    }
  }
  if data.length() > 65536 {
    return brotli_encode_chunked_standard(data, opts)
  }
  let hash_config = brotli_hash_config_for_quality(opts.quality)
  if data.length() <= @common.brotli_max_metablock_bytes {
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
          let hq_config = brotli_four_byte_hash_config(hq_config)
          let mixed_commands = brotli_build_mixed_dictionary_lz77_commands(
            data,
            hq_config,
            0,
            opts.window_bits,
          )
          match mixed_commands {
            Some(cmds) =>
              best = brotli_try_compressed_commands(
                data,
                Some(cmds),
                true,
                best,
                opts.quality,
              )
            None =>
              best = brotli_try_compressed_commands(
                data,
                brotli_build_simple_lz77_commands(data, hq_config),
                true,
                best,
                opts.quality,
              )
          }
        } else {
          best = brotli_try_compressed_commands(
            data,
            brotli_build_simple_lz77_commands(data, hq_config),
            true,
            best,
            opts.quality,
          )
          let hq_config_4 = brotli_four_byte_hash_config(hq_config)
          if brotli_mixed_dictionary_may_pay(data) {
            let mixed = brotli_try_compressed_commands(
              data,
              brotli_build_mixed_dictionary_lz77_commands(
                data,
                hq_config_4,
                0,
                opts.window_bits,
              ),
              true,
              best,
              opts.quality,
            )
            match (best, mixed) {
              (Some(before), Some(after)) =>
                if after.bit_pos < before.bit_pos {
                  best = mixed
                } else {
                  best = brotli_try_compressed_commands(
                    data,
                    brotli_build_simple_lz77_commands(data, hq_config_4),
                    true,
                    mixed,
                    opts.quality,
                  )
                }
              (_, _) => best = mixed
            }
          } else {
            best = brotli_try_compressed_commands(
              data,
              brotli_build_simple_lz77_commands(data, hq_config_4),
              true,
              best,
              opts.quality,
            )
          }
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
          if brotli_use_natural_four_byte_candidate(opts.quality, data.length()) {
            brotli_build_simple_lz77_commands(
              data,
              brotli_four_byte_hash_config(natural_config),
            )
          } else {
            None
          },
          true,
          best,
          opts.quality,
        )
        if opts.quality >= 4 {
          let intermediate_config = brotli_intermediate_hash_config_for_quality(
            opts.quality,
          )
          best = brotli_try_compressed_commands(
            data,
            brotli_build_simple_lz77_commands(data, intermediate_config),
            true,
            best,
            opts.quality,
          )
          if brotli_use_intermediate_four_byte_candidate(
              opts.quality,
              data.length(),
            ) {
            best = brotli_try_compressed_commands(
              data,
              brotli_build_simple_lz77_commands(
                data,
                brotli_four_byte_hash_config(intermediate_config),
              ),
              true,
              best,
              opts.quality,
            )
          }
        }
      }
    }
    match best {
      Some(compressed) => {
        let uncompressed = brotli_encode_uncompressed(data, opts)
        let compressed_size = @common.shft(compressed.bit_pos) + 1
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
fn brotli_validate_options(opts : BrotliOptions) -> Unit raise @common.FbrError {
  if opts.quality < 0 || opts.quality > 11 {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="Brotli quality must be 0..=11",
    )
  }
  if opts.max_input_size < 0 {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="Brotli max_input_size must be >= 0",
    )
  }
  @common.brotli_validate_window_bits(opts.window_bits)
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
) -> FixedArray[Byte] raise @common.FbrError {
  brotli_validate_options(opts)
  if data.length() > opts.max_input_size {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="input exceeds max_input_size",
    )
  }
  if opts.quality >= 10 && data.length() > 256 * 1024 * 1024 {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="Brotli q10/q11 input exceeds 256 MiB safety cap",
    )
  }
  match opts.quality {
    0 | 1 => brotli_encode_uncompressed(data, opts)
    2..=11 => brotli_encode_standard(data, opts)
    _ =>
      raise @common.fbr_err(
        @common.InvalidZipData,
        msg="Brotli quality must be 0..=11",
      )
  }
}

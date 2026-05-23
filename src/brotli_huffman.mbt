///|
/// One decoded Brotli Huffman table entry.
priv struct BrotliHuffmanCode {
  bits : Int
  value : Int
}

///|
fn BrotliHuffmanCode::empty() -> BrotliHuffmanCode {
  { bits: -1, value: 0 }
}

///|
fn BrotliHuffmanCode::new(bits : Int, value : Int) -> BrotliHuffmanCode {
  { bits, value }
}

///|
fn brotli_reverse_bits(code : Int, len : Int) -> Int {
  rev[code] >> (15 - len)
}

///|
fn brotli_log2_floor_plus_one(x : Int) -> Int {
  let mut x = x
  let mut result = 0
  while x != 0 {
    x = x >> 1
    result += 1
  }
  result
}

///|
fn brotli_validate_huffman_lengths(
  count : FixedArray[Int],
  nonzero : Int,
) -> Unit raise FzipError {
  if nonzero == 0 {
    raise fzip_err(BrotliInvalidHuffman, msg="empty Huffman code")
  }
  if nonzero == 1 {
    return
  }
  let mut left = 1
  for bits in 1..<=brotli_huffman_max_code_length {
    left = (left << 1) - count[bits]
    if left < 0 {
      raise fzip_err(BrotliInvalidHuffman, msg="over-subscribed Huffman code")
    }
  }
  if left != 0 {
    raise fzip_err(BrotliInvalidHuffman, msg="under-subscribed Huffman code")
  }
}

///|
fn brotli_build_huffman_table(
  code_lengths : FixedArray[Byte],
  alphabet_size : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  if alphabet_size < 1 || alphabet_size > code_lengths.length() {
    raise fzip_err(BrotliInvalidHuffman, msg="invalid Huffman alphabet size")
  }
  if root_bits < 1 || root_bits > brotli_huffman_table_bits {
    raise fzip_err(BrotliInvalidHuffman, msg="invalid Huffman root width")
  }
  let count = FixedArray::make(brotli_huffman_max_code_length + 1, 0)
  let mut nonzero = 0
  let mut single_symbol = 0
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len < 0 || len > brotli_huffman_max_code_length {
      raise fzip_err(BrotliInvalidHuffman, msg="Huffman length out of range")
    }
    if len != 0 {
      count[len] += 1
      nonzero += 1
      single_symbol = symbol
    }
  }
  brotli_validate_huffman_lengths(count, nonzero)
  let table_size = 1 << root_bits
  let table = FixedArray::make(table_size, BrotliHuffmanCode::empty())
  if nonzero == 1 {
    let code = BrotliHuffmanCode::new(0, single_symbol)
    for i in 0..<table_size {
      table[i] = code
    }
    return table
  }
  let next_code = FixedArray::make(brotli_huffman_max_code_length + 1, 0)
  let mut code = 0
  for bits in 1..<=brotli_huffman_max_code_length {
    code = (code + count[bits - 1]) << 1
    next_code[bits] = code
  }
  let root_mask = table_size - 1
  let sub_bits_by_root = FixedArray::make(table_size, 0)
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len > root_bits {
      let reversed = brotli_reverse_bits(next_code[len], len)
      next_code[len] += 1
      let root = reversed & root_mask
      let extra = len - root_bits
      if extra > sub_bits_by_root[root] {
        sub_bits_by_root[root] = extra
      }
    } else if len != 0 {
      next_code[len] += 1
    }
  }
  let sub_offsets = FixedArray::make(table_size, 0)
  let mut total_size = table_size
  for root in 0..<table_size {
    if sub_bits_by_root[root] > 0 {
      sub_offsets[root] = total_size
      total_size += 1 << sub_bits_by_root[root]
    }
  }
  if total_size > brotli_huffman_max_table_size {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="Brotli Huffman table exceeds arena limit",
    )
  }
  let table = FixedArray::make(total_size, BrotliHuffmanCode::empty())
  for root in 0..<table_size {
    if sub_bits_by_root[root] > 0 {
      table[root] = BrotliHuffmanCode::new(
        root_bits + sub_bits_by_root[root],
        sub_offsets[root],
      )
    }
  }
  for i in 0..<=brotli_huffman_max_code_length {
    next_code[i] = 0
  }
  code = 0
  for bits in 1..<=brotli_huffman_max_code_length {
    code = (code + count[bits - 1]) << 1
    next_code[bits] = code
  }
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len != 0 {
      let reversed = brotli_reverse_bits(next_code[len], len)
      next_code[len] += 1
      let entry = BrotliHuffmanCode::new(len, symbol)
      if len <= root_bits {
        let step = 1 << len
        let mut index = reversed
        while index < table_size {
          table[index] = entry
          index += step
        }
      } else {
        let root = reversed & root_mask
        let sub_bits = sub_bits_by_root[root]
        let sub_size = 1 << sub_bits
        let sub_offset = sub_offsets[root]
        let sub_index = reversed >> root_bits
        let sub_step = 1 << (len - root_bits)
        let sub_entry = BrotliHuffmanCode::new(len - root_bits, symbol)
        let mut index = sub_index
        while index < sub_size {
          table[sub_offset + index] = sub_entry
          index += sub_step
        }
      }
    }
  }
  table
}

///|
fn brotli_build_simple_huffman_table(
  symbols : FixedArray[Int],
  num_symbols_code : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  let table_size = 1 << root_bits
  let table = FixedArray::make(table_size, BrotliHuffmanCode::empty())
  let base_size = match num_symbols_code {
    0 => {
      table[0] = BrotliHuffmanCode::new(0, symbols[0])
      1
    }
    1 => {
      if symbols[1] > symbols[0] {
        table[0] = BrotliHuffmanCode::new(1, symbols[0])
        table[1] = BrotliHuffmanCode::new(1, symbols[1])
      } else {
        table[0] = BrotliHuffmanCode::new(1, symbols[1])
        table[1] = BrotliHuffmanCode::new(1, symbols[0])
      }
      2
    }
    2 => {
      table[0] = BrotliHuffmanCode::new(1, symbols[0])
      table[2] = BrotliHuffmanCode::new(1, symbols[0])
      if symbols[2] > symbols[1] {
        table[1] = BrotliHuffmanCode::new(2, symbols[1])
        table[3] = BrotliHuffmanCode::new(2, symbols[2])
      } else {
        table[1] = BrotliHuffmanCode::new(2, symbols[2])
        table[3] = BrotliHuffmanCode::new(2, symbols[1])
      }
      4
    }
    3 => {
      let vals = FixedArray::make(4, 0)
      for i in 0..<4 {
        vals[i] = symbols[i]
      }
      for i in 0..<3 {
        for k in (i + 1)..<4 {
          if vals[k] < vals[i] {
            let t = vals[k]
            vals[k] = vals[i]
            vals[i] = t
          }
        }
      }
      table[0] = BrotliHuffmanCode::new(2, vals[0])
      table[2] = BrotliHuffmanCode::new(2, vals[1])
      table[1] = BrotliHuffmanCode::new(2, vals[2])
      table[3] = BrotliHuffmanCode::new(2, vals[3])
      4
    }
    4 => {
      let vals = FixedArray::make(4, 0)
      for i in 0..<4 {
        vals[i] = symbols[i]
      }
      if vals[3] < vals[2] {
        let t = vals[3]
        vals[3] = vals[2]
        vals[2] = t
      }
      table[0] = BrotliHuffmanCode::new(1, vals[0])
      table[1] = BrotliHuffmanCode::new(2, vals[1])
      table[2] = BrotliHuffmanCode::new(1, vals[0])
      table[3] = BrotliHuffmanCode::new(3, vals[2])
      table[4] = BrotliHuffmanCode::new(1, vals[0])
      table[5] = BrotliHuffmanCode::new(2, vals[1])
      table[6] = BrotliHuffmanCode::new(1, vals[0])
      table[7] = BrotliHuffmanCode::new(3, vals[3])
      8
    }
    _ => raise fzip_err(BrotliInvalidHuffman, msg="invalid simple Huffman size")
  }
  let mut copied = base_size
  while copied < table_size {
    for i in 0..<copied {
      table[copied + i] = table[i]
    }
    copied *= 2
  }
  table
}

///|
fn brotli_read_simple_huffman_code(
  reader : BrotliBitReader,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  let num_symbols_code = reader.take_bits(2).reinterpret_as_int()
  let num_symbols_to_read = num_symbols_code + 1
  let max_bits = brotli_log2_floor_plus_one(alphabet_size_max - 1)
  let symbols = FixedArray::make(4, 0)
  for i in 0..<num_symbols_to_read {
    let value = reader.take_bits(max_bits).reinterpret_as_int()
    if value >= alphabet_size_limit {
      raise fzip_err(
        BrotliInvalidHuffman,
        msg="simple Huffman symbol exceeds alphabet limit",
      )
    }
    symbols[i] = value
  }
  for i in 0..<(num_symbols_to_read - 1) {
    for k in (i + 1)..<num_symbols_to_read {
      if symbols[i] == symbols[k] {
        raise fzip_err(
          BrotliInvalidHuffman,
          msg="duplicate simple Huffman symbol",
        )
      }
    }
  }
  let final_num_symbols_code = if num_symbols_code == 3 {
    num_symbols_code + reader.take_bits(1).reinterpret_as_int()
  } else {
    num_symbols_code
  }
  brotli_build_simple_huffman_table(symbols, final_num_symbols_code, root_bits)
}

///|
fn brotli_read_code_length_code_lengths(
  reader : BrotliBitReader,
  skip : Int,
) -> FixedArray[Byte] raise FzipError {
  let lengths = FixedArray::make(brotli_num_code_length_codes, b'\x00')
  let mut num_codes = 0
  let mut space = 32
  for i in skip..<brotli_num_code_length_codes {
    let ix = reader.peek_bits(4).reinterpret_as_int()
    let prefix_len = brotli_code_length_prefix_length[ix]
    let value = brotli_code_length_prefix_value[ix]
    reader.drop_bits(prefix_len)
    let code_len_idx = brotli_code_length_code_order[i]
    lengths[code_len_idx] = value.to_byte()
    if value != 0 {
      space -= 32 >> value
      num_codes += 1
      if space < 0 {
        raise fzip_err(
          BrotliInvalidHuffman,
          msg="over-subscribed code-length-code lengths",
        )
      }
    }
  }
  if !(num_codes == 1 || space == 0) {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="invalid code-length-code length space",
    )
  }
  lengths
}

///|
fn brotli_decode_symbol_code_lengths(
  reader : BrotliBitReader,
  code_length_table : FixedArray[BrotliHuffmanCode],
  alphabet_size : Int,
) -> FixedArray[Byte] raise FzipError {
  let lengths = FixedArray::make(alphabet_size, b'\x00')
  let mut symbol = 0
  let mut repeat = 0
  let mut space = 32768
  let mut prev_code_len = brotli_initial_repeated_code_length
  let mut repeat_code_len = 0
  while symbol < alphabet_size && space > 0 {
    let code_len = brotli_read_symbol(
      reader, code_length_table, brotli_huffman_max_code_length_code_length,
    )
    if code_len < brotli_repeat_previous_code_length {
      repeat = 0
      lengths[symbol] = code_len.to_byte()
      if code_len != 0 {
        prev_code_len = code_len
        space -= 32768 >> code_len
        if space < 0 {
          raise fzip_err(
            BrotliInvalidHuffman,
            msg="over-subscribed Huffman code lengths",
          )
        }
      }
      symbol += 1
    } else {
      let extra_bits = if code_len == brotli_repeat_previous_code_length {
        2
      } else if code_len == brotli_repeat_zero_code_length {
        3
      } else {
        raise fzip_err(BrotliInvalidHuffman, msg="invalid code-length repeat")
      }
      let new_len = if code_len == brotli_repeat_previous_code_length {
        prev_code_len
      } else {
        0
      }
      if repeat_code_len != new_len {
        repeat = 0
        repeat_code_len = new_len
      }
      let old_repeat = repeat
      if repeat > 0 {
        repeat -= 2
        repeat = repeat << extra_bits
      }
      repeat += reader.take_bits(extra_bits).reinterpret_as_int() + 3
      let repeat_delta = repeat - old_repeat
      if symbol > alphabet_size - repeat_delta {
        raise fzip_err(
          BrotliInvalidHuffman,
          msg="code-length repeat overflows alphabet",
        )
      }
      if repeat_code_len != 0 {
        for _ in 0..<repeat_delta {
          lengths[symbol] = repeat_code_len.to_byte()
          symbol += 1
        }
        space -= repeat_delta << (15 - repeat_code_len)
        if space < 0 {
          raise fzip_err(
            BrotliInvalidHuffman,
            msg="over-subscribed repeated Huffman code lengths",
          )
        }
      } else {
        symbol += repeat_delta
      }
    }
  }
  if space != 0 {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="under-subscribed Huffman code lengths",
    )
  }
  lengths
}

///|
fn brotli_read_complex_huffman_code(
  reader : BrotliBitReader,
  marker : Int,
  alphabet_size_limit : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  let code_length_code_lengths = brotli_read_code_length_code_lengths(
    reader, marker,
  )
  let code_length_table = brotli_build_huffman_table(
    code_length_code_lengths, brotli_num_code_length_codes, brotli_huffman_max_code_length_code_length,
  )
  let code_lengths = brotli_decode_symbol_code_lengths(
    reader, code_length_table, alphabet_size_limit,
  )
  brotli_build_huffman_table(code_lengths, alphabet_size_limit, root_bits)
}

///|
fn brotli_read_huffman_code(
  reader : BrotliBitReader,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  let marker = reader.take_bits(2).reinterpret_as_int()
  if marker == 1 {
    brotli_read_simple_huffman_code(
      reader, alphabet_size_max, alphabet_size_limit, root_bits,
    )
  } else {
    brotli_read_complex_huffman_code(
      reader, marker, alphabet_size_limit, root_bits,
    )
  }
}

///|
fn brotli_read_symbol(
  reader : BrotliBitReader,
  table : FixedArray[BrotliHuffmanCode],
  root_bits : Int,
) -> Int raise FzipError {
  let index = reader.peek_bits(root_bits).reinterpret_as_int()
  if index < 0 || index >= table.length() {
    raise fzip_err(BrotliInvalidHuffman, msg="Huffman lookup out of range")
  }
  let entry = table[index]
  if entry.bits < 0 {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="uninitialized Huffman table entry",
    )
  }
  if entry.bits <= root_bits {
    reader.drop_bits(entry.bits)
    return entry.value
  }
  reader.drop_bits(root_bits)
  let extra_bits = entry.bits - root_bits
  let sub_index = reader.peek_bits(extra_bits).reinterpret_as_int()
  let sub_entry = table[entry.value + sub_index]
  if sub_entry.bits < 0 {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="uninitialized Brotli Huffman sub-table entry",
    )
  }
  reader.drop_bits(sub_entry.bits)
  sub_entry.value
}

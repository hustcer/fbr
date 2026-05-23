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
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len != 0 {
      if len > root_bits {
        raise fzip_err(
          BrotliInvalidHuffman,
          msg="two-level Brotli Huffman tables are not implemented yet",
        )
      }
      let reversed = brotli_reverse_bits(next_code[len], len)
      next_code[len] += 1
      let step = 1 << len
      let entry = BrotliHuffmanCode::new(len, symbol)
      let mut index = reversed
      while index < table_size {
        table[index] = entry
        index += step
      }
    }
  }
  table
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
  if entry.bits > 0 {
    reader.drop_bits(entry.bits)
  }
  entry.value
}

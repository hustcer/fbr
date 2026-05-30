///|
/// One decoded Brotli Huffman table entry.
pub(all) struct BrotliHuffmanCode {
  bits : Int
  value : Int
}

///|
pub fn BrotliHuffmanCode::empty() -> BrotliHuffmanCode {
  { bits: -1, value: 0 }
}

///|
pub fn BrotliHuffmanCode::new(bits : Int, value : Int) -> BrotliHuffmanCode {
  { bits, value }
}

///|
pub fn brotli_reverse_bits(code : Int, len : Int) -> Int {
  rev[code] >> (15 - len)
}

///|
pub fn brotli_log2_floor_plus_one(x : Int) -> Int {
  let mut x = x
  let mut result = 0
  while x != 0 {
    x = x >> 1
    result += 1
  }
  result
}

///|
pub fn brotli_validate_huffman_lengths(
  count : FixedArray[Int],
  nonzero : Int,
) -> Unit raise FbrError {
  if nonzero == 0 {
    raise fbr_err(BrotliInvalidHuffman, msg="empty Huffman code")
  }
  if nonzero == 1 {
    return
  }
  let mut left = 1
  for bits in 1..<=brotli_huffman_max_code_length {
    left = (left << 1) - count[bits]
    if left < 0 {
      raise fbr_err(BrotliInvalidHuffman, msg="over-subscribed Huffman code")
    }
  }
  if left != 0 {
    raise fbr_err(BrotliInvalidHuffman, msg="under-subscribed Huffman code")
  }
}

///|
pub fn brotli_build_huffman_table(
  code_lengths : FixedArray[Byte],
  alphabet_size : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FbrError {
  if alphabet_size < 1 || alphabet_size > code_lengths.length() {
    raise fbr_err(BrotliInvalidHuffman, msg="invalid Huffman alphabet size")
  }
  if root_bits < 1 || root_bits > brotli_huffman_table_bits {
    raise fbr_err(BrotliInvalidHuffman, msg="invalid Huffman root width")
  }
  let count = FixedArray::make(brotli_huffman_max_code_length + 1, 0)
  let mut nonzero = 0
  let mut single_symbol = 0
  for symbol in 0..<alphabet_size {
    let len = code_lengths[symbol].to_int()
    if len < 0 || len > brotli_huffman_max_code_length {
      raise fbr_err(BrotliInvalidHuffman, msg="Huffman length out of range")
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
    raise fbr_err(
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
pub fn brotli_build_simple_huffman_table(
  symbols : FixedArray[Int],
  num_symbols_code : Int,
  root_bits : Int,
) -> FixedArray[BrotliHuffmanCode] raise FbrError {
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
    _ => raise fbr_err(BrotliInvalidHuffman, msg="invalid simple Huffman size")
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

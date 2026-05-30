///|
/// A decoded Brotli Huffman table entry, packed into a single `Int`.
///
/// Tables are stored as `FixedArray[Int]` rather than `FixedArray` of a boxed
/// struct so each lookup is one contiguous load instead of a pointer
/// dereference plus two field loads. The low 16 bits hold the code length as a
/// signed value (`-1` marks an unfilled entry); the high 16 bits hold the
/// symbol or sub-table offset. Code lengths fit in a few bits and values stay
/// well under 2^15, so the layout is lossless for every table Brotli builds.
pub fn brotli_huffman_code(bits : Int, value : Int) -> Int {
  (value << 16) | (bits & 0xffff)
}

///|
/// Extract the code length from a packed Huffman entry (sign-extended).
pub fn brotli_huffman_code_bits(code : Int) -> Int {
  code << 16 >> 16
}

///|
/// Extract the symbol / sub-table offset from a packed Huffman entry.
pub fn brotli_huffman_code_value(code : Int) -> Int {
  code >> 16
}

///|
/// Packed value for an unfilled Huffman table entry (`bits = -1`).
pub let brotli_huffman_code_empty : Int = brotli_huffman_code(-1, 0)

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
) -> FixedArray[Int] raise FbrError {
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
  if nonzero == 1 {
    let table = FixedArray::make(table_size, brotli_huffman_code_empty)
    let code = brotli_huffman_code(0, single_symbol)
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
  let table = FixedArray::make(total_size, brotli_huffman_code_empty)
  for root in 0..<table_size {
    if sub_bits_by_root[root] > 0 {
      table[root] = brotli_huffman_code(
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
      let entry = brotli_huffman_code(len, symbol)
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
        let sub_entry = brotli_huffman_code(len - root_bits, symbol)
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
) -> FixedArray[Int] raise FbrError {
  let table_size = 1 << root_bits
  let table = FixedArray::make(table_size, brotli_huffman_code_empty)
  let base_size = match num_symbols_code {
    0 => {
      table[0] = brotli_huffman_code(0, symbols[0])
      1
    }
    1 => {
      if symbols[1] > symbols[0] {
        table[0] = brotli_huffman_code(1, symbols[0])
        table[1] = brotli_huffman_code(1, symbols[1])
      } else {
        table[0] = brotli_huffman_code(1, symbols[1])
        table[1] = brotli_huffman_code(1, symbols[0])
      }
      2
    }
    2 => {
      table[0] = brotli_huffman_code(1, symbols[0])
      table[2] = brotli_huffman_code(1, symbols[0])
      if symbols[2] > symbols[1] {
        table[1] = brotli_huffman_code(2, symbols[1])
        table[3] = brotli_huffman_code(2, symbols[2])
      } else {
        table[1] = brotli_huffman_code(2, symbols[2])
        table[3] = brotli_huffman_code(2, symbols[1])
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
      table[0] = brotli_huffman_code(2, vals[0])
      table[2] = brotli_huffman_code(2, vals[1])
      table[1] = brotli_huffman_code(2, vals[2])
      table[3] = brotli_huffman_code(2, vals[3])
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
      table[0] = brotli_huffman_code(1, vals[0])
      table[1] = brotli_huffman_code(2, vals[1])
      table[2] = brotli_huffman_code(1, vals[0])
      table[3] = brotli_huffman_code(3, vals[2])
      table[4] = brotli_huffman_code(1, vals[0])
      table[5] = brotli_huffman_code(2, vals[1])
      table[6] = brotli_huffman_code(1, vals[0])
      table[7] = brotli_huffman_code(3, vals[3])
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

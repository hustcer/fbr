///|
fn brotli_read_simple_huffman_code(
  reader : BrotliBitReader,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
  root_bits : Int,
) -> FixedArray[Int] raise @common.FbrError {
  let num_symbols_code = reader.take_bits(2).reinterpret_as_int()
  let num_symbols_to_read = num_symbols_code + 1
  let max_bits = @common.brotli_log2_floor_plus_one(alphabet_size_max - 1)
  let symbols = FixedArray::make(4, 0)
  for i in 0..<num_symbols_to_read {
    let value = reader.take_bits(max_bits).reinterpret_as_int()
    if value >= alphabet_size_limit {
      raise @common.fbr_err(
        BrotliInvalidHuffman,
        msg="simple Huffman symbol exceeds alphabet limit",
      )
    }
    symbols[i] = value
  }
  for i in 0..<(num_symbols_to_read - 1) {
    for k in (i + 1)..<num_symbols_to_read {
      if symbols[i] == symbols[k] {
        raise @common.fbr_err(
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
  @common.brotli_build_simple_huffman_table(
    symbols, final_num_symbols_code, root_bits,
  )
}

///|
fn brotli_read_code_length_code_lengths(
  reader : BrotliBitReader,
  skip : Int,
) -> FixedArray[Byte] raise @common.FbrError {
  let lengths = FixedArray::make(@common.brotli_num_code_length_codes, b'\x00')
  let mut num_codes = 0
  let mut space = 32
  for i in skip..<@common.brotli_num_code_length_codes {
    let ix = reader.peek_bits(4).reinterpret_as_int()
    let prefix_len = @common.brotli_code_length_prefix_length[ix]
    let value = @common.brotli_code_length_prefix_value[ix]
    reader.drop_bits(prefix_len)
    let code_len_idx = @common.brotli_code_length_code_order[i]
    lengths[code_len_idx] = value.to_byte()
    if value != 0 {
      space -= 32 >> value
      num_codes += 1
      if space < 0 {
        raise @common.fbr_err(
          BrotliInvalidHuffman,
          msg="over-subscribed code-length-code lengths",
        )
      }
      if space == 0 {
        break
      }
    }
  }
  if !(num_codes == 1 || space == 0) {
    raise @common.fbr_err(
      BrotliInvalidHuffman,
      msg="invalid code-length-code length space",
    )
  }
  lengths
}

///|
fn brotli_decode_symbol_code_lengths(
  reader : BrotliBitReader,
  code_length_table : FixedArray[Int],
  alphabet_size : Int,
) -> FixedArray[Byte] raise @common.FbrError {
  let lengths = FixedArray::make(alphabet_size, b'\x00')
  let mut symbol = 0
  let mut repeat = 0
  let mut space = 32768
  let mut prev_code_len = @common.brotli_initial_repeated_code_length
  let mut repeat_code_len = 0
  while symbol < alphabet_size && space > 0 {
    let code_len = brotli_read_symbol(
      reader, code_length_table, @common.brotli_huffman_max_code_length_code_length,
    )
    if code_len < @common.brotli_repeat_previous_code_length {
      repeat = 0
      lengths[symbol] = code_len.to_byte()
      if code_len != 0 {
        prev_code_len = code_len
        space -= 32768 >> code_len
        if space < 0 {
          raise @common.fbr_err(
            BrotliInvalidHuffman,
            msg="over-subscribed Huffman code lengths",
          )
        }
      }
      symbol += 1
    } else {
      let extra_bits = if code_len == @common.brotli_repeat_previous_code_length {
        2
      } else if code_len == @common.brotli_repeat_zero_code_length {
        3
      } else {
        raise @common.fbr_err(
          BrotliInvalidHuffman,
          msg="invalid code-length repeat",
        )
      }
      let new_len = if code_len == @common.brotli_repeat_previous_code_length {
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
        raise @common.fbr_err(
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
          raise @common.fbr_err(
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
    raise @common.fbr_err(
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
) -> FixedArray[Int] raise @common.FbrError {
  let code_length_code_lengths = brotli_read_code_length_code_lengths(
    reader, marker,
  )
  let code_length_table = @common.brotli_build_huffman_table(
    code_length_code_lengths, @common.brotli_num_code_length_codes, @common.brotli_huffman_max_code_length_code_length,
  )
  let code_lengths = brotli_decode_symbol_code_lengths(
    reader, code_length_table, alphabet_size_limit,
  )
  @common.brotli_build_huffman_table(
    code_lengths, alphabet_size_limit, root_bits,
  )
}

///|
fn brotli_read_huffman_code(
  reader : BrotliBitReader,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
  root_bits : Int,
) -> FixedArray[Int] raise @common.FbrError {
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
  table : FixedArray[Int],
  root_bits : Int,
) -> Int raise @common.FbrError {
  // Table entries are packed ints: code length in the low 16 bits (signed),
  // symbol / sub-table offset in the high 16 bits. Extraction is inlined as
  // shifts so the hot path never makes a call (the C backend at -O0 would not
  // inline a helper). `>> 16` recovers the value; `<< 16 >> 16` sign-extends
  // the length so the `-1` empty sentinel stays negative.
  let entry0 = table[0]
  if (entry0 & 0xffff) == 0 {
    // Single-symbol table: length 0, value in the high bits.
    return entry0 >> 16
  }
  // Inlined fast path: refill until we have root_bits, or tolerate
  // running short at end of stream when an existing prefix can still
  // resolve a short Huffman code in the root table.
  if reader.bits_avail < root_bits {
    if reader.byte_pos >= reader.byte_end {
      if reader.bits_avail == 0 {
        raise @common.fbr_err(
          UnexpectedEOF,
          msg="brotli input ended during Huffman code",
        )
      }
      // Tail decode: leave bit_buf as-is, lookup may still pick a short code
    } else {
      reader.refill_to(root_bits)
    }
  }
  let mask_root = brotli_low_mask_lut[root_bits]
  // index < 2^root_bits <= table.length(), so no separate bound check is
  // needed: the root table always spans the first 2^root_bits entries.
  // `to_uint()` truncates the 64-bit accumulator to its low 32 bits, which
  // is enough because root_bits <= 15.
  let index = (reader.bit_buf.to_uint() & mask_root).reinterpret_as_int()
  let entry = table[index]
  let entry_bits = entry << 16 >> 16
  if entry_bits < 0 {
    raise @common.fbr_err(
      BrotliInvalidHuffman,
      msg="uninitialized Huffman table entry",
    )
  }
  if entry_bits <= root_bits {
    if entry_bits > reader.bits_avail {
      raise @common.fbr_err(
        UnexpectedEOF,
        msg="brotli input ended during Huffman code",
      )
    }
    // Inlined drop_bits: bit_buf >>= entry_bits; bits_avail -= entry_bits
    reader.bit_buf = reader.bit_buf >> entry_bits
    reader.bits_avail -= entry_bits
    return entry >> 16
  }
  // Sub-table path: drop root_bits, refill for the extra bits, lookup.
  reader.bit_buf = reader.bit_buf >> root_bits
  reader.bits_avail -= root_bits
  let extra_bits = entry_bits - root_bits
  if reader.bits_avail < extra_bits {
    reader.refill_to(extra_bits)
  }
  let mask_extra = brotli_low_mask_lut[extra_bits]
  let sub_index = (reader.bit_buf.to_uint() & mask_extra).reinterpret_as_int()
  let sub_entry = table[(entry >> 16) + sub_index]
  let sub_bits = sub_entry << 16 >> 16
  if sub_bits < 0 {
    raise @common.fbr_err(
      BrotliInvalidHuffman,
      msg="uninitialized Brotli Huffman sub-table entry",
    )
  }
  reader.bit_buf = reader.bit_buf >> sub_bits
  reader.bits_avail -= sub_bits
  sub_entry >> 16
}

///|
fn brotli_decode_var_len_uint8(reader : BrotliBitReader) -> Int raise FzipError {
  if reader.take_bits(1) == 0U {
    0
  } else {
    let bits = reader.take_bits(3).reinterpret_as_int()
    if bits == 0 {
      1
    } else {
      (1 << bits) + reader.take_bits(bits).reinterpret_as_int()
    }
  }
}

///|
fn brotli_read_block_type_count(
  reader : BrotliBitReader,
) -> Int raise FzipError {
  brotli_decode_var_len_uint8(reader) + 1
}

///|
fn brotli_read_block_length(
  reader : BrotliBitReader,
  table : FixedArray[BrotliHuffmanCode],
) -> Int raise FzipError {
  let code = brotli_read_symbol(reader, table, brotli_huffman_table_bits)
  if code < 0 || code >= brotli_num_block_length_symbols {
    raise fzip_err(
      BrotliInvalidMetablock,
      msg="invalid Brotli block length code",
    )
  }
  let extra_bits = brotli_block_length_extra_bits[code]
  brotli_block_length_bases[code] +
  reader.take_bits(extra_bits).reinterpret_as_int()
}

///|
priv struct BrotliBlockTracker {
  num_types : Int
  mut current_type : Int
  mut previous_type_2 : Int
  mut previous_type_1 : Int
  mut remaining : Int
}

///|
fn BrotliBlockTracker::new(
  num_types : Int,
) -> BrotliBlockTracker raise FzipError {
  if num_types < 1 {
    raise fzip_err(
      BrotliInvalidMetablock,
      msg="block type count must be positive",
    )
  }
  {
    num_types,
    current_type: 0,
    previous_type_2: 1,
    previous_type_1: 0,
    remaining: brotli_block_size_cap,
  }
}

///|
fn BrotliBlockTracker::resolve_type_code(
  self : BrotliBlockTracker,
  code : Int,
) -> Int raise FzipError {
  if self.num_types == 1 {
    self.current_type = 0
    return 0
  }
  let mut block_type = if code == 1 {
    self.previous_type_1 + 1
  } else if code == 0 {
    self.previous_type_2
  } else {
    code - 2
  }
  if block_type < 0 {
    raise fzip_err(BrotliInvalidMetablock, msg="negative block type")
  }
  if block_type >= self.num_types {
    block_type -= self.num_types
  }
  self.previous_type_2 = self.previous_type_1
  self.previous_type_1 = block_type
  self.current_type = block_type
  block_type
}

///|
fn BrotliBlockTracker::switch_with_code(
  self : BrotliBlockTracker,
  code : Int,
  length : Int,
) -> Unit raise FzipError {
  if length < 1 {
    raise fzip_err(BrotliInvalidMetablock, msg="block length must be positive")
  }
  ignore(self.resolve_type_code(code))
  self.remaining = length
}

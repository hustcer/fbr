///|
fn brotli_decode_var_len_uint8(
  reader : BrotliBitReader,
) -> Int raise @common.FbrError {
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
) -> Int raise @common.FbrError {
  brotli_decode_var_len_uint8(reader) + 1
}

///|
fn brotli_read_block_length(
  reader : BrotliBitReader,
  table : FixedArray[Int],
) -> Int raise @common.FbrError {
  let code = brotli_read_symbol(
    reader, table, @common.brotli_huffman_table_bits,
  )
  if code < 0 || code >= @common.brotli_num_block_length_symbols {
    raise @common.fbr_err(
      BrotliInvalidMetablock,
      msg="invalid Brotli block length code",
    )
  }
  let extra_bits = @common.brotli_block_length_extra_bits[code]
  @common.brotli_block_length_bases[code] +
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
fn BrotliBlockTracker::new_with_length(
  num_types : Int,
  initial_length : Int,
) -> BrotliBlockTracker raise @common.FbrError {
  if num_types < 1 {
    raise @common.fbr_err(
      BrotliInvalidMetablock,
      msg="block type count must be positive",
    )
  }
  if initial_length < 1 {
    raise @common.fbr_err(
      BrotliInvalidMetablock,
      msg="block length must be positive",
    )
  }
  {
    num_types,
    current_type: 0,
    previous_type_2: 1,
    previous_type_1: 0,
    remaining: initial_length,
  }
}

///|
fn BrotliBlockTracker::resolve_type_code(
  self : BrotliBlockTracker,
  code : Int,
) -> Int raise @common.FbrError {
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
    raise @common.fbr_err(
      BrotliInvalidMetablock,
      msg="negative block type",
    )
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
) -> Unit raise @common.FbrError {
  if length < 1 {
    raise @common.fbr_err(
      @common.BrotliInvalidMetablock,
      msg="block length must be positive",
    )
  }
  ignore(self.resolve_type_code(code))
  self.remaining = length
}

///|
fn BrotliBlockTracker::ensure_ready(
  self : BrotliBlockTracker,
  reader : BrotliBitReader,
  header : BrotliBlockSwitchHeader,
) -> Unit raise @common.FbrError {
  if self.remaining > 0 {
    return
  }
  if header.num_types == 1 {
    self.current_type = 0
    self.remaining = @common.brotli_block_size_cap
    return
  }
  guard header.type_tree is Some(type_tree) else {
    raise @common.fbr_err(
      BrotliInvalidMetablock,
      msg="missing Brotli block type tree",
    )
  }
  guard header.length_tree is Some(length_tree) else {
    raise @common.fbr_err(
      BrotliInvalidMetablock,
      msg="missing Brotli block length tree",
    )
  }
  let type_code = brotli_read_symbol(
    reader, type_tree, @common.brotli_huffman_table_bits,
  )
  let length = brotli_read_block_length(reader, length_tree)
  self.switch_with_code(type_code, length)
}

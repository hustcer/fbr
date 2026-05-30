///|
type FbrErrorCode = @common.FbrErrorCode

///|
type FbrError = @common.FbrError

///|
type BrotliDistanceRing = @common.BrotliDistanceRing

///|
let default_max_input_size = @common.default_max_input_size

///|
let default_max_output_size = @common.default_max_output_size

///|
let brotli_block_size_cap = @common.brotli_block_size_cap

///|
let brotli_huffman_table_bits = @common.brotli_huffman_table_bits

///|
let brotli_num_literal_symbols = @common.brotli_num_literal_symbols

///|
let brotli_num_command_symbols = @common.brotli_num_command_symbols

///|
let brotli_num_block_length_symbols = @common.brotli_num_block_length_symbols

///|
let brotli_literal_context_bits = @common.brotli_literal_context_bits

///|
let brotli_distance_context_bits = @common.brotli_distance_context_bits

///|
fn fbr_err(code : FbrErrorCode, msg? : String = "") -> FbrError {
  @common.fbr_err(code, msg~)
}

///|
fn trim_buf(data : FixedArray[Byte], len : Int) -> FixedArray[Byte] {
  @common.trim_buf(data, len)
}

///|
fn brotli_build_huffman_table(
  lengths : FixedArray[Byte],
  alphabet_size : Int,
  root_bits : Int,
) -> FixedArray[Int] raise FbrError {
  @common.brotli_build_huffman_table(lengths, alphabet_size, root_bits)
}

///|
fn brotli_distance_alphabet_size(
  postfix_bits : Int,
  direct_codes : Int,
  max_distance_bits : Int,
) -> Int {
  @common.brotli_distance_alphabet_size(
    postfix_bits, direct_codes, max_distance_bits,
  )
}

///|
fn brotli_command_info(
  symbol : Int,
) -> @common.BrotliCommandInfo raise FbrError {
  @common.brotli_command_info(symbol)
}

///|
fn brotli_distance_ring_slot(code : Int) -> Int {
  @common.brotli_distance_ring_slot(code)
}

///|
fn brotli_distance_extra_bits(
  code : Int,
  postfix_bits : Int,
  direct_codes : Int,
) -> Int raise FbrError {
  @common.brotli_distance_extra_bits(code, postfix_bits, direct_codes)
}

///|
fn brotli_distance_offset(
  code : Int,
  postfix_bits : Int,
  direct_codes : Int,
) -> Int raise FbrError {
  @common.brotli_distance_offset(code, postfix_bits, direct_codes)
}

///|
fn brotli_literal_context_id(
  mode : Int,
  previous_byte : Int,
  previous_byte2 : Int,
) -> Int raise FbrError {
  @common.brotli_literal_context_id(mode, previous_byte, previous_byte2)
}

///|
fn brotli_transform_count() -> Int {
  @common.brotli_transform_count()
}

///|
type FzipErrorCode = @common.FzipErrorCode

///|
type FzipError = @common.FzipError

///|
let default_max_input_size = @common.default_max_input_size

///|
let brotli_max_metablock_bytes = @common.brotli_max_metablock_bytes

///|
let brotli_dictionary_size_bits_by_length = @common.brotli_dictionary_size_bits_by_length

///|
fn brotli_literal_context_id(
  mode : Int,
  previous_byte : Int,
  previous_byte2 : Int,
) -> Int raise FzipError {
  @common.brotli_literal_context_id(mode, previous_byte, previous_byte2)
}

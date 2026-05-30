///|
pub type FbrErrorCode = @common.FbrErrorCode

///|
pub type FbrError = @common.FbrError

///|
pub type FlateStreamHandler = @common.FlateStreamHandler

///|
pub type UnbrotliOptions = @decode.UnbrotliOptions

///|
pub type BrotliOptions = @encode.BrotliOptions

///|
pub type UnbrotliStream = @decode.UnbrotliStream

///|
pub type BrotliStream = @encode.BrotliStream

///|
pub let default_max_output_size : Int = @common.default_max_output_size

///|
pub let default_max_input_size : Int = @common.default_max_input_size

///|
pub fn fbr_err(
  code : @common.FbrErrorCode,
  msg? : String = "",
) -> @common.FbrError {
  @common.fbr_err(code, msg~)
}

///|
pub fn fbr_error_code_to_int(code : @common.FbrErrorCode) -> Int {
  @common.fbr_error_code_to_int(code)
}

///|
pub fn unbrotli_sync(
  data : FixedArray[Byte],
  opts? : @decode.UnbrotliOptions = @decode.UnbrotliOptions::default(),
) -> FixedArray[Byte] raise @common.FbrError {
  @decode.unbrotli_sync(data, opts~)
}

///|
pub fn brotli_sync(
  data : FixedArray[Byte],
  opts? : @encode.BrotliOptions = @encode.BrotliOptions::default(),
) -> FixedArray[Byte] raise @common.FbrError {
  @encode.brotli_sync(data, opts~)
}

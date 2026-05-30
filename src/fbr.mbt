///|
pub type FzipErrorCode = @common.FzipErrorCode

///|
pub type FzipError = @common.FzipError

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
pub fn fzip_err(
  code : @common.FzipErrorCode,
  msg? : String = "",
) -> @common.FzipError {
  @common.fzip_err(code, msg~)
}

///|
pub fn fzip_error_code_to_int(code : @common.FzipErrorCode) -> Int {
  @common.fzip_error_code_to_int(code)
}

///|
pub fn unbrotli_sync(
  data : FixedArray[Byte],
  opts? : @decode.UnbrotliOptions = @decode.UnbrotliOptions::default(),
) -> FixedArray[Byte] raise @common.FzipError {
  @decode.unbrotli_sync(data, opts~)
}

///|
pub fn brotli_sync(
  data : FixedArray[Byte],
  opts? : @encode.BrotliOptions = @encode.BrotliOptions::default(),
) -> FixedArray[Byte] raise @common.FzipError {
  @encode.brotli_sync(data, opts~)
}

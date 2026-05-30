///|
pub fn brotli_literal_context_id(
  mode : Int,
  previous_byte_1 : Int,
  previous_byte_2 : Int,
) -> Int raise FbrError {
  let p1 = previous_byte_1 & 0xff
  let p2 = previous_byte_2 & 0xff
  match mode & 3 {
    0 => p1 & 0x3f
    1 => p1 >> 2
    2 => brotli_utf8_lut1[p1] | brotli_utf8_lut2[p2]
    3 => brotli_signed_lut1[p1] | brotli_signed_lut2[p2]
    _ =>
      raise fbr_err(BrotliInvalidContextMap, msg="invalid Brotli context mode")
  }
}

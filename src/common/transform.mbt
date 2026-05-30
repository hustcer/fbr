///|
pub let brotli_transform_identity : Int = 0

///|
pub let brotli_transform_omit_last_9 : Int = 9

///|
pub let brotli_transform_uppercase_first : Int = 10

///|
pub let brotli_transform_uppercase_all : Int = 11

///|
pub let brotli_transform_omit_first_1 : Int = 12

///|
pub let brotli_transform_omit_first_9 : Int = 20

///|
pub let brotli_transform_shift_first : Int = 21

///|
pub let brotli_transform_shift_all : Int = 22

///|
pub fn brotli_transform_count() -> Int {
  brotli_transform_triplets.length() / 3
}

///|
pub fn brotli_transform_string_offset(id : Int) -> Int raise FbrError {
  if id < 0 || id >= brotli_transform_prefix_suffix_map.length() {
    raise fbr_err(
      BrotliInvalidTransform,
      msg="Brotli transform string id out of range",
    )
  }
  let offset = brotli_transform_prefix_suffix_map[id]
  if offset < 0 || offset >= brotli_transform_prefix_suffix.length() {
    raise fbr_err(
      BrotliInvalidTransform,
      msg="Brotli transform string out of range",
    )
  }
  offset
}

///|
pub fn brotli_transform_string_length(id : Int) -> Int raise FbrError {
  brotli_transform_prefix_suffix[brotli_transform_string_offset(id)].to_int()
}

///|
pub fn brotli_ascii_upper(byte : Byte) -> Byte {
  let value = byte.to_int()
  if value >= 97 && value <= 122 {
    (value - 32).to_byte()
  } else {
    byte
  }
}

///|
pub fn brotli_uppercase_first(
  buf : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  if length <= 0 {
    return
  }
  let first = buf[offset].to_int()
  if first < 0xc0 {
    buf[offset] = brotli_ascii_upper(buf[offset])
  } else if first < 0xe0 && length >= 2 {
    buf[offset + 1] = (buf[offset + 1].to_int() ^ 32).to_byte()
  } else if length >= 3 {
    buf[offset + 2] = (buf[offset + 2].to_int() ^ 5).to_byte()
  }
}

///|
pub fn brotli_uppercase_all(
  buf : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  let mut index = offset
  let end = offset + length
  while index < end {
    let first = buf[index].to_int()
    let step = if first < 0xc0 {
      buf[index] = brotli_ascii_upper(buf[index])
      1
    } else if first < 0xe0 {
      if index + 1 < end {
        buf[index + 1] = (buf[index + 1].to_int() ^ 32).to_byte()
      }
      2
    } else {
      if index + 2 < end {
        buf[index + 2] = (buf[index + 2].to_int() ^ 5).to_byte()
      }
      3
    }
    index += step
  }
}

///|

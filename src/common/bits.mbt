///|
/// Get end of byte boundary
pub fn shft(p : Int) -> Int {
  (p + 7) / 8
}

///|
/// Largest positive Int value, used to clamp capacity math before allocation
pub fn max_int_val() -> Int {
  ((-1).reinterpret_as_uint() >> 1).reinterpret_as_int()
}

///|
/// Slice a FixedArray (copy)
pub fn slc(
  v : FixedArray[Byte],
  s : Int,
  e? : Int = v.length(),
) -> FixedArray[Byte] {
  let start = if s < 0 { 0 } else { s }
  let end = if e > v.length() { v.length() } else { e }
  let len = end - start
  if len <= 0 {
    return FixedArray::make(0, b'\x00')
  }
  let result = FixedArray::make(len, b'\x00')
  v.blit_to(result, len~, src_offset=start, dst_offset=0)
  result
}

///|
/// Trim buffer to actual length (avoid copy if already exact size)
pub fn trim_buf(buf : FixedArray[Byte], len : Int) -> FixedArray[Byte] {
  if len < buf.length() {
    slc(buf, 0, e=len)
  } else {
    buf
  }
}

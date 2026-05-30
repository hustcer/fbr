// Shared white-box test helpers for the Brotli encoder tests.

///|
fn str_to_u8(s : String, latin1? : Bool = false) -> FixedArray[Byte] {
  if latin1 {
    let ar = FixedArray::make(s.length(), b'\x00')
    for i in 0..<s.length() {
      ar[i] = s[i].to_int().to_byte()
    }
    return ar
  }
  let l = s.length()
  let mut ar = FixedArray::make(l + (l >> 1) + 8, b'\x00')
  let mut ai = 0
  let mut i = 0
  while i < l {
    if ai + 5 > ar.length() {
      let n = FixedArray::make(ai + 8 + ((l - i) << 1), b'\x00')
      ar.blit_to(n, len=ai, src_offset=0, dst_offset=0)
      ar = n
    }
    let mut c = s[i].to_int()
    if c < 128 {
      ar[ai] = c.to_byte()
      ai += 1
    } else if c < 2048 {
      ar[ai] = (192 | (c >> 6)).to_byte()
      ai += 1
      ar[ai] = (128 | (c & 63)).to_byte()
      ai += 1
    } else if c > 55295 && c < 57344 {
      i += 1
      let low = if i < l { s[i].to_int() } else { 0 }
      c = (65536 + ((c & 1023) << 10)) | (low & 1023)
      ar[ai] = (240 | (c >> 18)).to_byte()
      ai += 1
      ar[ai] = (128 | ((c >> 12) & 63)).to_byte()
      ai += 1
      ar[ai] = (128 | ((c >> 6) & 63)).to_byte()
      ai += 1
      ar[ai] = (128 | (c & 63)).to_byte()
      ai += 1
    } else {
      ar[ai] = (224 | (c >> 12)).to_byte()
      ai += 1
      ar[ai] = (128 | ((c >> 6) & 63)).to_byte()
      ai += 1
      ar[ai] = (128 | (c & 63)).to_byte()
      ai += 1
    }
    i += 1
  }
  @common.trim_buf(ar, ai)
}

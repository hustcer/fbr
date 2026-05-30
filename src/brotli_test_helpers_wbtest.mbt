// Shared white-box test helpers for the Brotli decoder tests.
//
// These functions are only used by `*_wbtest.mbt` files (e.g. to build raw
// Brotli bitstreams and to render decoded output as a `String`), so they live
// in a test file rather than in package source to avoid unused-symbol warnings
// in non-test builds.

///|
/// Encode a `String` into UTF-8 (or latin1) bytes (test helper).
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
  trim_buf(ar, ai)
}

///|
/// Write bits to data at bit position p (test helper).
fn wbits(d : FixedArray[Byte], p : Int, v : Int) -> Unit {
  let v = v << (p & 7)
  let o = p / 8
  d[o] = (d[o].to_int() | v).to_byte()
  if o + 1 < d.length() {
    d[o + 1] = (d[o + 1].to_int() | (v >> 8)).to_byte()
  }
}

///|
/// Write 16+ bits to data at bit position p (test helper).
fn wbits16(d : FixedArray[Byte], p : Int, v : Int) -> Unit {
  let v = v << (p & 7)
  let o = p / 8
  d[o] = (d[o].to_int() | v).to_byte()
  if o + 1 < d.length() {
    d[o + 1] = (d[o + 1].to_int() | (v >> 8)).to_byte()
  }
  if o + 2 < d.length() {
    d[o + 2] = (d[o + 2].to_int() | (v >> 16)).to_byte()
  }
}

///|
/// Decode bytes into a `String` as strict UTF-8 (test helper).
///
/// Mirrors the strict RFC 3629 decoding used by the original fzip helper so the
/// decoder tests can render output text. Raises `FzipError(InvalidUTF8)` on any
/// invalid sequence.
fn str_from_u8(
  data : FixedArray[Byte],
  latin1? : Bool = false,
  offset? : Int = 0,
  len? : Int = -1,
) -> String raise FzipError {
  let actual_len = if len < 0 { data.length() - offset } else { len }
  let end = offset + actual_len
  if latin1 {
    let buf = StringBuilder::new()
    for i in offset..<end {
      buf.write_char(data[i].to_int().unsafe_to_char())
    }
    return buf.to_string()
  }
  let buf = StringBuilder::new()
  let mut i = offset
  while i < end {
    let c = data[i].to_int()
    if c < 0x80 {
      buf.write_char(c.unsafe_to_char())
      i += 1
    } else if c < 0xC2 {
      raise fzip_err(InvalidUTF8)
    } else if c < 0xE0 {
      if i + 1 >= end {
        raise fzip_err(InvalidUTF8)
      }
      let c1 = data[i + 1].to_int()
      if (c1 & 0xC0) != 0x80 {
        raise fzip_err(InvalidUTF8)
      }
      let cp = ((c & 0x1F) << 6) | (c1 & 0x3F)
      buf.write_char(cp.unsafe_to_char())
      i += 2
    } else if c < 0xF0 {
      if i + 2 >= end {
        raise fzip_err(InvalidUTF8)
      }
      let c1 = data[i + 1].to_int()
      let c2 = data[i + 2].to_int()
      if (c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80 {
        raise fzip_err(InvalidUTF8)
      }
      let cp = ((c & 0x0F) << 12) | ((c1 & 0x3F) << 6) | (c2 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise fzip_err(InvalidUTF8)
      }
      buf.write_char(cp.unsafe_to_char())
      i += 3
    } else if c < 0xF5 {
      if i + 3 >= end {
        raise fzip_err(InvalidUTF8)
      }
      let c1 = data[i + 1].to_int()
      let c2 = data[i + 2].to_int()
      let c3 = data[i + 3].to_int()
      if (c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80 {
        raise fzip_err(InvalidUTF8)
      }
      let cp = ((c & 0x07) << 18) |
        ((c1 & 0x3F) << 12) |
        ((c2 & 0x3F) << 6) |
        (c3 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise fzip_err(InvalidUTF8)
      }
      let v = cp - 0x10000
      buf.write_char((0xD800 | (v >> 10)).unsafe_to_char())
      buf.write_char((0xDC00 | (v & 0x3FF)).unsafe_to_char())
      i += 4
    } else {
      raise fzip_err(InvalidUTF8)
    }
  }
  buf.to_string()
}

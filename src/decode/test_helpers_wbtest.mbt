// Shared white-box test helpers for the Brotli decoder tests.
//
// These functions are only used by `*_wbtest.mbt` files (e.g. to build raw
// Brotli bitstreams and to render decoded output as a `String`), so they live
// in a test file rather than in package source to avoid unused-symbol warnings
// in non-test builds.

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
/// decoder tests can render output text. Raises `FbrError(InvalidUTF8)` on any
/// invalid sequence.
fn str_from_u8(
  data : FixedArray[Byte],
  latin1? : Bool = false,
  offset? : Int = 0,
  len? : Int = -1,
) -> String raise FbrError {
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
      raise fbr_err(InvalidUTF8)
    } else if c < 0xE0 {
      if i + 1 >= end {
        raise fbr_err(InvalidUTF8)
      }
      let c1 = data[i + 1].to_int()
      if (c1 & 0xC0) != 0x80 {
        raise fbr_err(InvalidUTF8)
      }
      let cp = ((c & 0x1F) << 6) | (c1 & 0x3F)
      buf.write_char(cp.unsafe_to_char())
      i += 2
    } else if c < 0xF0 {
      if i + 2 >= end {
        raise fbr_err(InvalidUTF8)
      }
      let c1 = data[i + 1].to_int()
      let c2 = data[i + 2].to_int()
      if (c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80 {
        raise fbr_err(InvalidUTF8)
      }
      let cp = ((c & 0x0F) << 12) | ((c1 & 0x3F) << 6) | (c2 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise fbr_err(InvalidUTF8)
      }
      buf.write_char(cp.unsafe_to_char())
      i += 3
    } else if c < 0xF5 {
      if i + 3 >= end {
        raise fbr_err(InvalidUTF8)
      }
      let c1 = data[i + 1].to_int()
      let c2 = data[i + 2].to_int()
      let c3 = data[i + 3].to_int()
      if (c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80 {
        raise fbr_err(InvalidUTF8)
      }
      let cp = ((c & 0x07) << 18) |
        ((c1 & 0x3F) << 12) |
        ((c2 & 0x3F) << 6) |
        (c3 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise fbr_err(InvalidUTF8)
      }
      let v = cp - 0x10000
      buf.write_char((0xD800 | (v >> 10)).unsafe_to_char())
      buf.write_char((0xDC00 | (v & 0x3FF)).unsafe_to_char())
      i += 4
    } else {
      raise fbr_err(InvalidUTF8)
    }
  }
  buf.to_string()
}

///|
/// LSB-first bit reader used by the Brotli decoder.
priv struct BrotliBitReader {
  buf : FixedArray[Byte]
  mut byte_pos : Int
  byte_end : Int
  mut bit_buf : UInt
  mut bits_avail : Int
}

///|
fn BrotliBitReader::new(
  buf : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> BrotliBitReader {
  {
    buf,
    byte_pos: offset,
    byte_end: offset + length,
    bit_buf: 0U,
    bits_avail: 0,
  }
}

///|
fn BrotliBitReader::clone(self : BrotliBitReader) -> BrotliBitReader {
  {
    buf: self.buf,
    byte_pos: self.byte_pos,
    byte_end: self.byte_end,
    bit_buf: self.bit_buf,
    bits_avail: self.bits_avail,
  }
}

///|
fn BrotliBitReader::with_buffer(
  self : BrotliBitReader,
  buf : FixedArray[Byte],
) -> BrotliBitReader {
  {
    buf,
    byte_pos: self.byte_pos,
    byte_end: buf.length(),
    bit_buf: self.bit_buf,
    bits_avail: self.bits_avail,
  }
}

///|
fn BrotliBitReader::refill_to(
  self : BrotliBitReader,
  n : Int,
) -> Unit raise @common.FbrError {
  if self.bits_avail >= n {
    return
  }
  if self.bits_avail == 0 && self.byte_pos + 3 < self.byte_end {
    let p = self.byte_pos
    let buf = self.buf
    self.bit_buf = buf[p].to_uint() |
      (buf[p + 1].to_uint() << 8) |
      (buf[p + 2].to_uint() << 16) |
      (buf[p + 3].to_uint() << 24)
    self.byte_pos = p + 4
    self.bits_avail = 32
    return
  }
  // Fast path: when at least one byte of room remains in the accumulator
  // (bits_avail <= 24) and at least 3 bytes of input are available, fill
  // three bytes at once. Branch-free, no EOF check needed for the fast
  // path because we only take it when 3 input bytes are guaranteed.
  if self.bits_avail < n &&
    self.bits_avail <= 8 &&
    self.byte_pos + 2 < self.byte_end {
    let p = self.byte_pos
    let buf = self.buf
    self.bit_buf = self.bit_buf |
      (buf[p].to_uint() << self.bits_avail) |
      (buf[p + 1].to_uint() << (self.bits_avail + 8)) |
      (buf[p + 2].to_uint() << (self.bits_avail + 16))
    self.byte_pos = p + 3
    self.bits_avail += 24
    if self.bits_avail >= n {
      return
    }
  }
  while self.bits_avail < n {
    if self.byte_pos >= self.byte_end {
      raise @common.fbr_err(
        @common.UnexpectedEOF,
        msg="brotli input ended while reading bits need=\{n} available=\{self.bits_avail}",
      )
    }
    self.bit_buf = self.bit_buf |
      (self.buf[self.byte_pos].to_uint() << self.bits_avail)
    self.byte_pos += 1
    self.bits_avail += 8
  }
}

///|
/// Pre-computed low-`n` bit masks indexed by `n` (0..=32). Allows
/// `brotli_low_mask(n)` to be a single array load instead of a branched
/// shift, which removes a measurable slice from the Huffman hot path.
let brotli_low_mask_lut : FixedArray[UInt] = [
  0U, 0x1U, 0x3U, 0x7U, 0xfU, 0x1fU, 0x3fU, 0x7fU, 0xffU, 0x1ffU, 0x3ffU, 0x7ffU,
  0xfffU, 0x1fffU, 0x3fffU, 0x7fffU, 0xffffU, 0x1ffffU, 0x3ffffU, 0x7ffffU, 0xfffffU,
  0x1fffffU, 0x3fffffU, 0x7fffffU, 0xffffffU, 0x1ffffffU, 0x3ffffffU, 0x7ffffffU,
  0xfffffffU, 0x1fffffffU, 0x3fffffffU, 0x7fffffffU, 0xffffffffU,
]

///|
fn brotli_low_mask(n : Int) -> UInt {
  brotli_low_mask_lut[n]
}

///|
fn BrotliBitReader::peek_bits(
  self : BrotliBitReader,
  n : Int,
) -> UInt raise @common.FbrError {
  if n < 0 || n > 24 {
    raise @common.fbr_err(
      @common.BrotliInvalidMetablock,
      msg="invalid Brotli bit read width",
    )
  }
  self.refill_to(n)
  self.bit_buf & brotli_low_mask(n)
}

///|
fn BrotliBitReader::drop_bits(
  self : BrotliBitReader,
  n : Int,
) -> Unit raise @common.FbrError {
  if n < 0 || n > self.bits_avail {
    raise @common.fbr_err(
      @common.BrotliInvalidMetablock,
      msg="invalid Brotli bit drop width",
    )
  }
  self.bit_buf = self.bit_buf >> n
  self.bits_avail -= n
}

///|
fn BrotliBitReader::take_bits(
  self : BrotliBitReader,
  n : Int,
) -> UInt raise @common.FbrError {
  let value = self.peek_bits(n)
  self.drop_bits(n)
  value
}

///|
fn BrotliBitReader::align_to_byte(
  self : BrotliBitReader,
) -> Unit raise @common.FbrError {
  // bits_avail is always non-negative; `bits_avail & 7` matches the number of
  // padding bits we must consume to land on the next byte boundary (because
  // every refill loads whole bytes and starts byte-aligned).
  let extra = self.bits_avail & 7
  if extra > 0 {
    let padding = self.take_bits(extra)
    if padding != 0U {
      raise @common.fbr_err(@common.BrotliInvalidPadding)
    }
  }
}

///|
fn BrotliBitReader::take_bytes(
  self : BrotliBitReader,
  out : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit raise @common.FbrError {
  self.align_to_byte()
  if offset < 0 || length < 0 || offset > out.length() - length {
    raise @common.fbr_err(@common.InvalidZipData, msg="output buffer too small")
  }
  let mut dst = offset
  let end = offset + length
  while dst < end && self.bits_avail >= 8 {
    out[dst] = (self.bit_buf & 0xffU).to_byte()
    self.bit_buf = self.bit_buf >> 8
    self.bits_avail -= 8
    dst += 1
  }
  let remaining = end - dst
  if remaining > self.byte_end - self.byte_pos {
    raise @common.fbr_err(
      @common.UnexpectedEOF,
      msg="brotli input ended while reading bytes",
    )
  }
  if remaining > 0 {
    self.buf.blit_to(
      out,
      len=remaining,
      src_offset=self.byte_pos,
      dst_offset=dst,
    )
    self.byte_pos += remaining
  }
}

///|
fn BrotliBitReader::expect_final_padding_zero(
  self : BrotliBitReader,
) -> Unit raise @common.FbrError {
  if self.bits_avail > 0 {
    let mask = brotli_low_mask(self.bits_avail)
    if (self.bit_buf & mask) != 0U {
      raise @common.fbr_err(@common.BrotliInvalidPadding)
    }
  }
  while self.byte_pos < self.byte_end {
    if self.buf[self.byte_pos] != b'\x00' {
      raise @common.fbr_err(@common.BrotliInvalidPadding)
    }
    self.byte_pos += 1
  }
}

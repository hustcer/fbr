///|
/// LSB-first bit reader used by the Brotli decoder.
priv struct BrotliBitReader {
  buf : FixedArray[Byte]
  mut byte_pos : Int
  byte_end : Int
  mut bit_buf : UInt
  mut bits_avail : Int
  mut consumed : Int
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
    consumed: 0,
  }
}

///|
fn BrotliBitReader::refill_to(
  self : BrotliBitReader,
  n : Int,
) -> Unit raise FzipError {
  while self.bits_avail < n {
    if self.byte_pos >= self.byte_end {
      raise fzip_err(UnexpectedEOF, msg="brotli input ended while reading bits")
    }
    self.bit_buf = self.bit_buf |
      (self.buf[self.byte_pos].to_uint() << self.bits_avail)
    self.byte_pos += 1
    self.bits_avail += 8
  }
}

///|
fn brotli_low_mask(n : Int) -> UInt {
  if n == 0 {
    0U
  } else if n >= 32 {
    0xffffffffU
  } else {
    (1U << n) - 1U
  }
}

///|
fn BrotliBitReader::peek_bits(
  self : BrotliBitReader,
  n : Int,
) -> UInt raise FzipError {
  if n < 0 || n > 24 {
    raise fzip_err(BrotliInvalidMetablock, msg="invalid Brotli bit read width")
  }
  self.refill_to(n)
  self.bit_buf & brotli_low_mask(n)
}

///|
fn BrotliBitReader::drop_bits(
  self : BrotliBitReader,
  n : Int,
) -> Unit raise FzipError {
  if n < 0 || n > self.bits_avail {
    raise fzip_err(BrotliInvalidMetablock, msg="invalid Brotli bit drop width")
  }
  self.bit_buf = self.bit_buf >> n
  self.bits_avail -= n
  self.consumed += n
}

///|
fn BrotliBitReader::take_bits(
  self : BrotliBitReader,
  n : Int,
) -> UInt raise FzipError {
  let value = self.peek_bits(n)
  self.drop_bits(n)
  value
}

///|
fn BrotliBitReader::align_to_byte(
  self : BrotliBitReader,
) -> Unit raise FzipError {
  let extra = self.consumed & 7
  if extra > 0 {
    let padding = self.take_bits(8 - extra)
    if padding != 0U {
      raise fzip_err(BrotliInvalidPadding)
    }
  }
}

///|
fn BrotliBitReader::take_bytes(
  self : BrotliBitReader,
  out : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit raise FzipError {
  self.align_to_byte()
  if offset < 0 || length < 0 || offset > out.length() - length {
    raise fzip_err(InvalidZipData, msg="output buffer too small")
  }
  let mut dst = offset
  let end = offset + length
  while dst < end && self.bits_avail >= 8 {
    out[dst] = (self.bit_buf & 0xffU).to_byte()
    self.bit_buf = self.bit_buf >> 8
    self.bits_avail -= 8
    self.consumed += 8
    dst += 1
  }
  let remaining = end - dst
  if remaining > self.byte_end - self.byte_pos {
    raise fzip_err(UnexpectedEOF, msg="brotli input ended while reading bytes")
  }
  if remaining > 0 {
    self.buf.blit_to(
      out,
      len=remaining,
      src_offset=self.byte_pos,
      dst_offset=dst,
    )
    self.byte_pos += remaining
    self.consumed += remaining * 8
  }
}

///|
fn BrotliBitReader::expect_final_padding_zero(
  self : BrotliBitReader,
) -> Unit raise FzipError {
  if self.bits_avail > 0 {
    let mask = brotli_low_mask(self.bits_avail)
    if (self.bit_buf & mask) != 0U {
      raise fzip_err(BrotliInvalidPadding)
    }
  }
  while self.byte_pos < self.byte_end {
    if self.buf[self.byte_pos] != b'\x00' {
      raise fzip_err(BrotliInvalidPadding)
    }
    self.byte_pos += 1
  }
}

///|
fn BrotliBitReader::bits_consumed(self : BrotliBitReader) -> Int {
  self.consumed
}

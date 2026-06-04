///|
fn brotli_decode_window_bits(
  reader : BrotliBitReader,
) -> Int raise @common.FbrError {
  if reader.take_bits(1) == 0U {
    16
  } else {
    let n = reader.take_bits(3).reinterpret_as_int()
    if n != 0 {
      17 + n
    } else {
      let m = reader.take_bits(3).reinterpret_as_int()
      match m {
        0 => 17
        1 => raise @common.fbr_err(@common.BrotliLargeWindowNotSupported)
        2..=7 => 8 + m
        _ => raise @common.fbr_err(@common.BrotliInvalidWindowBits)
      }
    }
  }
}

///|
fn brotli_validate_window_bits(
  window_bits : Int,
) -> Unit raise @common.FbrError {
  if window_bits < @common.brotli_min_window_bits ||
    window_bits > @common.brotli_max_window_bits {
    raise @common.fbr_err(@common.BrotliInvalidWindowBits)
  }
}

///|
fn brotli_empty_output(opts : UnbrotliOptions) -> FixedArray[Byte] {
  match opts.out {
    Some(out) => @common.trim_buf(out, 0)
    None => FixedArray::make(0, b'\x00')
  }
}

///|
priv struct BrotliMetablockHeader {
  is_last : Bool
  is_empty : Bool
  is_metadata : Bool
  is_uncompressed : Bool
  length : Int
}

///|
priv struct BrotliOutputBuilder {
  mut buf : FixedArray[Byte]
  mut len : Int
  fixed : Bool
  max_output_size : Int
}

///|
priv struct BrotliDecoderState {
  distance_ring : @common.BrotliDistanceRing
  max_backward_distance : Int
}

///|
fn BrotliDecoderState::new_with_window_bits(
  window_bits : Int,
) -> BrotliDecoderState {
  {
    distance_ring: @common.BrotliDistanceRing::new(),
    max_backward_distance: (1 << window_bits) - @common.brotli_window_gap,
  }
}

///|
fn BrotliDecoderState::max_distance(
  self : BrotliDecoderState,
  output_len : Int,
) -> Int {
  if output_len < self.max_backward_distance {
    output_len
  } else {
    self.max_backward_distance
  }
}

///|
fn brotli_initial_output_capacity(
  max_output_size : Int,
  input_len : Int,
) -> Int {
  if max_output_size <= 0 {
    return 0
  }
  let min_capacity = 4096
  let base = if input_len > min_capacity { input_len } else { min_capacity }
  let scaled = if input_len > @common.max_int_val() / 5 {
    @common.max_int_val()
  } else {
    input_len * 5
  }
  let wanted = if scaled > base { scaled } else { base }
  if wanted > max_output_size {
    max_output_size
  } else {
    wanted
  }
}

///|
fn BrotliOutputBuilder::new(
  opts : UnbrotliOptions,
  input_len? : Int = 0,
) -> BrotliOutputBuilder {
  match opts.out {
    Some(out) =>
      { buf: out, len: 0, fixed: true, max_output_size: opts.max_output_size }
    None => {
      let initial = brotli_initial_output_capacity(
        opts.max_output_size,
        input_len,
      )
      {
        buf: FixedArray::make(initial, b'\x00'),
        len: 0,
        fixed: false,
        max_output_size: opts.max_output_size,
      }
    }
  }
}

///|
fn BrotliOutputBuilder::ensure(
  self : BrotliOutputBuilder,
  additional : Int,
) -> Unit raise @common.FbrError {
  if additional < 0 {
    raise @common.fbr_err(
      @common.BrotliInvalidMetablock,
      msg="negative Brotli output length",
    )
  }
  if self.len > self.max_output_size - additional {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="output exceeds max_output_size",
    )
  }
  let needed = self.len + additional
  if needed <= self.buf.length() {
    return
  }
  if self.fixed {
    raise @common.fbr_err(@common.InvalidZipData, msg="output buffer too small")
  }
  let mut capacity = self.buf.length()
  if capacity == 0 {
    capacity = 1
  }
  while capacity < needed {
    if capacity > @common.max_int_val() / 2 {
      capacity = needed
      break
    }
    capacity *= 2
  }
  if capacity > self.max_output_size {
    capacity = self.max_output_size
  }
  let grown = FixedArray::make(capacity, b'\x00')
  self.buf.blit_to(grown, len=self.len, src_offset=0, dst_offset=0)
  self.buf = grown
}

///|
fn BrotliOutputBuilder::finish(self : BrotliOutputBuilder) -> FixedArray[Byte] {
  @common.trim_buf(self.buf, self.len)
}

///|
fn BrotliOutputBuilder::clone(
  self : BrotliOutputBuilder,
) -> BrotliOutputBuilder {
  let buf = FixedArray::make(self.buf.length(), b'\x00')
  if self.len > 0 {
    self.buf.blit_to(buf, len=self.len, src_offset=0, dst_offset=0)
  }
  {
    buf,
    len: self.len,
    fixed: self.fixed,
    max_output_size: self.max_output_size,
  }
}

///|
fn BrotliOutputBuilder::copy_from_distance(
  self : BrotliOutputBuilder,
  distance : Int,
  length : Int,
) -> Unit raise @common.FbrError {
  if length < 0 {
    raise @common.fbr_err(
      @common.BrotliInvalidMetablock,
      msg="negative Brotli copy length",
    )
  }
  if distance <= 0 || distance > self.len {
    raise @common.fbr_err(
      @common.BrotliInvalidDistance,
      msg="Brotli backward distance out of range",
    )
  }
  self.ensure(length)
  let start = self.len
  if length == 0 {
    return
  }
  if distance == 1 {
    let value = self.buf[start - 1]
    for i in 0..<length {
      self.buf[start + i] = value
    }
    self.len = start + length
    return
  }
  if distance >= length {
    self.buf.blit_to(
      self.buf,
      len=length,
      src_offset=start - distance,
      dst_offset=start,
    )
    self.len = start + length
    return
  }
  self.buf.blit_to(
    self.buf,
    len=distance,
    src_offset=start - distance,
    dst_offset=start,
  )
  let mut copied = distance
  while copied < length {
    let remaining = length - copied
    let chunk = if copied < remaining { copied } else { remaining }
    self.buf.blit_to(
      self.buf,
      len=chunk,
      src_offset=start,
      dst_offset=start + copied,
    )
    copied += chunk
  }
  self.len = start + length
}

///|
fn brotli_decode_metablock_header(
  reader : BrotliBitReader,
) -> BrotliMetablockHeader raise @common.FbrError {
  let is_last = reader.take_bits(1) == 1U
  if is_last && reader.take_bits(1) == 1U {
    return {
      is_last,
      is_empty: true,
      is_metadata: false,
      is_uncompressed: false,
      length: 0,
    }
  }
  let mnibbles = reader.take_bits(2).reinterpret_as_int()
  if mnibbles == 3 {
    let reserved = reader.take_bits(1)
    if reserved != 0U {
      raise @common.fbr_err(
        @common.BrotliReserved,
        msg="reserved metadata meta-block bit set",
      )
    }
    let size_bytes = reader.take_bits(2).reinterpret_as_int()
    if size_bytes == 0 {
      return {
        is_last,
        is_empty: false,
        is_metadata: true,
        is_uncompressed: false,
        length: 0,
      }
    }
    let mut length = 0
    for i in 0..<size_bytes {
      let part = reader.take_bits(8).reinterpret_as_int()
      if i + 1 == size_bytes && size_bytes > 1 && part == 0 {
        raise @common.fbr_err(
          @common.BrotliInvalidMetablock,
          msg="exuberant metadata length",
        )
      }
      length = length | (part << (i * 8))
    }
    return {
      is_last,
      is_empty: false,
      is_metadata: true,
      is_uncompressed: false,
      length: length + 1,
    }
  }
  let size_nibbles = mnibbles + 4
  let mut length = 0
  for i in 0..<size_nibbles {
    let part = reader.take_bits(4).reinterpret_as_int()
    if i + 1 == size_nibbles && size_nibbles > 4 && part == 0 {
      raise @common.fbr_err(
        @common.BrotliInvalidMetablock,
        msg="exuberant meta-block length",
      )
    }
    length = length | (part << (i * 4))
  }
  length += 1
  if length > @common.brotli_max_metablock_bytes {
    raise @common.fbr_err(
      @common.BrotliInvalidMetablock,
      msg="Brotli meta-block too large",
    )
  }
  let is_uncompressed = if is_last { false } else { reader.take_bits(1) == 1U }
  { is_last, is_empty: false, is_metadata: false, is_uncompressed, length }
}

///|
fn brotli_skip_metadata(
  reader : BrotliBitReader,
  length : Int,
) -> Unit raise @common.FbrError {
  if length == 0 {
    reader.align_to_byte()
    return
  }
  let scratch = FixedArray::make(length, b'\x00')
  reader.take_bytes(scratch, 0, length)
}

///|
fn brotli_copy_uncompressed(
  reader : BrotliBitReader,
  output : BrotliOutputBuilder,
  length : Int,
) -> Unit raise @common.FbrError {
  output.ensure(length)
  reader.take_bytes(output.buf, output.len, length)
  output.len += length
}

///|
fn brotli_decode_next_metablock(
  reader : BrotliBitReader,
  output : BrotliOutputBuilder,
  state : BrotliDecoderState,
) -> Bool raise @common.FbrError {
  let header = brotli_decode_metablock_header(reader)
  if header.is_empty {
    reader.expect_final_padding_zero()
    return true
  }
  if header.is_metadata {
    brotli_skip_metadata(reader, header.length)
  } else if header.is_uncompressed {
    brotli_copy_uncompressed(reader, output, header.length)
  } else if header.length == 0 {
    ()
  } else {
    let compressed_header = brotli_read_compressed_metablock_header(reader)
    brotli_decode_compressed_metablock_body(
      reader,
      compressed_header,
      output,
      header.length,
      state,
    )
  }
  if header.is_last {
    reader.expect_final_padding_zero()
    true
  } else {
    false
  }
}

///|
fn brotli_decode_scaffold(
  data : FixedArray[Byte],
  opts : UnbrotliOptions,
) -> FixedArray[Byte] raise @common.FbrError {
  let reader = BrotliBitReader::new(data, 0, data.length())
  let window_bits = brotli_decode_window_bits(reader)
  brotli_validate_window_bits(window_bits)
  let output = BrotliOutputBuilder::new(opts, input_len=data.length())
  let state = BrotliDecoderState::new_with_window_bits(window_bits)
  while true {
    if brotli_decode_next_metablock(reader, output, state) {
      if output.len == 0 {
        return brotli_empty_output(opts)
      }
      return output.finish()
    }
  }
  raise @common.fbr_err(
    @common.BrotliInvalidMetablock,
    msg="unreachable Brotli decoder state",
  )
}

///|
/// Decompress a Brotli stream.
///
/// This public entry point enforces fzip's input and output caps and returns a
/// freshly trimmed output buffer. The RFC 7932 decoder is being filled in behind
/// this API with each intermediate path still reporting unsupported or malformed
/// Brotli constructs as `@common.FbrError`.
pub fn unbrotli_sync(
  data : FixedArray[Byte],
  opts? : UnbrotliOptions = UnbrotliOptions::default(),
) -> FixedArray[Byte] raise @common.FbrError {
  if data.length() > opts.max_input_size {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="input exceeds max_input_size",
    )
  }
  let out = brotli_decode_scaffold(data, opts)
  if out.length() > opts.max_output_size {
    raise @common.fbr_err(
      @common.InvalidZipData,
      msg="output exceeds max_output_size",
    )
  }
  out
}

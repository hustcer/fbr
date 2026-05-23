///|
fn brotli_decode_window_bits(reader : BrotliBitReader) -> Int raise FzipError {
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
        1 => raise fzip_err(BrotliLargeWindowNotSupported)
        2..=7 => 8 + m
        _ => raise fzip_err(BrotliInvalidWindowBits)
      }
    }
  }
}

///|
fn brotli_validate_window_bits(window_bits : Int) -> Unit raise FzipError {
  if window_bits < brotli_min_window_bits ||
    window_bits > brotli_max_window_bits {
    raise fzip_err(BrotliInvalidWindowBits)
  }
}

///|
fn brotli_empty_output(opts : UnbrotliOptions) -> FixedArray[Byte] {
  match opts.out {
    Some(out) => trim_buf(out, 0)
    None => FixedArray::make(0, b'\x00')
  }
}

///|
fn brotli_decode_scaffold(
  data : FixedArray[Byte],
  opts : UnbrotliOptions,
) -> FixedArray[Byte] raise FzipError {
  let reader = BrotliBitReader::new(data, 0, data.length())
  let window_bits = brotli_decode_window_bits(reader)
  brotli_validate_window_bits(window_bits)
  let is_last = reader.take_bits(1) == 1U
  if is_last {
    let is_last_empty = reader.take_bits(1) == 1U
    if is_last_empty {
      reader.expect_final_padding_zero()
      return brotli_empty_output(opts)
    }
  }
  raise fzip_err(
    BrotliInvalidMetablock,
    msg="Brotli compressed meta-block decoder is not implemented yet",
  )
}

///|
/// Decompress a Brotli stream.
///
/// This public entry point enforces fzip's input and output caps and returns a
/// freshly trimmed output buffer. The full RFC 7932 decoder is being filled in
/// behind this API; the current scaffold accepts the legal empty Brotli stream
/// and rejects unsupported meta-block paths with `FzipError`.
pub fn unbrotli_sync(
  data : FixedArray[Byte],
  opts? : UnbrotliOptions = UnbrotliOptions::default(),
) -> FixedArray[Byte] raise FzipError {
  if data.length() > opts.max_input_size {
    raise fzip_err(InvalidZipData, msg="input exceeds max_input_size")
  }
  let out = brotli_decode_scaffold(data, opts)
  if out.length() > opts.max_output_size {
    raise fzip_err(InvalidZipData, msg="output exceeds max_output_size")
  }
  out
}

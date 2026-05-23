///|
fn assert_brotli_error(
  result : Result[FixedArray[Byte], FzipError],
  expected : FzipErrorCode,
) -> Unit raise {
  guard result is Err(FzipError(code~, ..)) else {
    fail("expected Brotli FzipError")
  }
  assert_eq(code, expected)
}

///|
test "brotli error codes show stable names" {
  inspect(BrotliInvalidWindowBits, content="BrotliInvalidWindowBits")
  inspect(BrotliInvalidMetablock, content="BrotliInvalidMetablock")
  inspect(BrotliInvalidPadding, content="BrotliInvalidPadding")
}

///|
test "brotli constants expose reference limits" {
  inspect(brotli_min_window_bits, content="10")
  inspect(brotli_max_window_bits, content="24")
  inspect(brotli_max_metablock_bytes, content="16777216")
}

///|
test "BrotliBitReader reads and aligns LSB-first bits" {
  let reader = BrotliBitReader::new([0xa1, 0x01], 0, 2)
  inspect(reader.take_bits(1), content="1")
  inspect(reader.take_bits(3), content="0")
  inspect(reader.take_bits(3), content="2")
  inspect(reader.bits_consumed(), content="7")
  inspect(reader.take_bits(1), content="1")
  inspect(reader.take_bits(1), content="1")
  reader.align_to_byte()
  reader.expect_final_padding_zero()
}

///|
test "BrotliBitReader align_to_byte rejects non-zero padding" {
  let reader = BrotliBitReader::new([0x09], 0, 1)
  inspect(reader.take_bits(1), content="1")
  let result : Result[Unit, FzipError] = try? reader.align_to_byte()
  guard result is Err(FzipError(code~, ..)) else {
    fail("expected padding error")
  }
  assert_eq(code, BrotliInvalidPadding)
}

///|
test "unbrotli_sync decodes empty Brotli stream" {
  let compressed : FixedArray[Byte] = [0xa1, 0x01]
  let decoded = unbrotli_sync(compressed)
  assert_eq(decoded.length(), 0)
}

///|
test "unbrotli_sync enforces max_input_size" {
  let compressed : FixedArray[Byte] = [0xa1, 0x01]
  let result = try? unbrotli_sync(compressed, opts={
    out: None,
    max_output_size: default_max_output_size,
    max_input_size: 1,
  })
  assert_brotli_error(result, InvalidZipData)
}

///|
test "unbrotli_sync rejects unsupported meta-block path with Brotli error" {
  let compressed : FixedArray[Byte] = [0x21]
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliInvalidMetablock)
}

///|
test "unbrotli_sync rejects non-zero final padding" {
  let compressed : FixedArray[Byte] = [0xa1, 0x03]
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliInvalidPadding)
}

///|
test "UnbrotliStream buffers chunks until final push" {
  let stream = UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  let finals : Array[Bool] = []
  stream.ondata = Some(
    FlateStreamHandler((data, final_) => {
      finals.push(final_)
      output.push(data)
    }),
  )
  stream.push([0xa1], final_=false)
  assert_eq(output.length(), 0)
  stream.push([0x01], final_=true)
  assert_eq(output.length(), 1)
  assert_true(finals[0])
  assert_eq(output[0].length(), 0)
}

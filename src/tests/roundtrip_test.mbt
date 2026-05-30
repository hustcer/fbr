///|
/// Black-box Brotli roundtrip across quality levels.
test "brotli roundtrip (default quality)" {
  let data : FixedArray[Byte] = FixedArray::make(200, b'\x00')
  for i in 0..<200 {
    data[i] = (i % 50).to_byte()
  }
  let compressed = @fbr.brotli_sync(data)
  let decompressed = @fbr.unbrotli_sync(compressed)
  assert_eq(decompressed.length(), data.length())
  for i in 0..<data.length() {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "brotli roundtrip (multiple qualities)" {
  let data : FixedArray[Byte] = FixedArray::make(512, b'\x00')
  for i in 0..<512 {
    data[i] = ((i * 7 + 3) % 64).to_byte()
  }
  for q in [0, 1, 2, 5, 9, 10, 11] {
    let compressed = @fbr.brotli_sync(data, opts={
      ..@fbr.BrotliOptions::default(),
      quality: q,
    })
    let decompressed = @fbr.unbrotli_sync(compressed)
    assert_eq(decompressed.length(), data.length())
    for i in 0..<data.length() {
      assert_eq(decompressed[i], data[i])
    }
  }
}

///|
test "brotli roundtrip (empty input)" {
  let data : FixedArray[Byte] = FixedArray::make(0, b'\x00')
  let compressed = @fbr.brotli_sync(data)
  let decompressed = @fbr.unbrotli_sync(compressed)
  assert_eq(decompressed.length(), 0)
}

///|
/// Literal-heavy roundtrip that drives the decoder's single-literal-tree fast
/// path (and its single-block-type sub-path) over long insert runs. The data is
/// a skewed byte distribution with few long repeats, so the encoder keeps most
/// of it as literals rather than copies. Covering several qualities and sizes
/// exercises both the tight no-block-tracking inner loop and the general path.
test "brotli roundtrip (literal-heavy, single literal tree path)" {
  for size in [1024, 8192, 33000] {
    let data : FixedArray[Byte] = FixedArray::make(size, b'\x00')
    let mut state = 0x1234_5678
    for i in 0..<size {
      // xorshift-ish pseudo-random stream squeezed into a small alphabet so
      // matches are rare and literals dominate.
      state = state * 1103515245 + 12345
      data[i] = (((state >> 16) & 0x3f) + 0x20).to_byte()
    }
    for q in [2, 4, 6, 9, 11] {
      let compressed = @fbr.brotli_sync(data, opts={
        ..@fbr.BrotliOptions::default(),
        quality: q,
      })
      let decompressed = @fbr.unbrotli_sync(compressed)
      assert_eq(decompressed.length(), data.length())
      for i in 0..<data.length() {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}

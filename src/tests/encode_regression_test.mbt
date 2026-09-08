///|
test "short matches respect the requested window at every quality" {
  let data = FixedArray::make(9600, b'\x00')
  let mut state : UInt = 1
  for i in 0..<4800 {
    state = state * 1664525 + 1013904223
    data[i] = (state >> 24).reinterpret_as_int().to_byte()
    data[i + 4800] = if i % 8 == 7 {
      (data[i].to_int() ^ 1).to_byte()
    } else {
      data[i]
    }
  }
  for window_bits in [13, 12, 10] {
    for quality in 0..<=11 {
      let compressed = @fbr.brotli_sync(data, opts={
        ..@fbr.BrotliOptions::default(),
        quality,
        window_bits,
      })
      let decoded = @fbr.unbrotli_sync(compressed)
      assert_eq(decoded.length(), data.length())
      for i in 0..<data.length() {
        assert_eq(decoded[i], data[i])
      }
    }
  }
}

///|
test "q3 short matches do not discard a compressible block at the command limit" {
  // Each unique record offers a 6..9-byte copy, followed by a long zero tail.
  // The former 52,000-command cap discarded the entire 700,000-byte parse.
  // The larger case also crosses the 2 MiB chunk boundary and the former
  // doubled command cap for large blocks.
  for case in [(60000, 700000), (200000, 2200000)] {
    let (records, size) = case
    let data = FixedArray::make(size, b'\x00')
    for i in 0..<records {
      for j in 0..<6 {
        data[i * 10 + j] = (201 + j).to_byte()
      }
      for j in 0..<4 {
        data[i * 10 + 6 + j] = ((i >> (24 - j * 8)) & 255).to_byte()
      }
    }
    let compressed = @fbr.brotli_sync(data, opts={
      ..@fbr.BrotliOptions::default(),
      quality: 3,
    })
    let decoded = @fbr.unbrotli_sync(compressed)
    assert_eq(decoded.length(), data.length())
    for i in 0..<data.length() {
      assert_eq(decoded[i], data[i])
    }
    // The previous min=10 profile emitted 327,561 bytes on the 700 KB case.
    assert_true(compressed.length() < size * 4 / 7)
  }
}

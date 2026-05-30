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

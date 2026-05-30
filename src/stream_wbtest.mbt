///|
test "BrotliStream - basic usage" {
  let stream = BrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  stream.ondata = Some(FlateStreamHandler((data, _) => output.push(data)))
  let data : FixedArray[Byte] = [1, 2, 3]
  stream.push(data, final_=true)
  assert_true(output.length() > 0)
  let decoded = unbrotli_sync(output[0])
  assert_eq(decoded.length(), data.length())
  assert_eq(decoded[0], data[0])
  assert_eq(decoded[1], data[1])
  assert_eq(decoded[2], data[2])
}

///|
test "UnbrotliStream - basic usage" {
  let data : FixedArray[Byte] = [1, 2, 3, 4, 5]
  let compressed = brotli_sync(data)
  let stream = UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  stream.ondata = Some(FlateStreamHandler((data, _) => output.push(data)))
  stream.push(compressed, final_=true)
  assert_true(output.length() > 0)
  let result = output[0]
  assert_eq(result.length(), 5)
}

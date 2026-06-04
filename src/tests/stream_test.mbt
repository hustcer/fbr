///|

///|
fn test_slice(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> FixedArray[Byte] {
  let out = FixedArray::make(end - start, b'\x00')
  if out.length() > 0 {
    data.blit_to(out, len=out.length(), src_offset=start, dst_offset=0)
  }
  out
}

///|
test "BrotliStream - basic usage" {
  let stream = @fbr.BrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  stream.set_ondata((data, _) => output.push(data))
  let data : FixedArray[Byte] = [1, 2, 3]
  stream.push(data, final_=true)
  assert_true(output.length() > 0)
  let decoded = @fbr.unbrotli_sync(output[0])
  assert_eq(decoded.length(), data.length())
  assert_eq(decoded[0], data[0])
  assert_eq(decoded[1], data[1])
  assert_eq(decoded[2], data[2])
}

///|
test "UnbrotliStream - basic usage" {
  let data : FixedArray[Byte] = [1, 2, 3, 4, 5]
  let compressed = @fbr.brotli_sync(data)
  let stream = @fbr.UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  stream.set_ondata((data, _) => output.push(data))
  stream.push(compressed, final_=true)
  assert_true(output.length() > 0)
  let result = output[0]
  assert_eq(result.length(), 5)
}

///|
test "UnbrotliStream emits complete meta-block before final input" {
  let data : FixedArray[Byte] = FixedArray::make(128, b'\x00')
  for i in 0..<data.length() {
    data[i] = (i & 0xff).to_byte()
  }
  let compressed = @fbr.brotli_sync(data, opts={
    ..@fbr.BrotliOptions::default(),
    quality: 0,
  })
  let stream = @fbr.UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  let finals : Array[Bool] = []
  stream.set_ondata((chunk, is_final) => {
    output.push(chunk)
    finals.push(is_final)
  })
  // q0 writes a non-final stored meta-block followed by the final empty
  // meta-block. Holding back the last compressed byte should still let the
  // decoder emit the stored meta-block payload before user finalization.
  stream.push(test_slice(compressed, 0, compressed.length() - 1))
  assert_true(output.length() > 0)
  assert_false(finals[0])
  let mut total = 0
  for i in 0..<output.length() {
    total += output[i].length()
  }
  assert_eq(total, data.length())
  stream.push(
    test_slice(compressed, compressed.length() - 1, compressed.length()),
    final_=true,
  )
  assert_true(finals[finals.length() - 1])
}

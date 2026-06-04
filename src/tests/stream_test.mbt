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

///|
/// Concatenate emitted chunks into a single buffer for comparison.
fn collect_bytes(chunks : Array[FixedArray[Byte]]) -> FixedArray[Byte] {
  let mut total = 0
  for i in 0..<chunks.length() {
    total += chunks[i].length()
  }
  let out = FixedArray::make(total, b'\x00')
  let mut offset = 0
  for i in 0..<chunks.length() {
    let chunk = chunks[i]
    if chunk.length() > 0 {
      chunk.blit_to(out, len=chunk.length(), src_offset=0, dst_offset=offset)
      offset += chunk.length()
    }
  }
  out
}

///|
fn bytes_eq(a : FixedArray[Byte], b : FixedArray[Byte]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Mildly repetitive payload so quality-11 compression emits back-references
/// (exercising the distance-ring rollback), not just stored literals.
fn sample_data(n : Int) -> FixedArray[Byte] {
  let data = FixedArray::make(n, b'\x00')
  for i in 0..<n {
    data[i] = ((i * 7) & 0x3f).to_byte()
  }
  data
}

///|
test "UnbrotliStream matches one-shot output across every split point" {
  let data = sample_data(512)
  let compressed = @fbr.brotli_sync(data)
  // Decode the same stream split at every possible byte boundary; the
  // concatenated streamed output must always equal the original payload and
  // end with a final marker.
  for split in 0..<=compressed.length() {
    let stream = @fbr.UnbrotliStream::new()
    let output : Array[FixedArray[Byte]] = []
    let finals : Array[Bool] = []
    stream.set_ondata((chunk, is_final) => {
      output.push(chunk)
      finals.push(is_final)
    })
    stream.push(test_slice(compressed, 0, split))
    stream.push(test_slice(compressed, split, compressed.length()), final_=true)
    assert_true(bytes_eq(collect_bytes(output), data))
    assert_true(finals.length() > 0 && finals[finals.length() - 1])
  }
}

///|
test "UnbrotliStream decodes one byte at a time" {
  let data = sample_data(300)
  let compressed = @fbr.brotli_sync(data)
  let stream = @fbr.UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  stream.set_ondata((chunk, _is_final) => output.push(chunk))
  for i in 0..<compressed.length() {
    let is_last = i + 1 == compressed.length()
    stream.push(test_slice(compressed, i, i + 1), final_=is_last)
  }
  assert_true(bytes_eq(collect_bytes(output), data))
}

///|
test "UnbrotliStream enforces max_input_size" {
  let data = sample_data(64)
  let compressed = @fbr.brotli_sync(data)
  let stream = @fbr.UnbrotliStream::new(opts={
    ..@fbr.UnbrotliOptions::default(),
    max_input_size: 2,
  })
  try stream.push(compressed) catch {
    _ => ()
  } noraise {
    _ => fail("expected max_input_size to be enforced")
  }
}

///|
test "UnbrotliStream rejects input after the stream finishes" {
  let data = sample_data(32)
  let compressed = @fbr.brotli_sync(data)
  let stream = @fbr.UnbrotliStream::new()
  stream.set_ondata((_chunk, _is_final) => ())
  stream.push(compressed, final_=true)
  // Empty trailing pushes are accepted.
  stream.push(FixedArray::make(0, b'\x00'))
  // Any non-empty input after completion is rejected.
  try stream.push(test_slice(compressed, 0, 1)) catch {
    _ => ()
  } noraise {
    _ => fail("expected push after finish to raise")
  }
}

///|
test "UnbrotliStream emits a final marker for empty input" {
  let empty = FixedArray::make(0, b'\x00')
  let compressed = @fbr.brotli_sync(empty)
  let stream = @fbr.UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  let finals : Array[Bool] = []
  stream.set_ondata((chunk, is_final) => {
    output.push(chunk)
    finals.push(is_final)
  })
  stream.push(compressed, final_=true)
  assert_eq(collect_bytes(output).length(), 0)
  assert_true(finals.length() > 0 && finals[finals.length() - 1])
}

///|
test "UnbrotliStream rejects truncated input at finalization" {
  let data = sample_data(128)
  let compressed = @fbr.brotli_sync(data)
  let stream = @fbr.UnbrotliStream::new()
  stream.set_ondata((_chunk, _is_final) => ())
  // Feed only the first byte but declare it final: the stream cannot be
  // completed, so finalization must raise rather than silently truncate.
  try stream.push(test_slice(compressed, 0, 1), final_=true) catch {
    _ => ()
  } noraise {
    _ => fail("expected truncated final input to raise")
  }
}

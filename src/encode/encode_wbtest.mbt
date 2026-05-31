///|
fn assert_brotli_error(
  result : Result[FixedArray[Byte], FbrError],
  expected : FbrErrorCode,
) -> Unit raise {
  guard result is Err(FbrError(code~, ..)) else {
    fail("expected Brotli FbrError")
  }
  assert_eq(code, expected)
}

///|
test "brotli_sync q0 encodes empty stream" {
  let input : FixedArray[Byte] = []
  let compressed = brotli_sync(input, opts={
    quality: 0,
    window_bits: 16,
    max_input_size: default_max_input_size,
  })
  let decoded = @decode.unbrotli_sync(compressed)
  assert_eq(decoded.length(), 0)
}

///|
test "brotli_sync q0 round-trips uncompressed meta-block" {
  let input : FixedArray[Byte] = [1, 2, 3, 4, 5, 0, 255]
  let compressed = brotli_sync(input, opts={
    quality: 0,
    window_bits: 16,
    max_input_size: default_max_input_size,
  })
  let decoded = @decode.unbrotli_sync(compressed)
  assert_eq(decoded.length(), input.length())
  for i in 0..<input.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync supports all standard window bits" {
  let input : FixedArray[Byte] = [42]
  for window_bits in 10..<=24 {
    let compressed = brotli_sync(input, opts={
      quality: 0,
      window_bits,
      max_input_size: default_max_input_size,
    })
    let decoded = @decode.unbrotli_sync(compressed)
    assert_eq(decoded.length(), 1)
    assert_eq(decoded[0], input[0])
  }
}

///|
test "brotli_sync q1 round-trips large input across meta-blocks" {
  let input = FixedArray::make(brotli_max_metablock_bytes + 17, b'\x00')
  for i in 0..<input.length() {
    input[i] = (i & 0xff).to_byte()
  }
  let compressed = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let decoded = @decode.unbrotli_sync(compressed)
  assert_eq(decoded.length(), input.length())
  assert_eq(decoded[0], input[0])
  assert_eq(
    decoded[brotli_max_metablock_bytes],
    input[brotli_max_metablock_bytes],
  )
  assert_eq(decoded[input.length() - 1], input[input.length() - 1])
}

///|
test "brotli_sync q2 compresses repeated byte with LZ77 copy" {
  let input = FixedArray::make(1024, b'A')
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q9 = brotli_sync(input, opts={
    quality: 9,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  assert_true(q9.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], b'A')
  }
}

///|
test "brotli_sync q2 compresses short periodic input with LZ77 copy" {
  let input = FixedArray::make(1024, b'\x00')
  let pattern : FixedArray[Byte] = [b'A', b'B', b'C', b'D']
  for i in 0..<input.length() {
    input[i] = pattern[i & 3]
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q9 = brotli_sync(input, opts={
    quality: 9,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  assert_true(q9.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses large 256-byte periodic input with one copy" {
  let input = FixedArray::make(70000, b'\x00')
  for i in 0..<input.length() {
    input[i] = (i & 255).to_byte()
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q9 = brotli_sync(input, opts={
    quality: 9,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < 400)
  assert_true(q9.length() < 400)
  assert_true(q2.length() < q1.length())
  assert_true(q9.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q9)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 writes implicit last-distance commands" {
  let input = FixedArray::make(20, b'\x00')
  let pattern : FixedArray[Byte] = [b'A', b'B', b'C', b'D']
  for i in 0..<input.length() {
    input[i] = pattern[i & 3]
  }
  let command = brotli_make_encode_command_with_distance_mode(
    0, 4, 16, 4, true, false,
  )
  assert_false(brotli_command_uses_distance_symbol(command))
  let commands : Array[BrotliEncodeCommand] = []
  commands.push(command)
  let body = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(body, input, commands, true, true)
  let encoded = BrotliBitWriter::new(16 + body.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(body.buf, body.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 emits complex literal Huffman tree" {
  let input = FixedArray::make(1025, b'\x00')
  let pattern : FixedArray[Byte] = [b'A', b'B', b'C', b'D', b'E']
  for i in 0..<input.length() {
    input[i] = pattern[i % pattern.length()]
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses literal prefix then copied suffix" {
  let input = FixedArray::make(1024, b'\x00')
  input[0] = b'X'
  let pattern : FixedArray[Byte] = [b'A', b'B', b'C']
  for i in 1..<input.length() {
    input[i] = pattern[(i - 1) % 3]
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses multiple small alphabet copies" {
  let input = FixedArray::make(1207, b'\x00')
  let prefix : FixedArray[Byte] = [b'A', b'B', b'C', b'A', b'B', b'C', b'X']
  for i in 0..<prefix.length() {
    input[i] = prefix[i]
  }
  let pattern : FixedArray[Byte] = [b'A', b'B', b'C', b'A', b'B', b'C']
  for i in prefix.length()..<input.length() {
    input[i] = pattern[(i - prefix.length()) % pattern.length()]
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 emits complex command Huffman tree" {
  let input = FixedArray::make(1400, b'\x00')
  let alphabet : FixedArray[Byte] = [b'A', b'B', b'C', b'D']
  let mut state = 17
  for chunk in 0..<200 {
    let offset = chunk * 7
    input[offset] = b'A'
    input[offset + 1] = b'B'
    input[offset + 2] = b'C'
    input[offset + 3] = b'A'
    input[offset + 4] = b'B'
    input[offset + 5] = b'C'
    input[offset + 6] = alphabet[state % 4]
    state = (state * 73 + 41) % 257
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q9 = brotli_sync(input, opts={
    quality: 9,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  assert_true(q9.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses low alphabet literal chunks" {
  let input = FixedArray::make(4096, b'\x00')
  for i in 0..<input.length() {
    let mixed = (i * 73 + i / 31 * 19 + i / 997 * 11) & 31
    input[i] = (mixed + 65).to_byte()
  }
  assert_true(brotli_count_unique_literals_up_to(input, 64) <= 64)
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses skewed high alphabet literal chunks" {
  let input = FixedArray::make(8192, b'\x00')
  for i in 0..<128 {
    input[i] = i.to_byte()
  }
  let common : FixedArray[Byte] = [b' ', b'e', b't', b'a', b'o', b'n']
  let mut state = 37
  for i in 128..<input.length() {
    state = (state * 73 + 19) % 9973
    input[i] = if state % 8 == 0 {
      (state % 128).to_byte()
    } else {
      common[state % common.length()]
    }
  }
  assert_true(brotli_count_unique_literals_up_to(input, 64) > 64)
  match brotli_build_literal_only_command(input) {
    Some(_) => ()
    None => fail("expected high-alphabet literal-only candidate")
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 splits literal-only blocks" {
  let input = FixedArray::make(8192, b'\x00')
  for i in 0..<4096 {
    input[i] = (97 + i % 4).to_byte()
  }
  let mut state = 12345
  for i in 4096..<input.length() {
    state = (state * 73 + 41) % 9973
    input[i] = (32 + state % 95).to_byte()
  }
  assert_eq(brotli_best_split_literal_point(input), 4096)
  let single = brotli_write_best_lz77_metablock(
    input,
    brotli_build_literal_only_command(input).unwrap(),
    true,
    2,
    true,
    0,
    0,
  )
  let split = match brotli_try_split_literal_only_metablock(input, true, None) {
    Some(candidate) => candidate
    None => fail("expected split literal candidate")
  }
  assert_true(split.bit_pos < single.bit_pos)
  match
    brotli_build_simple_lz77_commands(
      input,
      brotli_natural_hash_config_for_quality(2),
    ) {
    Some(commands) => assert_true(brotli_commands_copy_bytes(commands) > 1000)
    None => fail("expected natural long-match candidate")
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }

  let flat = FixedArray::make(4096, b'a')
  assert_eq(brotli_best_split_literal_point(flat), 0)
}

///|
test "brotli_sync q2 splits LZ77 command literal blocks" {
  let input = FixedArray::make(8320, b'\x00')
  for i in 0..<4096 {
    input[i] = (97 + i % 4).to_byte()
  }
  for i in 4096..<4224 {
    input[i] = input[i - 4096]
  }
  let mut state = 12345
  for i in 4224..<input.length() {
    state = (state * 73 + 41) % 9973
    input[i] = (32 + state % 95).to_byte()
  }
  let commands : Array[BrotliEncodeCommand] = []
  commands.push(brotli_make_encode_command(0, 4096, 128, 4096, true))
  commands.push(brotli_make_encode_command(4224, 4096, 0, 1, false))
  assert_eq(brotli_best_command_literal_split_point(input, commands), 4096)
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let split = match
    brotli_write_split_lz77_metablock(input, commands, 4096, true) {
    Some(candidate) => candidate
    None => fail("expected split LZ77 candidate")
  }
  assert_true(split.bit_pos < weighted.bit_pos)
  let encoded = BrotliBitWriter::new(16 + split.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(split.buf, split.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync splits LZ77 command blocks by command histograms" {
  let input = FixedArray::make(5124, b'\x00')
  for i in 0..<input.length() {
    input[i] = (97 + i % 4).to_byte()
  }
  let commands : Array[BrotliEncodeCommand] = []
  let mut offset = 0
  for _ in 0..<256 {
    let insert_length = if offset == 0 { 4 } else { 0 }
    commands.push(brotli_make_encode_command(offset, insert_length, 4, 4, true))
    offset += insert_length + 4
  }
  for _ in 0..<256 {
    commands.push(brotli_make_encode_command(offset, 0, 16, 4, true))
    offset += 16
  }
  assert_eq(offset, input.length())
  assert_eq(brotli_best_command_block_split_point(commands), 256)
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let split = match
    brotli_write_command_split_lz77_metablock(input, commands, 256, true) {
    Some(candidate) => candidate
    None => fail("expected command block split candidate")
  }
  assert_true(split.bit_pos < weighted.bit_pos)
  let best = brotli_write_best_lz77_metablock(
    input, commands, true, 9, false, 0, 0,
  )
  assert_eq(best.bit_pos, split.bit_pos)
  let encoded = BrotliBitWriter::new(16 + split.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(split.buf, split.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync splits LZ77 literal and command blocks together" {
  let input = FixedArray::make(7168, b'\x00')
  let commands : Array[BrotliEncodeCommand] = []
  let first_pattern : FixedArray[Byte] = [b'a', b'b', b'c', b'd']
  let second_pattern : FixedArray[Byte] = [b'w', b'x', b'y', b'z']
  let mut offset = 0
  for _ in 0..<256 {
    for i in 0..<4 {
      input[offset + i] = first_pattern[i]
      input[offset + 4 + i] = first_pattern[i]
    }
    commands.push(brotli_make_encode_command(offset, 4, 4, 4, true))
    offset += 8
  }
  for _ in 0..<256 {
    for repeat in 0..<5 {
      for i in 0..<4 {
        input[offset + repeat * 4 + i] = second_pattern[i]
      }
    }
    commands.push(brotli_make_encode_command(offset, 4, 16, 4, true))
    offset += 20
  }
  assert_eq(offset, input.length())
  assert_eq(brotli_best_command_literal_split_point(input, commands), 1024)
  assert_eq(brotli_best_command_block_split_point(commands), 256)
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let literal_split = match
    brotli_write_split_lz77_metablock(input, commands, 1024, true) {
    Some(candidate) => candidate
    None => fail("expected literal block split candidate")
  }
  let command_split = match
    brotli_write_command_split_lz77_metablock(input, commands, 256, true) {
    Some(candidate) => candidate
    None => fail("expected command block split candidate")
  }
  let joint_split = match
    brotli_write_literal_command_split_lz77_metablock(
      input, commands, 1024, 256, true,
    ) {
    Some(candidate) => candidate
    None => fail("expected joint literal/command block split candidate")
  }
  assert_true(joint_split.bit_pos < weighted.bit_pos)
  assert_true(joint_split.bit_pos < literal_split.bit_pos)
  assert_true(joint_split.bit_pos < command_split.bit_pos)
  let best = brotli_write_best_lz77_metablock(
    input, commands, true, 9, false, 0, 0,
  )
  assert_eq(best.bit_pos, joint_split.bit_pos)
  let encoded = BrotliBitWriter::new(16 + joint_split.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(joint_split.buf, joint_split.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync splits LZ77 distance blocks by distance histograms" {
  let input = FixedArray::make(2112, b'\x00')
  for i in 0..<input.length() {
    input[i] = (97 + i % 4).to_byte()
  }
  let commands : Array[BrotliEncodeCommand] = []
  let mut offset = 0
  for i in 0..<256 {
    let insert_length = if i == 0 { 64 } else { 0 }
    commands.push(brotli_make_encode_command(offset, insert_length, 4, 4, true))
    offset += insert_length + 4
  }
  for _ in 0..<256 {
    commands.push(brotli_make_encode_command(offset, 0, 4, 64, true))
    offset += 4
  }
  assert_eq(offset, input.length())
  assert_eq(brotli_best_distance_block_split_point(commands), 256)
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let split = match
    brotli_write_distance_split_lz77_metablock(input, commands, 256, true) {
    Some(candidate) => candidate
    None => fail("expected distance block split candidate")
  }
  assert_true(split.bit_pos < weighted.bit_pos)
  let best = brotli_write_best_lz77_metablock(
    input, commands, true, 9, false, 0, 0,
  )
  assert_eq(best.bit_pos, split.bit_pos)
  let encoded = BrotliBitWriter::new(16 + split.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(split.buf, split.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync splits LZ77 literal and distance blocks together" {
  let input = FixedArray::make(4096, b'\x00')
  let commands : Array[BrotliEncodeCommand] = []
  let first_pattern : FixedArray[Byte] = [b'a', b'b', b'c', b'd']
  let second_pattern : FixedArray[Byte] = [b'w', b'x', b'y', b'z']
  let mut offset = 0
  for _ in 0..<256 {
    for i in 0..<4 {
      input[offset + i] = first_pattern[i]
      input[offset + 4 + i] = first_pattern[i]
    }
    commands.push(brotli_make_encode_command(offset, 4, 4, 4, true))
    offset += 8
  }
  for _ in 0..<256 {
    for i in 0..<4 {
      input[offset + i] = second_pattern[i]
      input[offset + 4 + i] = input[offset + 4 + i - 64]
    }
    commands.push(brotli_make_encode_command(offset, 4, 4, 64, true))
    offset += 8
  }
  assert_eq(offset, input.length())
  assert_eq(brotli_best_command_literal_split_point(input, commands), 1024)
  assert_eq(brotli_best_distance_block_split_point(commands), 256)
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let literal_split = match
    brotli_write_split_lz77_metablock(input, commands, 1024, true) {
    Some(candidate) => candidate
    None => fail("expected literal block split candidate")
  }
  let distance_split = match
    brotli_write_distance_split_lz77_metablock(input, commands, 256, true) {
    Some(candidate) => candidate
    None => fail("expected distance block split candidate")
  }
  let joint_split = match
    brotli_write_literal_distance_split_lz77_metablock(
      input, commands, 1024, 256, true,
    ) {
    Some(candidate) => candidate
    None => fail("expected joint literal/distance block split candidate")
  }
  assert_true(joint_split.bit_pos < weighted.bit_pos)
  assert_true(joint_split.bit_pos < literal_split.bit_pos)
  assert_true(joint_split.bit_pos < distance_split.bit_pos)
  let best = brotli_write_best_lz77_metablock(
    input, commands, true, 9, false, 0, 0,
  )
  assert_eq(best.bit_pos, joint_split.bit_pos)
  let encoded = BrotliBitWriter::new(16 + joint_split.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(joint_split.buf, joint_split.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync splits LZ77 command and distance blocks together" {
  let input = FixedArray::make(5184, b'\x00')
  for i in 0..<input.length() {
    input[i] = (97 + i % 4).to_byte()
  }
  let commands : Array[BrotliEncodeCommand] = []
  let mut offset = 0
  for i in 0..<256 {
    let insert_length = if i == 0 { 64 } else { 0 }
    commands.push(brotli_make_encode_command(offset, insert_length, 4, 4, true))
    offset += insert_length + 4
  }
  for _ in 0..<256 {
    commands.push(brotli_make_encode_command(offset, 0, 16, 64, true))
    offset += 16
  }
  assert_eq(offset, input.length())
  assert_eq(brotli_best_command_block_split_point(commands), 256)
  assert_eq(brotli_best_distance_block_split_point(commands), 256)
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let command_split = match
    brotli_write_command_split_lz77_metablock(input, commands, 256, true) {
    Some(candidate) => candidate
    None => fail("expected command block split candidate")
  }
  let distance_split = match
    brotli_write_distance_split_lz77_metablock(input, commands, 256, true) {
    Some(candidate) => candidate
    None => fail("expected distance block split candidate")
  }
  let joint_split = match
    brotli_write_command_distance_split_lz77_metablock(
      input, commands, 256, 256, true,
    ) {
    Some(candidate) => candidate
    None => fail("expected joint command/distance block split candidate")
  }
  assert_true(joint_split.bit_pos < weighted.bit_pos)
  assert_true(joint_split.bit_pos < command_split.bit_pos)
  assert_true(joint_split.bit_pos < distance_split.bit_pos)
  let best = brotli_write_best_lz77_metablock(
    input, commands, true, 9, false, 0, 0,
  )
  assert_eq(best.bit_pos, joint_split.bit_pos)
  let encoded = BrotliBitWriter::new(16 + joint_split.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(joint_split.buf, joint_split.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 writes UTF-8 context literal trees" {
  let input = FixedArray::make(4096, b'e')
  let previous_1 = FixedArray::make(16, 0)
  let previous_2 = FixedArray::make(16, 0)
  let found = FixedArray::make(16, false)
  for p2 in 0..<256 {
    for p1 in 0..<256 {
      let tree = brotli_utf8_context_tree16(
        brotli_literal_context_id(2, p1, p2),
      )
      if !found[tree] {
        previous_1[tree] = p1
        previous_2[tree] = p2
        found[tree] = true
      }
    }
  }
  for tree in 0..<16 {
    assert_true(found[tree])
  }
  let mut offset = 0
  while offset + 48 <= input.length() {
    for tree in 0..<16 {
      input[offset] = previous_2[tree].to_byte()
      input[offset + 1] = previous_1[tree].to_byte()
      input[offset + 2] = (97 + tree % 16).to_byte()
      offset += 3
    }
  }
  let commands : Array[BrotliEncodeCommand] = []
  commands.push(brotli_make_encode_command(0, input.length(), 0, 0, false))
  let weighted = BrotliBitWriter::new(
    128 + input.length() * 4 + commands.length() * 8,
  )
  brotli_write_simple_lz77_metablock(weighted, input, commands, true, true)
  let context = match
    brotli_write_context_lz77_metablock(input, commands, true, 0, 0) {
    Some(candidate) => candidate
    None => fail("expected UTF-8 context candidate")
  }
  assert_true(context.bit_pos < weighted.bit_pos)
  let context4 = match
    brotli_write_context4_lz77_metablock(input, commands, true, 0, 0) {
    Some(candidate) => candidate
    None => fail("expected four-tree UTF-8 context candidate")
  }
  assert_true(context4.bit_pos < context.bit_pos)
  inspect(brotli_utf8_context_tree8(0), content="0")
  inspect(brotli_utf8_context_tree8(12), content="2")
  inspect(brotli_utf8_context_tree8(56), content="6")
  inspect(brotli_utf8_context_tree16(0), content="0")
  inspect(brotli_utf8_context_tree16(12), content="3")
  inspect(brotli_utf8_context_tree16(56), content="14")
  let context8 = match
    brotli_write_context8_lz77_metablock(input, commands, true, 0, 0) {
    Some(candidate) => candidate
    None => fail("expected eight-tree UTF-8 context candidate")
  }
  assert_true(context8.bit_pos > 0)
  let context16 = match
    brotli_write_context16_lz77_metablock(input, commands, true, 0, 0) {
    Some(candidate) => candidate
    None => fail("expected sixteen-tree UTF-8 context candidate")
  }
  assert_true(context16.bit_pos > 0)
  let best_with_contexts = brotli_write_best_lz77_metablock(
    input, commands, true, 5, true, 0, 0,
  )
  let best_without_contexts = brotli_write_best_lz77_metablock(
    input, commands, true, 5, false, 0, 0,
  )
  assert_true(best_with_contexts.bit_pos > 0)
  let prefix : FixedArray[Byte] = [0xC3, 0xA9]
  let combined = BrotliBitWriter::new(
    32 + prefix.length() + best_without_contexts.buf.length(),
  )
  brotli_encode_window_bits(combined, 22)
  brotli_write_uncompressed_metablock(combined, prefix, 0, prefix.length())
  // A context-free second meta-block remains valid even when the decoder's
  // previous literal bytes come from an earlier meta-block.
  combined.write_from_bits(
    best_without_contexts.buf,
    best_without_contexts.bit_pos,
  )
  let decoded_combined = @decode.unbrotli_sync(combined.finish())
  assert_eq(decoded_combined.length(), prefix.length() + input.length())
  for i in 0..<prefix.length() {
    assert_eq(decoded_combined[i], prefix[i])
  }
  for i in 0..<input.length() {
    assert_eq(decoded_combined[prefix.length() + i], input[i])
  }
  let encoded = BrotliBitWriter::new(16 + context.buf.length())
  brotli_encode_window_bits(encoded, 22)
  encoded.write_from_bits(context.buf, context.bit_pos)
  let decoded = @decode.unbrotli_sync(encoded.finish())
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
  let encoded4 = BrotliBitWriter::new(16 + context4.buf.length())
  brotli_encode_window_bits(encoded4, 22)
  encoded4.write_from_bits(context4.buf, context4.bit_pos)
  let decoded4 = @decode.unbrotli_sync(encoded4.finish())
  assert_eq(decoded4.length(), input.length())
  for i in 0..<decoded4.length() {
    assert_eq(decoded4[i], input[i])
  }
  let encoded8 = BrotliBitWriter::new(16 + context8.buf.length())
  brotli_encode_window_bits(encoded8, 22)
  encoded8.write_from_bits(context8.buf, context8.bit_pos)
  let decoded8 = @decode.unbrotli_sync(encoded8.finish())
  assert_eq(decoded8.length(), input.length())
  for i in 0..<decoded8.length() {
    assert_eq(decoded8[i], input[i])
  }
  let encoded16 = BrotliBitWriter::new(16 + context16.buf.length())
  brotli_encode_window_bits(encoded16, 22)
  encoded16.write_from_bits(context16.buf, context16.bit_pos)
  let decoded16 = @decode.unbrotli_sync(encoded16.finish())
  assert_eq(decoded16.length(), input.length())
  for i in 0..<decoded16.length() {
    assert_eq(decoded16[i], input[i])
  }
}

///|
test "brotli_sync q9 admits shorter high-quality matches" {
  let input = FixedArray::make(2600, b'\x00')
  let pattern : FixedArray[Byte] = [
    b'a', b'b', b'c', b'd', b'e', b'f', b'g', b'h', b'i', b'j', b'k', b'l',
  ]
  for block in 0..<200 {
    let offset = block * 13
    for i in 0..<pattern.length() {
      input[offset + i] = pattern[i]
    }
    input[offset + 12] = (block & 0xff).to_byte()
  }
  match
    brotli_build_simple_lz77_commands(
      input,
      brotli_natural_hash_config_for_quality(2),
    ) {
    Some(commands) => assert_true(brotli_commands_copy_bytes(commands) > 2000)
    None => fail("expected q2 natural candidate")
  }
  match
    brotli_build_simple_lz77_commands(
      input,
      brotli_high_quality_hash_config_for_quality(9),
    ) {
    Some(commands) => assert_true(brotli_commands_copy_bytes(commands) > 2000)
    None => fail("expected q9 high-quality candidate")
  }
}

///|
test "brotli_sync q10 bounded shortest-path candidate roundtrips" {
  let input = FixedArray::make(12000, b'\x00')
  let pattern : FixedArray[Byte] = [
    b'm', b'o', b'o', b'n', b'b', b'i', b't', b'-', b'b', b'r', b'o', b't', b'l',
    b'i', b'-', b'q', b'1', b'0', b'-', b'p', b'a', b'r', b's', b'e',
  ]
  for block in 0..<500 {
    let offset = block * pattern.length()
    for i in 0..<pattern.length() {
      input[offset + i] = pattern[i]
    }
    input[offset + pattern.length() - 1] = (block & 0xff).to_byte()
  }
  let config = brotli_four_byte_hash_config(
    brotli_high_quality_hash_config_for_quality(10),
  )
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  match
    brotli_build_bounded_shortest_path_command_candidate(
      input, config, 0, 22, distance_cache,
    ) {
    Some(candidate) => {
      assert_true(candidate.commands.length() > 0)
      assert_true(brotli_commands_copy_bytes(candidate.commands) > 0)
      let body = brotli_write_best_lz77_metablock(
        input,
        candidate.commands,
        true,
        10,
        true,
        0,
        0,
      )
      let encoded = BrotliBitWriter::new(16 + body.buf.length())
      brotli_encode_window_bits(encoded, 22)
      encoded.write_from_bits(body.buf, body.bit_pos)
      let decoded = @decode.unbrotli_sync(encoded.finish())
      assert_eq(decoded.length(), input.length())
      for i in 0..<decoded.length() {
        assert_eq(decoded[i], input[i])
      }
    }
    None => fail("expected bounded shortest-path candidate")
  }
  let encoded = brotli_sync(input, opts={
    quality: 10,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let decoded = @decode.unbrotli_sync(encoded)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q10 bounded shortest-path enumerates multiple matches" {
  let input : FixedArray[Byte] = [
    b'a', b'b', b'c', b'd', b'e', b'f', b'X', b'a', b'b', b'c', b'd', b'e', b'f',
    b'Y', b'a', b'b', b'c', b'd', b'e', b'f', b'Z',
  ]
  let config = brotli_bounded_shortest_path_config(
    brotli_four_byte_hash_config(
      brotli_high_quality_hash_config_for_quality(10),
    ),
  )
  let previous = brotli_previous_match_positions(input, config)
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  let matches = brotli_bounded_previous_hash_matches_with_cache(
    input, previous, 14, config, distance_cache,
  )
  let mut saw_distance_7 = false
  let mut saw_distance_14 = false
  for i in 0..<matches.length() {
    if matches[i].distance == 7 && matches[i].length >= 6 {
      saw_distance_7 = true
    }
    if matches[i].distance == 14 && matches[i].length >= 6 {
      saw_distance_14 = true
    }
  }
  assert_true(saw_distance_7)
  assert_true(saw_distance_14)
}

///|
test "brotli_sync q10 bounded suffix tree enumerates matches" {
  let input : FixedArray[Byte] = [
    b'a', b'b', b'c', b'd', b'e', b'f', b'X', b'a', b'b', b'c', b'd', b'e', b'f',
    b'Y', b'a', b'b', b'c', b'd', b'e', b'f', b'Z',
  ]
  let config = brotli_bounded_shortest_path_config(
    brotli_four_byte_hash_config(
      brotli_high_quality_hash_config_for_quality(10),
    ),
  )
  let table = brotli_bounded_suffix_tree_match_table(input, config)
  let matches = table[14]
  let mut saw_distance_7 = false
  let mut saw_distance_14 = false
  for i in 0..<matches.length() {
    if matches[i].distance == 7 && matches[i].length >= 6 {
      saw_distance_7 = true
    }
    if matches[i].distance == 14 && matches[i].length >= 6 {
      saw_distance_14 = true
    }
  }
  assert_true(saw_distance_7)
  assert_true(saw_distance_14)
}

///|
test "brotli_sync q10 bounded shortest-path costs recent distances" {
  let cached : FixedArray[Int] = [4, 11, 15, 16]
  let uncached : FixedArray[Int] = [11, 15, 16, 20]
  let model = brotli_bounded_shortest_path_default_cost_model()
  assert_true(
    brotli_bounded_shortest_path_copy_cost(8, 4, 64, cached, model) <
    brotli_bounded_shortest_path_copy_cost(8, 4, 64, uncached, model),
  )
  assert_eq(brotli_compute_distance_code(4, 64, cached), 0)
  assert_true(brotli_compute_distance_code(4, 64, uncached) >= 16)
}

///|
test "brotli_sync q10 bounded shortest-path cost model follows histograms" {
  let input : FixedArray[Byte] = [
    b'a', b'a', b'a', b'a', b'b', b'c', b'd', b'e', b'f', b'g', b'h', b'i',
  ]
  let commands : Array[BrotliEncodeCommand] = []
  commands.push(brotli_make_encode_command(0, input.length(), 0, 0, false))
  let model = brotli_bounded_shortest_path_cost_model_from_commands(
    input, commands,
  )
  assert_true(
    model.literal_bits[b'a'.to_int()] <= model.literal_bits[b'i'.to_int()],
  )
}

///|
test "brotli_sync q10 bounded shortest-path keeps a two-state beam" {
  let state_count = 4
  let costs = FixedArray::make(state_count, 9999)
  let cache0 = FixedArray::make(state_count, 0)
  let cache1 = FixedArray::make(state_count, 0)
  let cache2 = FixedArray::make(state_count, 0)
  let cache3 = FixedArray::make(state_count, 0)
  let previous_position = FixedArray::make(state_count, -1)
  let previous_slot = FixedArray::make(state_count, -1)
  let copy_length = FixedArray::make(state_count, 0)
  let copy_distance = FixedArray::make(state_count, 0)
  let copy_output_length = FixedArray::make(state_count, 0)
  brotli_bounded_shortest_path_offer_state(
    costs,
    cache0,
    cache1,
    cache2,
    cache3,
    previous_position,
    previous_slot,
    copy_length,
    copy_distance,
    copy_output_length,
    1,
    30,
    [4, 11, 15, 16],
    0,
    0,
    4,
    4,
    0,
  )
  brotli_bounded_shortest_path_offer_state(
    costs,
    cache0,
    cache1,
    cache2,
    cache3,
    previous_position,
    previous_slot,
    copy_length,
    copy_distance,
    copy_output_length,
    1,
    10,
    [7, 11, 15, 16],
    0,
    1,
    5,
    7,
    0,
  )
  brotli_bounded_shortest_path_offer_state(
    costs,
    cache0,
    cache1,
    cache2,
    cache3,
    previous_position,
    previous_slot,
    copy_length,
    copy_distance,
    copy_output_length,
    1,
    20,
    [9, 11, 15, 16],
    0,
    0,
    6,
    9,
    0,
  )
  let first = brotli_bounded_shortest_path_state_index(1, 0)
  let second = brotli_bounded_shortest_path_state_index(1, 1)
  assert_eq(costs[first], 10)
  assert_eq(costs[second], 20)
  assert_eq(cache0[first], 7)
  assert_eq(cache0[second], 9)
  assert_eq(previous_slot[first], 1)
  assert_eq(copy_length[second], 6)
  assert_eq(copy_distance[second], 9)
}

///|
test "brotli_sync q2 through q9 allow two-mebibyte chunks" {
  assert_eq(brotli_standard_chunk_size_for_quality(2), 2097152)
  assert_eq(brotli_standard_chunk_size_for_quality(8), 2097152)
  assert_eq(brotli_standard_chunk_size_for_quality(9), 2097152)
  assert_eq(brotli_standard_chunk_size_for_quality(10), 1048576)
  assert_eq(
    brotli_hash_max_input_length(brotli_natural_hash_config_for_quality(2)),
    2097152,
  )
  assert_eq(
    brotli_effective_max_commands(
      brotli_natural_hash_config_for_quality(2),
      65536,
    ),
    52000,
  )
  assert_eq(
    brotli_effective_max_commands(
      brotli_natural_hash_config_for_quality(2),
      2097152,
    ),
    104000,
  )
  assert_eq(
    brotli_hash_max_input_length(brotli_natural_hash_config_for_quality(8)),
    2097152,
  )
  assert_eq(
    brotli_hash_max_input_length(brotli_intermediate_hash_config_for_quality(8)),
    2097152,
  )
  assert_eq(
    brotli_hash_max_input_length(brotli_high_quality_hash_config_for_quality(9)),
    2097152,
  )
}

///|
test "brotli_sync encoder uses distance-cache short codes" {
  let distance_cache : FixedArray[Int] = [4, 11, 15, 16]
  inspect(brotli_compute_distance_code(4, 64, distance_cache), content="0")
  inspect(brotli_compute_distance_code(11, 64, distance_cache), content="1")
  inspect(brotli_compute_distance_code(15, 64, distance_cache), content="2")
  inspect(brotli_compute_distance_code(16, 64, distance_cache), content="3")
  let same_distance = brotli_make_encode_command_with_distance_code(
    0, 4, 8, 4, 0,
  )
  assert_false(brotli_command_uses_distance_symbol(same_distance))
  let cached_distance = brotli_make_encode_command_with_distance_code(
    4, 3, 8, 11, 1,
  )
  assert_true(brotli_command_uses_distance_symbol(cached_distance))
  assert_eq(cached_distance.distance_prefix.symbol, 1)
  brotli_update_distance_cache(distance_cache, 11, 1)
  inspect(distance_cache[0], content="11")
  inspect(distance_cache[1], content="4")
  let carried_cache : FixedArray[Int] = [8, 4, 11, 15]
  let repeated : FixedArray[Byte] = [
    b'a', b'b', b'c', b'd', b'a', b'b', b'c', b'd', b'a', b'b', b'c', b'd',
  ]
  match
    brotli_build_simple_lz77_command_candidate(
      repeated,
      brotli_hash_config_for_quality(5),
      carried_cache,
    ) {
    Some(candidate) => {
      assert_true(candidate.commands.length() > 0)
      assert_true(brotli_command_uses_distance_symbol(candidate.commands[0]))
      assert_eq(candidate.commands[0].distance_prefix.symbol, 1)
      inspect(candidate.distance_cache[0], content="4")
      inspect(candidate.distance_cache[1], content="8")
    }
    None => fail("expected carried distance-cache command")
  }
}

///|
fn brotli_reference_command_prefix_for_mode(
  insert_length : Int,
  copy_length : Int,
  mode : Int,
) -> BrotliCommandPrefix raise FbrError {
  for symbol in 0..<@common.brotli_num_command_symbols {
    let info = @common.brotli_command_info(symbol)
    let distance_ok = if mode == 2 {
      true
    } else if mode == 1 {
      info.distance_code < 0
    } else {
      info.distance_code >= 0
    }
    if distance_ok &&
      insert_length >= info.insert_len_offset &&
      copy_length >= info.copy_len_offset {
      let insert_extra = insert_length - info.insert_len_offset
      let copy_extra = copy_length - info.copy_len_offset
      if insert_extra < 1 << info.insert_len_extra_bits &&
        copy_extra < 1 << info.copy_len_extra_bits {
        return {
          symbol,
          insert_extra,
          copy_extra,
          insert_extra_bits: info.insert_len_extra_bits,
          copy_extra_bits: info.copy_len_extra_bits,
        }
      }
    }
  }
  raise @common.fbr_err(
    BrotliInvalidMetablock,
    msg="no reference command prefix",
  )
}

///|
fn assert_command_prefix_matches_reference(
  insert_length : Int,
  copy_length : Int,
  mode : Int,
) -> Unit raise {
  let direct_result : Result[BrotliCommandPrefix, FbrError] = try? brotli_command_prefix_for_mode(
    insert_length, copy_length, mode,
  )
  let reference_result : Result[BrotliCommandPrefix, FbrError] = try? brotli_reference_command_prefix_for_mode(
    insert_length, copy_length, mode,
  )
  match (direct_result, reference_result) {
    (Ok(direct), Ok(reference)) => {
      assert_eq(direct.symbol, reference.symbol)
      assert_eq(direct.insert_extra, reference.insert_extra)
      assert_eq(direct.copy_extra, reference.copy_extra)
      assert_eq(direct.insert_extra_bits, reference.insert_extra_bits)
      assert_eq(direct.copy_extra_bits, reference.copy_extra_bits)
    }
    (Err(_), Err(_)) => ()
    _ => fail("command prefix lookup diverged from reference scan")
  }
}

///|
test "brotli encoder command prefix table matches reference scan" {
  for insert_code in 0..<@common.brotli_insert_length_extra_bits.length() {
    let insert_offset = @common.brotli_prefix_offset(
      @common.brotli_insert_length_extra_bits, insert_code, 0,
    )
    let insert_last = insert_offset +
      (1 << @common.brotli_insert_length_extra_bits[insert_code]) -
      1
    for copy_code in 0..<@common.brotli_copy_length_extra_bits.length() {
      let copy_offset = @common.brotli_prefix_offset(
        @common.brotli_copy_length_extra_bits, copy_code, 2,
      )
      let copy_last = copy_offset +
        (1 << @common.brotli_copy_length_extra_bits[copy_code]) -
        1
      for mode in 0..<=2 {
        assert_command_prefix_matches_reference(
          insert_offset, copy_offset, mode,
        )
        assert_command_prefix_matches_reference(insert_offset, copy_last, mode)
        assert_command_prefix_matches_reference(insert_last, copy_offset, mode)
        assert_command_prefix_matches_reference(insert_last, copy_last, mode)
      }
    }
  }
}

///|
test "brotli encoder maps distance prefixes by range boundary" {
  for
    code in @common.brotli_num_distance_short_codes..<@common.brotli_distance_alphabet_size(
      0, 0, 24,
    ) {
    let extra_bits = @common.brotli_distance_extra_bits(code, 0, 0)
    let offset = @common.brotli_distance_offset(code, 0, 0)
    let first = brotli_distance_prefix_for_distance(offset)
    assert_eq(first.symbol, code)
    assert_eq(first.insert_extra_bits, extra_bits)
    assert_eq(first.insert_extra, 0)
    let last_extra = (1 << extra_bits) - 1
    let last = brotli_distance_prefix_for_distance(offset + last_extra)
    assert_eq(last.symbol, code)
    assert_eq(last.insert_extra_bits, extra_bits)
    assert_eq(last.insert_extra, last_extra)
  }
}

///|
test "brotli_sync matcher probes distance-cache candidates" {
  let input : FixedArray[Byte] = [
    b'a', b'b', b'c', b'd', b'0', b'1', b'a', b'b', b'c', b'd', b'2', b'3',
  ]
  let config = brotli_high_quality_hash_config_for_quality(9)
  let previous = brotli_previous_match_positions(input, config)
  let distance_cache : FixedArray[Int] = [6, 11, 15, 16]
  let (length, distance) = brotli_longest_previous_hash_match_with_cache(
    input, previous, 6, config, distance_cache,
  )
  inspect(length, content="4")
  inspect(distance, content="6")
}

///|
/// The hash-chain walk uses a boundary-byte pre-check that skips any candidate
/// whose byte at offset `best_length` differs, since its common prefix cannot
/// then exceed the incumbent. This must never discard a genuinely longer match
/// that sits deeper in the chain than a shorter one. Here the most recent chain
/// entry (distance 12) matches only the 4-byte prefix while the older entry
/// (distance 32) matches all 16 bytes; the walk sets best_length=4 on the short
/// one first, so the long one is reached only after the pre-check, which must
/// pass it through. A regression that wrongly skipped it would return (4, 12).
test "brotli matcher keeps longer chain match past boundary pre-check" {
  let input : FixedArray[Byte] = [
    // [0..15] long source
    b'A', b'B', b'C', b'D', b'E', b'F', b'G', b'H', b'I', b'J', b'K', b'L', b'M',
    b'N', b'O', b'P',
    // [16..19] filler (distinct hash)
     b'1', b'2', b'3', b'4',
    // [20..27] short source: ABCD prefix then diverges
     b'A', b'B', b'C', b'D', b'w', b'x', b'y', b'z',
    // [28..31] filler
     b'5', b'6', b'7', b'8',
    // [32..47] match target, identical to [0..15]
     b'A', b'B', b'C', b'D', b'E', b'F', b'G', b'H', b'I', b'J', b'K', b'L', b'M',
    b'N', b'O', b'P',
  ]
  let config = brotli_high_quality_hash_config_for_quality(9)
  let previous = brotli_previous_match_positions(input, config)
  // All cache distances exceed the position, so no distance-cache candidate
  // qualifies; the result is determined purely by the hash chain.
  let distance_cache : FixedArray[Int] = [100, 100, 100, 100]
  let (length, distance) = brotli_longest_previous_hash_match_with_cache(
    input, previous, 32, config, distance_cache,
  )
  inspect(length, content="16")
  inspect(distance, content="32")
}

///|
test "brotli_sync q2 keeps alternate hash candidates exact-costed" {
  let input = FixedArray::make(1400, b'\x00')
  let alphabet : FixedArray[Byte] = [b'A', b'B', b'C', b'D']
  let mut state = 17
  for chunk in 0..<200 {
    let offset = chunk * 7
    input[offset] = b'A'
    input[offset + 1] = b'B'
    input[offset + 2] = b'C'
    input[offset + 3] = b'A'
    input[offset + 4] = b'B'
    input[offset + 5] = b'C'
    input[offset + 6] = alphabet[state % 4]
    state = (state * 73 + 41) % 257
  }
  let natural = brotli_natural_hash_config_for_quality(2)
  let four_byte = brotli_four_byte_hash_config(natural)
  inspect(natural.hash_bytes, content="3")
  inspect(natural.table_size, content="32768")
  inspect(natural.max_match_checks, content="8")
  inspect(natural.min_match_length, content="10")
  inspect(natural.max_commands, content="52000")
  inspect(four_byte.hash_bytes, content="4")
  inspect(four_byte.table_size, content="32768")
  inspect(
    brotli_high_quality_hash_config_for_quality(9).table_size,
    content="32768",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(9).max_match_checks,
    content="32",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(9).min_match_length,
    content="5",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(9).max_commands,
    content="300000",
  )
  inspect(
    brotli_intermediate_hash_config_for_quality(4).max_match_checks,
    content="8",
  )
  inspect(
    brotli_intermediate_hash_config_for_quality(4).min_match_length,
    content="6",
  )
  inspect(
    brotli_intermediate_hash_config_for_quality(6).max_match_checks,
    content="16",
  )
  inspect(
    brotli_intermediate_hash_config_for_quality(8).max_match_checks,
    content="32",
  )
  inspect(
    brotli_intermediate_hash_config_for_quality(8).max_commands,
    content="240000",
  )
  inspect(brotli_hash_config_for_quality(4).lazy_lookahead, content="0")
  inspect(brotli_natural_hash_config_for_quality(8).lazy_lookahead, content="0")
  inspect(
    brotli_intermediate_hash_config_for_quality(8).lazy_lookahead,
    content="0",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(9).lazy_lookahead,
    content="3",
  )
  assert_true(brotli_use_intermediate_lz77_candidate(3))
  assert_false(brotli_use_intermediate_lz77_candidate(4))
  assert_false(brotli_use_intermediate_lz77_candidate(8))
  assert_true(brotli_use_intermediate_lz77_candidate(9))
  assert_false(brotli_use_intermediate_four_byte_candidate(5, 65536))
  assert_false(brotli_use_intermediate_four_byte_candidate(6, 65536))
  assert_false(brotli_use_intermediate_four_byte_candidate(7, 65536))
  assert_false(brotli_use_intermediate_four_byte_candidate(7, 65537))
  assert_false(brotli_use_intermediate_four_byte_candidate(8, 65536))
  assert_true(brotli_use_natural_four_byte_candidate(3, 65536))
  assert_false(brotli_use_natural_four_byte_candidate(4, 65536))
  assert_false(brotli_use_natural_four_byte_candidate(5, 65536))
  assert_false(brotli_use_natural_four_byte_candidate(6, 65536))
  assert_false(brotli_use_natural_four_byte_candidate(8, 65536))
  assert_true(brotli_use_natural_four_byte_candidate(9, 65536))
  assert_false(brotli_use_literal_split_lz77_candidate(3))
  assert_false(brotli_use_literal_split_lz77_candidate(4))
  assert_false(brotli_use_literal_split_lz77_candidate(8))
  assert_true(brotli_use_literal_split_lz77_candidate(9))
  assert_false(brotli_use_context8_first_lz77_candidate(3, 4096))
  assert_true(brotli_use_context8_first_lz77_candidate(3, 8192))
  assert_false(brotli_use_context8_first_lz77_candidate(4, 4096))
  assert_true(brotli_use_context8_first_lz77_candidate(4, 8192))
  assert_true(brotli_use_context8_first_lz77_candidate(8, 65536))
  assert_false(brotli_use_context8_first_lz77_candidate(9, 65536))
  assert_true(brotli_use_literal_only_lz77_candidate(3, 4096))
  assert_false(brotli_use_literal_only_lz77_candidate(3, 8192))
  assert_true(brotli_use_literal_only_lz77_candidate(4, 4096))
  assert_false(brotli_use_literal_only_lz77_candidate(4, 8192))
  assert_false(brotli_use_literal_only_lz77_candidate(8, 65536))
  assert_true(brotli_use_literal_only_lz77_candidate(9, 65536))
  inspect(
    brotli_high_quality_hash_config_for_quality(10).max_match_checks,
    content="256",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(10).min_match_length,
    content="5",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(10).max_commands,
    content="600000",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(10).table_size,
    content="131072",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(11).max_match_checks,
    content="256",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(11).max_commands,
    content="600000",
  )
  inspect(
    brotli_high_quality_hash_config_for_quality(11).table_size,
    content="131072",
  )
  assert_false(brotli_use_context4_lz77_candidate(3))
  assert_false(brotli_use_context4_lz77_candidate(4))
  assert_false(brotli_use_context4_lz77_candidate(8))
  assert_true(brotli_use_context4_lz77_candidate(9))
  assert_false(brotli_use_context16_lz77_candidate(3))
  assert_false(brotli_use_context16_lz77_candidate(4))
  assert_false(brotli_use_context16_lz77_candidate(8))
  assert_true(brotli_use_context16_lz77_candidate(9))
  assert_false(brotli_use_command_distance_split_lz77_candidates(3))
  assert_false(brotli_use_command_distance_split_lz77_candidates(4))
  assert_false(brotli_use_command_distance_split_lz77_candidates(8))
  assert_true(brotli_use_command_distance_split_lz77_candidates(9))
  let best3 = match brotli_build_simple_lz77_commands(input, natural) {
    Some(commands) =>
      brotli_write_best_lz77_metablock(input, commands, true, 2, true, 0, 0)
    None => fail("expected three-byte hash candidate")
  }
  let previous = brotli_previous_match_positions(input, natural)
  let cache_a : FixedArray[Int] = [4, 11, 15, 16]
  let cache_b : FixedArray[Int] = [4, 11, 15, 16]
  let commands_a = match
    brotli_build_simple_lz77_commands_with_distance_cache(
      input, natural, cache_a,
    ) {
    Some(commands) => commands
    None => fail("expected normal LZ77 commands")
  }
  let commands_b = match
    brotli_build_simple_lz77_commands_with_distance_cache_and_previous(
      input, natural, cache_b, previous,
    ) {
    Some(commands) => commands
    None => fail("expected previous-table LZ77 commands")
  }
  assert_eq(commands_a.length(), commands_b.length())
  assert_eq(cache_a[0], cache_b[0])
  assert_eq(cache_a[1], cache_b[1])
  assert_eq(cache_a[2], cache_b[2])
  assert_eq(cache_a[3], cache_b[3])
  for i in 0..<commands_a.length() {
    assert_eq(commands_a[i].insert_start, commands_b[i].insert_start)
    assert_eq(commands_a[i].insert_length, commands_b[i].insert_length)
    assert_eq(commands_a[i].copy_length, commands_b[i].copy_length)
    assert_eq(commands_a[i].output_length, commands_b[i].output_length)
    assert_eq(commands_a[i].has_copy, commands_b[i].has_copy)
    assert_eq(commands_a[i].command.symbol, commands_b[i].command.symbol)
    assert_eq(
      commands_a[i].command.insert_extra,
      commands_b[i].command.insert_extra,
    )
    assert_eq(
      commands_a[i].command.copy_extra,
      commands_b[i].command.copy_extra,
    )
    assert_eq(
      commands_a[i].distance_prefix.symbol,
      commands_b[i].distance_prefix.symbol,
    )
    assert_eq(
      commands_a[i].distance_prefix.insert_extra,
      commands_b[i].distance_prefix.insert_extra,
    )
  }
  let best4 = match brotli_build_simple_lz77_commands(input, four_byte) {
    Some(commands) =>
      brotli_write_best_lz77_metablock(input, commands, true, 2, true, 0, 0)
    None => fail("expected four-byte hash candidate")
  }
  assert_true(best3.bit_pos > 0)
  assert_true(best4.bit_pos > 0)
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() <= 195)
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 uses identity static dictionary words" {
  let input = str_to_u8(
    "time area unit home work water world house about other these first right after where",
  )
  let config = brotli_hash_config_for_quality(2)
  match brotli_build_identity_dictionary_commands(input, config, 0, 22) {
    Some(commands) => {
      assert_true(commands.length() > 8)
      assert_eq(commands[0].insert_length, 0)
      assert_eq(commands[0].copy_length, 4)
      assert_true(commands[0].has_copy)
    }
    None => fail("expected static dictionary command candidate")
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 uses uppercase static dictionary transforms" {
  let input = str_to_u8("Time Area Unit Home Work")
  let config = brotli_hash_config_for_quality(2)
  let index = brotli_build_dictionary_encode_index()
  let mut found_transform = false
  for position in 0..<input.length() {
    match brotli_find_identity_dictionary_match(index, input, position, 0, 22) {
      Some((length, _, distance)) => {
        let identity_limit = 1 +
          (1 << brotli_dictionary_size_bits_by_length[length])
        if distance > identity_limit {
          found_transform = true
        }
      }
      None => ()
    }
  }
  assert_true(found_transform)
  match brotli_build_identity_dictionary_commands(input, config, 0, 22) {
    Some(commands) => {
      assert_true(commands.length() >= 5)
      assert_eq(commands[0].insert_length, 0)
      assert_eq(commands[0].copy_length, 4)
      assert_true(commands[0].has_copy)
    }
    None => fail("expected transformed static dictionary command candidate")
  }
  let encoded = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let decoded = @decode.unbrotli_sync(encoded)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 uses static dictionary suffix transforms" {
  let input = str_to_u8("time area unit ")
  let config = brotli_hash_config_for_quality(2)
  let index = brotli_build_dictionary_encode_index()
  match brotli_find_identity_dictionary_match(index, input, 0, 0, 22) {
    Some((word_length, output_length, distance)) => {
      assert_eq(word_length, 4)
      assert_eq(output_length, 5)
      let identity_limit = 1 +
        (1 << brotli_dictionary_size_bits_by_length[word_length])
      assert_true(distance >= identity_limit)
    }
    None => fail("expected suffix static dictionary match")
  }
  match brotli_build_identity_dictionary_commands(input, config, 0, 22) {
    Some(commands) => {
      assert_true(commands.length() >= 3)
      assert_eq(commands[0].insert_length, 0)
      assert_eq(commands[0].copy_length, 4)
      assert_true(commands[0].has_copy)
    }
    None => fail("expected suffix static dictionary command candidate")
  }
  let encoded = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let decoded = @decode.unbrotli_sync(encoded)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses chunked large input" {
  let input = FixedArray::make(200_000, b'\x00')
  let pattern : FixedArray[Byte] = [b'A', b'B', b'C', b'D', b'E']
  for i in 0..<input.length() {
    input[i] = pattern[i % pattern.length()]
  }
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q2 compresses high alphabet repetitive chunks" {
  let input = FixedArray::make(80_000, b'\x00')
  for i in 0..<input.length() {
    input[i] = (i & 0xff).to_byte()
  }
  assert_true(brotli_count_unique_literals_up_to(input, 16) > 16)
  let q1 = brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q2 = brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_true(q2.length() < q1.length())
  let decoded = @decode.unbrotli_sync(q2)
  assert_eq(decoded.length(), input.length())
  for i in 0..<decoded.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync q9 mixed dictionary beats q8 on dictionary text" {
  // English words from the static dictionary, repeated to give the mixed
  // dictionary candidate enough input to engage (>= 8192 bytes).
  let words = str_to_u8(
    " the time was full of work because they could find new other place over",
  )
  let pattern = words
  let total = 9000
  let input = FixedArray::make(total, b'\x00')
  let pattern_len = pattern.length()
  for i in 0..<total {
    input[i] = pattern[i % pattern_len]
  }
  let q8 = brotli_sync(input, opts={
    quality: 8,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  let q9 = brotli_sync(input, opts={
    quality: 9,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  // q9 enables the mixed-dictionary candidate, so the output is not larger
  // than q8 for any input we can reach this gate with.
  assert_true(q9.length() <= q8.length())
  let decoded_q9 = @decode.unbrotli_sync(q9)
  assert_eq(decoded_q9.length(), input.length())
  for i in 0..<decoded_q9.length() {
    assert_eq(decoded_q9[i], input[i])
  }
}

///|
test "brotli_sync q0 through q11 round-trip" {
  let input : FixedArray[Byte] = [0, 1, 1, 2, 3, 5, 8, 13]
  for quality in 0..<=11 {
    let compressed = brotli_sync(input, opts={
      quality,
      window_bits: 22,
      max_input_size: default_max_input_size,
    })
    let decoded = @decode.unbrotli_sync(compressed)
    assert_eq(decoded.length(), input.length())
    for i in 0..<input.length() {
      assert_eq(decoded[i], input[i])
    }
  }
}

///|
test "brotli_sync default quality round-trips" {
  let input : FixedArray[Byte] = [9, 8, 7]
  let compressed = brotli_sync(input)
  let decoded = @decode.unbrotli_sync(compressed)
  assert_eq(decoded.length(), input.length())
  for i in 0..<input.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync rejects invalid quality" {
  let input : FixedArray[Byte] = [1]
  let result : Result[FixedArray[Byte], FbrError] = try? brotli_sync(input, opts={
    quality: 12,
    window_bits: 22,
    max_input_size: default_max_input_size,
  })
  assert_brotli_error(result, InvalidZipData)
}

///|
test "brotli_sync enforces max_input_size" {
  let input : FixedArray[Byte] = [1, 2]
  let result : Result[FixedArray[Byte], FbrError] = try? brotli_sync(input, opts={
    quality: 1,
    window_bits: 22,
    max_input_size: 1,
  })
  assert_brotli_error(result, InvalidZipData)
}

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
  inspect(brotli_huffman_max_code_length, content="15")
  inspect(brotli_huffman_table_bits, content="8")
  inspect(brotli_huffman_max_table_size, content="1080")
  inspect(brotli_num_literal_symbols, content="256")
  inspect(brotli_num_command_symbols, content="704")
  inspect(brotli_distance_alphabet_size(0, 0, 24), content="64")
}

///|
test "brotli_command_info matches reference lookup cases" {
  let first = brotli_command_info(0)
  inspect(first.insert_len_extra_bits, content="0")
  inspect(first.copy_len_extra_bits, content="0")
  inspect(first.distance_code, content="0")
  inspect(first.distance_context, content="0")
  inspect(first.insert_len_offset, content="0")
  inspect(first.copy_len_offset, content="2")

  let insert_extra = brotli_command_info(48)
  inspect(insert_extra.insert_len_extra_bits, content="1")
  inspect(insert_extra.copy_len_extra_bits, content="0")
  inspect(insert_extra.insert_len_offset, content="6")
  inspect(insert_extra.copy_len_offset, content="2")

  let copy_extra = brotli_command_info(64)
  inspect(copy_extra.insert_len_extra_bits, content="0")
  inspect(copy_extra.copy_len_extra_bits, content="1")
  inspect(copy_extra.distance_context, content="3")
  inspect(copy_extra.copy_len_offset, content="10")

  let explicit_distance = brotli_command_info(128)
  inspect(explicit_distance.distance_code, content="-1")
}

///|
test "BrotliDistanceRing resolves initial implicit distance" {
  inspect(brotli_distance_ring_slot(-1), content="3")
  inspect(brotli_distance_ring_slot(-2), content="2")
  inspect(brotli_distance_ring_slot(4), content="0")
  let ring = BrotliDistanceRing::new()
  inspect(ring.take_short_code(0), content="4")
  ring.record(4)
  inspect(ring.take_short_code(0), content="4")
}

///|
test "brotli distance formula decodes direct and postfix distances" {
  inspect(brotli_distance_extra_bits(16, 0, 0), content="1")
  inspect(brotli_distance_offset(16, 0, 0), content="1")
  inspect(brotli_distance_offset(17, 0, 0), content="3")
  inspect(brotli_distance_extra_bits(20, 1, 4), content="1")
  inspect(brotli_distance_offset(20, 1, 4), content="5")
}

///|
test "brotli_huffman_code packs bits and value losslessly" {
  // Round-trip a spread of (bits, value) pairs spanning the ranges Brotli
  // builds: code lengths 0..15 and values up to the largest sub-table offset.
  for bits in [0, 1, 8, 15] {
    for value in [0, 1, 65, 255, 704, 2080] {
      let code = brotli_huffman_code(bits, value)
      assert_eq(brotli_huffman_code_bits(code), bits)
      assert_eq(brotli_huffman_code_value(code), value)
    }
  }
  // The empty sentinel carries a negative length so callers can detect
  // unfilled entries.
  assert_eq(brotli_huffman_code_bits(brotli_huffman_code_empty), -1)
  assert_eq(brotli_huffman_code_value(brotli_huffman_code_empty), 0)
}

///|
test "brotli_build_huffman_table rejects malformed length sets" {
  let empty : FixedArray[Byte] = [0, 0, 0, 0]
  let empty_result : Result[FixedArray[Int], FbrError] = try? brotli_build_huffman_table(
    empty, 4, 3,
  )
  guard empty_result is Err(FbrError(code=empty_code, ..)) else {
    fail("expected empty Huffman error")
  }
  assert_eq(empty_code, BrotliInvalidHuffman)

  let over : FixedArray[Byte] = [1, 1, 1]
  let over_result : Result[FixedArray[Int], FbrError] = try? brotli_build_huffman_table(
    over, 3, 3,
  )
  guard over_result is Err(FbrError(code=over_code, ..)) else {
    fail("expected over-subscribed Huffman error")
  }
  assert_eq(over_code, BrotliInvalidHuffman)

  let under : FixedArray[Byte] = [2, 2, 0, 0]
  let under_result : Result[FixedArray[Int], FbrError] = try? brotli_build_huffman_table(
    under, 4, 3,
  )
  guard under_result is Err(FbrError(code=under_code, ..)) else {
    fail("expected under-subscribed Huffman error")
  }
  assert_eq(under_code, BrotliInvalidHuffman)
}

///|
fn brotli_ascii_utf8_context1_ref(byte : Int) -> Int {
  if byte == 9 || byte == 10 || byte == 13 {
    1
  } else if byte == 32 {
    2
  } else if byte == 34 || byte == 39 {
    4
  } else if byte == 37 {
    5
  } else if byte == 40 || byte == 60 || byte == 91 || byte == 123 {
    6
  } else if byte == 41 || byte == 62 || byte == 93 || byte == 125 {
    7
  } else if byte == 44 || byte == 59 || byte == 58 {
    8
  } else if byte == 46 {
    9
  } else if byte == 61 {
    10
  } else if byte >= 48 && byte <= 57 {
    11
  } else if byte == 65 || byte == 69 || byte == 73 || byte == 79 || byte == 85 {
    12
  } else if byte >= 65 && byte <= 90 {
    13
  } else if byte == 97 ||
    byte == 101 ||
    byte == 105 ||
    byte == 111 ||
    byte == 117 {
    14
  } else if byte >= 97 && byte <= 122 {
    15
  } else if byte < 32 || byte == 127 {
    0
  } else {
    3
  }
}

///|
fn brotli_ascii_utf8_context2_ref(byte : Int) -> Int {
  if byte <= 32 || byte == 127 {
    0
  } else if byte >= 48 && byte <= 57 {
    2
  } else if byte >= 65 && byte <= 90 {
    2
  } else if byte >= 97 && byte <= 122 {
    3
  } else {
    1
  }
}

///|
test "brotli literal context LUT matches if-else reference for UTF8 and signed" {
  for p1 in 0..<256 {
    let expected_lut1_utf8 = if p1 < 128 {
      brotli_ascii_utf8_context1_ref(p1) << 2
    } else if p1 < 192 {
      p1 & 1
    } else {
      2 | (p1 & 1)
    }
    assert_eq(brotli_utf8_lut1[p1], expected_lut1_utf8)
    let expected_lut2_utf8 = if p1 < 128 {
      brotli_ascii_utf8_context2_ref(p1)
    } else if p1 < 224 {
      0
    } else {
      2
    }
    assert_eq(brotli_utf8_lut2[p1], expected_lut2_utf8)
    let expected_lut1_signed = if p1 == 0 {
      0
    } else if p1 < 16 {
      8
    } else if p1 < 64 {
      16
    } else if p1 < 128 {
      24
    } else if p1 < 192 {
      32
    } else if p1 < 240 {
      40
    } else if p1 < 255 {
      48
    } else {
      56
    }
    assert_eq(brotli_signed_lut1[p1], expected_lut1_signed)
    let expected_lut2_signed = if p1 == 0 {
      0
    } else if p1 < 16 {
      1
    } else if p1 < 64 {
      2
    } else if p1 < 128 {
      3
    } else if p1 < 192 {
      4
    } else if p1 < 240 {
      5
    } else if p1 < 255 {
      6
    } else {
      7
    }
    assert_eq(brotli_signed_lut2[p1], expected_lut2_signed)
  }
}

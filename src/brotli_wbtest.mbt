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
fn append_byte(data : FixedArray[Byte], byte : Byte) -> FixedArray[Byte] {
  let out = FixedArray::make(data.length() + 1, b'\x00')
  data.blit_to(out, len=data.length(), src_offset=0, dst_offset=0)
  out[data.length()] = byte
  out
}

///|
fn assert_truncated_prefixes_raise_unexpected_eof(
  data : FixedArray[Byte],
) -> Unit raise {
  for length in 1..<data.length() {
    let prefix = slc(data, 0, e=length)
    let result = try? unbrotli_sync(prefix)
    assert_brotli_error(result, UnexpectedEOF)
  }
}

///|
fn make_uncompressed_bomb_header() -> FixedArray[Byte] {
  let compressed = FixedArray::make(4, b'\x00')
  let mut pos = 0
  wbits(compressed, pos, 1) // WBITS: standard 10-bit window
  pos += 1
  wbits(compressed, pos, 0)
  pos += 3
  wbits(compressed, pos, 2)
  pos += 3
  wbits(compressed, pos, 0) // not final, so ISUNCOMPRESSED follows MLEN
  pos += 1
  wbits(compressed, pos, 0) // MNIBBLES = 0, 16-bit MLEN
  pos += 2
  wbits16(compressed, pos, 0xffff) // MLEN = 65536
  pos += 16
  wbits(compressed, pos, 1) // uncompressed meta-block
  compressed
}

///|
fn write_simple_one_symbol_huffman(
  encoded : FixedArray[Byte],
  start : Int,
  symbol : Int,
  symbol_bits : Int,
) -> Int {
  let mut pos = start
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 0)
  pos += 2
  wbits16(encoded, pos, symbol)
  pos += symbol_bits
  pos
}

///|
fn write_trivial_compressed_header(
  encoded : FixedArray[Byte],
  start : Int,
  command_symbol : Int,
  distance_symbol? : Int = 0,
) -> Int {
  let mut pos = start
  wbits(encoded, pos, 0) // one literal block type
  pos += 1
  wbits(encoded, pos, 0) // one command block type
  pos += 1
  wbits(encoded, pos, 0) // one distance block type
  pos += 1
  wbits(encoded, pos, 0) // NPOSTFIX = 0, NDIRECT = 0
  pos += 6
  wbits(encoded, pos, 0) // context mode for the only literal block type
  pos += 2
  wbits(encoded, pos, 0) // literal context map has one tree
  pos += 1
  wbits(encoded, pos, 0) // distance context map has one tree
  pos += 1
  pos = write_simple_one_symbol_huffman(encoded, pos, 65, 8)
  pos = write_simple_one_symbol_huffman(encoded, pos, command_symbol, 10)
  write_simple_one_symbol_huffman(encoded, pos, distance_symbol, 6)
}

///|
fn write_window10_final_metablock_header(
  encoded : FixedArray[Byte],
  length : Int,
) -> Int {
  let mut pos = 0
  wbits(encoded, pos, 1) // WBITS: standard 10-bit window
  pos += 1
  wbits(encoded, pos, 0)
  pos += 3
  wbits(encoded, pos, 2)
  pos += 3
  wbits(encoded, pos, 1) // final meta-block, not empty
  pos += 1
  wbits(encoded, pos, 0)
  pos += 1
  wbits(encoded, pos, 0) // MNIBBLES = 0
  pos += 2
  wbits16(encoded, pos, length - 1)
  pos + 16
}

///|
fn make_one_symbol_tree(
  symbol : Int,
  alphabet_size : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  let lengths = FixedArray::make(alphabet_size, b'\x00')
  lengths[symbol] = b'\x01'
  brotli_build_huffman_table(lengths, alphabet_size, brotli_huffman_table_bits)
}

///|
fn make_tree_group(
  alphabet_size : Int,
  trees : Array[FixedArray[BrotliHuffmanCode]],
) -> BrotliHuffmanTreeGroup {
  ignore(alphabet_size)
  { trees, }
}

///|
fn make_single_block_body_header(
  command_symbol : Int,
  distance_symbol : Int,
) -> BrotliCompressedMetablockHeader raise FzipError {
  let literal_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols))
  let command_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  command_trees.push(
    make_one_symbol_tree(command_symbol, brotli_num_command_symbols),
  )
  let distance_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  distance_trees.push(
    make_one_symbol_tree(
      distance_symbol,
      brotli_distance_alphabet_size(0, 0, 24),
    ),
  )
  {
    literal_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    command_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    distance_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    distance_postfix_bits: 0,
    num_direct_distance_codes: 0,
    context_modes: [0],
    literal_context_map: {
      num_trees: 1,
      map: FixedArray::make(1 << brotli_literal_context_bits, b'\x00'),
    },
    distance_context_map: {
      num_trees: 1,
      map: FixedArray::make(1 << brotli_distance_context_bits, b'\x00'),
    },
    literal_trees: make_tree_group(brotli_num_literal_symbols, literal_trees),
    command_trees: make_tree_group(brotli_num_command_symbols, command_trees),
    distance_trees: make_tree_group(
      brotli_distance_alphabet_size(0, 0, 24),
      distance_trees,
    ),
  }
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
  inspect(brotli_huffman_max_code_length, content="15")
  inspect(brotli_huffman_table_bits, content="8")
  inspect(brotli_huffman_max_table_size, content="1080")
  inspect(brotli_num_literal_symbols, content="256")
  inspect(brotli_num_command_symbols, content="704")
  inspect(brotli_distance_alphabet_size(0, 0, 24), content="64")
}

///|
test "BrotliBitReader reads and aligns LSB-first bits" {
  let reader = BrotliBitReader::new([0xa1, 0x01], 0, 2)
  inspect(reader.take_bits(1), content="1")
  inspect(reader.take_bits(3), content="0")
  inspect(reader.take_bits(3), content="2")
  inspect(reader.consumed, content="7")
  inspect(reader.take_bits(1), content="1")
  inspect(reader.take_bits(1), content="1")
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
test "BrotliBitReader copies aligned bytes after padding" {
  let reader = BrotliBitReader::new([0x01, 0x40, 0x41, 0x42], 0, 4)
  inspect(reader.take_bits(1), content="1")
  let out = FixedArray::make(2, b'\x00')
  reader.take_bytes(out, 0, 2)
  inspect(out[0].to_int(), content="64")
  inspect(out[1].to_int(), content="65")
}

///|
test "brotli_build_huffman_table decodes canonical root table" {
  let lengths : FixedArray[Byte] = [1, 2, 3, 3]
  let table = brotli_build_huffman_table(lengths, 4, 3)
  let reader = BrotliBitReader::new([0xda, 0x01], 0, 2)
  inspect(brotli_read_symbol(reader, table, 3), content="0")
  inspect(brotli_read_symbol(reader, table, 3), content="1")
  inspect(brotli_read_symbol(reader, table, 3), content="2")
  inspect(brotli_read_symbol(reader, table, 3), content="3")
}

///|
test "brotli_build_huffman_table supports single-symbol tree" {
  let lengths : FixedArray[Byte] = [0, 0, 1, 0]
  let table = brotli_build_huffman_table(lengths, 4, 3)
  let reader = BrotliBitReader::new([0xff], 0, 1)
  inspect(brotli_read_symbol(reader, table, 3), content="2")
  inspect(reader.consumed, content="0")
}

///|
test "brotli_build_huffman_table decodes two-level table entries" {
  let lengths : FixedArray[Byte] = [1, 3, 3, 3, 3]
  let table = brotli_build_huffman_table(lengths, 5, 2)
  let encoded = FixedArray::make(4, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 0)
  pos += 1
  wbits(encoded, pos, 1)
  pos += 3
  wbits(encoded, pos, 5)
  pos += 3
  wbits(encoded, pos, 3)
  pos += 3
  wbits(encoded, pos, 7)
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  inspect(brotli_read_symbol(reader, table, 2), content="0")
  inspect(brotli_read_symbol(reader, table, 2), content="1")
  inspect(brotli_read_symbol(reader, table, 2), content="2")
  inspect(brotli_read_symbol(reader, table, 2), content="3")
  inspect(brotli_read_symbol(reader, table, 2), content="4")
}

///|
test "brotli_read_huffman_code reads simple three-symbol table" {
  let encoded = FixedArray::make(4, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 1) // simple marker
  pos += 2
  wbits(encoded, pos, 2) // read 3 symbols
  pos += 2
  wbits(encoded, pos, 0)
  pos += 2
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 2)
  pos += 2
  wbits(encoded, pos, 0)
  pos += 1
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 3)
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let table = brotli_read_huffman_code(reader, 4, 4, 3)
  inspect(brotli_read_symbol(reader, table, 3), content="0")
  inspect(brotli_read_symbol(reader, table, 3), content="1")
  inspect(brotli_read_symbol(reader, table, 3), content="2")
}

///|
test "brotli_read_huffman_code rejects malformed simple tables" {
  let duplicate = FixedArray::make(2, b'\x00')
  let mut pos = 0
  wbits(duplicate, pos, 1)
  pos += 2
  wbits(duplicate, pos, 1)
  pos += 2
  wbits(duplicate, pos, 1)
  pos += 2
  wbits(duplicate, pos, 1)
  let duplicate_reader = BrotliBitReader::new(duplicate, 0, duplicate.length())
  let duplicate_result : Result[FixedArray[BrotliHuffmanCode], FzipError] = try? brotli_read_huffman_code(
    duplicate_reader, 4, 4, 3,
  )
  guard duplicate_result is Err(FzipError(code=duplicate_code, ..)) else {
    fail("expected duplicate simple Huffman error")
  }
  assert_eq(duplicate_code, BrotliInvalidHuffman)

  let out_of_range = FixedArray::make(2, b'\x00')
  pos = 0
  wbits(out_of_range, pos, 1)
  pos += 2
  wbits(out_of_range, pos, 0)
  pos += 2
  wbits(out_of_range, pos, 3)
  let out_of_range_reader = BrotliBitReader::new(
    out_of_range,
    0,
    out_of_range.length(),
  )
  let out_of_range_result : Result[FixedArray[BrotliHuffmanCode], FzipError] = try? brotli_read_huffman_code(
    out_of_range_reader, 4, 3, 3,
  )
  guard out_of_range_result is Err(FzipError(code=range_code, ..)) else {
    fail("expected out-of-range simple Huffman error")
  }
  assert_eq(range_code, BrotliInvalidHuffman)
}

///|
test "brotli_read_huffman_code reads complex two-symbol table" {
  let encoded = FixedArray::make(8, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 0) // complex marker, no skipped code-length codes
  pos += 2
  wbits(encoded, pos, 7) // code-length-code symbol 1 has length 1
  pos += 4
  for _ in 0..<17 {
    wbits(encoded, pos, 0) // remaining code-length-code lengths are zero
    pos += 2
  }
  wbits(encoded, pos, 0) // decoded table payload: symbol 0
  pos += 1
  wbits(encoded, pos, 1) // decoded table payload: symbol 1
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let table = brotli_read_huffman_code(reader, 2, 2, 2)
  inspect(brotli_read_symbol(reader, table, 2), content="0")
  inspect(brotli_read_symbol(reader, table, 2), content="1")
}

///|
test "brotli_read_huffman_code rejects complex repeat overflow" {
  let encoded = FixedArray::make(8, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 0)
  pos += 2
  for _ in 0..<6 {
    wbits(encoded, pos, 0)
    pos += 2
  }
  wbits(encoded, pos, 7) // code-length-code symbol 17 has length 1
  pos += 4
  for _ in 0..<11 {
    wbits(encoded, pos, 0)
    pos += 2
  }
  wbits(encoded, pos, 7) // repeat-zero extra bits: 10 zeros for alphabet 4
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let result : Result[FixedArray[BrotliHuffmanCode], FzipError] = try? brotli_read_huffman_code(
    reader, 4, 4, 2,
  )
  guard result is Err(FzipError(code~, ..)) else {
    fail("expected complex repeat overflow error")
  }
  assert_eq(code, BrotliInvalidHuffman)
}

///|
test "brotli_decode_var_len_uint8 reads RFC encodings" {
  let encoded = FixedArray::make(4, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 0)
  pos += 1
  wbits(encoded, pos, 1)
  pos += 1
  wbits(encoded, pos, 0)
  pos += 3
  wbits(encoded, pos, 1)
  pos += 1
  wbits(encoded, pos, 3)
  pos += 3
  wbits(encoded, pos, 2)
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  inspect(brotli_decode_var_len_uint8(reader), content="0")
  inspect(brotli_decode_var_len_uint8(reader), content="1")
  inspect(brotli_decode_var_len_uint8(reader), content="10")
}

///|
test "brotli_read_block_type_count adds one to encoded value" {
  let reader = BrotliBitReader::new([0x00], 0, 1)
  inspect(brotli_read_block_type_count(reader), content="1")
}

///|
test "brotli_read_block_length decodes base plus extra bits" {
  let lengths = FixedArray::make(brotli_num_block_length_symbols, b'\x00')
  lengths[0] = b'\x01'
  let table = brotli_build_huffman_table(
    lengths, brotli_num_block_length_symbols, brotli_huffman_table_bits,
  )
  let reader = BrotliBitReader::new([0x02], 0, 1)
  inspect(brotli_read_block_length(reader, table), content="3")
}

///|
test "BrotliBlockTracker resolves block type ring codes" {
  let tracker = BrotliBlockTracker::new_with_length(3, brotli_block_size_cap)
  inspect(tracker.resolve_type_code(0), content="1")
  inspect(tracker.resolve_type_code(1), content="2")
  inspect(tracker.resolve_type_code(4), content="2")
  tracker.switch_with_code(2, 7)
  inspect(tracker.current_type, content="0")
  inspect(tracker.remaining, content="7")
}

///|
test "brotli_read_context_map returns implicit zero map" {
  let reader = BrotliBitReader::new([0x00], 0, 1)
  let context_map = brotli_read_context_map(reader, 4)
  inspect(context_map.num_trees, content="1")
  inspect(context_map.map[0].to_int(), content="0")
  inspect(context_map.map[3].to_int(), content="0")
}

///|
test "brotli_read_context_map decodes direct map values" {
  let encoded = FixedArray::make(8, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 1) // num_trees - 1 = 2
  pos += 1
  wbits(encoded, pos, 1)
  pos += 3
  wbits(encoded, pos, 0)
  pos += 1
  wbits(encoded, pos, 0) // no RLE prefix
  pos += 1
  wbits(encoded, pos, 1) // simple Huffman marker
  pos += 2
  wbits(encoded, pos, 2) // read 3 symbols: 0, 1, 2
  pos += 2
  wbits(encoded, pos, 0)
  pos += 2
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 2)
  pos += 2
  wbits(encoded, pos, 0)
  pos += 1
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 3)
  pos += 2
  wbits(encoded, pos, 0) // no IMTF
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let context_map = brotli_read_context_map(reader, 3)
  inspect(context_map.num_trees, content="3")
  inspect(context_map.map[0].to_int(), content="0")
  inspect(context_map.map[1].to_int(), content="1")
  inspect(context_map.map[2].to_int(), content="2")
}

///|
test "brotli_inverse_move_to_front transforms map in place" {
  let context_map : FixedArray[Byte] = [1, 0, 1]
  brotli_inverse_move_to_front(context_map)
  inspect(context_map[0].to_int(), content="1")
  inspect(context_map[1].to_int(), content="1")
  inspect(context_map[2].to_int(), content="0")
}

///|
test "brotli_read_context_map rejects RLE overflow" {
  let encoded = FixedArray::make(6, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 1) // num_trees - 1 = 1
  pos += 1
  wbits(encoded, pos, 0)
  pos += 3
  wbits(encoded, pos, 1) // use RLE prefix
  pos += 1
  wbits(encoded, pos, 0) // max_run_length_prefix = 1
  pos += 4
  wbits(encoded, pos, 1) // simple Huffman marker
  pos += 2
  wbits(encoded, pos, 0) // one symbol
  pos += 2
  wbits(encoded, pos, 1) // symbol 1, the run code
  pos += 2
  wbits(encoded, pos, 1) // reps = 3 for a 2-entry map
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let result : Result[BrotliContextMap, FzipError] = try? brotli_read_context_map(
    reader, 2,
  )
  guard result is Err(FzipError(code~, ..)) else {
    fail("expected context map repeat overflow")
  }
  assert_eq(code, BrotliInvalidContextMap)
}

///|
test "brotli_read_huffman_tree_group reads consecutive trees" {
  let encoded = FixedArray::make(8, b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 1) // tree 0: simple one-symbol tree
  pos += 2
  wbits(encoded, pos, 0)
  pos += 2
  wbits(encoded, pos, 2)
  pos += 2
  wbits(encoded, pos, 1) // tree 1: simple two-symbol tree
  pos += 2
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 0)
  pos += 2
  wbits(encoded, pos, 1)
  pos += 2
  wbits(encoded, pos, 0) // payload for tree 1 symbol 0
  pos += 1
  wbits(encoded, pos, 1) // payload for tree 1 symbol 1
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let group = brotli_read_huffman_tree_group(reader, 4, 4, 2, 3)
  inspect(group.trees.length(), content="2")
  inspect(brotli_read_symbol(reader, group.tree(0), 3), content="2")
  inspect(brotli_read_symbol(reader, group.tree(1), 3), content="0")
  inspect(brotli_read_symbol(reader, group.tree(1), 3), content="1")
}

///|
test "brotli_read_huffman_tree_group validates parameters" {
  let reader = BrotliBitReader::new([0x00], 0, 1)
  let empty : Result[BrotliHuffmanTreeGroup, FzipError] = try? brotli_read_huffman_tree_group(
    reader, 4, 4, 0, 3,
  )
  guard empty is Err(FzipError(code=empty_code, ..)) else {
    fail("expected empty tree group error")
  }
  assert_eq(empty_code, BrotliInvalidHuffman)

  let invalid_alphabet : Result[BrotliHuffmanTreeGroup, FzipError] = try? brotli_read_huffman_tree_group(
    reader, 2, 4, 1, 3,
  )
  guard invalid_alphabet is Err(FzipError(code=alphabet_code, ..)) else {
    fail("expected invalid alphabet error")
  }
  assert_eq(alphabet_code, BrotliInvalidHuffman)
}

///|
test "brotli_read_compressed_metablock_header reads trivial header" {
  let encoded = FixedArray::make(16, b'\x00')
  ignore(write_trivial_compressed_header(encoded, 0, 0))
  let reader = BrotliBitReader::new(encoded, 0, encoded.length())
  let header = brotli_read_compressed_metablock_header(reader)
  inspect(header.literal_block.num_types, content="1")
  inspect(header.command_block.num_types, content="1")
  inspect(header.distance_block.num_types, content="1")
  inspect(header.distance_postfix_bits, content="0")
  inspect(header.num_direct_distance_codes, content="0")
  inspect(header.context_modes[0].to_int(), content="0")
  inspect(header.literal_context_map.num_trees, content="1")
  inspect(header.distance_context_map.num_trees, content="1")
  inspect(header.literal_trees.trees.length(), content="1")
  inspect(header.command_trees.trees.length(), content="1")
  inspect(header.distance_trees.trees.length(), content="1")
  inspect(
    brotli_read_symbol(reader, header.literal_trees.tree(0), 8),
    content="65",
  )
  inspect(
    brotli_read_symbol(reader, header.command_trees.tree(0), 8),
    content="0",
  )
  inspect(
    brotli_read_symbol(reader, header.distance_trees.tree(0), 8),
    content="0",
  )
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
test "brotli_read_command applies insert and copy extra bits" {
  let lengths = FixedArray::make(brotli_num_command_symbols, b'\x00')
  lengths[48] = b'\x01'
  let command_tree = brotli_build_huffman_table(
    lengths, brotli_num_command_symbols, brotli_huffman_table_bits,
  )
  let reader = BrotliBitReader::new([0x01], 0, 1)
  let command = brotli_read_command(reader, command_tree)
  inspect(command.insert_length, content="7")
  inspect(command.copy_length, content="2")
  inspect(command.distance_code, content="0")
  inspect(command.distance_context, content="0")
}

///|
test "BrotliDistanceRing resolves initial implicit distance" {
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
test "compressed body switches literal blocks" {
  let literal_map = FixedArray::make(2 << brotli_literal_context_bits, b'\x00')
  for i in (1 << brotli_literal_context_bits)..<literal_map.length() {
    literal_map[i] = b'\x01'
  }
  let literal_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols))
  literal_trees.push(make_one_symbol_tree(66, brotli_num_literal_symbols))
  let command_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  command_trees.push(make_one_symbol_tree(16, brotli_num_command_symbols))
  let distance_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  distance_trees.push(
    make_one_symbol_tree(0, brotli_distance_alphabet_size(0, 0, 24)),
  )
  let header : BrotliCompressedMetablockHeader = {
    literal_block: {
      num_types: 2,
      type_tree: Some(make_one_symbol_tree(1, 4)),
      length_tree: Some(
        make_one_symbol_tree(0, brotli_num_block_length_symbols),
      ),
      first_length: 1,
    },
    command_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    distance_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    distance_postfix_bits: 0,
    num_direct_distance_codes: 0,
    context_modes: [0, 0],
    literal_context_map: { num_trees: 2, map: literal_map },
    distance_context_map: {
      num_trees: 1,
      map: FixedArray::make(1 << brotli_distance_context_bits, b'\x00'),
    },
    literal_trees: make_tree_group(brotli_num_literal_symbols, literal_trees),
    command_trees: make_tree_group(brotli_num_command_symbols, command_trees),
    distance_trees: make_tree_group(
      brotli_distance_alphabet_size(0, 0, 24),
      distance_trees,
    ),
  }
  let reader = BrotliBitReader::new([0x00, 0x00], 0, 2)
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  brotli_decode_compressed_metablock_body(
    reader,
    header,
    output,
    2,
    BrotliDecoderState::new_with_window_bits(24),
  )
  inspect(str_from_u8(output.finish()), content="AB")
}

///|
test "brotli literal context modes match reference categories" {
  inspect(brotli_literal_context_id(0, 65, 0), content="1")
  inspect(brotli_literal_context_id(1, 255, 0), content="63")
  inspect(brotli_literal_context_id(2, 65, 32), content="48")
  inspect(brotli_literal_context_id(2, 97, 65), content="58")
  inspect(brotli_literal_context_id(2, 117, 221), content="56")
  inspect(brotli_literal_context_id(2, 117, 224), content="58")
  inspect(brotli_literal_context_id(2, 127, 0), content="0")
  inspect(brotli_literal_context_id(2, 127, 65), content="2")
  inspect(brotli_literal_context_id(2, 65, 127), content="48")
  inspect(brotli_literal_context_id(3, 255, 128), content="60")
}

///|
test "compressed body selects literal tree by LSB context" {
  let literal_map = FixedArray::make(1 << brotli_literal_context_bits, b'\x00')
  literal_map[1] = b'\x01'
  let literal_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols))
  literal_trees.push(make_one_symbol_tree(66, brotli_num_literal_symbols))
  let command_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  command_trees.push(make_one_symbol_tree(16, brotli_num_command_symbols))
  let distance_trees : Array[FixedArray[BrotliHuffmanCode]] = []
  distance_trees.push(
    make_one_symbol_tree(0, brotli_distance_alphabet_size(0, 0, 24)),
  )
  let header : BrotliCompressedMetablockHeader = {
    literal_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    command_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    distance_block: {
      num_types: 1,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    },
    distance_postfix_bits: 0,
    num_direct_distance_codes: 0,
    context_modes: [0],
    literal_context_map: { num_trees: 2, map: literal_map },
    distance_context_map: {
      num_trees: 1,
      map: FixedArray::make(1 << brotli_distance_context_bits, b'\x00'),
    },
    literal_trees: make_tree_group(brotli_num_literal_symbols, literal_trees),
    command_trees: make_tree_group(brotli_num_command_symbols, command_trees),
    distance_trees: make_tree_group(
      brotli_distance_alphabet_size(0, 0, 24),
      distance_trees,
    ),
  }
  let reader = BrotliBitReader::new([0x00, 0x00], 0, 2)
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  brotli_decode_compressed_metablock_body(
    reader,
    header,
    output,
    2,
    BrotliDecoderState::new_with_window_bits(24),
  )
  inspect(str_from_u8(output.finish()), content="AB")
}

///|
test "compressed body preserves distance ring in decoder state" {
  let state = BrotliDecoderState::new_with_window_bits(24)
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  let first_reader = BrotliBitReader::new([0x01], 0, 1)
  brotli_decode_compressed_metablock_body(
    first_reader,
    make_single_block_body_header(144, 16),
    output,
    4,
    state,
  )
  inspect(str_from_u8(output.finish()), content="AAAA")

  let second_reader = BrotliBitReader::new([0x00], 0, 1)
  brotli_decode_compressed_metablock_body(
    second_reader,
    make_single_block_body_header(0, 0),
    output,
    2,
    state,
  )
  inspect(str_from_u8(output.finish()), content="AAAAAA")
}

///|
test "BrotliOutputBuilder copies identity dictionary word" {
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  output.copy_from_dictionary_after_max_distance(1, 4, 0)
  inspect(str_from_u8(output.finish()), content="time")
}

///|
test "BrotliOutputBuilder applies dictionary uppercase transform" {
  inspect(brotli_transform_count(), content="121")
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  output.copy_from_dictionary_after_max_distance(4097, 4, 0)
  inspect(str_from_u8(output.finish()), content="Time ")
}

///|
test "BrotliDecoderState caps backward distance by window gap" {
  let state = BrotliDecoderState::new_with_window_bits(10)
  inspect(state.max_distance(20), content="20")
  inspect(state.max_distance(2000), content="1008")
}

///|
test "BrotliOutputBuilder dictionary address uses capped max distance" {
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  output.ensure(1100)
  output.len = 1100
  output.copy_from_dictionary_after_max_distance(1009, 4, 1008)
  assert_eq(output.buf[1100], b't')
  assert_eq(output.buf[1101], b'i')
  assert_eq(output.buf[1102], b'm')
  assert_eq(output.buf[1103], b'e')
}

///|
test "compressed body decodes identity dictionary reference" {
  let state = BrotliDecoderState::new_with_window_bits(24)
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  let reader = BrotliBitReader::new([0x00], 0, 1)
  brotli_decode_compressed_metablock_body(
    reader,
    make_single_block_body_header(130, 16),
    output,
    4,
    state,
  )
  inspect(str_from_u8(output.finish()), content="time")
}

///|
test "brotli_build_huffman_table rejects malformed length sets" {
  let empty : FixedArray[Byte] = [0, 0, 0, 0]
  let empty_result : Result[FixedArray[BrotliHuffmanCode], FzipError] = try? brotli_build_huffman_table(
    empty, 4, 3,
  )
  guard empty_result is Err(FzipError(code=empty_code, ..)) else {
    fail("expected empty Huffman error")
  }
  assert_eq(empty_code, BrotliInvalidHuffman)

  let over : FixedArray[Byte] = [1, 1, 1]
  let over_result : Result[FixedArray[BrotliHuffmanCode], FzipError] = try? brotli_build_huffman_table(
    over, 3, 3,
  )
  guard over_result is Err(FzipError(code=over_code, ..)) else {
    fail("expected over-subscribed Huffman error")
  }
  assert_eq(over_code, BrotliInvalidHuffman)

  let under : FixedArray[Byte] = [2, 2, 0, 0]
  let under_result : Result[FixedArray[BrotliHuffmanCode], FzipError] = try? brotli_build_huffman_table(
    under, 4, 3,
  )
  guard under_result is Err(FzipError(code=under_code, ..)) else {
    fail("expected under-subscribed Huffman error")
  }
  assert_eq(under_code, BrotliInvalidHuffman)
}

///|
test "unbrotli_sync decodes empty Brotli stream" {
  let compressed : FixedArray[Byte] = [0xa1, 0x01]
  let decoded = unbrotli_sync(compressed)
  assert_eq(decoded.length(), 0)
}

///|
test "unbrotli_sync decodes q0 uncompressed Brotli stream from CLI" {
  let compressed : FixedArray[Byte] = [
    0x03, 0x05, 0x80, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x77, 0x6f, 0x72, 0x6c,
    0x64, 0x03,
  ]
  let decoded = unbrotli_sync(compressed)
  inspect(str_from_u8(decoded), content="hello world")
}

///|
test "brotli_sync q0 encodes empty stream" {
  let input : FixedArray[Byte] = []
  let compressed = brotli_sync(input, opts={ quality: 0, window_bits: 16 })
  let decoded = unbrotli_sync(compressed)
  assert_eq(decoded.length(), 0)
}

///|
test "brotli_sync q0 round-trips uncompressed meta-block" {
  let input : FixedArray[Byte] = [1, 2, 3, 4, 5, 0, 255]
  let compressed = brotli_sync(input, opts={ quality: 0, window_bits: 16 })
  let decoded = unbrotli_sync(compressed)
  assert_eq(decoded.length(), input.length())
  for i in 0..<input.length() {
    assert_eq(decoded[i], input[i])
  }
}

///|
test "brotli_sync supports all standard window bits" {
  let input : FixedArray[Byte] = [42]
  for window_bits in 10..<=24 {
    let compressed = brotli_sync(input, opts={ quality: 0, window_bits })
    let decoded = unbrotli_sync(compressed)
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
  let compressed = brotli_sync(input, opts={ quality: 1, window_bits: 22 })
  let decoded = unbrotli_sync(compressed)
  assert_eq(decoded.length(), input.length())
  assert_eq(decoded[0], input[0])
  assert_eq(
    decoded[brotli_max_metablock_bytes],
    input[brotli_max_metablock_bytes],
  )
  assert_eq(decoded[input.length() - 1], input[input.length() - 1])
}

///|
test "brotli_sync rejects unsupported quality phases" {
  let input : FixedArray[Byte] = [1]
  let p3 : Result[FixedArray[Byte], FzipError] = try? brotli_sync(input, opts={
    quality: 2,
    window_bits: 22,
  })
  assert_brotli_error(p3, InvalidZipData)
  let p4 : Result[FixedArray[Byte], FzipError] = try? brotli_sync(input, opts={
    quality: 10,
    window_bits: 22,
  })
  assert_brotli_error(p4, InvalidZipData)
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
test "unbrotli_sync rejects invalid compressed back-reference distance" {
  let compressed = FixedArray::make(12, b'\x00')
  let pos = write_window10_final_metablock_header(compressed, 2)
  ignore(write_trivial_compressed_header(compressed, pos, 0))
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliInvalidDistance)
}

///|
test "unbrotli_sync decodes literal-only compressed meta-block" {
  let compressed = FixedArray::make(12, b'\x00')
  let pos = write_window10_final_metablock_header(compressed, 2)
  ignore(write_trivial_compressed_header(compressed, pos, 16))
  let decoded = unbrotli_sync(compressed)
  inspect(str_from_u8(decoded), content="AA")
}

///|
test "unbrotli_sync decodes compressed implicit-distance copy" {
  let compressed = FixedArray::make(12, b'\x00')
  let pos = write_window10_final_metablock_header(compressed, 6)
  ignore(write_trivial_compressed_header(compressed, pos, 32))
  let decoded = unbrotli_sync(compressed)
  inspect(str_from_u8(decoded), content="AAAAAA")
}

///|
test "unbrotli_sync decodes compressed explicit-distance copy" {
  let compressed = FixedArray::make(12, b'\x00')
  let pos = write_window10_final_metablock_header(compressed, 6)
  let pos = write_trivial_compressed_header(
    compressed,
    pos,
    160,
    distance_symbol=17,
  )
  wbits(compressed, pos, 1) // distance code 17, extra bit 1 => distance 4
  let decoded = unbrotli_sync(compressed)
  inspect(str_from_u8(decoded), content="AAAAAA")
}

///|
test "unbrotli_sync rejects non-zero final padding" {
  let compressed : FixedArray[Byte] = [0xa1, 0x03]
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliInvalidPadding)
}

///|
test "unbrotli_sync rejects large-window header path" {
  let compressed : FixedArray[Byte] = [0x11]
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliLargeWindowNotSupported)
}

///|
test "unbrotli_sync rejects trailing nonzero data after final meta-block" {
  let compressed = append_byte(brotli_fixture_quickfox_compressed, b'\x01')
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliInvalidPadding)
}

///|
test "unbrotli_sync rejects uncompressed output bomb before allocation" {
  let compressed = make_uncompressed_bomb_header()
  let result = try? unbrotli_sync(compressed, opts={
    out: None,
    max_output_size: (1 << 16) - 1,
    max_input_size: default_max_input_size,
  })
  assert_brotli_error(result, InvalidZipData)
}

///|
test "unbrotli_sync rejects truncated embedded fixture prefixes" {
  assert_truncated_prefixes_raise_unexpected_eof(
    brotli_fixture_empty_compressed,
  )
  assert_truncated_prefixes_raise_unexpected_eof(
    brotli_fixture_10x10y_compressed,
  )
  assert_truncated_prefixes_raise_unexpected_eof(brotli_fixture_64x_compressed)
  assert_truncated_prefixes_raise_unexpected_eof(
    brotli_fixture_quickfox_compressed,
  )
  assert_truncated_prefixes_raise_unexpected_eof(
    brotli_fixture_ukkonooa_compressed,
  )
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

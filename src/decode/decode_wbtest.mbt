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
) -> FixedArray[Int] raise FbrError {
  let lengths = FixedArray::make(alphabet_size, b'\x00')
  lengths[symbol] = b'\x01'
  brotli_build_huffman_table(lengths, alphabet_size, brotli_huffman_table_bits)
}

///|
fn make_tree_group(
  alphabet_size : Int,
  trees : Array[FixedArray[Int]],
) -> BrotliHuffmanTreeGroup {
  ignore(alphabet_size)
  { trees, }
}

///|
fn make_single_block_body_header(
  command_symbol : Int,
  distance_symbol : Int,
) -> BrotliCompressedMetablockHeader raise FbrError {
  let literal_trees : Array[FixedArray[Int]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols))
  let command_trees : Array[FixedArray[Int]] = []
  command_trees.push(
    make_one_symbol_tree(command_symbol, brotli_num_command_symbols),
  )
  let distance_trees : Array[FixedArray[Int]] = []
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
test "BrotliBitReader reads and aligns LSB-first bits" {
  let reader = BrotliBitReader::new([0xa1, 0x01], 0, 2)
  inspect(reader.take_bits(1), content="1")
  inspect(reader.take_bits(3), content="0")
  inspect(reader.take_bits(3), content="2")
  inspect(reader.byte_pos * 8 - reader.bits_avail, content="7")
  inspect(reader.take_bits(1), content="1")
  inspect(reader.take_bits(1), content="1")
  reader.expect_final_padding_zero()
}

///|
test "BrotliBitReader zero-width read does not prefetch" {
  let reader = BrotliBitReader::new([0x01, 0x02, 0x03, 0x04], 0, 4)
  inspect(reader.take_bits(0), content="0")
  inspect(reader.byte_pos, content="0")
  inspect(reader.bits_avail, content="0")
}

///|
test "BrotliBitReader align_to_byte rejects non-zero padding" {
  let reader = BrotliBitReader::new([0x09], 0, 1)
  inspect(reader.take_bits(1), content="1")
  let result : Result[Unit, FbrError] = try? reader.align_to_byte()
  guard result is Err(FbrError(code~, ..)) else {
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
  inspect(reader.byte_pos * 8 - reader.bits_avail, content="0")
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
  let duplicate_result : Result[FixedArray[Int], FbrError] = try? brotli_read_huffman_code(
    duplicate_reader, 4, 4, 3,
  )
  guard duplicate_result is Err(FbrError(code=duplicate_code, ..)) else {
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
  let out_of_range_result : Result[FixedArray[Int], FbrError] = try? brotli_read_huffman_code(
    out_of_range_reader, 4, 3, 3,
  )
  guard out_of_range_result is Err(FbrError(code=range_code, ..)) else {
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
  let result : Result[FixedArray[Int], FbrError] = try? brotli_read_huffman_code(
    reader, 4, 4, 2,
  )
  guard result is Err(FbrError(code~, ..)) else {
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
test "brotli_context_map_tree_index rejects invalid mapped tree" {
  let context_map = BrotliContextMap::{ num_trees: 1, map: [1, 0, 0, 0] }
  let result : Result[Int, FbrError] = try? brotli_context_map_tree_index(
    context_map, 0, brotli_distance_context_bits, 0,
  )
  guard result is Err(FbrError(code~, ..)) else {
    fail("expected invalid context-map tree")
  }
  assert_eq(code, BrotliInvalidContextMap)
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
  let result : Result[BrotliContextMap, FbrError] = try? brotli_read_context_map(
    reader, 2,
  )
  guard result is Err(FbrError(code~, ..)) else {
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
  let empty : Result[BrotliHuffmanTreeGroup, FbrError] = try? brotli_read_huffman_tree_group(
    reader, 4, 4, 0, 3,
  )
  guard empty is Err(FbrError(code=empty_code, ..)) else {
    fail("expected empty tree group error")
  }
  assert_eq(empty_code, BrotliInvalidHuffman)

  let invalid_alphabet : Result[BrotliHuffmanTreeGroup, FbrError] = try? brotli_read_huffman_tree_group(
    reader, 2, 4, 1, 3,
  )
  guard invalid_alphabet is Err(FbrError(code=alphabet_code, ..)) else {
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
test "brotli_command_info_table matches checked helper cases" {
  for symbol in [0, 48, 64, 128] {
    let checked = brotli_command_info(symbol)
    let direct = @common.brotli_command_info_table[symbol]
    assert_eq(direct.insert_len_extra_bits, checked.insert_len_extra_bits)
    assert_eq(direct.copy_len_extra_bits, checked.copy_len_extra_bits)
    assert_eq(direct.distance_code, checked.distance_code)
    assert_eq(direct.distance_context, checked.distance_context)
    assert_eq(direct.insert_len_offset, checked.insert_len_offset)
    assert_eq(direct.copy_len_offset, checked.copy_len_offset)
  }
}

///|
/// Test helper: decode a single command into a fresh record. The decode loop
/// itself reuses one `BrotliCommand` via `read_into`, but tests find a
/// value-returning wrapper more convenient.
fn brotli_read_command(
  reader : BrotliBitReader,
  command_tree : FixedArray[Int],
) -> BrotliCommand raise @common.FbrError {
  let command = BrotliCommand::{
    insert_length: 0,
    copy_length: 0,
    distance_code: 0,
    distance_context: 0,
  }
  command.read_into(reader, command_tree)
  command
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
test "brotli_read_command skips zero-width extra bits" {
  let command_tree = make_one_symbol_tree(0, brotli_num_command_symbols)
  let reader = BrotliBitReader::new([], 0, 0)
  let command = brotli_read_command(reader, command_tree)
  inspect(command.insert_length, content="0")
  inspect(command.copy_length, content="2")
  inspect(reader.byte_pos * 8 - reader.bits_avail, content="0")
}

///|
test "BrotliCommand::read_into overwrites every field when a record is reused" {
  // The meta-block loop reuses one command record across all commands, filling
  // it via `read_into`. A stale field surviving from a previous command would
  // silently corrupt the stream, so verify a second read fully replaces the
  // first. Eight zero bytes give the insert/copy extra-bit reads enough room to
  // resolve to 0, so each length equals its base offset from the info table.
  let command = BrotliCommand::{
    insert_length: -99,
    copy_length: -99,
    distance_code: -99,
    distance_context: -99,
  }
  // Symbol 64 selects an implicit (last-distance) command with context 3.
  let tree_a = make_one_symbol_tree(64, brotli_num_command_symbols)
  let info_a = brotli_command_info(64)
  command.read_into(
    BrotliBitReader::new([0, 0, 0, 0, 0, 0, 0, 0], 0, 8),
    tree_a,
  )
  assert_eq(command.insert_length, info_a.insert_len_offset)
  assert_eq(command.copy_length, info_a.copy_len_offset)
  assert_eq(command.distance_code, info_a.distance_code)
  assert_eq(command.distance_context, info_a.distance_context)
  // Symbol 128 selects an explicit distance (distance_code -1). Reading it into
  // the same record must overwrite the previous distance_code and context.
  let tree_b = make_one_symbol_tree(128, brotli_num_command_symbols)
  let info_b = brotli_command_info(128)
  command.read_into(
    BrotliBitReader::new([0, 0, 0, 0, 0, 0, 0, 0], 0, 8),
    tree_b,
  )
  assert_eq(command.distance_code, -1)
  assert_eq(command.distance_code, info_b.distance_code)
  assert_eq(command.distance_context, info_b.distance_context)
  assert_eq(command.insert_length, info_b.insert_len_offset)
  assert_eq(command.copy_length, info_b.copy_len_offset)
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
test "validated short-distance helper matches checked ring lookup" {
  let checked = BrotliDistanceRing::new()
  let validated = BrotliDistanceRing::new()
  inspect(checked.take_short_code(0), content="4")
  inspect(brotli_take_short_code_validated(validated, 0), content="4")
  checked.record(7)
  validated.record(7)
  inspect(checked.take_short_code(4), content="6")
  inspect(brotli_take_short_code_validated(validated, 4), content="6")
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
test "brotli_read_distance decodes direct and postfix explicit distances" {
  let direct_tree = make_one_symbol_tree(
    17,
    brotli_distance_alphabet_size(0, 4, 24),
  )
  inspect(
    brotli_read_distance(
      BrotliBitReader::new([], 0, 0),
      direct_tree,
      BrotliDistanceRing::new(),
      0,
      4,
    ),
    content="2",
  )
  let postfix_tree = make_one_symbol_tree(
    20,
    brotli_distance_alphabet_size(1, 4, 24),
  )
  inspect(
    brotli_read_distance(
      BrotliBitReader::new([0x01], 0, 1),
      postfix_tree,
      BrotliDistanceRing::new(),
      1,
      4,
    ),
    content="7",
  )
}

///|
test "compressed body switches literal blocks" {
  let literal_map = FixedArray::make(2 << brotli_literal_context_bits, b'\x00')
  for i in (1 << brotli_literal_context_bits)..<literal_map.length() {
    literal_map[i] = b'\x01'
  }
  let literal_trees : Array[FixedArray[Int]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols))
  literal_trees.push(make_one_symbol_tree(66, brotli_num_literal_symbols))
  let command_trees : Array[FixedArray[Int]] = []
  command_trees.push(make_one_symbol_tree(16, brotli_num_command_symbols))
  let distance_trees : Array[FixedArray[Int]] = []
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
  let literal_trees : Array[FixedArray[Int]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols))
  literal_trees.push(make_one_symbol_tree(66, brotli_num_literal_symbols))
  let command_trees : Array[FixedArray[Int]] = []
  command_trees.push(make_one_symbol_tree(16, brotli_num_command_symbols))
  let distance_trees : Array[FixedArray[Int]] = []
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
test "compressed body rejects command lengths past meta-block boundary" {
  let insert_result : Result[Unit, FbrError] = try? brotli_decode_compressed_metablock_body(
    BrotliBitReader::new([0x00], 0, 1),
    make_single_block_body_header(24, 0),
    BrotliOutputBuilder::new(UnbrotliOptions::default()),
    2,
    BrotliDecoderState::new_with_window_bits(24),
  )
  guard insert_result is Err(FbrError(code=insert_code, ..)) else {
    fail("expected insert length overflow")
  }
  assert_eq(insert_code, BrotliInvalidMetablock)
}

///|
test "brotli_initial_output_capacity uses compressed-size hint" {
  inspect(brotli_initial_output_capacity(1024, 1000), content="1024")
  inspect(brotli_initial_output_capacity(100000000, 1000), content="5000")
  inspect(brotli_initial_output_capacity(100000000, 1000000), content="5000000")
}

///|
test "BrotliOutputBuilder copy_from_distance keeps overlap semantics" {
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  output.ensure(8)
  for i in 0..<8 {
    output.buf[i] = (65 + i).to_byte()
  }
  output.len = 8
  output.copy_from_distance(8, 4)
  inspect(str_from_u8(trim_buf(output.buf, output.len)), content="ABCDEFGHABCD")
  output.copy_from_distance(1, 3)
  inspect(
    str_from_u8(trim_buf(output.buf, output.len)),
    content="ABCDEFGHABCDDDD",
  )
  output.copy_from_distance(4, 8)
  inspect(
    str_from_u8(trim_buf(output.buf, output.len)),
    content="ABCDEFGHABCDDDDDDDDDDDD",
  )
}

///|
test "unbrotli_sync rejects non-zero final padding" {
  let compressed : FixedArray[Byte] = [0xa1, 0x03]
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliInvalidPadding)
}

///|
test "unbrotli_sync returns caller buffer slice for empty output" {
  let out = FixedArray::make(8, b'x')
  let decoded = unbrotli_sync([0xa1, 0x01], opts={
    out: Some(out),
    max_output_size: default_max_output_size,
    max_input_size: default_max_input_size,
  })
  assert_eq(decoded.length(), 0)
}

///|
test "unbrotli_sync rejects large-window header path" {
  let compressed : FixedArray[Byte] = [0x11]
  let result = try? unbrotli_sync(compressed)
  assert_brotli_error(result, BrotliLargeWindowNotSupported)
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
test "UnbrotliStream buffers chunks until final push" {
  let stream = UnbrotliStream::new()
  let output : Array[FixedArray[Byte]] = []
  let finals : Array[Bool] = []
  stream.ondata = Some(
    FbrStreamHandler((data, final_) => {
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

///|
fn make_window10_metadata_stream(
  metadata : FixedArray[Byte],
) -> FixedArray[Byte] {
  let encoded = FixedArray::make(16 + metadata.length(), b'\x00')
  let mut pos = 0
  wbits(encoded, pos, 1) // WBITS: standard 10-bit window
  pos += 1
  wbits(encoded, pos, 0)
  pos += 3
  wbits(encoded, pos, 2)
  pos += 3
  wbits(encoded, pos, 0) // non-final metadata meta-block
  pos += 1
  wbits(encoded, pos, 3) // MNIBBLES = metadata
  pos += 2
  wbits(encoded, pos, 0) // reserved bit
  pos += 1
  if metadata.length() == 0 {
    wbits(encoded, pos, 0) // size_bytes = 0
    pos += 2
  } else {
    wbits(encoded, pos, 1) // one metadata length byte
    pos += 2
    wbits(encoded, pos, metadata.length() - 1)
    pos += 8
  }
  let bit_remainder = pos & 7
  if bit_remainder != 0 {
    pos += 8 - bit_remainder
  }
  for i in 0..<metadata.length() {
    encoded[pos / 8 + i] = metadata[i]
  }
  pos += metadata.length() * 8
  wbits(encoded, pos, 1) // final empty meta-block
  pos += 1
  wbits(encoded, pos, 1)
  @common.trim_buf(encoded, (pos + 7) / 8)
}

///|
test "unbrotli_sync skips zero and non-empty metadata meta-blocks" {
  let empty_metadata = unbrotli_sync(make_window10_metadata_stream([]))
  assert_eq(empty_metadata.length(), 0)

  let metadata : FixedArray[Byte] = [b'a', b'b', b'c']
  let non_empty_metadata = unbrotli_sync(
    make_window10_metadata_stream(metadata),
  )
  assert_eq(non_empty_metadata.length(), 0)
}

///|
test "brotli metadata header rejects reserved and exuberant lengths" {
  let reserved = FixedArray::make(2, b'\x00')
  let mut pos = 0
  wbits(reserved, pos, 0)
  pos += 1
  wbits(reserved, pos, 3)
  pos += 2
  wbits(reserved, pos, 1)
  let reserved_result : Result[BrotliMetablockHeader, FbrError] = try? brotli_decode_metablock_header(
    BrotliBitReader::new(reserved, 0, reserved.length()),
  )
  guard reserved_result is Err(FbrError(code=reserved_code, ..)) else {
    fail("expected reserved metadata bit error")
  }
  assert_eq(reserved_code, BrotliReserved)

  let exuberant = FixedArray::make(4, b'\x00')
  pos = 0
  wbits(exuberant, pos, 0)
  pos += 1
  wbits(exuberant, pos, 3)
  pos += 2
  wbits(exuberant, pos, 0)
  pos += 1
  wbits(exuberant, pos, 2)
  pos += 2
  wbits(exuberant, pos, 1)
  pos += 8
  wbits(exuberant, pos, 0)
  let exuberant_result : Result[BrotliMetablockHeader, FbrError] = try? brotli_decode_metablock_header(
    BrotliBitReader::new(exuberant, 0, exuberant.length()),
  )
  guard exuberant_result is Err(FbrError(code=exuberant_code, ..)) else {
    fail("expected exuberant metadata length error")
  }
  assert_eq(exuberant_code, BrotliInvalidMetablock)
}

///|
test "brotli meta-block header handles six-nibble and exuberant lengths" {
  let exuberant = FixedArray::make(4, b'\x00')
  let mut pos = 0
  wbits(exuberant, pos, 0)
  pos += 1
  wbits(exuberant, pos, 1) // six length nibbles
  pos += 2
  for _ in 0..<4 {
    wbits(exuberant, pos, 1)
    pos += 4
  }
  wbits(exuberant, pos, 0)
  let exuberant_result : Result[BrotliMetablockHeader, FbrError] = try? brotli_decode_metablock_header(
    BrotliBitReader::new(exuberant, 0, exuberant.length()),
  )
  guard exuberant_result is Err(FbrError(code=exuberant_code, ..)) else {
    fail("expected exuberant meta-block length error")
  }
  assert_eq(exuberant_code, BrotliInvalidMetablock)

  let max_length = FixedArray::make(4, b'\x00')
  pos = 0
  wbits(max_length, pos, 0)
  pos += 1
  wbits(max_length, pos, 2) // six length nibbles
  pos += 2
  for _ in 0..<6 {
    wbits(max_length, pos, 0xf)
    pos += 4
  }
  let max_header = brotli_decode_metablock_header(
    BrotliBitReader::new(max_length, 0, max_length.length()),
  )
  assert_eq(max_header.length, @common.brotli_max_metablock_bytes)
}

///|
test "BrotliOutputBuilder covers fixed buffer, growth, and error paths" {
  let invalid_window : Result[Unit, FbrError] = try? brotli_validate_window_bits(
    9,
  )
  guard invalid_window is Err(FbrError(code=window_code, ..)) else {
    fail("expected invalid window bits")
  }
  assert_eq(window_code, BrotliInvalidWindowBits)

  inspect(brotli_initial_output_capacity(0, 100), content="0")
  inspect(
    brotli_initial_output_capacity(@common.max_int_val(), @common.max_int_val()),
    content="\{@common.max_int_val()}",
  )

  let fixed = BrotliOutputBuilder::new({
    out: Some(FixedArray::make(1, b'\x00')),
    max_output_size: 8,
    max_input_size: default_max_input_size,
  })
  let fixed_result : Result[Unit, FbrError] = try? fixed.ensure(2)
  guard fixed_result is Err(FbrError(code=fixed_code, ..)) else {
    fail("expected fixed output buffer error")
  }
  assert_eq(fixed_code, InvalidZipData)

  let grown = BrotliOutputBuilder::{
    buf: FixedArray::make(0, b'\x00'),
    len: 0,
    fixed: false,
    max_output_size: 3,
  }
  grown.ensure(3)
  assert_eq(grown.buf.length(), 3)

  let negative_ensure : Result[Unit, FbrError] = try? grown.ensure(-1)
  guard negative_ensure is Err(FbrError(code=ensure_code, ..)) else {
    fail("expected negative ensure error")
  }
  assert_eq(ensure_code, BrotliInvalidMetablock)

  let negative_copy : Result[Unit, FbrError] = try? grown.copy_from_distance(
    1, -1,
  )
  guard negative_copy is Err(FbrError(code=copy_code, ..)) else {
    fail("expected negative copy error")
  }
  assert_eq(copy_code, BrotliInvalidMetablock)

  let invalid_distance : Result[Unit, FbrError] = try? grown.copy_from_distance(
    0, 1,
  )
  guard invalid_distance is Err(FbrError(code=distance_code, ..)) else {
    fail("expected invalid distance error")
  }
  assert_eq(distance_code, BrotliInvalidDistance)

  grown.buf[0] = b'Z'
  grown.len = 1
  grown.copy_from_distance(1, 0)
  assert_eq(grown.len, 1)
}

///|
test "BrotliBitReader rejects malformed bit and byte reads" {
  let empty_reader = BrotliBitReader::new([], 0, 0)
  let eof_bits : Result[UInt, FbrError] = try? empty_reader.take_bits(1)
  guard eof_bits is Err(FbrError(code=eof_bits_code, ..)) else {
    fail("expected bit EOF")
  }
  assert_eq(eof_bits_code, UnexpectedEOF)

  let width_reader = BrotliBitReader::new([0], 0, 1)
  let bad_width : Result[UInt, FbrError] = try? width_reader.peek_bits(25)
  guard bad_width is Err(FbrError(code=width_code, ..)) else {
    fail("expected invalid bit width")
  }
  assert_eq(width_code, BrotliInvalidMetablock)

  let drop_reader = BrotliBitReader::new([0], 0, 1)
  let bad_drop : Result[Unit, FbrError] = try? drop_reader.drop_bits(1)
  guard bad_drop is Err(FbrError(code=drop_code, ..)) else {
    fail("expected invalid bit drop")
  }
  assert_eq(drop_code, BrotliInvalidMetablock)

  let out = FixedArray::make(1, b'\x00')
  let bad_offset : Result[Unit, FbrError] = try? BrotliBitReader::new([0], 0, 1).take_bytes(
    out, 1, 1,
  )
  guard bad_offset is Err(FbrError(code=offset_code, ..)) else {
    fail("expected output buffer error")
  }
  assert_eq(offset_code, InvalidZipData)

  let eof_bytes : Result[Unit, FbrError] = try? BrotliBitReader::new([0], 0, 1).take_bytes(
    FixedArray::make(2, b'\x00'),
    0,
    2,
  )
  guard eof_bytes is Err(FbrError(code=eof_bytes_code, ..)) else {
    fail("expected byte EOF")
  }
  assert_eq(eof_bytes_code, UnexpectedEOF)
}

///|
test "BrotliBlockTracker rejects invalid block switch state" {
  let invalid_types : Result[BrotliBlockTracker, FbrError] = try? BrotliBlockTracker::new_with_length(
    0, 1,
  )
  guard invalid_types is Err(FbrError(code=type_count_code, ..)) else {
    fail("expected invalid block type count")
  }
  assert_eq(type_count_code, BrotliInvalidMetablock)

  let invalid_length : Result[BrotliBlockTracker, FbrError] = try? BrotliBlockTracker::new_with_length(
    1, 0,
  )
  guard invalid_length is Err(FbrError(code=length_code, ..)) else {
    fail("expected invalid initial block length")
  }
  assert_eq(length_code, BrotliInvalidMetablock)

  let tracker = BrotliBlockTracker::new_with_length(2, 1)
  let switch_result : Result[Unit, FbrError] = try? tracker.switch_with_code(
    0, 0,
  )
  guard switch_result is Err(FbrError(code=switch_code, ..)) else {
    fail("expected invalid switch length")
  }
  assert_eq(switch_code, BrotliInvalidMetablock)

  let missing_header : BrotliBlockSwitchHeader = {
    num_types: 2,
    type_tree: None,
    length_tree: None,
    first_length: 1,
  }
  tracker.remaining = 0
  let missing_tree : Result[Unit, FbrError] = try? tracker.ensure_ready(
    BrotliBitReader::new([], 0, 0),
    missing_header,
  )
  guard missing_tree is Err(FbrError(code=missing_code, ..)) else {
    fail("expected missing block tree")
  }
  assert_eq(missing_code, BrotliInvalidMetablock)
}

///|
test "brotli_read_symbol rejects EOF and uninitialized table entries" {
  let one_bit_table : FixedArray[Int] = [
    @common.brotli_huffman_code(1, 0),
    @common.brotli_huffman_code(1, 1),
  ]
  let eof_result : Result[Int, FbrError] = try? brotli_read_symbol(
    BrotliBitReader::new([], 0, 0),
    one_bit_table,
    1,
  )
  guard eof_result is Err(FbrError(code=eof_code, ..)) else {
    fail("expected Huffman EOF")
  }
  assert_eq(eof_code, UnexpectedEOF)

  let root_empty : FixedArray[Int] = [
    @common.brotli_huffman_code_empty,
    @common.brotli_huffman_code(1, 1),
  ]
  let root_result : Result[Int, FbrError] = try? brotli_read_symbol(
    BrotliBitReader::new([0], 0, 1),
    root_empty,
    1,
  )
  guard root_result is Err(FbrError(code=root_code, ..)) else {
    fail("expected uninitialized root Huffman entry")
  }
  assert_eq(root_code, BrotliInvalidHuffman)

  let sub_empty : FixedArray[Int] = [
    @common.brotli_huffman_code(2, 2),
    @common.brotli_huffman_code(1, 1),
    @common.brotli_huffman_code_empty,
    @common.brotli_huffman_code(1, 2),
  ]
  let sub_result : Result[Int, FbrError] = try? brotli_read_symbol(
    BrotliBitReader::new([0], 0, 1),
    sub_empty,
    1,
  )
  guard sub_result is Err(FbrError(code=sub_code, ..)) else {
    fail("expected uninitialized sub-table Huffman entry")
  }
  assert_eq(sub_code, BrotliInvalidHuffman)
}

///|
test "complex Huffman code-length decoding rejects invalid spaces and repeats" {
  let invalid_space : Result[FixedArray[Byte], FbrError] = try? brotli_read_code_length_code_lengths(
    BrotliBitReader::new(FixedArray::make(8, b'\x00'), 0, 8),
    0,
  )
  guard invalid_space is Err(FbrError(code=space_code, ..)) else {
    fail("expected invalid code-length-code space")
  }
  assert_eq(space_code, BrotliInvalidHuffman)

  let zero_length_table = make_one_symbol_tree(
    0, @common.brotli_num_code_length_codes,
  )
  let under : Result[FixedArray[Byte], FbrError] = try? brotli_decode_symbol_code_lengths(
    BrotliBitReader::new([], 0, 0),
    zero_length_table,
    2,
  )
  guard under is Err(FbrError(code=under_code, ..)) else {
    fail("expected under-subscribed symbol lengths")
  }
  assert_eq(under_code, BrotliInvalidHuffman)

  let repeat_previous_table = make_one_symbol_tree(
    @common.brotli_repeat_previous_code_length, @common.brotli_num_code_length_codes,
  )
  let repeat_overflow : Result[FixedArray[Byte], FbrError] = try? brotli_decode_symbol_code_lengths(
    BrotliBitReader::new([0], 0, 1),
    repeat_previous_table,
    2,
  )
  guard repeat_overflow is Err(FbrError(code=repeat_code, ..)) else {
    fail("expected repeat overflow")
  }
  assert_eq(repeat_code, BrotliInvalidHuffman)
}

///|
test "dictionary copy rejects invalid distance and transform boundaries" {
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  let bad_length : Result[Unit, FbrError] = try? output.copy_from_dictionary_after_max_distance(
    1, 3, 0,
  )
  guard bad_length is Err(FbrError(code=length_code, ..)) else {
    fail("expected dictionary length error")
  }
  assert_eq(length_code, BrotliInvalidDistance)

  let bad_address : Result[Unit, FbrError] = try? output.copy_from_dictionary_after_max_distance(
    1, 4, 10,
  )
  guard bad_address is Err(FbrError(code=address_code, ..)) else {
    fail("expected dictionary address error")
  }
  assert_eq(address_code, BrotliInvalidDistance)

  let transform_count = @common.brotli_transform_count()
  let bad_transform : Result[Unit, FbrError] = try? output.copy_transformed_dictionary_word(
    0, 4, transform_count,
  )
  guard bad_transform is Err(FbrError(code=transform_code, ..)) else {
    fail("expected transform index error")
  }
  assert_eq(transform_code, BrotliInvalidTransform)
}

///|
test "dictionary transforms reject over-omit cases" {
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  let mut omit_index = -1
  for index in 0..<@common.brotli_transform_count() {
    let transform_type = @common.brotli_transform_triplets[index * 3 + 1]
    if transform_type == @common.brotli_transform_omit_last_9 {
      omit_index = index
    }
  }
  assert_true(omit_index >= 0)
  let omit_result : Result[Unit, FbrError] = try? output.copy_transformed_dictionary_word(
    0, 4, omit_index,
  )
  guard omit_result is Err(FbrError(code=omit_code, ..)) else {
    fail("expected over-omit transform")
  }
  assert_eq(omit_code, BrotliInvalidTransform)
}

///|
test "context map indexing rejects negative and out-of-range contexts" {
  let context_map = BrotliContextMap::{ num_trees: 2, map: [0, 1, 0, 1] }
  let negative : Result[Int, FbrError] = try? brotli_context_map_tree_index(
    context_map, -1, 1, 0,
  )
  guard negative is Err(FbrError(code=negative_code, ..)) else {
    fail("expected negative context-map index")
  }
  assert_eq(negative_code, BrotliInvalidContextMap)

  let context_out : Result[Int, FbrError] = try? brotli_context_map_tree_index(
    context_map, 0, 1, 2,
  )
  guard context_out is Err(FbrError(code=context_code, ..)) else {
    fail("expected context out of range")
  }
  assert_eq(context_code, BrotliInvalidContextMap)

  let index_out : Result[Int, FbrError] = try? brotli_context_map_tree_index(
    context_map, 2, 1, 0,
  )
  guard index_out is Err(FbrError(code=index_code, ..)) else {
    fail("expected context map index out of range")
  }
  assert_eq(index_code, BrotliInvalidContextMap)
}

///|
test "compressed body fast path decodes single-tree literals" {
  // A single literal tree (num_trees == 1) with two symbols 'A'/'B' exercises
  // the single-literal-tree fast path: it must skip context modeling yet still
  // decode distinct literals straight from the one tree. Command symbol 24 sets
  // insert_length = 3, so the whole 3-byte meta-block is literals.
  let literal_lengths = FixedArray::make(brotli_num_literal_symbols, b'\x00')
  literal_lengths[65] = b'\x01' // 'A', 1-bit code 0
  literal_lengths[66] = b'\x01' // 'B', 1-bit code 1
  let literal_trees : Array[FixedArray[Int]] = []
  literal_trees.push(
    brotli_build_huffman_table(
      literal_lengths, brotli_num_literal_symbols, brotli_huffman_table_bits,
    ),
  )
  let command_trees : Array[FixedArray[Int]] = []
  command_trees.push(make_one_symbol_tree(24, brotli_num_command_symbols))
  let distance_trees : Array[FixedArray[Int]] = []
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
  // Literal bits (LSB-first): 0 -> 'A', 1 -> 'B', 0 -> 'A'  =>  byte 0x02.
  let reader = BrotliBitReader::new([0x02], 0, 1)
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  brotli_decode_compressed_metablock_body(
    reader,
    header,
    output,
    3,
    BrotliDecoderState::new_with_window_bits(24),
  )
  inspect(str_from_u8(output.finish()), content="ABA")
}

///|
test "compressed body general path tracks context across literals" {
  // Multiple literal trees (num_trees == 2) drive the general path. Context
  // mode 0 maps `prev_byte & 0x3f` to a tree, so each decoded literal changes
  // the tree used for the next one. This exercises the inlined context-map
  // lookup and the register-tracked previous byte across context transitions.
  let literal_map = FixedArray::make(1 << brotli_literal_context_bits, b'\x00')
  literal_map[1] = b'\x01' // context 1 -> tree 1
  let literal_trees : Array[FixedArray[Int]] = []
  literal_trees.push(make_one_symbol_tree(65, brotli_num_literal_symbols)) // 'A'
  literal_trees.push(make_one_symbol_tree(66, brotli_num_literal_symbols)) // 'B'
  let command_trees : Array[FixedArray[Int]] = []
  command_trees.push(make_one_symbol_tree(24, brotli_num_command_symbols)) // insert 3
  let distance_trees : Array[FixedArray[Int]] = []
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
  // prev=0   -> ctx 0 -> tree0 -> 'A'; prev='A'(65) -> ctx 1 -> tree1 -> 'B';
  // prev='B'(66) -> ctx 2 -> tree0 -> 'A'.  One-symbol trees consume no bits.
  let reader = BrotliBitReader::new([0x00, 0x00], 0, 2)
  let output = BrotliOutputBuilder::new(UnbrotliOptions::default())
  brotli_decode_compressed_metablock_body(
    reader,
    header,
    output,
    3,
    BrotliDecoderState::new_with_window_bits(24),
  )
  inspect(str_from_u8(output.finish()), content="ABA")
}

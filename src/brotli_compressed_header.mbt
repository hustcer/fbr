///|
priv struct BrotliBlockSwitchHeader {
  num_types : Int
  type_tree : FixedArray[BrotliHuffmanCode]?
  length_tree : FixedArray[BrotliHuffmanCode]?
  first_length : Int
}

///|
priv struct BrotliCompressedMetablockHeader {
  literal_block : BrotliBlockSwitchHeader
  command_block : BrotliBlockSwitchHeader
  distance_block : BrotliBlockSwitchHeader
  distance_postfix_bits : Int
  num_direct_distance_codes : Int
  context_modes : FixedArray[Byte]
  literal_context_map : BrotliContextMap
  distance_context_map : BrotliContextMap
  literal_trees : BrotliHuffmanTreeGroup
  command_trees : BrotliHuffmanTreeGroup
  distance_trees : BrotliHuffmanTreeGroup
}

///|
fn brotli_read_block_switch_header(
  reader : BrotliBitReader,
) -> BrotliBlockSwitchHeader raise FzipError {
  let num_types = brotli_read_block_type_count(reader)
  if num_types == 1 {
    return {
      num_types,
      type_tree: None,
      length_tree: None,
      first_length: brotli_block_size_cap,
    }
  }
  let type_tree = brotli_read_huffman_code(
    reader,
    num_types + 2,
    num_types + 2,
    brotli_huffman_table_bits,
  )
  let length_tree = brotli_read_huffman_code(
    reader, brotli_num_block_length_symbols, brotli_num_block_length_symbols, brotli_huffman_table_bits,
  )
  {
    num_types,
    type_tree: Some(type_tree),
    length_tree: Some(length_tree),
    first_length: brotli_read_block_length(reader, length_tree),
  }
}

///|
fn brotli_read_context_modes(
  reader : BrotliBitReader,
  num_literal_block_types : Int,
) -> FixedArray[Byte] raise FzipError {
  let modes = FixedArray::make(num_literal_block_types, b'\x00')
  for i in 0..<num_literal_block_types {
    modes[i] = reader.take_bits(2).to_byte()
  }
  modes
}

///|
fn brotli_read_compressed_metablock_header(
  reader : BrotliBitReader,
) -> BrotliCompressedMetablockHeader raise FzipError {
  let literal_block = brotli_read_block_switch_header(reader)
  let command_block = brotli_read_block_switch_header(reader)
  let distance_block = brotli_read_block_switch_header(reader)
  let bits = reader.take_bits(6).reinterpret_as_int()
  let distance_postfix_bits = bits & 3
  let num_direct_distance_codes = bits >> 2 << distance_postfix_bits
  let context_modes = brotli_read_context_modes(reader, literal_block.num_types)
  let literal_context_map = brotli_read_context_map(
    reader,
    literal_block.num_types << brotli_literal_context_bits,
  )
  let distance_context_map = brotli_read_context_map(
    reader,
    distance_block.num_types << brotli_distance_context_bits,
  )
  let distance_alphabet_size = brotli_distance_alphabet_size(
    distance_postfix_bits, num_direct_distance_codes, brotli_max_distance_bits,
  )
  let literal_trees = brotli_read_huffman_tree_group(
    reader,
    brotli_num_literal_symbols,
    brotli_num_literal_symbols,
    literal_context_map.num_trees,
    brotli_huffman_table_bits,
  )
  let command_trees = brotli_read_huffman_tree_group(
    reader,
    brotli_num_command_symbols,
    brotli_num_command_symbols,
    command_block.num_types,
    brotli_huffman_table_bits,
  )
  let distance_trees = brotli_read_huffman_tree_group(
    reader,
    distance_alphabet_size,
    distance_alphabet_size,
    distance_context_map.num_trees,
    brotli_huffman_table_bits,
  )
  {
    literal_block,
    command_block,
    distance_block,
    distance_postfix_bits,
    num_direct_distance_codes,
    context_modes,
    literal_context_map,
    distance_context_map,
    literal_trees,
    command_trees,
    distance_trees,
  }
}

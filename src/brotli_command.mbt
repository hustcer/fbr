///|
priv struct BrotliCommandInfo {
  insert_len_extra_bits : Int
  copy_len_extra_bits : Int
  distance_code : Int
  distance_context : Int
  insert_len_offset : Int
  copy_len_offset : Int
}

///|
priv struct BrotliCommand {
  insert_length : Int
  copy_length : Int
  distance_code : Int
  distance_context : Int
}

///|
let brotli_insert_length_extra_bits : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24,
]

///|
let brotli_copy_length_extra_bits : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24,
]

///|
let brotli_command_cell_pos : FixedArray[Int] = [
  0, 1, 0, 1, 8, 9, 2, 16, 10, 17, 18,
]

///|
fn brotli_prefix_offset(
  extra_bits : FixedArray[Int],
  code : Int,
  initial : Int,
) -> Int {
  let mut offset = initial
  for i in 0..<code {
    offset += 1 << extra_bits[i]
  }
  offset
}

///|
fn brotli_command_info(symbol : Int) -> BrotliCommandInfo raise FzipError {
  if symbol < 0 || symbol >= brotli_num_command_symbols {
    raise fzip_err(BrotliInvalidMetablock, msg="invalid Brotli command symbol")
  }
  let cell_index = symbol >> 6
  let cell_pos = brotli_command_cell_pos[cell_index]
  let copy_code = ((cell_pos << 3) & 0x18) + (symbol & 0x7)
  let insert_code = (cell_pos & 0x18) + ((symbol >> 3) & 0x7)
  let copy_len_offset = brotli_prefix_offset(
    brotli_copy_length_extra_bits, copy_code, 2,
  )
  {
    insert_len_extra_bits: brotli_insert_length_extra_bits[insert_code],
    copy_len_extra_bits: brotli_copy_length_extra_bits[copy_code],
    distance_code: if cell_index >= 2 {
      -1
    } else {
      0
    },
    distance_context: if copy_len_offset > 4 {
      3
    } else {
      copy_len_offset - 2
    },
    insert_len_offset: brotli_prefix_offset(
      brotli_insert_length_extra_bits, insert_code, 0,
    ),
    copy_len_offset,
  }
}

///|
fn brotli_read_command(
  reader : BrotliBitReader,
  command_tree : FixedArray[BrotliHuffmanCode],
) -> BrotliCommand raise FzipError {
  let symbol = brotli_read_symbol(
    reader, command_tree, brotli_huffman_table_bits,
  )
  let info = brotli_command_info(symbol)
  let insert_extra = reader
    .take_bits(info.insert_len_extra_bits)
    .reinterpret_as_int()
  let copy_extra = reader
    .take_bits(info.copy_len_extra_bits)
    .reinterpret_as_int()
  {
    insert_length: info.insert_len_offset + insert_extra,
    copy_length: info.copy_len_offset + copy_extra,
    distance_code: info.distance_code,
    distance_context: info.distance_context,
  }
}

///|
fn brotli_decode_compressed_metablock_body(
  reader : BrotliBitReader,
  header : BrotliCompressedMetablockHeader,
  output : BrotliOutputBuilder,
  length : Int,
  state : BrotliDecoderState,
) -> Unit raise FzipError {
  let literal_blocks = BrotliBlockTracker::new_with_length(
    header.literal_block.num_types,
    header.literal_block.first_length,
  )
  let command_blocks = BrotliBlockTracker::new_with_length(
    header.command_block.num_types,
    header.command_block.first_length,
  )
  let distance_blocks = BrotliBlockTracker::new_with_length(
    header.distance_block.num_types,
    header.distance_block.first_length,
  )
  let mut remaining = length
  while remaining > 0 {
    command_blocks.ensure_ready(reader, header.command_block)
    let command = brotli_read_command(
      reader,
      header.command_trees.tree(command_blocks.current_type),
    )
    command_blocks.remaining -= 1
    if command.insert_length > remaining {
      raise fzip_err(
        BrotliInvalidMetablock,
        msg="Brotli insert length exceeds meta-block",
      )
    }
    output.ensure(command.insert_length)
    for _ in 0..<command.insert_length {
      literal_blocks.ensure_ready(reader, header.literal_block)
      let previous_byte_1 = if output.len > 0 {
        output.buf[output.len - 1].to_int()
      } else {
        0
      }
      let previous_byte_2 = if output.len > 1 {
        output.buf[output.len - 2].to_int()
      } else {
        0
      }
      let literal_context = brotli_literal_context_id(
        header.context_modes[literal_blocks.current_type].to_int(),
        previous_byte_1,
        previous_byte_2,
      )
      let literal_tree_index = brotli_context_map_tree_index(
        header.literal_context_map,
        literal_blocks.current_type,
        brotli_literal_context_bits,
        literal_context,
      )
      let literal = brotli_read_symbol(
        reader,
        header.literal_trees.tree(literal_tree_index),
        brotli_huffman_table_bits,
      )
      if literal < 0 || literal > 255 {
        raise fzip_err(
          BrotliInvalidMetablock,
          msg="Brotli literal out of byte range",
        )
      }
      output.buf[output.len] = literal.to_byte()
      output.len += 1
      literal_blocks.remaining -= 1
    }
    remaining -= command.insert_length
    if remaining == 0 {
      return
    }
    if command.copy_length > remaining {
      raise fzip_err(
        BrotliInvalidMetablock,
        msg="Brotli copy length exceeds meta-block",
      )
    }
    let distance = if command.distance_code >= 0 {
      state.distance_ring.take_short_code(command.distance_code)
    } else {
      distance_blocks.ensure_ready(reader, header.distance_block)
      let distance_tree_index = brotli_context_map_tree_index(
        header.distance_context_map,
        distance_blocks.current_type,
        brotli_distance_context_bits,
        command.distance_context,
      )
      let distance_tree = header.distance_trees.tree(distance_tree_index)
      distance_blocks.remaining -= 1
      brotli_read_distance(
        reader,
        distance_tree,
        state.distance_ring,
        header.distance_postfix_bits,
        header.num_direct_distance_codes,
      )
    }
    if distance <= output.len {
      output.copy_from_distance(distance, command.copy_length)
    } else {
      output.copy_from_dictionary(distance, command.copy_length)
    }
    state.distance_ring.record(distance)
    remaining -= command.copy_length
  }
}

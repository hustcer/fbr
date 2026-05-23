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

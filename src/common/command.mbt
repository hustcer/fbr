///|
pub(all) struct BrotliCommandInfo {
  insert_len_extra_bits : Int
  copy_len_extra_bits : Int
  distance_code : Int
  distance_context : Int
  insert_len_offset : Int
  copy_len_offset : Int
}

///|

///|
pub let brotli_insert_length_extra_bits : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24,
]

///|
pub let brotli_copy_length_extra_bits : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24,
]

///|
pub let brotli_command_cell_pos : FixedArray[Int] = [
  0, 1, 0, 1, 8, 9, 2, 16, 10, 17, 18,
]

///|
pub fn brotli_prefix_offset(
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
pub fn brotli_build_command_info(symbol : Int) -> BrotliCommandInfo {
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
pub let brotli_command_info_table : FixedArray[BrotliCommandInfo] = {
  let table = FixedArray::make(
    brotli_num_command_symbols,
    brotli_build_command_info(0),
  )
  for symbol in 0..<brotli_num_command_symbols {
    table[symbol] = brotli_build_command_info(symbol)
  }
  table
}

///|
pub fn brotli_command_info(symbol : Int) -> BrotliCommandInfo raise FbrError {
  if symbol < 0 || symbol >= brotli_num_command_symbols {
    raise fbr_err(BrotliInvalidMetablock, msg="invalid Brotli command symbol")
  }
  brotli_command_info_table[symbol]
}

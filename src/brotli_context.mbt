///|
priv struct BrotliContextMap {
  num_trees : Int
  map : FixedArray[Byte]
}

///|
fn brotli_inverse_move_to_front(map : FixedArray[Byte]) -> Unit {
  let mtf = FixedArray::make(256, b'\x00')
  for i in 0..<256 {
    mtf[i] = i.to_byte()
  }
  for i in 0..<map.length() {
    let index = map[i].to_int()
    let value = mtf[index]
    map[i] = value
    let mut j = index
    while j > 0 {
      mtf[j] = mtf[j - 1]
      j -= 1
    }
    mtf[0] = value
  }
}

///|
fn brotli_read_context_map(
  reader : BrotliBitReader,
  context_map_size : Int,
) -> BrotliContextMap raise FzipError {
  if context_map_size < 0 {
    raise fzip_err(BrotliInvalidContextMap, msg="negative context map size")
  }
  let num_trees = brotli_decode_var_len_uint8(reader) + 1
  let context_map = FixedArray::make(context_map_size, b'\x00')
  if num_trees <= 1 {
    return { num_trees, map: context_map }
  }
  let max_run_length_prefix = if reader.take_bits(1) == 1U {
    reader.take_bits(4).reinterpret_as_int() + 1
  } else {
    0
  }
  let alphabet_size = num_trees + max_run_length_prefix
  let table = brotli_read_huffman_code(
    reader, alphabet_size, alphabet_size, brotli_huffman_table_bits,
  )
  let mut index = 0
  while index < context_map_size {
    let code = brotli_read_symbol(reader, table, brotli_huffman_table_bits)
    if code == 0 {
      context_map[index] = b'\x00'
      index += 1
    } else if code > max_run_length_prefix {
      let value = code - max_run_length_prefix
      if value >= num_trees {
        raise fzip_err(
          BrotliInvalidContextMap,
          msg="context map tree index exceeds tree count",
        )
      }
      context_map[index] = value.to_byte()
      index += 1
    } else {
      let reps = (1 << code) + reader.take_bits(code).reinterpret_as_int()
      if index > context_map_size - reps {
        raise fzip_err(
          BrotliInvalidContextMap,
          msg="context map repeat overflows",
        )
      }
      for _ in 0..<reps {
        context_map[index] = b'\x00'
        index += 1
      }
    }
  }
  if reader.take_bits(1) != 0U {
    brotli_inverse_move_to_front(context_map)
  }
  { num_trees, map: context_map }
}

///|
fn brotli_context_map_tree_index(
  context_map : BrotliContextMap,
  block_type : Int,
  context_bits : Int,
  context : Int,
) -> Int raise FzipError {
  if block_type < 0 || context < 0 || context_bits < 0 {
    raise fzip_err(BrotliInvalidContextMap, msg="negative context map index")
  }
  let context_count = 1 << context_bits
  if context >= context_count {
    raise fzip_err(BrotliInvalidContextMap, msg="Brotli context out of range")
  }
  let index = block_type * context_count + context
  if index < 0 || index >= context_map.map.length() {
    raise fzip_err(
      BrotliInvalidContextMap,
      msg="Brotli context map index out of range",
    )
  }
  let tree_index = context_map.map[index].to_int()
  if tree_index < 0 || tree_index >= context_map.num_trees {
    raise fzip_err(
      BrotliInvalidContextMap,
      msg="Brotli context map tree out of range",
    )
  }
  tree_index
}

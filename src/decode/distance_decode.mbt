///|
fn brotli_take_short_code_validated(
  distance_ring : @common.BrotliDistanceRing,
  code : Int,
) -> Int raise @common.FbrError {
  distance_ring.last_distance_context = 0
  if code <= 3 {
    let offset = code - 3
    let distance_context = 1 >> code
    let distance = distance_ring.distances[@common.brotli_distance_ring_slot(
        distance_ring.index - offset,
      )]
    distance_ring.index -= distance_context
    distance_ring.last_distance_context = distance_context
    return distance
  }
  let mut index_delta = 3
  let mut base = code - 10
  if code < 10 {
    base = code - 4
  } else {
    index_delta = 2
  }
  let delta = ((0x605142 >> (4 * base)) & 0xf) - 3
  let distance = distance_ring.distances[@common.brotli_distance_ring_slot(
      distance_ring.index + index_delta,
    )] +
    delta
  if distance <= 0 {
    raise @common.fbr_err(
      BrotliInvalidDistance,
      msg="invalid Brotli short distance",
    )
  }
  distance
}

///|
fn brotli_read_distance(
  reader : BrotliBitReader,
  distance_tree : FixedArray[Int],
  distance_ring : @common.BrotliDistanceRing,
  npostfix : Int,
  ndirect : Int,
) -> Int raise @common.FbrError {
  let code = brotli_read_symbol(
    reader, distance_tree, @common.brotli_huffman_table_bits,
  )
  if code < @common.brotli_num_distance_short_codes {
    return brotli_take_short_code_validated(distance_ring, code)
  }
  let direct_limit = @common.brotli_num_distance_short_codes + ndirect
  if code < direct_limit {
    return code - @common.brotli_num_distance_short_codes + 1
  }
  let xcode = code - ndirect - @common.brotli_num_distance_short_codes
  let extra_bits = 1 + (xcode >> (npostfix + 1))
  let half = (xcode >> npostfix) & 1
  let postfix = xcode & ((1 << npostfix) - 1)
  let offset = ndirect +
    ((((2 + half) << extra_bits) - 4) << npostfix) +
    postfix +
    1
  offset + (reader.take_bits(extra_bits).reinterpret_as_int() << npostfix)
}

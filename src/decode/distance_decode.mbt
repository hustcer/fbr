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
      @common.BrotliInvalidDistance,
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
  let extra_bits = @common.brotli_distance_extra_bits(code, npostfix, ndirect)
  let offset = @common.brotli_distance_offset(code, npostfix, ndirect)
  offset + (reader.take_bits(extra_bits).reinterpret_as_int() << npostfix)
}

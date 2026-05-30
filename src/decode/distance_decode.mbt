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
    return distance_ring.take_short_code(code)
  }
  let extra_bits = @common.brotli_distance_extra_bits(code, npostfix, ndirect)
  let offset = @common.brotli_distance_offset(code, npostfix, ndirect)
  offset + (reader.take_bits(extra_bits).reinterpret_as_int() << npostfix)
}

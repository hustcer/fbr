///|
priv struct BrotliDistanceRing {
  distances : FixedArray[Int]
  mut index : Int
  mut last_distance_context : Int
}

///|
fn BrotliDistanceRing::new() -> BrotliDistanceRing {
  { distances: [16, 15, 11, 4], index: 0, last_distance_context: 0 }
}

///|
fn brotli_distance_ring_slot(index : Int) -> Int {
  let mut slot = index % 4
  if slot < 0 {
    slot += 4
  }
  slot
}

///|
fn BrotliDistanceRing::take_short_code(
  self : BrotliDistanceRing,
  code : Int,
) -> Int raise FzipError {
  if code < 0 || code >= brotli_num_distance_short_codes {
    raise fzip_err(BrotliInvalidDistance, msg="invalid Brotli short distance")
  }
  self.last_distance_context = 0
  if code <= 3 {
    let offset = code - 3
    let distance_context = 1 >> code
    let distance = self.distances[brotli_distance_ring_slot(self.index - offset)]
    self.index -= distance_context
    self.last_distance_context = distance_context
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
  let distance = self.distances[brotli_distance_ring_slot(
      self.index + index_delta,
    )] +
    delta
  if distance <= 0 {
    raise fzip_err(BrotliInvalidDistance, msg="invalid Brotli short distance")
  }
  distance
}

///|
fn BrotliDistanceRing::compensate_dictionary_copy(
  self : BrotliDistanceRing,
) -> Unit {
  self.index += self.last_distance_context
  self.last_distance_context = 0
}

///|
fn BrotliDistanceRing::record(
  self : BrotliDistanceRing,
  distance : Int,
) -> Unit raise FzipError {
  if distance <= 0 {
    raise fzip_err(BrotliInvalidDistance, msg="invalid Brotli distance")
  }
  self.distances[brotli_distance_ring_slot(self.index)] = distance
  self.index += 1
  self.last_distance_context = 0
}

///|
fn brotli_distance_extra_bits(
  code : Int,
  npostfix : Int,
  ndirect : Int,
) -> Int raise FzipError {
  if code < 0 {
    raise fzip_err(BrotliInvalidDistance, msg="negative Brotli distance code")
  }
  if code < brotli_num_distance_short_codes + ndirect {
    0
  } else {
    let xcode = code - ndirect - brotli_num_distance_short_codes
    1 + (xcode >> (npostfix + 1))
  }
}

///|
fn brotli_distance_offset(
  code : Int,
  npostfix : Int,
  ndirect : Int,
) -> Int raise FzipError {
  if code < brotli_num_distance_short_codes {
    raise fzip_err(BrotliInvalidDistance, msg="short code has no direct offset")
  }
  if code < brotli_num_distance_short_codes + ndirect {
    code - brotli_num_distance_short_codes + 1
  } else {
    let xcode = code - ndirect - brotli_num_distance_short_codes
    let bits = 1 + (xcode >> (npostfix + 1))
    let half = (xcode >> npostfix) & 1
    let postfix = xcode & ((1 << npostfix) - 1)
    ndirect + ((((2 + half) << bits) - 4) << npostfix) + postfix + 1
  }
}

///|
fn brotli_read_distance(
  reader : BrotliBitReader,
  distance_tree : FixedArray[BrotliHuffmanCode],
  distance_ring : BrotliDistanceRing,
  npostfix : Int,
  ndirect : Int,
) -> Int raise FzipError {
  let code = brotli_read_symbol(
    reader, distance_tree, brotli_huffman_table_bits,
  )
  if code < brotli_num_distance_short_codes {
    return distance_ring.take_short_code(code)
  }
  let extra_bits = brotli_distance_extra_bits(code, npostfix, ndirect)
  let offset = brotli_distance_offset(code, npostfix, ndirect)
  offset + (reader.take_bits(extra_bits).reinterpret_as_int() << npostfix)
}

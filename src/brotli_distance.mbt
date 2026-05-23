///|
priv struct BrotliDistanceRing {
  distances : FixedArray[Int]
  mut index : Int
}

///|
fn BrotliDistanceRing::new() -> BrotliDistanceRing {
  { distances: [16, 15, 11, 4], index: 0 }
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
  if code <= 3 {
    let offset = code - 3
    let distance_context = 1 >> code
    let distance = self.distances[brotli_distance_ring_slot(self.index - offset)]
    self.index -= distance_context
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
fn BrotliDistanceRing::record(
  self : BrotliDistanceRing,
  distance : Int,
) -> Unit raise FzipError {
  if distance <= 0 {
    raise fzip_err(BrotliInvalidDistance, msg="invalid Brotli distance")
  }
  self.distances[brotli_distance_ring_slot(self.index)] = distance
  self.index += 1
}

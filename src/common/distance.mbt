///|
pub(all) struct BrotliDistanceRing {
  distances : FixedArray[Int]
  mut index : Int
  mut last_distance_context : Int
}

///|
pub fn BrotliDistanceRing::new() -> BrotliDistanceRing {
  { distances: [16, 15, 11, 4], index: 0, last_distance_context: 0 }
}

///|
pub fn brotli_distance_ring_slot(index : Int) -> Int {
  // The ring has four slots, so a bit mask gives the same wraparound as
  // modulo 4, including negative indices used by short-distance codes.
  index & 3
}

///|
pub fn BrotliDistanceRing::take_short_code(
  self : BrotliDistanceRing,
  code : Int,
) -> Int raise FbrError {
  if code < 0 || code >= brotli_num_distance_short_codes {
    raise fbr_err(BrotliInvalidDistance, msg="invalid Brotli short distance")
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
    raise fbr_err(BrotliInvalidDistance, msg="invalid Brotli short distance")
  }
  distance
}

///|
pub fn BrotliDistanceRing::compensate_dictionary_copy(
  self : BrotliDistanceRing,
) -> Unit {
  self.index += self.last_distance_context
  self.last_distance_context = 0
}

///|
pub fn BrotliDistanceRing::record(
  self : BrotliDistanceRing,
  distance : Int,
) -> Unit raise FbrError {
  if distance <= 0 {
    raise fbr_err(BrotliInvalidDistance, msg="invalid Brotli distance")
  }
  self.distances[brotli_distance_ring_slot(self.index)] = distance
  self.index += 1
  self.last_distance_context = 0
}

///|
pub fn brotli_distance_extra_bits(
  code : Int,
  npostfix : Int,
  ndirect : Int,
) -> Int raise FbrError {
  if code < 0 {
    raise fbr_err(BrotliInvalidDistance, msg="negative Brotli distance code")
  }
  if code < brotli_num_distance_short_codes + ndirect {
    0
  } else {
    let xcode = code - ndirect - brotli_num_distance_short_codes
    1 + (xcode >> (npostfix + 1))
  }
}

///|
pub fn brotli_distance_offset(
  code : Int,
  npostfix : Int,
  ndirect : Int,
) -> Int raise FbrError {
  if code < brotli_num_distance_short_codes {
    raise fbr_err(BrotliInvalidDistance, msg="short code has no direct offset")
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

///|
let brotli_dictionary_min_word_length : Int = 4

///|
let brotli_dictionary_max_word_length : Int = 24

///|
let brotli_dictionary_size_bits_by_length : FixedArray[Int] = [
  0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5,
  5, 0, 0, 0, 0, 0, 0, 0,
]

///|
let brotli_dictionary_offsets_by_length : FixedArray[Int] = [
  0, 0, 0, 0, 0, 4096, 9216, 21504, 35840, 44032, 53248, 63488, 74752, 87040, 93696,
  100864, 104704, 106752, 108928, 113536, 115968, 118528, 119872, 121280, 122016,
  122784, 122784, 122784, 122784, 122784, 122784, 122784,
]

///|
fn BrotliOutputBuilder::copy_from_dictionary(
  self : BrotliOutputBuilder,
  distance : Int,
  length : Int,
) -> Unit raise FzipError {
  if length < brotli_dictionary_min_word_length ||
    length > brotli_dictionary_max_word_length {
    raise fzip_err(
      BrotliInvalidDistance,
      msg="Brotli dictionary length out of range",
    )
  }
  let size_bits = brotli_dictionary_size_bits_by_length[length]
  if size_bits == 0 {
    raise fzip_err(
      BrotliInvalidDistance,
      msg="Brotli dictionary bucket is empty",
    )
  }
  let address = distance - self.len - 1
  if address < 0 {
    raise fzip_err(
      BrotliInvalidDistance,
      msg="negative Brotli dictionary address",
    )
  }
  let word_mask = (1 << size_bits) - 1
  let word_index = address & word_mask
  let transform_index = address >> size_bits
  let offset = brotli_dictionary_offsets_by_length[length] + word_index * length
  if offset < 0 || offset > brotli_dictionary_data.length() - length {
    raise fzip_err(
      BrotliInvalidDistance,
      msg="Brotli dictionary address out of range",
    )
  }
  self.copy_transformed_dictionary_word(offset, length, transform_index)
}

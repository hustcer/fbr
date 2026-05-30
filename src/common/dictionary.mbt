///|
pub let brotli_dictionary_min_word_length : Int = 4

///|
pub let brotli_dictionary_max_word_length : Int = 24

///|
pub let brotli_dictionary_size_bits_by_length : FixedArray[Int] = [
  0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5,
  5, 0, 0, 0, 0, 0, 0, 0,
]

///|
pub let brotli_dictionary_offsets_by_length : FixedArray[Int] = [
  0, 0, 0, 0, 0, 4096, 9216, 21504, 35840, 44032, 53248, 63488, 74752, 87040, 93696,
  100864, 104704, 106752, 108928, 113536, 115968, 118528, 119872, 121280, 122016,
  122784, 122784, 122784, 122784, 122784, 122784, 122784,
]

///|

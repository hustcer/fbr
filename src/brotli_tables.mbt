///|
/// Order in which Brotli code-length-code lengths are transmitted.
let brotli_code_length_code_order : FixedArray[Int] = [
  1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

///|
/// Static prefix-code lengths for complex Huffman code-length-code lengths.
let brotli_code_length_prefix_length : FixedArray[Int] = [
  2, 2, 2, 3, 2, 2, 2, 4, 2, 2, 2, 3, 2, 2, 2, 4,
]

///|
/// Static prefix-code values for complex Huffman code-length-code lengths.
let brotli_code_length_prefix_value : FixedArray[Int] = [
  0, 4, 3, 2, 0, 4, 3, 1, 0, 4, 3, 2, 0, 4, 3, 5,
]

///|
/// Base values for Brotli block-length prefix-code symbols.
let brotli_block_length_bases : FixedArray[Int] = [
  1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369,
  497, 753, 1265, 2289, 4337, 8433, 16625,
]

///|
/// Extra-bit counts for Brotli block-length prefix-code symbols.
let brotli_block_length_extra_bits : FixedArray[Int] = [
  2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13,
  24,
]

///|
/// Minimum standard Brotli window size in bits.
let brotli_min_window_bits : Int = 10

///|
/// Maximum standard Brotli window size in bits. fzip intentionally rejects the
/// large-window extension above this limit.
let brotli_max_window_bits : Int = 24

///|
/// Bytes reserved by RFC 7932 section 9.1 when deriving the maximum
/// backward-reference distance from the advertised window size.
let brotli_window_gap : Int = 16

///|
/// Operational cap on uncompressed bytes per Brotli meta-block. Matches the C
/// reference `MAX_METABLOCK_SIZE`.
let brotli_max_metablock_bytes : Int = 1 << 24

///|
/// Maximum code length in bits for any Brotli Huffman alphabet.
let brotli_huffman_max_code_length : Int = 15

///|
/// Root table width for Brotli Huffman lookup tables.
let brotli_huffman_table_bits : Int = 8

///|
/// Maximum per-tree table size from the reference implementation.
let brotli_huffman_max_table_size : Int = 1080

///|
/// Brotli code-length repeat symbol for the previous nonzero code length.
let brotli_repeat_previous_code_length : Int = 16

///|
/// Brotli code-length repeat symbol for zero code lengths.
let brotli_repeat_zero_code_length : Int = 17

///|
/// Number of symbols in the code-length-code alphabet.
let brotli_num_code_length_codes : Int = brotli_repeat_zero_code_length + 1

///|
/// Maximum bit length for the code-length-code alphabet.
let brotli_huffman_max_code_length_code_length : Int = 5

///|
/// Initial previous length used by repeat-previous code-length symbols.
let brotli_initial_repeated_code_length : Int = 8

///|
/// Number of literal symbols in Brotli literal Huffman trees.
let brotli_num_literal_symbols : Int = 256

///|
/// Number of insert-and-copy command symbols.
let brotli_num_command_symbols : Int = 704

///|
/// Number of block-length prefix-code symbols.
let brotli_num_block_length_symbols : Int = 26

///|
/// Sentinel block length used when a stream has a single block type.
let brotli_block_size_cap : Int = 1 << 24

///|
/// Number of distance short codes backed by the recent-distance ring.
let brotli_num_distance_short_codes : Int = 16

///|
/// Maximum standard distance extra-bit count.
let brotli_max_distance_bits : Int = 24

///|
/// Literal context ID bit count per literal block type.
let brotli_literal_context_bits : Int = 6

///|
/// Distance context ID bit count per distance block type.
let brotli_distance_context_bits : Int = 2

///|
fn brotli_distance_alphabet_size(
  npostfix : Int,
  ndirect : Int,
  max_distance_bits : Int,
) -> Int {
  brotli_num_distance_short_codes +
  ndirect +
  (max_distance_bits << (npostfix + 1))
}

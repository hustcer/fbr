///|
/// Minimum standard Brotli window size in bits.
pub let brotli_min_window_bits : Int = 10

///|
/// Maximum standard Brotli window size in bits. fzip intentionally rejects the
/// large-window extension above this limit.
pub let brotli_max_window_bits : Int = 24

///|
/// Bytes reserved by RFC 7932 section 9.1 when deriving the maximum
/// backward-reference distance from the advertised window size.
pub let brotli_window_gap : Int = 16

///|
/// Operational cap on uncompressed bytes per Brotli meta-block. Matches the C
/// reference `MAX_METABLOCK_SIZE`.
pub let brotli_max_metablock_bytes : Int = 1 << 24

///|
/// Maximum code length in bits for any Brotli Huffman alphabet.
pub let brotli_huffman_max_code_length : Int = 15

///|
/// Root table width for Brotli Huffman lookup tables.
pub let brotli_huffman_table_bits : Int = 8

///|
/// Maximum per-tree table size from the reference implementation.
pub let brotli_huffman_max_table_size : Int = 1080

///|
/// Brotli code-length repeat symbol for the previous nonzero code length.
pub let brotli_repeat_previous_code_length : Int = 16

///|
/// Brotli code-length repeat symbol for zero code lengths.
pub let brotli_repeat_zero_code_length : Int = 17

///|
/// Number of symbols in the code-length-code alphabet.
pub let brotli_num_code_length_codes : Int = brotli_repeat_zero_code_length + 1

///|
/// Maximum bit length for the code-length-code alphabet.
pub let brotli_huffman_max_code_length_code_length : Int = 5

///|
/// Initial previous length used by repeat-previous code-length symbols.
pub let brotli_initial_repeated_code_length : Int = 8

///|
/// Number of literal symbols in Brotli literal Huffman trees.
pub let brotli_num_literal_symbols : Int = 256

///|
/// Number of insert-and-copy command symbols.
pub let brotli_num_command_symbols : Int = 704

///|
/// Number of block-length prefix-code symbols.
pub let brotli_num_block_length_symbols : Int = 26

///|
/// Sentinel block length used when a stream has a single block type.
pub let brotli_block_size_cap : Int = 1 << 24

///|
/// Number of distance short codes backed by the recent-distance ring.
pub let brotli_num_distance_short_codes : Int = 16

///|
/// Maximum standard distance extra-bit count.
pub let brotli_max_distance_bits : Int = 24

///|
/// Literal context ID bit count per literal block type.
pub let brotli_literal_context_bits : Int = 6

///|
/// Distance context ID bit count per distance block type.
pub let brotli_distance_context_bits : Int = 2

///|
pub fn brotli_distance_alphabet_size(
  npostfix : Int,
  ndirect : Int,
  max_distance_bits : Int,
) -> Int {
  brotli_num_distance_short_codes +
  ndirect +
  (max_distance_bits << (npostfix + 1))
}

///|
pub fn brotli_validate_window_bits(window_bits : Int) -> Unit raise FbrError {
  if window_bits < brotli_min_window_bits ||
    window_bits > brotli_max_window_bits {
    raise fbr_err(BrotliInvalidWindowBits)
  }
}

///|
/// Minimum standard Brotli window size in bits.
let brotli_min_window_bits : Int = 10

///|
/// Maximum standard Brotli window size in bits. fzip intentionally rejects the
/// large-window extension above this limit.
let brotli_max_window_bits : Int = 24

///|
/// Operational cap on uncompressed bytes per Brotli meta-block. Matches the C
/// reference `MAX_METABLOCK_SIZE`.
let brotli_max_metablock_bytes : Int = 1 << 24

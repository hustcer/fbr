///|
/// future suffix-tree/Zopfli backend.
pub(all) struct BrotliOptions {
  /// Compression quality, from 0 (fastest) to 11 (maximum compression).
  quality : Int
  /// Standard Brotli window size in bits, from 10 to 24.
  window_bits : Int
  /// Maximum allowed uncompressed input size.
  max_input_size : Int
} derive(Debug)

///|
/// Return the default Brotli compression options.
pub fn BrotliOptions::default() -> BrotliOptions {
  {
    quality: 11,
    window_bits: 22,
    max_input_size: @common.default_max_input_size,
  }
}

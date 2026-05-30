///|
/// Options for Brotli decompression.
///
/// `out` lets callers provide a reusable output buffer. The buffer must fit the
/// full decompressed payload when supplied. The Brotli decoder may allocate a
/// ring buffer up to `1 << window_bits` from the stream header; the default
/// `max_output_size` still caps the final output returned by the sync API.
pub(all) struct UnbrotliOptions {
  /// Optional pre-allocated output buffer; when supplied, it must fit the full output.
  out : FixedArray[Byte]?
  /// Maximum allowed uncompressed output size.
  max_output_size : Int
  /// Maximum allowed compressed input size.
  max_input_size : Int
} derive(Debug)

///|
/// Return the default Brotli decompression options.
pub fn UnbrotliOptions::default() -> UnbrotliOptions {
  {
    out: None,
    max_output_size: default_max_output_size,
    max_input_size: default_max_input_size,
  }
}

///|
/// Options for Brotli compression.
///
/// `quality` follows Brotli's 0-11 scale. All standard quality levels are
/// accepted by the current encoder backend. `window_bits` controls the
/// advertised Brotli window and must stay within the standard RFC 7932 range 10
/// through 24. `max_input_size` caps the sync API input before encoder
/// allocation; q=10 and q=11 apply an additional 256 MiB safety cap for the
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
  { quality: 11, window_bits: 22, max_input_size: default_max_input_size }
}

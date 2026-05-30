///|
/// Error categories reported by Brotli operations.
///
/// The public decode/encode APIs raise `FzipError` with one of these codes. The
/// code is intended for programmatic handling while the message gives a
/// human-readable explanation.
pub(all) enum FzipErrorCode {
  /// The input ended before the stream could be fully decoded.
  UnexpectedEOF
  /// Byte data could not be decoded as valid UTF-8.
  InvalidUTF8
  /// Input or output violates a configured safety limit (size cap, unsupported
  /// option value, or otherwise malformed/oversized input).
  InvalidZipData
  /// Brotli window-bits field is out of range or reserved.
  BrotliInvalidWindowBits
  /// Brotli meta-block header is malformed.
  BrotliInvalidMetablock
  /// Brotli Huffman code tree could not be built from declared lengths.
  BrotliInvalidHuffman
  /// Brotli context map encoding is invalid.
  BrotliInvalidContextMap
  /// Brotli distance code references a position outside the window.
  BrotliInvalidDistance
  /// Brotli transform index is out of range.
  BrotliInvalidTransform
  /// Brotli shared-dictionary APIs are not supported.
  BrotliDictionaryNotSupported
  /// Brotli stream uses the large-window extension that is not supported.
  BrotliLargeWindowNotSupported
  /// Brotli stream contains a reserved bit or pattern.
  BrotliReserved
  /// Brotli padding bits at end of stream are non-zero.
  BrotliInvalidPadding
} derive(Eq, Debug)

///|
/// Write the symbolic error-code name, such as `"BrotliInvalidHuffman"`.
pub impl Show for FzipErrorCode with fn output(self, logger) {
  match self {
    UnexpectedEOF => logger.write_string("UnexpectedEOF")
    InvalidUTF8 => logger.write_string("InvalidUTF8")
    InvalidZipData => logger.write_string("InvalidZipData")
    BrotliInvalidWindowBits => logger.write_string("BrotliInvalidWindowBits")
    BrotliInvalidMetablock => logger.write_string("BrotliInvalidMetablock")
    BrotliInvalidHuffman => logger.write_string("BrotliInvalidHuffman")
    BrotliInvalidContextMap => logger.write_string("BrotliInvalidContextMap")
    BrotliInvalidDistance => logger.write_string("BrotliInvalidDistance")
    BrotliInvalidTransform => logger.write_string("BrotliInvalidTransform")
    BrotliDictionaryNotSupported =>
      logger.write_string("BrotliDictionaryNotSupported")
    BrotliLargeWindowNotSupported =>
      logger.write_string("BrotliLargeWindowNotSupported")
    BrotliReserved => logger.write_string("BrotliReserved")
    BrotliInvalidPadding => logger.write_string("BrotliInvalidPadding")
  }
}

///|
let error_messages : Array[String] = [
  "unexpected EOF", "invalid UTF-8 data", "invalid input data", "invalid Brotli window bits",
  "invalid Brotli meta-block", "invalid Brotli Huffman tree", "invalid Brotli context map",
  "invalid Brotli distance", "invalid Brotli transform", "Brotli shared dictionary not supported",
  "Brotli large window not supported", "reserved Brotli bit pattern", "invalid Brotli padding",
]

///|
/// Error raised by Brotli decoding, decompression, and encoding APIs.
///
/// `code` is stable enough for branching in callers. `message` may include
/// additional context such as the failed format check.
pub(all) suberror FzipError {
  FzipError(code~ : FzipErrorCode, message~ : String)
}

///|
fn fzip_error_code_to_int(code : FzipErrorCode) -> Int {
  match code {
    UnexpectedEOF => 0
    InvalidUTF8 => 1
    InvalidZipData => 2
    BrotliInvalidWindowBits => 3
    BrotliInvalidMetablock => 4
    BrotliInvalidHuffman => 5
    BrotliInvalidContextMap => 6
    BrotliInvalidDistance => 7
    BrotliInvalidTransform => 8
    BrotliDictionaryNotSupported => 9
    BrotliLargeWindowNotSupported => 10
    BrotliReserved => 11
    BrotliInvalidPadding => 12
  }
}

///|
fn fzip_err(code : FzipErrorCode, msg? : String = "") -> FzipError {
  let message = if msg != "" {
    msg
  } else {
    error_messages[fzip_error_code_to_int(code)]
  }
  FzipError(code~, message~)
}

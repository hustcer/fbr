///|
/// Buffering convenience wrapper around `brotli_sync`.
///
/// Input chunks are buffered until the final push, then encoded with
/// `brotli_sync` and emitted through `ondata`. This is not a true incremental
/// Brotli encoder.
pub(all) struct BrotliStream {
  /// Called with compressed data when a final chunk is pushed.
  mut ondata : @common.FbrStreamHandler?
  priv opts : BrotliOptions
  priv mut chunks : Array[FixedArray[Byte]]
}

///|
/// Create a Brotli compression stream.
pub fn BrotliStream::new(
  opts? : BrotliOptions = BrotliOptions::default(),
) -> BrotliStream {
  { ondata: None, opts, chunks: [] }
}

///|
/// Set the output callback for a Brotli compression stream.
pub fn BrotliStream::set_ondata(
  self : BrotliStream,
  handler : (FixedArray[Byte], Bool) -> Unit,
) -> Unit {
  self.ondata = Some(@common.FbrStreamHandler(handler))
}

///|
/// Push one input chunk into the Brotli compression stream.
pub fn BrotliStream::push(
  self : BrotliStream,
  chunk : FixedArray[Byte],
  final_? : Bool = false,
) -> Unit raise @common.FbrError {
  self.chunks.push(chunk)
  if final_ {
    let data = @common.concat_chunks(self.chunks)
    let result = brotli_sync(data, opts=self.opts)
    match self.ondata {
      Some(h) => @common.call_handler(h, result, true)
      None => ()
    }
    self.chunks = []
  }
}

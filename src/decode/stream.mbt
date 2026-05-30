///|
/// Chunk-oriented Brotli decompressor.
///
/// Input chunks are buffered until the final push, then decoded with
/// `unbrotli_sync` and emitted through `ondata`.
pub(all) struct UnbrotliStream {
  /// Called with decompressed data when a final chunk is pushed.
  mut ondata : @common.FbrStreamHandler?
  priv opts : UnbrotliOptions
  priv mut chunks : Array[FixedArray[Byte]]
}

///|
/// Create a Brotli decompression stream.
pub fn UnbrotliStream::new(
  opts? : UnbrotliOptions = UnbrotliOptions::default(),
) -> UnbrotliStream {
  { ondata: None, opts, chunks: [] }
}

///|
/// Set the output callback for a Brotli decompression stream.
pub fn UnbrotliStream::set_ondata(
  self : UnbrotliStream,
  handler : (FixedArray[Byte], Bool) -> Unit,
) -> Unit {
  self.ondata = Some(@common.FbrStreamHandler(handler))
}

///|
/// Push one input chunk into the Brotli decompression stream.
pub fn UnbrotliStream::push(
  self : UnbrotliStream,
  chunk : FixedArray[Byte],
  final_? : Bool = false,
) -> Unit raise @common.FbrError {
  self.chunks.push(chunk)
  if final_ {
    let data = @common.concat_chunks(self.chunks)
    let result = unbrotli_sync(data, opts=self.opts)
    match self.ondata {
      Some(h) => @common.call_handler(h, result, true)
      None => ()
    }
    self.chunks = []
  }
}

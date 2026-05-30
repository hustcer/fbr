///|
/// Callback wrapper used by stream-style APIs.
///
/// The wrapped function receives `(data, is_final)`. `data` is the produced
/// output chunk and `is_final` is `true` for the final callback of a stream.
pub(all) struct FlateStreamHandler((FixedArray[Byte], Bool) -> Unit)

///|
fn call_handler(
  h : FlateStreamHandler,
  data : FixedArray[Byte],
  final_ : Bool,
) -> Unit {
  (h.0)(data, final_)
}

///|
fn concat_chunks(chunks : Array[FixedArray[Byte]]) -> FixedArray[Byte] {
  let mut total = 0
  for i in 0..<chunks.length() {
    total += chunks[i].length()
  }
  let data = FixedArray::make(total, b'\x00')
  let mut offset = 0
  for i in 0..<chunks.length() {
    let c = chunks[i]
    c.blit_to(data, len=c.length(), src_offset=0, dst_offset=offset)
    offset += c.length()
  }
  data
}

///|
/// Chunk-oriented Brotli decompressor.
///
/// Input chunks are buffered until the final push, then decoded with
/// `unbrotli_sync` and emitted through `ondata`.
pub(all) struct UnbrotliStream {
  /// Called with decompressed data when a final chunk is pushed.
  mut ondata : FlateStreamHandler?
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
/// Push one input chunk into the Brotli decompression stream.
pub fn UnbrotliStream::push(
  self : UnbrotliStream,
  chunk : FixedArray[Byte],
  final_? : Bool = false,
) -> Unit raise FzipError {
  self.chunks.push(chunk)
  if final_ {
    let data = concat_chunks(self.chunks)
    let result = unbrotli_sync(data, opts=self.opts)
    match self.ondata {
      Some(h) => call_handler(h, result, true)
      None => ()
    }
    self.chunks = []
  }
}

///|
/// Chunk-oriented Brotli compressor.
///
/// Input chunks are buffered until the final push, then encoded with
/// `brotli_sync` and emitted through `ondata`.
pub(all) struct BrotliStream {
  /// Called with compressed data when a final chunk is pushed.
  mut ondata : FlateStreamHandler?
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
/// Push one input chunk into the Brotli compression stream.
pub fn BrotliStream::push(
  self : BrotliStream,
  chunk : FixedArray[Byte],
  final_? : Bool = false,
) -> Unit raise FzipError {
  self.chunks.push(chunk)
  if final_ {
    let data = concat_chunks(self.chunks)
    let result = brotli_sync(data, opts=self.opts)
    match self.ondata {
      Some(h) => call_handler(h, result, true)
      None => ()
    }
    self.chunks = []
  }
}

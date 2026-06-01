///|
/// Incremental Brotli decompressor.
///
/// Input chunks are decoded as soon as complete Brotli meta-blocks are
/// available. Produced chunks are emitted through `ondata`.
pub(all) struct UnbrotliStream {
  /// Called with decompressed data as complete meta-blocks are decoded.
  mut ondata : @common.FbrStreamHandler?
  priv opts : UnbrotliOptions
  priv mut input : FixedArray[Byte]
  priv mut input_seen : Int
  priv mut reader : BrotliBitReader?
  priv mut output : BrotliOutputBuilder
  priv mut state : BrotliDecoderState?
  priv mut emitted_len : Int
  priv mut header_read : Bool
  priv mut finished : Bool
}

///|
/// Create a Brotli decompression stream.
pub fn UnbrotliStream::new(
  opts? : UnbrotliOptions = UnbrotliOptions::default(),
) -> UnbrotliStream {
  let stream_opts = {
    out: None,
    max_output_size: opts.max_output_size,
    max_input_size: opts.max_input_size,
  }
  {
    ondata: None,
    opts: stream_opts,
    input: FixedArray::make(0, b'\x00'),
    input_seen: 0,
    reader: None,
    output: BrotliOutputBuilder::new(stream_opts),
    state: None,
    emitted_len: 0,
    header_read: false,
    finished: false,
  }
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
  if self.finished {
    if chunk.length() > 0 {
      raise @common.fbr_err(
        InvalidZipData,
        msg="input after Brotli stream finished",
      )
    }
    return
  }
  if chunk.length() > self.opts.max_input_size - self.input_seen {
    raise @common.fbr_err(InvalidZipData, msg="input exceeds max_input_size")
  }
  self.input_seen += chunk.length()
  self.append_input(chunk)
  self.process_available(final_)
}

///|
fn UnbrotliStream::append_input(
  self : UnbrotliStream,
  chunk : FixedArray[Byte],
) -> Unit {
  if chunk.length() == 0 {
    return
  }
  let combined = FixedArray::make(self.input.length() + chunk.length(), b'\x00')
  if self.input.length() > 0 {
    self.input.blit_to(
      combined,
      len=self.input.length(),
      src_offset=0,
      dst_offset=0,
    )
  }
  chunk.blit_to(
    combined,
    len=chunk.length(),
    src_offset=0,
    dst_offset=self.input.length(),
  )
  self.input = combined
  match self.reader {
    Some(reader) => self.reader = Some(reader.with_buffer(self.input))
    None => ()
  }
}

///|
fn UnbrotliStream::process_available(
  self : UnbrotliStream,
  final_ : Bool,
) -> Unit raise @common.FbrError {
  if !self.header_read {
    let reader = BrotliBitReader::new(self.input, 0, self.input.length())
    let result : Result[Int, @common.FbrError] = try? brotli_decode_window_bits(
      reader,
    )
    match result {
      Ok(window_bits) => {
        brotli_validate_window_bits(window_bits)
        self.header_read = true
        self.reader = Some(reader)
        self.state = Some(BrotliDecoderState::new_with_window_bits(window_bits))
        self.compact_input()
      }
      Err(FbrError(code=UnexpectedEOF, ..)) =>
        if final_ {
          raise @common.fbr_err(UnexpectedEOF)
        } else {
          return
        }
      Err(e) => raise e
    }
  }
  while !self.finished {
    guard self.reader is Some(reader) else { return }
    guard self.state is Some(state) else { return }
    let trial_reader = reader.clone()
    let trial_output = self.output.clone()
    let trial_state = brotli_clone_decoder_state(state)
    let result : Result[Bool, @common.FbrError] = try? brotli_decode_next_metablock(
      trial_reader, trial_output, trial_state,
    )
    match result {
      Ok(done) => {
        let produced = trial_output.len > self.emitted_len
        self.reader = Some(trial_reader)
        self.output = trial_output
        self.state = Some(trial_state)
        self.emit_new_output(done)
        self.compact_input()
        if done {
          self.finished = true
          if !produced {
            self.emit_empty_final()
          }
          return
        }
      }
      Err(FbrError(code=UnexpectedEOF, ..)) =>
        if final_ {
          raise @common.fbr_err(UnexpectedEOF)
        } else {
          return
        }
      Err(e) => raise e
    }
  }
}

///|
fn UnbrotliStream::emit_new_output(
  self : UnbrotliStream,
  final_ : Bool,
) -> Unit {
  let length = self.output.len - self.emitted_len
  if length <= 0 {
    return
  }
  let chunk = FixedArray::make(length, b'\x00')
  self.output.buf.blit_to(
    chunk,
    len=length,
    src_offset=self.emitted_len,
    dst_offset=0,
  )
  self.emitted_len = self.output.len
  match self.ondata {
    Some(h) => @common.call_handler(h, chunk, final_)
    None => ()
  }
}

///|
fn UnbrotliStream::emit_empty_final(self : UnbrotliStream) -> Unit {
  match self.ondata {
    Some(h) => @common.call_handler(h, FixedArray::make(0, b'\x00'), true)
    None => ()
  }
}

///|
fn UnbrotliStream::compact_input(self : UnbrotliStream) -> Unit {
  guard self.reader is Some(reader) else { return }
  if reader.byte_pos == 0 ||
    (reader.byte_pos < self.input.length() / 2 && reader.byte_pos < 65536) {
    return
  }
  let remaining = self.input.length() - reader.byte_pos
  let compacted = FixedArray::make(remaining, b'\x00')
  if remaining > 0 {
    self.input.blit_to(
      compacted,
      len=remaining,
      src_offset=reader.byte_pos,
      dst_offset=0,
    )
  }
  self.input = compacted
  self.reader = Some({
    buf: self.input,
    byte_pos: 0,
    byte_end: self.input.length(),
    bit_buf: reader.bit_buf,
    bits_avail: reader.bits_avail,
  })
}

///|
fn brotli_clone_decoder_state(state : BrotliDecoderState) -> BrotliDecoderState {
  let distances = FixedArray::make(4, 0)
  for i in 0..<4 {
    distances[i] = state.distance_ring.distances[i]
  }
  {
    distance_ring: {
      distances,
      index: state.distance_ring.index,
      last_distance_context: state.distance_ring.last_distance_context,
    },
    max_backward_distance: state.max_backward_distance,
  }
}

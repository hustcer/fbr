///|
/// Callback wrapper used by stream-style APIs.
///
/// The wrapped function receives `(data, is_final)`. `data` is the produced
/// output chunk and `is_final` is `true` for the final callback of a stream.
pub(all) struct FbrStreamHandler((FixedArray[Byte], Bool) -> Unit)

///|
pub fn call_handler(
  h : FbrStreamHandler,
  data : FixedArray[Byte],
  final_ : Bool,
) -> Unit {
  (h.0)(data, final_)
}

///|
pub fn concat_chunks(chunks : Array[FixedArray[Byte]]) -> FixedArray[Byte] {
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

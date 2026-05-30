///|
/// 15-bit reversal table (32768 entries).
///
/// Shared canonical-Huffman support used by `brotli_reverse_bits` to map a
/// forward code to its reversed bit order.
pub let rev : FixedArray[Int] = {
  let t : FixedArray[Int] = FixedArray::make(32768, 0)
  for i in 0..<32768 {
    let mut x = ((i & 0xAAAA) >> 1) | ((i & 0x5555) << 1)
    x = ((x & 0xCCCC) >> 2) | ((x & 0x3333) << 2)
    x = ((x & 0xF0F0) >> 4) | ((x & 0x0F0F) << 4)
    t[i] = (((x & 0xFF00) >> 8) | ((x & 0x00FF) << 8)) >> 1
  }
  t
}

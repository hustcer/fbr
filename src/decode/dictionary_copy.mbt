///|
fn BrotliOutputBuilder::copy_from_dictionary_after_max_distance(
  self : BrotliOutputBuilder,
  distance : Int,
  length : Int,
  max_distance : Int,
) -> Unit raise @common.FbrError {
  if length < @common.brotli_dictionary_min_word_length ||
    length > @common.brotli_dictionary_max_word_length {
    raise @common.fbr_err(
      BrotliInvalidDistance,
      msg="Brotli dictionary length out of range",
    )
  }
  let size_bits = @common.brotli_dictionary_size_bits_by_length[length]
  if size_bits == 0 {
    raise @common.fbr_err(
      BrotliInvalidDistance,
      msg="Brotli dictionary bucket is empty",
    )
  }
  let address = distance - max_distance - 1
  if address < 0 {
    raise @common.fbr_err(
      BrotliInvalidDistance,
      msg="negative Brotli dictionary address",
    )
  }
  let word_mask = (1 << size_bits) - 1
  let word_index = address & word_mask
  let transform_index = address >> size_bits
  if transform_index < 0 || transform_index >= @common.brotli_transform_count() {
    raise @common.fbr_err(
      @common.BrotliInvalidTransform,
      msg="Brotli transform index out of range index=\{transform_index} count=\{@common.brotli_transform_count()} distance=\{distance} max_distance=\{max_distance} output_len=\{self.len} length=\{length} address=\{address}",
    )
  }
  let offset = @common.brotli_dictionary_offsets_by_length[length] +
    word_index * length
  if offset < 0 || offset > @common.brotli_dictionary_data.length() - length {
    raise @common.fbr_err(
      BrotliInvalidDistance,
      msg="Brotli dictionary address out of range",
    )
  }
  self.copy_transformed_dictionary_word(offset, length, transform_index)
}

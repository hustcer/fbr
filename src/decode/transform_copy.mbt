///|
fn BrotliOutputBuilder::copy_transformed_dictionary_word(
  self : BrotliOutputBuilder,
  word_offset : Int,
  word_length : Int,
  transform_index : Int,
) -> Unit raise @common.FbrError {
  if transform_index < 0 || transform_index >= @common.brotli_transform_count() {
    raise @common.fbr_err(
      BrotliInvalidTransform,
      msg="Brotli transform index out of range",
    )
  }
  let triplet_offset = transform_index * 3
  let prefix_id = @common.brotli_transform_triplets[triplet_offset]
  let transform_type = @common.brotli_transform_triplets[triplet_offset + 1]
  let suffix_id = @common.brotli_transform_triplets[triplet_offset + 2]
  if transform_type == @common.brotli_transform_shift_first ||
    transform_type == @common.brotli_transform_shift_all {
    raise @common.fbr_err(
      BrotliInvalidTransform,
      msg="Brotli shift transform is not supported",
    )
  }
  let prefix_offset = @common.brotli_transform_string_offset(prefix_id)
  let prefix_length = @common.brotli_transform_string_length(prefix_id)
  let suffix_offset = @common.brotli_transform_string_offset(suffix_id)
  let suffix_length = @common.brotli_transform_string_length(suffix_id)
  let mut source_offset = word_offset
  let mut source_length = word_length
  if transform_type <= @common.brotli_transform_omit_last_9 {
    source_length -= transform_type
  } else if transform_type >= @common.brotli_transform_omit_first_1 &&
    transform_type <= @common.brotli_transform_omit_first_9 {
    let skip = transform_type - (@common.brotli_transform_omit_first_1 - 1)
    source_offset += skip
    source_length -= skip
  } else if transform_type != @common.brotli_transform_uppercase_first &&
    transform_type != @common.brotli_transform_uppercase_all &&
    transform_type != @common.brotli_transform_identity {
    raise @common.fbr_err(
      @common.BrotliInvalidTransform,
      msg="unknown Brotli transform",
    )
  }
  if source_length < 0 {
    raise @common.fbr_err(
      BrotliInvalidTransform,
      msg="Brotli transform omits too much",
    )
  }
  self.ensure(prefix_length + source_length + suffix_length)
  @common.brotli_transform_prefix_suffix.blit_to(
    self.buf,
    len=prefix_length,
    src_offset=prefix_offset + 1,
    dst_offset=self.len,
  )
  self.len += prefix_length
  let word_output_offset = self.len
  @common.brotli_dictionary_data.blit_to(
    self.buf,
    len=source_length,
    src_offset=source_offset,
    dst_offset=self.len,
  )
  self.len += source_length
  if transform_type == @common.brotli_transform_uppercase_first {
    @common.brotli_uppercase_first(self.buf, word_output_offset, source_length)
  } else if transform_type == @common.brotli_transform_uppercase_all {
    @common.brotli_uppercase_all(self.buf, word_output_offset, source_length)
  }
  @common.brotli_transform_prefix_suffix.blit_to(
    self.buf,
    len=suffix_length,
    src_offset=suffix_offset + 1,
    dst_offset=self.len,
  )
  self.len += suffix_length
}

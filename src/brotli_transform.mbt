///|
let brotli_transform_identity : Int = 0

///|
let brotli_transform_omit_last_9 : Int = 9

///|
let brotli_transform_uppercase_first : Int = 10

///|
let brotli_transform_uppercase_all : Int = 11

///|
let brotli_transform_omit_first_1 : Int = 12

///|
let brotli_transform_omit_first_9 : Int = 20

///|
let brotli_transform_shift_first : Int = 21

///|
let brotli_transform_shift_all : Int = 22

///|
fn brotli_transform_count() -> Int {
  brotli_transform_triplets.length() / 3
}

///|
fn brotli_transform_string_offset(id : Int) -> Int raise FzipError {
  if id < 0 || id >= brotli_transform_prefix_suffix_map.length() {
    raise fzip_err(
      BrotliInvalidTransform,
      msg="Brotli transform string id out of range",
    )
  }
  let offset = brotli_transform_prefix_suffix_map[id]
  if offset < 0 || offset >= brotli_transform_prefix_suffix.length() {
    raise fzip_err(
      BrotliInvalidTransform,
      msg="Brotli transform string out of range",
    )
  }
  offset
}

///|
fn brotli_transform_string_length(id : Int) -> Int raise FzipError {
  brotli_transform_prefix_suffix[brotli_transform_string_offset(id)].to_int()
}

///|
fn brotli_ascii_upper(byte : Byte) -> Byte {
  let value = byte.to_int()
  if value >= 97 && value <= 122 {
    (value - 32).to_byte()
  } else {
    byte
  }
}

///|
fn brotli_uppercase_first(
  buf : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  if length <= 0 {
    return
  }
  let first = buf[offset].to_int()
  if first < 0xc0 {
    buf[offset] = brotli_ascii_upper(buf[offset])
  } else if first < 0xe0 && length >= 2 {
    buf[offset + 1] = (buf[offset + 1].to_int() ^ 32).to_byte()
  } else if length >= 3 {
    buf[offset + 2] = (buf[offset + 2].to_int() ^ 5).to_byte()
  }
}

///|
fn brotli_uppercase_all(
  buf : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  let mut index = offset
  let end = offset + length
  while index < end {
    let first = buf[index].to_int()
    let step = if first < 0xc0 {
      buf[index] = brotli_ascii_upper(buf[index])
      1
    } else if first < 0xe0 {
      if index + 1 < end {
        buf[index + 1] = (buf[index + 1].to_int() ^ 32).to_byte()
      }
      2
    } else {
      if index + 2 < end {
        buf[index + 2] = (buf[index + 2].to_int() ^ 5).to_byte()
      }
      3
    }
    index += step
  }
}

///|
fn BrotliOutputBuilder::copy_transformed_dictionary_word(
  self : BrotliOutputBuilder,
  word_offset : Int,
  word_length : Int,
  transform_index : Int,
) -> Unit raise FzipError {
  if transform_index < 0 || transform_index >= brotli_transform_count() {
    raise fzip_err(
      BrotliInvalidTransform,
      msg="Brotli transform index out of range",
    )
  }
  let triplet_offset = transform_index * 3
  let prefix_id = brotli_transform_triplets[triplet_offset]
  let transform_type = brotli_transform_triplets[triplet_offset + 1]
  let suffix_id = brotli_transform_triplets[triplet_offset + 2]
  if transform_type == brotli_transform_shift_first ||
    transform_type == brotli_transform_shift_all {
    raise fzip_err(
      BrotliInvalidTransform,
      msg="Brotli shift transform is not supported",
    )
  }
  let prefix_offset = brotli_transform_string_offset(prefix_id)
  let prefix_length = brotli_transform_string_length(prefix_id)
  let suffix_offset = brotli_transform_string_offset(suffix_id)
  let suffix_length = brotli_transform_string_length(suffix_id)
  let mut source_offset = word_offset
  let mut source_length = word_length
  if transform_type <= brotli_transform_omit_last_9 {
    source_length -= transform_type
  } else if transform_type >= brotli_transform_omit_first_1 &&
    transform_type <= brotli_transform_omit_first_9 {
    let skip = transform_type - (brotli_transform_omit_first_1 - 1)
    source_offset += skip
    source_length -= skip
  } else if transform_type != brotli_transform_uppercase_first &&
    transform_type != brotli_transform_uppercase_all &&
    transform_type != brotli_transform_identity {
    raise fzip_err(BrotliInvalidTransform, msg="unknown Brotli transform")
  }
  if source_length < 0 {
    raise fzip_err(
      BrotliInvalidTransform,
      msg="Brotli transform omits too much",
    )
  }
  self.ensure(prefix_length + source_length + suffix_length)
  brotli_transform_prefix_suffix.blit_to(
    self.buf,
    len=prefix_length,
    src_offset=prefix_offset + 1,
    dst_offset=self.len,
  )
  self.len += prefix_length
  let word_output_offset = self.len
  brotli_dictionary_data.blit_to(
    self.buf,
    len=source_length,
    src_offset=source_offset,
    dst_offset=self.len,
  )
  self.len += source_length
  if transform_type == brotli_transform_uppercase_first {
    brotli_uppercase_first(self.buf, word_output_offset, source_length)
  } else if transform_type == brotli_transform_uppercase_all {
    brotli_uppercase_all(self.buf, word_output_offset, source_length)
  }
  brotli_transform_prefix_suffix.blit_to(
    self.buf,
    len=suffix_length,
    src_offset=suffix_offset + 1,
    dst_offset=self.len,
  )
  self.len += suffix_length
}

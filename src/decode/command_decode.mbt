///|
/// A decoded Brotli command. Fields are mutable so the meta-block loop can
/// reuse a single instance across every command (filling it in place via
/// `read_into`) instead of heap-allocating one per command — the decode loop
/// runs this once per match, so eliminating the per-command allocation removes
/// a `malloc`/GC cost from the hot path.
priv struct BrotliCommand {
  mut insert_length : Int
  mut copy_length : Int
  mut distance_code : Int
  mut distance_context : Int
}

///|
/// Decode one command from `command_tree` into `self`, overwriting all four
/// fields. The caller reuses the same `BrotliCommand` every iteration, so this
/// performs no allocation.
fn BrotliCommand::read_into(
  self : BrotliCommand,
  reader : BrotliBitReader,
  command_tree : FixedArray[Int],
) -> Unit raise @common.FbrError {
  let symbol = brotli_read_symbol(
    reader, command_tree, @common.brotli_huffman_table_bits,
  )
  let info = @common.brotli_command_info_table[symbol]
  let insert_extra = if info.insert_len_extra_bits == 0 {
    0
  } else {
    reader.take_bits(info.insert_len_extra_bits).reinterpret_as_int()
  }
  let copy_extra = if info.copy_len_extra_bits == 0 {
    0
  } else {
    reader.take_bits(info.copy_len_extra_bits).reinterpret_as_int()
  }
  self.insert_length = info.insert_len_offset + insert_extra
  self.copy_length = info.copy_len_offset + copy_extra
  self.distance_code = info.distance_code
  self.distance_context = info.distance_context
}

///|
fn brotli_decode_compressed_metablock_body(
  reader : BrotliBitReader,
  header : BrotliCompressedMetablockHeader,
  output : BrotliOutputBuilder,
  length : Int,
  state : BrotliDecoderState,
) -> Unit raise @common.FbrError {
  let literal_blocks = BrotliBlockTracker::new_with_length(
    header.literal_block.num_types,
    header.literal_block.first_length,
  )
  let command_blocks = BrotliBlockTracker::new_with_length(
    header.command_block.num_types,
    header.command_block.first_length,
  )
  let distance_blocks = BrotliBlockTracker::new_with_length(
    header.distance_block.num_types,
    header.distance_block.first_length,
  )
  // When the literal context map resolves to a single Huffman tree, every
  // literal decodes from that one tree regardless of context. Detect this once
  // per meta-block so the inner loop can skip the per-literal context-id and
  // context-map work entirely (the dominant cost for low-quality streams, which
  // are literal-heavy and almost always single-tree). `tree(0)` is always valid
  // because the tree group is built with at least one tree.
  let single_literal_tree = header.literal_context_map.num_trees == 1
  let literal_tree0 = header.literal_trees.tree(0)
  // When the literal side also has a single block type there are no literal
  // block-switch commands in the stream, so the inner loop can drop the
  // per-byte `ensure_ready` call and `remaining` bookkeeping entirely. This is
  // the dominant shape for literal-heavy low-quality streams.
  let single_literal_block = single_literal_tree &&
    header.literal_block.num_types == 1
  // Reuse one command record for the whole meta-block; `read_into` overwrites
  // every field each iteration, so the loop performs no per-command allocation.
  let command = BrotliCommand::{
    insert_length: 0,
    copy_length: 0,
    distance_code: 0,
    distance_context: 0,
  }
  let mut remaining = length
  while remaining > 0 {
    command_blocks.ensure_ready(reader, header.command_block)
    command.read_into(
      reader,
      header.command_trees.tree(command_blocks.current_type),
    )
    command_blocks.remaining -= 1
    if command.insert_length > remaining {
      raise @common.fbr_err(
        BrotliInvalidMetablock,
        msg="Brotli insert length exceeds meta-block",
      )
    }
    output.ensure(command.insert_length)
    if single_literal_tree {
      // Fast path: the literal context map has a single tree, so every literal
      // decodes from `literal_tree0` regardless of context. Skip the per-byte
      // context-id, context-map lookup and tree indexing entirely, and write
      // straight into the buffer through locals (`ensure` reserved the run).
      let buf = output.buf
      let mut pos = output.len
      if single_literal_block {
        // Tightest path: one tree and one block type, so there are no literal
        // block-switch commands to consume — drop the per-byte `ensure_ready`
        // call and `remaining` decrement.
        for _ in 0..<command.insert_length {
          let literal = brotli_read_symbol(
            reader, literal_tree0, @common.brotli_huffman_table_bits,
          )
          if literal < 0 || literal > 255 {
            raise @common.fbr_err(
              BrotliInvalidMetablock,
              msg="Brotli literal out of byte range",
            )
          }
          buf[pos] = literal.to_byte()
          pos += 1
        }
      } else {
        for _ in 0..<command.insert_length {
          literal_blocks.ensure_ready(reader, header.literal_block)
          let literal = brotli_read_symbol(
            reader, literal_tree0, @common.brotli_huffman_table_bits,
          )
          if literal < 0 || literal > 255 {
            raise @common.fbr_err(
              BrotliInvalidMetablock,
              msg="Brotli literal out of byte range",
            )
          }
          buf[pos] = literal.to_byte()
          pos += 1
          literal_blocks.remaining -= 1
        }
      }
      output.len = pos
    } else {
      // General path: multiple literal trees. Track the two context bytes in
      // registers and index the context map directly. The explicit bounds
      // checks in `brotli_context_map_tree_index` are dead here because header
      // parsing guarantees `current_type < num_types`, the context fits in
      // `literal_context_bits`, and every map value was validated `< num_trees`;
      // `tree()` still bounds-checks the resulting index.
      let buf = output.buf
      let mut pos = output.len
      let lit_map = header.literal_context_map.map
      let mut prev1 = if pos > 0 { buf[pos - 1].to_int() } else { 0 }
      let mut prev2 = if pos > 1 { buf[pos - 2].to_int() } else { 0 }
      for _ in 0..<command.insert_length {
        literal_blocks.ensure_ready(reader, header.literal_block)
        let ct = literal_blocks.current_type
        let literal_context = @common.brotli_literal_context_id(
          header.context_modes[ct].to_int(),
          prev1,
          prev2,
        )
        let tree_index = lit_map[(ct << @common.brotli_literal_context_bits) +
        literal_context].to_int()
        let literal = brotli_read_symbol(
          reader,
          header.literal_trees.tree(tree_index),
          @common.brotli_huffman_table_bits,
        )
        if literal < 0 || literal > 255 {
          raise @common.fbr_err(
            BrotliInvalidMetablock,
            msg="Brotli literal out of byte range",
          )
        }
        buf[pos] = literal.to_byte()
        pos += 1
        prev2 = prev1
        prev1 = literal
        literal_blocks.remaining -= 1
      }
      output.len = pos
    }
    remaining -= command.insert_length
    if remaining == 0 {
      return
    }
    let distance = if command.distance_code >= 0 {
      brotli_take_short_code_validated(
        state.distance_ring,
        command.distance_code,
      )
    } else {
      distance_blocks.ensure_ready(reader, header.distance_block)
      let distance_tree_index = brotli_context_map_tree_index(
        header.distance_context_map,
        distance_blocks.current_type,
        @common.brotli_distance_context_bits,
        command.distance_context,
      )
      let distance_tree = header.distance_trees.tree(distance_tree_index)
      distance_blocks.remaining -= 1
      brotli_read_distance(
        reader,
        distance_tree,
        state.distance_ring,
        header.distance_postfix_bits,
        header.num_direct_distance_codes,
      )
    }
    let output_before_copy = output.len
    let max_distance = state.max_distance(output.len)
    if distance <= max_distance {
      output.copy_from_distance(distance, command.copy_length)
      state.distance_ring.record(distance)
    } else {
      state.distance_ring.compensate_dictionary_copy()
      output.copy_from_dictionary_after_max_distance(
        distance,
        command.copy_length,
        max_distance,
      )
    }
    let copied = output.len - output_before_copy
    if copied > remaining {
      raise @common.fbr_err(
        BrotliInvalidMetablock,
        msg="Brotli copy length exceeds meta-block",
      )
    }
    remaining -= copied
  }
}

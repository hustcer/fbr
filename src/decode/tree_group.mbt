///|
priv struct BrotliHuffmanTreeGroup {
  trees : Array[FixedArray[Int]]
}

///|
fn BrotliHuffmanTreeGroup::tree(
  self : BrotliHuffmanTreeGroup,
  index : Int,
) -> FixedArray[Int] {
  self.trees[index]
}

///|
fn brotli_read_huffman_tree_group(
  reader : BrotliBitReader,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
  num_trees : Int,
  root_bits : Int,
) -> BrotliHuffmanTreeGroup raise @common.FbrError {
  if num_trees < 1 {
    raise @common.fbr_err(
      @common.BrotliInvalidHuffman,
      msg="empty Brotli Huffman tree group",
    )
  }
  if alphabet_size_limit < 1 || alphabet_size_max < alphabet_size_limit {
    raise @common.fbr_err(
      @common.BrotliInvalidHuffman,
      msg="invalid Brotli Huffman tree group alphabet",
    )
  }
  let trees : Array[FixedArray[Int]] = []
  for _ in 0..<num_trees {
    trees.push(
      brotli_read_huffman_code(
        reader, alphabet_size_max, alphabet_size_limit, root_bits,
      ),
    )
  }
  { trees, }
}

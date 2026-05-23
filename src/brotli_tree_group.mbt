///|
priv struct BrotliHuffmanTreeGroup {
  alphabet_size_max : Int
  alphabet_size_limit : Int
  root_bits : Int
  trees : Array[FixedArray[BrotliHuffmanCode]]
}

///|
fn BrotliHuffmanTreeGroup::num_trees(self : BrotliHuffmanTreeGroup) -> Int {
  self.trees.length()
}

///|
fn BrotliHuffmanTreeGroup::tree(
  self : BrotliHuffmanTreeGroup,
  index : Int,
) -> FixedArray[BrotliHuffmanCode] raise FzipError {
  if index < 0 || index >= self.trees.length() {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="Brotli tree group index out of range",
    )
  }
  self.trees[index]
}

///|
fn brotli_read_huffman_tree_group(
  reader : BrotliBitReader,
  alphabet_size_max : Int,
  alphabet_size_limit : Int,
  num_trees : Int,
  root_bits : Int,
) -> BrotliHuffmanTreeGroup raise FzipError {
  if num_trees < 1 {
    raise fzip_err(BrotliInvalidHuffman, msg="empty Brotli Huffman tree group")
  }
  if alphabet_size_limit < 1 || alphabet_size_max < alphabet_size_limit {
    raise fzip_err(
      BrotliInvalidHuffman,
      msg="invalid Brotli Huffman tree group alphabet",
    )
  }
  let trees : Array[FixedArray[BrotliHuffmanCode]] = []
  for _ in 0..<num_trees {
    trees.push(
      brotli_read_huffman_code(
        reader, alphabet_size_max, alphabet_size_limit, root_bits,
      ),
    )
  }
  { alphabet_size_max, alphabet_size_limit, root_bits, trees }
}

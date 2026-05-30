// Canonical-Huffman code-length construction shared from the original fzip
// DEFLATE core. The Brotli encoder reuses this length-limited Huffman builder
// (`h_tree`) and the code-length cost helper (`clen`) to size its Huffman
// payloads. These helpers are encoder-only within fbr.

///|
/// Recursively get max depth and assign code lengths using implicit array tree
fn ln_node(
  node_idx : Int,
  s_arr : FixedArray[Int],
  l_arr : FixedArray[Int],
  r_arr : FixedArray[Int],
  lengths : FixedArray[Int],
  d : Int,
) -> Int {
  if s_arr[node_idx] == -1 {
    let left = l_arr[node_idx]
    let right = r_arr[node_idx]
    let left_max = if left != -1 {
      ln_node(left, s_arr, l_arr, r_arr, lengths, d + 1)
    } else {
      d
    }
    let right_max = if right != -1 {
      ln_node(right, s_arr, l_arr, r_arr, lengths, d + 1)
    } else {
      d
    }
    if left_max > right_max {
      left_max
    } else {
      right_max
    }
  } else {
    lengths[s_arr[node_idx]] = d
    d
  }
}

///|
let h_tree_s_pool : Array[FixedArray[Int]] = []

///|
let h_tree_f_pool : Array[FixedArray[Int]] = []

///|
let h_tree_l_pool : Array[FixedArray[Int]] = []

///|
let h_tree_r_pool : Array[FixedArray[Int]] = []

///|
/// Create code lengths from a frequency table
/// d: frequency table, mb: max allowed bits
/// Returns (t: code lengths, l: max bits used)
fn h_tree(d : FixedArray[Int], mb : Int) -> (FixedArray[Byte], Int) {
  let et : FixedArray[Byte] = FixedArray::make(0, b'\x00')
  let s_arr = match h_tree_s_pool.pop() {
    Some(arr) => arr
    None => FixedArray::make(600, 0)
  }
  let f_arr = match h_tree_f_pool.pop() {
    Some(arr) => arr
    None => FixedArray::make(600, 0)
  }
  let l_arr = match h_tree_l_pool.pop() {
    Some(arr) => arr
    None => FixedArray::make(600, -1)
  }
  let r_arr = match h_tree_r_pool.pop() {
    Some(arr) => arr
    None => FixedArray::make(600, -1)
  }
  let nodes : Array[Int] = []
  let mut next_node_idx = 0
  for i in 0..<d.length() {
    if d[i] != 0 {
      s_arr[next_node_idx] = i
      f_arr[next_node_idx] = d[i]
      l_arr[next_node_idx] = -1
      r_arr[next_node_idx] = -1
      nodes.push(next_node_idx)
      next_node_idx += 1
    }
  }
  let s = nodes.length()
  let t2 : Array[Int] = []
  for i in 0..<s {
    t2.push(nodes[i])
  }
  if s == 0 {
    h_tree_s_pool.push(s_arr)
    h_tree_f_pool.push(f_arr)
    h_tree_l_pool.push(l_arr)
    h_tree_r_pool.push(r_arr)
    return (et, 0)
  }
  if s == 1 {
    let node_idx = nodes[0]
    let symbol = s_arr[node_idx]
    let v : FixedArray[Byte] = FixedArray::make(symbol + 1, b'\x00')
    v[symbol] = b'\x01'
    h_tree_s_pool.push(s_arr)
    h_tree_f_pool.push(f_arr)
    h_tree_l_pool.push(l_arr)
    h_tree_r_pool.push(r_arr)
    return (v, 1)
  }
  // Sort by frequency
  nodes.sort_by(fn(a, b) { f_arr[a] - f_arr[b] })
  // sentinel
  s_arr[next_node_idx] = -1
  f_arr[next_node_idx] = 1 << 30
  l_arr[next_node_idx] = -1
  r_arr[next_node_idx] = -1
  nodes.push(next_node_idx)
  next_node_idx += 1
  let l_node_idx = nodes[0]
  let r_node_idx = nodes[1]
  s_arr[next_node_idx] = -1
  f_arr[next_node_idx] = f_arr[l_node_idx] + f_arr[r_node_idx]
  l_arr[next_node_idx] = l_node_idx
  r_arr[next_node_idx] = r_node_idx
  nodes[0] = next_node_idx
  next_node_idx += 1
  let mut i0 = 0
  let mut i1 = 1
  let mut i2 = 2
  while i1 != s - 1 {
    let left = if f_arr[nodes[i0]] < f_arr[nodes[i2]] {
      let n = nodes[i0]
      i0 += 1
      n
    } else {
      let n = nodes[i2]
      i2 += 1
      n
    }
    let right = if i0 != i1 && f_arr[nodes[i0]] < f_arr[nodes[i2]] {
      let n = nodes[i0]
      i0 += 1
      n
    } else {
      let n = nodes[i2]
      i2 += 1
      n
    }
    s_arr[next_node_idx] = -1
    f_arr[next_node_idx] = f_arr[left] + f_arr[right]
    l_arr[next_node_idx] = left
    r_arr[next_node_idx] = right
    nodes[i1] = next_node_idx
    next_node_idx += 1
    i1 += 1
  }
  // Find max symbol
  let mut max_sym = s_arr[t2[0]]
  for i in 1..<s {
    if s_arr[t2[i]] > max_sym {
      max_sym = s_arr[t2[i]]
    }
  }
  // Compute code lengths
  let tr : FixedArray[Int] = FixedArray::make(max_sym + 1, 0)
  let mut mbt = ln_node(nodes[i1 - 1], s_arr, l_arr, r_arr, tr, 0)
  if mbt > mb {
    // Limit code lengths to mb
    let mut i = 0
    let mut dt = 0
    let lft = mbt - mb
    let cst = 1 << lft
    // Sort by code length desc, then frequency asc
    t2.sort_by(fn(a, b) {
      if tr[s_arr[b]] != tr[s_arr[a]] {
        tr[s_arr[b]] - tr[s_arr[a]]
      } else {
        f_arr[a] - f_arr[b]
      }
    })
    while i < s {
      let i2v = s_arr[t2[i]]
      if tr[i2v] > mb {
        dt += cst - (1 << (mbt - tr[i2v]))
        tr[i2v] = mb
        i += 1
      } else {
        break
      }
    }
    dt = dt >> lft
    while dt > 0 {
      let i2v = s_arr[t2[i]]
      if tr[i2v] < mb {
        dt -= 1 << (mb - tr[i2v] - 1)
        tr[i2v] = tr[i2v] + 1
      } else {
        i += 1
      }
    }
    // i >= 0 check
    while i > 0 && dt < 0 {
      i -= 1
      let i2v = s_arr[t2[i]]
      if tr[i2v] == mb {
        tr[i2v] = tr[i2v] - 1
        dt += 1
      }
    }
    mbt = mb
  }
  h_tree_s_pool.push(s_arr)
  h_tree_f_pool.push(f_arr)
  h_tree_l_pool.push(l_arr)
  h_tree_r_pool.push(r_arr)
  // Convert to byte array
  let result : FixedArray[Byte] = FixedArray::make(max_sym + 1, b'\x00')
  for i in 0..<=max_sym {
    result[i] = tr[i].to_byte()
  }
  (result, mbt)
}

///|
/// Sum of `cf[i] * cl[i]` — the total bit cost of a code-length assignment.
fn clen(cf : FixedArray[Int], cl : FixedArray[Byte]) -> Int {
  let mut l = 0
  for i in 0..<cl.length() {
    if i < cf.length() {
      l += cf[i] * cl[i].to_int()
    }
  }
  l
}

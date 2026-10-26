///|
/// All supported coders have one output; BCJ2 consumes four inputs. Indices in
/// bindings are global input/output stream indices, not coder positions.
priv struct Layout {
  nodes : Array[Coder]
  input_counts : Array[Int32]
  input_offsets : Array[Int32]
  bindings : Array[Int32]
  packed : Array[Int32]
  order : Array[Int32]
  sizes : Array[Int32]
  final_output : Int32
  mut pack_start : Int32
}

///|
fn Layout::ordered_coders(self : Layout) -> Array[Coder] {
  self.order.map(i => self.nodes[i])
}

///|
fn read_node(r : Cursor) -> (Coder, Int32) raise ArchiveError {
  let flags = r.byte()
  let width = flags & 15
  guard width > 0 && width <= 8 && (flags & 0xc0) == 0 else {
    raise Invalid(
      offset=r.pos - 1,
      reason="invalid coder flags or method ID length",
    )
  }
  let codec_id = r.take(width)
  let (inputs, outputs) = if (flags & 0x10) == 0 {
    (1UL, 1UL)
  } else {
    (r.number(), r.number())
  }
  let properties = if (flags & 0x20) == 0 {
    b""
  } else {
    r.take(r.count(64, "coder properties"))
  }
  let coder : Coder = { codec_id, properties, }
  validate_coder(coder)
  let expected = if codec_id == b"\x03\x03\x01\x1b" { 4 } else { 1 }
  guard inputs == expected.to_uint64() && outputs == 1UL else {
    raise Invalid(
      offset=r.pos,
      reason="declared stream count differs from codec arity",
    )
  }
  (coder, expected)
}

///|
fn read_pipeline(
  r : Cursor,
  limits~ : Limits = Limits::new(),
) -> Layout raise ArchiveError {
  let count = r.count(limits.coders, "coders per folder")
  guard count > 0 else {
    raise Invalid(offset=r.pos, reason="folder has no coders")
  }
  let nodes : Array[Coder] = []
  let input_counts : Array[Int32] = []
  let input_offsets : Array[Int32] = []
  let mut total_inputs = 0
  for _ in 0..<count {
    let (coder, inputs) = read_node(r)
    nodes.push(coder)
    input_counts.push(inputs)
    input_offsets.push(total_inputs)
    total_inputs += inputs
  }
  let bindings = Array::make(total_inputs, -1)
  let used_outputs = Array::make(count, false)
  for _ in 0..<(count - 1) {
    let input = r.count(total_inputs - 1, "bind input index")
    let output = r.count(count - 1, "bind output index")
    guard bindings[input] == -1 && !used_outputs[output] else {
      raise Invalid(offset=r.pos, reason="duplicate coder binding")
    }
    bindings[input] = output
    used_outputs[output] = true
  }
  let packed_count = total_inputs - count + 1
  let packed : Array[Int32] = []
  if packed_count == 1 {
    for input in 0..<total_inputs {
      if bindings[input] == -1 {
        packed.push(input)
      }
    }
  } else {
    let used_inputs = Array::make(total_inputs, false)
    for _ in 0..<packed_count {
      let input = r.count(total_inputs - 1, "packed input index")
      guard bindings[input] == -1 && !used_inputs[input] else {
        raise Invalid(
          offset=r.pos,
          reason="duplicate or bound packed input index",
        )
      }
      used_inputs[input] = true
      packed.push(input)
    }
  }
  guard packed.length() == packed_count else {
    raise Invalid(offset=r.pos, reason="missing packed input")
  }
  let final_outputs = Array::makei(count, i => i).filter(i => !used_outputs[i])
  guard final_outputs.length() == 1 else {
    raise Invalid(offset=r.pos, reason="folder must have one final output")
  }
  let order : Array[Int32] = []
  let ready = Array::make(count, false)
  while order.length() < count {
    let mut progress = false
    for node in 0..<count {
      if ready[node] {
        continue
      }
      let start = input_offsets[node]
      let mut available = true
      for input in start..<(start + input_counts[node]) {
        if bindings[input] >= 0 && !ready[bindings[input]] {
          available = false
        }
      }
      if available {
        ready[node] = true
        order.push(node)
        progress = true
      }
    }
    guard progress else {
      raise Invalid(offset=r.pos, reason="cyclic or disconnected coder graph")
    }
  }
  guard order[order.length() - 1] == final_outputs[0] else {
    raise Invalid(
      offset=r.pos,
      reason="coder outputs do not converge on final stream",
    )
  }
  {
    nodes,
    input_counts,
    input_offsets,
    bindings,
    packed,
    order,
    sizes: Array::make(count, 0),
    final_output: final_outputs[0],
    pack_start: 0,
  }
}

///|
fn pack_range(streams : Streams, folder : Int32) -> (Int32, Int32) {
  if streams.layouts.is_empty() {
    (folder, 1)
  } else {
    let layout = streams.layouts[folder]
    (layout.pack_start, layout.packed.length())
  }
}

///|
fn packed_folder_bytes(streams : Streams, folder : Int32) -> Int32 {
  let (first, count) = pack_range(streams, folder)
  let mut bytes = 0
  for i in first..<(first + count) {
    bytes += streams.pack_sizes[i]
  }
  bytes
}

///|
fn graph_input_size(
  layout : Layout,
  input : Int32,
  packed_sizes : Array[Int32],
) -> Int32 {
  let source = layout.bindings[input]
  if source >= 0 {
    return layout.sizes[source]
  }
  for i, mapped in layout.packed {
    if mapped == input {
      return packed_sizes[layout.pack_start + i]
    }
  }
  abort("validated graph input has no source")
}

///|
fn validate_graph_sizes(
  layout : Layout,
  packed_sizes : Array[Int32],
) -> Unit raise ArchiveError {
  for node, coder in layout.nodes {
    let input = layout.input_offsets[node]
    if is_filter(coder.codec_id) || coder.codec_id == b"\x00" {
      guard layout.sizes[node] == graph_input_size(layout, input, packed_sizes) else {
        raise Invalid(
          offset=0,
          reason="length-preserving coder output sizes differ",
        )
      }
    } else if coder.codec_id == b"\x03\x03\x01\x1b" {
      let main = graph_input_size(layout, input, packed_sizes)
      let call = graph_input_size(layout, input + 1, packed_sizes)
      let jump = graph_input_size(layout, input + 2, packed_sizes)
      let control = graph_input_size(layout, input + 3, packed_sizes)
      guard call % 4 == 0 &&
        jump % 4 == 0 &&
        control >= 5 &&
        main.to_uint64() + call.to_uint64() + jump.to_uint64() ==
        layout.sizes[node].to_uint64() else {
        raise Invalid(
          offset=0,
          reason="BCJ2 stream sizes do not map to declared output",
        )
      }
    }
  }
}

///|
fn decode_graph(
  layout : Layout,
  packed : Array[Bytes],
  limits : Limits,
) -> Bytes raise ArchiveError {
  let inputs : Array[Bytes?] = Array::make(layout.bindings.length(), None)
  for i, input in layout.packed {
    inputs[input] = Some(packed[i])
  }
  let outputs : Array[Bytes?] = Array::make(layout.nodes.length(), None)
  for node in layout.order {
    let incoming : Array[Bytes] = []
    let first = layout.input_offsets[node]
    for input in first..<(first + layout.input_counts[node]) {
      let source = layout.bindings[input]
      incoming.push(
        if source < 0 {
          inputs[input].unwrap()
        } else {
          outputs[source].unwrap()
        },
      )
    }
    let coder = layout.nodes[node]
    let size = layout.sizes[node]
    let bytes = if coder.codec_id == b"\x03\x03\x01\x1b" {
      decode_bcj2(incoming, size)
    } else {
      let coders = if is_filter(coder.codec_id) {
        [{ codec_id: b"\x00", properties: b"", }, coder]
      } else {
        [coder]
      }
      decode({ coders, size, crc: None, pieces: [], }, incoming[0], limits)
    }
    for input in first..<(first + layout.input_counts[node]) {
      let source = layout.bindings[input]
      if source < 0 {
        inputs[input] = None
      } else {
        outputs[source] = None
      }
    }
    outputs[node] = Some(bytes)
  }
  outputs[layout.final_output].unwrap()
}

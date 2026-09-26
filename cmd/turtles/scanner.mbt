///|
struct OpSpec {
  group : OperatorGroup
  original : String
  replacement : String
}

///|
fn operator_specs() -> Array[OpSpec] {
  [
    { group: Comparison, original: "==", replacement: "!=", },
    { group: Comparison, original: "!=", replacement: "==", },
    { group: Comparison, original: ">=", replacement: "<", },
    { group: Comparison, original: "<=", replacement: ">", },
    { group: Boolean, original: "&&", replacement: "||", },
    { group: Boolean, original: "||", replacement: "&&", },
    { group: Literal, original: "true", replacement: "false", },
    { group: Literal, original: "false", replacement: "true", },
    { group: Arithmetic, original: "+", replacement: "-", },
    { group: Arithmetic, original: "-", replacement: "+", },
    { group: Arithmetic, original: "*", replacement: "/", },
    { group: Arithmetic, original: "/", replacement: "*", },
    { group: Comparison, original: ">", replacement: "<", },
    { group: Comparison, original: "<", replacement: ">", },
  ]
}

///|
fn bytes_starts(bytes : Bytes, index : Int, needle : Bytes) -> Bool {
  if index < 0 || index + needle.length() > bytes.length() {
    return false
  }
  let mut j = 0
  while j < needle.length() {
    if bytes[index + j] != needle[j] {
      return false
    }
    j = j + 1
  }
  true
}

///|
fn ident_byte(byte : Byte) -> Bool {
  byte == b'_' ||
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'A' && byte <= b'Z') ||
  (byte >= b'0' && byte <= b'9')
}

///|
fn word_start_boundary(bytes : Bytes, index : Int) -> Bool {
  index == 0 || !ident_byte(bytes[index - 1])
}

///|
fn word_end_boundary(bytes : Bytes, index : Int) -> Bool {
  index >= bytes.length() || !ident_byte(bytes[index])
}

///|
fn is_syntax_punctuation(bytes : Bytes, index : Int, token : String) -> Bool {
  match token {
    "-" => index + 1 < bytes.length() && bytes[index + 1] == b'>'
    ">" => index > 0 && bytes[index - 1] == b'-'
    "/" =>
      index + 1 < bytes.length() &&
      (bytes[index + 1] == b'/' || bytes[index + 1] == b'*')
    "*" => index > 0 && bytes[index - 1] == b'/'
    _ => false
  }
}

///|
fn advance_plain(
  bytes : Bytes,
  start : Int,
  line0 : Int,
  column0 : Int,
  width : Int,
) -> (Int, Int, Int) {
  let mut index = start
  let mut line = line0
  let mut column = column0
  let end = start + width
  while index < end && index < bytes.length() {
    if bytes[index] == b'\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
    index = index + 1
  }
  (index, line, column)
}

///|
fn advance_line_comment(
  bytes : Bytes,
  start : Int,
  line0 : Int,
  column0 : Int,
) -> (Int, Int, Int) {
  let mut index = start
  let mut line = line0
  let mut column = column0
  while index < bytes.length() {
    let byte = bytes[index]
    let next = advance_plain(bytes, index, line, column, 1)
    index = next.0
    line = next.1
    column = next.2
    if byte == b'\n' {
      break
    }
  }
  (index, line, column)
}

///|
fn advance_block_comment(
  bytes : Bytes,
  start : Int,
  line0 : Int,
  column0 : Int,
) -> (Int, Int, Int) {
  let first = advance_plain(bytes, start, line0, column0, 2)
  let mut index = first.0
  let mut line = first.1
  let mut column = first.2
  let mut depth = 1
  let open = @utf8.encode("/*")
  let close = @utf8.encode("*/")
  while index < bytes.length() && depth > 0 {
    if bytes_starts(bytes, index, open) {
      depth = depth + 1
      let next = advance_plain(bytes, index, line, column, 2)
      index = next.0
      line = next.1
      column = next.2
    } else if bytes_starts(bytes, index, close) {
      depth = depth - 1
      let next = advance_plain(bytes, index, line, column, 2)
      index = next.0
      line = next.1
      column = next.2
    } else {
      let next = advance_plain(bytes, index, line, column, 1)
      index = next.0
      line = next.1
      column = next.2
    }
  }
  (index, line, column)
}

///|
fn advance_quoted(
  bytes : Bytes,
  start : Int,
  line0 : Int,
  column0 : Int,
  quote : Byte,
) -> (Int, Int, Int) {
  let first = advance_plain(bytes, start, line0, column0, 1)
  let mut index = first.0
  let mut line = first.1
  let mut column = first.2
  while index < bytes.length() {
    if bytes[index] == b'\\' {
      let width = if index + 1 < bytes.length() { 2 } else { 1 }
      let next = advance_plain(bytes, index, line, column, width)
      index = next.0
      line = next.1
      column = next.2
      continue
    }
    let current = bytes[index]
    let next = advance_plain(bytes, index, line, column, 1)
    index = next.0
    line = next.1
    column = next.2
    if current == quote {
      break
    }
  }
  (index, line, column)
}

///|
fn scan_source(
  path : String,
  source : String,
  project_config : ProjectConfig,
) -> Array[Mutation] {
  let specs = operator_specs()
  let bytes = @utf8.encode(source)
  let slashslash = @utf8.encode("//")
  let slashstar = @utf8.encode("/*")
  let mutations : Array[Mutation] = []
  let mut index = 0
  let mut line = 1
  let mut column = 1
  while index < bytes.length() {
    if bytes_starts(bytes, index, slashslash) {
      let next = advance_line_comment(bytes, index, line, column)
      index = next.0
      line = next.1
      column = next.2
      continue
    }
    if bytes_starts(bytes, index, slashstar) {
      let next = advance_block_comment(bytes, index, line, column)
      index = next.0
      line = next.1
      column = next.2
      continue
    }
    if bytes[index] == b'"' || bytes[index] == b'\'' {
      let next = advance_quoted(bytes, index, line, column, bytes[index])
      index = next.0
      line = next.1
      column = next.2
      continue
    }

    let mut matched = false
    for spec in specs {
      if !project_config.operator_enabled(spec.group) {
        continue
      }
      let token = @utf8.encode(spec.original)
      if !bytes_starts(bytes, index, token) {
        continue
      }
      if (spec.original == "true" || spec.original == "false") &&
        (
          !word_start_boundary(bytes, index) ||
          !word_end_boundary(bytes, index + token.length())
        ) {
        continue
      }
      if is_syntax_punctuation(bytes, index, spec.original) {
        continue
      }
      mutations.push({
        path,
        start: index,
        end: index + token.length(),
        line,
        column,
        original: spec.original,
        replacement: spec.replacement,
      })
      let next = advance_plain(bytes, index, line, column, token.length())
      index = next.0
      line = next.1
      column = next.2
      matched = true
      break
    }
    if !matched {
      let next = advance_plain(bytes, index, line, column, 1)
      index = next.0
      line = next.1
      column = next.2
    }
  }
  mutations
}

///|
fn apply_mutation(source : String, mutation : Mutation) -> String raise {
  let bytes = @utf8.encode(source)
  guard mutation.start >= 0 &&
    mutation.end >= mutation.start &&
    mutation.end <= bytes.length() else {
    fail("mutation offsets are outside the source")
  }
  guard @utf8.decode(bytes[mutation.start:mutation.end]) == mutation.original else {
    fail("source changed after mutation discovery")
  }
  let output = @buffer.Buffer(
    size_hint=bytes.length() + mutation.replacement.length(),
  )
  output.write_bytes(bytes[:mutation.start])
  output.write_string_utf8(mutation.replacement)
  output.write_bytes(bytes[mutation.end:])
  @utf8.decode(output.to_bytes())
}

///|
fn describe_mutation(mutation : Mutation) -> String {
  "\{mutation.path}:\{mutation.line}:\{mutation.column}: \{mutation.original} -> \{mutation.replacement}"
}

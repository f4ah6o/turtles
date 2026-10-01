///|
/// Quote a string for the turtles.toml string-array subset, escaping the
/// bytes the configuration parser treats specially.
fn qc_quote_bytes(value : String) -> Bytes {
  let bytes = @utf8.encode(value)
  let out = @buffer.Buffer(size_hint=bytes.length() + 8)
  out.write_byte(b'"')
  for byte in bytes {
    match byte {
      b'"' => out.write_string_utf8("\\\"")
      b'\\' => out.write_string_utf8("\\\\")
      b'\n' => out.write_string_utf8("\\n")
      b'\r' => out.write_string_utf8("\\r")
      b'\t' => out.write_string_utf8("\\t")
      other => out.write_byte(other)
    }
  }
  out.write_byte(b'"')
  out.to_bytes()
}

///|
fn qc_config_bytes(values : Array[String]) -> Bytes {
  let out = @buffer.Buffer()
  for name in ["include", "exclude"] {
    out.write_string_utf8(name)
    out.write_string_utf8(" = [")
    for i, value in values {
      if i > 0 {
        out.write_string_utf8(", ")
      }
      out.write_bytes(qc_quote_bytes(value))
    }
    out.write_string_utf8("]\n")
  }
  out.to_bytes()
}

///|
fn qc_strings_equal(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i in 0..<left.length() {
    if left[i] != right[i] {
      return false
    }
  }
  true
}

///|
test "prop config string arrays round-trip" {
  @quickcheck.check((values : Array[String]) => {
    let source = @utf8.decode_lossy(qc_config_bytes(values)[:])
    let config = parse_project_config(source)
    qc_strings_equal(config.include_patterns, values) &&
    qc_strings_equal(config.exclude_patterns, values)
  })
}

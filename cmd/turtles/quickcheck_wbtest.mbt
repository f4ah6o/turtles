///|
/// Property-based tests for turtles' pure invariants, driven by the official
/// MoonBit QuickCheck (`moonbitlang/core/quickcheck`). Seeds are fixed so the
/// same cases run inside every mutated workspace during self-mutation.
fn qc_part(parts : Array[String], index : Int) -> String {
  if index < parts.length() {
    parts[index]
  } else {
    ""
  }
}

///|
fn qc_count(values : Array[Int], index : Int) -> Int {
  if index < values.length() {
    let value = values[index] % 1000
    if value < 0 {
      -value
    } else {
      value
    }
  } else {
    0
  }
}

///|
fn qc_outcome(code : Int) -> Outcome {
  match code % 4 {
    0 => Killed
    1 => Survived
    2 => Timeout
    _ => Unviable
  }
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
test "quickcheck: byte boundaries span the encoded source" {
  @quickcheck.check(
    (source : String) => {
      let bytes = @utf8.encode(source)
      let boundaries = source_byte_boundaries(bytes)
      let mut ok = boundaries.length() > 0 &&
        boundaries[0] == 0 &&
        boundaries[boundaries.length() - 1] == bytes.length()
      let mut i = 0
      while ok && i + 1 < boundaries.length() {
        let step = boundaries[i + 1] - boundaries[i]
        if step < 1 || step > 4 {
          ok = false
        }
        i = i + 1
      }
      ok
    },
    seed=0xB0D1UL,
  )
}

///|
test "quickcheck: apply_mutation splices the replacement in place" {
  @quickcheck.check(
    (parts : Array[String]) => {
      let prefix = qc_part(parts, 0)
      let original = qc_part(parts, 1)
      let replacement = qc_part(parts, 2)
      let suffix = qc_part(parts, 3)
      let source = prefix + original + suffix
      let start = @utf8.encode(prefix).length()
      let end = start + @utf8.encode(original).length()
      let mutation : Mutation = {
        path: "qc.mbt",
        start,
        end,
        line: 1,
        column: 1,
        group: Literal,
        original,
        replacement,
      }
      apply_mutation(source, mutation) == prefix + replacement + suffix
    },
    seed=0xB0D2UL,
  )
}

///|
test "quickcheck: count_outcomes partitions every result" {
  @quickcheck.check(
    (codes : Array[Int]) => {
      let mutation : Mutation = {
        path: "qc.mbt",
        start: 0,
        end: 0,
        line: 1,
        column: 1,
        group: Literal,
        original: "",
        replacement: "",
      }
      let results : Array[MutationResult] = []
      let mut expected_killed = 0
      let mut expected_survived = 0
      let mut expected_timeout = 0
      let mut expected_unviable = 0
      for code in codes {
        let outcome = qc_outcome(code)
        results.push({ mutation, outcome, gate: None, duration_ms: 0L })
        match outcome {
          Killed => expected_killed = expected_killed + 1
          Survived => expected_survived = expected_survived + 1
          Timeout => expected_timeout = expected_timeout + 1
          Unviable => expected_unviable = expected_unviable + 1
        }
      }
      let (killed, survived, timeout, unviable) = count_outcomes(results)
      killed == expected_killed &&
      survived == expected_survived &&
      timeout == expected_timeout &&
      unviable == expected_unviable
    },
    seed=0xB0D3UL,
  )
}

///|
test "quickcheck: mutation_score stays within bounds" {
  @quickcheck.check(
    (values : Array[Int]) => {
      let killed = qc_count(values, 0)
      let survived = qc_count(values, 1)
      let timeout = qc_count(values, 2)
      let score = mutation_score(killed, survived, timeout)
      let mut ok = score >= 0.0 && score <= 100.0
      if survived == 0 && timeout == 0 {
        ok = ok && score == 100.0
      }
      if killed == 0 && (survived > 0 || timeout > 0) {
        ok = ok && score == 0.0
      }
      ok
    },
    seed=0xB0D4UL,
  )
}

///|
test "quickcheck: config string arrays round-trip" {
  @quickcheck.check(
    (values : Array[String]) => {
      let source = @utf8.decode(qc_config_bytes(values))
      let config = parse_project_config(source)
      qc_strings_equal(config.include_patterns, values) &&
      qc_strings_equal(config.exclude_patterns, values)
    },
    seed=0xB0D5UL,
  )
}

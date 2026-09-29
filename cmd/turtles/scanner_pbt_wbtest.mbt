///|
/// Fold an arbitrary integer into a valid index of `boundaries`
/// (a non-empty array, so the modulo never divides by zero).
fn pbt_boundary_index(raw : Int, length : Int) -> Int {
  (raw % length + length) % length
}

///|
test "prop source_byte_boundaries is strictly increasing and bounded" {
  @quickcheck.check((source : String) => {
    let bytes = @utf8.encode(source)
    let boundaries = source_byte_boundaries(bytes)
    let mut scalars = 0
    for _ in source {
      scalars = scalars + 1
    }
    if boundaries.length() != scalars + 1 {
      return false
    }
    if boundaries[0] != 0 ||
      boundaries[boundaries.length() - 1] != bytes.length() {
      return false
    }
    for i = 1; i < boundaries.length(); i = i + 1 {
      if boundaries[i] <= boundaries[i - 1] || boundaries[i] > bytes.length() {
        return false
      }
    }
    true
  })
}

///|
test "prop source_byte_offset lands inside the byte range ordered by scalar index" {
  @quickcheck.check((input : (String, Int, Int)) => {
    let (source, raw_i, raw_j) = input
    let bytes = @utf8.encode(source)
    let boundaries = source_byte_boundaries(bytes)
    let i = pbt_boundary_index(raw_i, boundaries.length())
    let j = pbt_boundary_index(raw_j, boundaries.length())
    let (lo, hi) = if i <= j { (i, j) } else { (j, i) }
    let start = source_byte_offset(boundaries, lo)
    let end = source_byte_offset(boundaries, hi)
    start >= 0 && start <= end && end <= bytes.length()
  })
}

///|
/// Byte-range-shaped mutation drawn from an arbitrary source: the recorded
/// range always sits on UTF-8 scalar boundaries, like scanner output.
fn pbt_range_mutation(
  source : String,
  raw_lo : Int,
  raw_hi : Int,
  replacement : String,
) -> (Bytes, Mutation) raise {
  let bytes = @utf8.encode(source)
  let boundaries = source_byte_boundaries(bytes)
  let i = pbt_boundary_index(raw_lo, boundaries.length())
  let j = pbt_boundary_index(raw_hi, boundaries.length())
  let (lo, hi) = if i <= j { (i, j) } else { (j, i) }
  (
    bytes,
    {
      path: "prop.mbt",
      start: boundaries[lo],
      end: boundaries[hi],
      line: 0,
      column: 0,
      group: Literal,
      original: @utf8.decode(bytes[boundaries[lo]:boundaries[hi]]),
      replacement,
    },
  )
}

///|
test "prop apply_mutation with the identity replacement is a no-op" {
  @quickcheck.check((input : (String, Int, Int)) => {
    let (source, raw_lo, raw_hi) = input
    let (_, mutation) = pbt_range_mutation(source, raw_lo, raw_hi, "")
    let mutation : Mutation = { ..mutation, replacement: mutation.original, }
    apply_mutation(source, mutation) == source
  })
}

///|
test "prop apply_mutation leaves bytes outside the recorded range untouched" {
  @quickcheck.check((input : (String, Int, Int, String)) => {
    let (source, raw_lo, raw_hi, replacement) = input
    let (bytes, mutation) = pbt_range_mutation(
      source, raw_lo, raw_hi, replacement,
    )
    let result = @utf8.encode(apply_mutation(source, mutation))
    let suffix = bytes.length() - mutation.end
    // Bytes before `start` and after `end` must survive byte-for-byte.
    @utf8.decode(result[:mutation.start]) ==
    @utf8.decode(bytes[:mutation.start]) &&
    @utf8.decode(result[result.length() - suffix:]) ==
    @utf8.decode(bytes[mutation.end:]) &&
    result.length() ==
    bytes.length() -
    (mutation.end - mutation.start) +
    @utf8.encode(replacement).length()
  })
}

///|
/// Keep only ASCII letters so the result stays a valid type identifier;
/// the "Zz" prefix keeps it non-empty and out of the known type table.
fn pbt_unknown_type_name(letters : String) -> String {
  let output = StringBuilder()
  for c in letters {
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
      output.write_char(c)
    }
  }
  "Zz" + output.to_string()
}

///|
test "prop unrecognised return types get no body replacement" {
  @quickcheck.check((letters : String) => {
    let name = pbt_unknown_type_name(letters)
    let source = "fn f() -> \{name} { 1 + 2 }"
    let config = parse_project_config("operators = [\"body\"]")
    scan_source("prop.mbt", source, config).is_empty()
  })
}

///|
/// The return-type table body_replacements implements: name plus the exact
/// replacement set the `body` group must propose.
fn pbt_body_table() -> Array[(String, Array[String])] {
  [
    ("Unit", ["()"]),
    ("Bool", ["true", "false"]),
    ("Int", ["0", "1", "-1"]),
    ("Int64", ["0", "1", "-1"]),
    ("Int16", ["0", "1", "-1"]),
    ("UInt", ["0", "1"]),
    ("UInt64", ["0", "1"]),
    ("UInt16", ["0", "1"]),
    ("Byte", ["0", "1"]),
    ("Double", ["0.0", "1.0"]),
    ("Float", ["0.0", "1.0"]),
    ("String", ["\"\"", "\"xyzzy\""]),
    ("Int?", ["None"]),
    ("Array[Int]", ["[]"]),
    ("FixedArray[Int]", ["[]"]),
    ("Map[String, Int]", ["{}"]),
  ]
}

///|
test "prop declared types yield exactly their trivial body replacements" {
  let table = pbt_body_table()
  @quickcheck.check((raw : Int) => {
    let (name, expected) = table[pbt_boundary_index(raw, table.length())]
    let source = "fn f() -> \{name} { 1 + 2 }"
    let config = parse_project_config("operators = [\"body\"]")
    let mutations = scan_source("prop.mbt", source, config)
    if mutations.length() != expected.length() {
      return false
    }
    for i = 0; i < mutations.length(); i = i + 1 {
      // Every body mutant swaps the whole body for the tabulated literal.
      if mutations[i].group != Body ||
        mutations[i].original != "1 + 2" ||
        mutations[i].replacement != expected[i] {
        return false
      }
    }
    true
  })
}

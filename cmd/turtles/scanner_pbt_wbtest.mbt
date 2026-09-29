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

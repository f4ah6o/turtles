///|
test "split_lines handles trailing newline and last unterminated line" {
  assert_eq(split_lines(@utf8.encode("a\nb\n")), ["a", "b"])
  assert_eq(split_lines(@utf8.encode("a\nb")), ["a", "b"])
  assert_eq(split_lines(@utf8.encode("")), [])
  assert_eq(split_lines(@utf8.encode("a\n\nb")), ["a", "", "b"])
}

///|
test "line_of_byte counts newlines before position" {
  let bytes = @utf8.encode("a\nb\nc")
  assert_eq(line_of_byte(bytes, 0), 0)
  assert_eq(line_of_byte(bytes, 2), 1)
  assert_eq(line_of_byte(bytes, 4), 2)
  assert_eq(line_of_byte(bytes, 999), 2)
}

///|
test "line_of_end_byte keeps a changed newline on its own line" {
  let bytes = @utf8.encode("a\nb")
  assert_eq(line_of_end_byte(bytes, 1), 0)
  // Exclusive end just past the '\n' still reports line 0.
  assert_eq(line_of_end_byte(bytes, 2), 0)
  assert_eq(line_of_end_byte(bytes, 3), 1)
  assert_eq(line_of_end_byte(bytes, 0), 0)
}

///|
test "unified_mutation_diff renders a single hunk with context" {
  let original = "line1\nline2\nline3\nline4\nline5\nline6\nline7\n"
  let mutated = "line1\nline2\nline3\nCHANGED\nline5\nline6\nline7\n"
  let diff = unified_mutation_diff("src/m.mbt", original, mutated)
  assert_true(diff.has_prefix("--- a/src/m.mbt\n+++ b/src/m.mbt\n"))
  assert_true(diff.contains("@@ -1,7 +1,7 @@"))
  assert_true(diff.contains("-line4"))
  assert_true(diff.contains("+CHANGED"))
  assert_true(diff.contains(" line3"))
}

///|
test "unified_mutation_diff clamps context at file edges" {
  let diff = unified_mutation_diff("m.mbt", "a\nb", "a\nc")
  assert_true(diff.contains("@@ -1,2 +1,2 @@"))
  assert_true(diff.contains("-b"))
  assert_true(diff.contains("+c"))
}

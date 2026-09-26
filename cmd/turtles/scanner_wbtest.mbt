///|
fn has_mutation(
  mutations : Array[Mutation],
  original : String,
  replacement : String,
) -> Bool {
  for mutation in mutations {
    if mutation.original == original && mutation.replacement == replacement {
      return true
    }
  }
  false
}

///|
test "line comments do not produce candidates" {
  let source = "// true && a > b\n"
  inspect(
    scan_source("comment.mbt", source, default_project_config()).length(),
    content="0",
  )
}

///|
test "AST discovery finds expression operators and literals" {
  let source =
    #|fn f(a : Int, b : Int) -> Bool {
    #|  // true && a > b
    #|  true && a > b
    #|}
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="3")
  assert_true(has_mutation(mutations, "&&", "||"))
  assert_true(has_mutation(mutations, ">", "<"))
  assert_true(has_mutation(mutations, "true", "false"))
}

///|
test "comments do not produce candidates" {
  let source = "/* true /* a + b */ false */"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="0")
}

///|
test "strings and character literals do not produce candidates" {
  let string_source = "fn f() -> String { \"true && a > b\" }"
  let char_source = "fn g() -> Char { 'a' }"
  inspect(
    scan_source("string.mbt", string_source, default_project_config()).length(),
    content="0",
  )
  inspect(
    scan_source("char.mbt", char_source, default_project_config()).length(),
    content="0",
  )
}

///|
test "function arrows are not operators but arithmetic is" {
  let source = "fn f(x : Int) -> Int { x - 1 }"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="1")
  inspect(mutations[0].original, content="-")
  inspect(mutations[0].replacement, content="+")
}

///|
test "nested expressions are all traversed" {
  let source = "fn f(a : Int, b : Int, c : Int, d : Int, e : Int) -> Bool { (a + b > c) && (d == e) }"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="4")
  assert_true(has_mutation(mutations, "+", "-"))
  assert_true(has_mutation(mutations, ">", "<"))
  assert_true(has_mutation(mutations, "&&", "||"))
  assert_true(has_mutation(mutations, "==", "!="))
}

///|
test "operator aliases preserve the existing mutation table" {
  let source =
    #|fn cmp(a : Int, b : Int) -> Bool {
    #|  a == b && a != b && a >= b && a <= b && a > b && a < b
    #|}
    #|fn logic(a : Bool, b : Bool) -> Bool { a || b }
    #|fn arithmetic(a : Int, b : Int) -> Int { a + b - a * b / 1 }
  let mutations = scan_source("aliases.mbt", source, default_project_config())
  inspect(mutations.length(), content="16")
  assert_true(has_mutation(mutations, "==", "!="))
  assert_true(has_mutation(mutations, "!=", "=="))
  assert_true(has_mutation(mutations, ">=", "<"))
  assert_true(has_mutation(mutations, "<=", ">"))
  assert_true(has_mutation(mutations, ">", "<"))
  assert_true(has_mutation(mutations, "<", ">"))
  assert_true(has_mutation(mutations, "&&", "||"))
  assert_true(has_mutation(mutations, "||", "&&"))
  assert_true(has_mutation(mutations, "+", "-"))
  assert_true(has_mutation(mutations, "-", "+"))
  assert_true(has_mutation(mutations, "*", "/"))
  assert_true(has_mutation(mutations, "/", "*"))
}

///|
test "if conditions are traversed" {
  let source = "fn f(a : Int, b : Int) -> Int { if a > b { a } else { b } }"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="1")
  inspect(mutations[0].original, content=">")
}

///|
test "return expressions are traversed" {
  let source = "fn f(a : Int, b : Int) -> Bool { return a == b }"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="1")
  inspect(mutations[0].original, content="==")
}

///|
test "nested function-body blocks are traversed" {
  let source =
    #|fn f(a : Int, b : Int) -> Int {
    #|  if a > b {
    #|    a + b
    #|  } else {
    #|    a - b
    #|  }
    #|}
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="3")
  assert_true(has_mutation(mutations, ">", "<"))
  assert_true(has_mutation(mutations, "+", "-"))
  assert_true(has_mutation(mutations, "-", "+"))
}

///|
test "Unicode source ranges use parser positions and apply by UTF-8 bytes" {
  let source =
    #|// 日本語 true && a > b
    #|fn f(値 : Int) -> Int {
    #|  let text = "😀 true && a > b"
    #|  値 + 1
    #|}
  let mutations = scan_source("unicode.mbt", source, default_project_config())
  inspect(mutations.length(), content="1")
  let mutation = mutations[0]
  inspect(mutation.start, content="92")
  inspect(mutation.end, content="93")
  inspect(mutation.line, content="4")
  inspect(mutation.column, content="5")
  inspect(mutation.original, content="+")
  inspect(
    apply_mutation(source, mutation),
    content=(
      #|// 日本語 true && a > b
      #|fn f(値 : Int) -> Int {
      #|  let text = "😀 true && a > b"
      #|  値 - 1
      #|}
    ),
  )
}

///|
test "mutation identity is explicitly deduplicated" {
  let source = "a + b"
  let bytes = @utf8.encode(source)
  let visitor = AstCandidateVisitor::{
    path: "sample.mbt",
    bytes,
    boundaries: source_byte_boundaries(bytes),
    specs: operator_specs(),
    project_config: default_project_config(),
    mutations: [],
  }
  let plus = operator_specs()[8]
  visitor.record(plus, 2, 3, 1, 3)
  visitor.record(plus, 2, 3, 1, 3)
  inspect(visitor.mutations.length(), content="1")
}

///|
test "parser failure does not fall back to lexical scanning" {
  try scan_source("broken.mbt", "fn broken(", default_project_config()) catch {
    _ => ()
  } noraise {
    _ => fail("parser failure unexpectedly produced mutation candidates")
  }
}

///|
test "existing fixture candidate parity" {
  let source =
    #|pub fn add(a : Int, b : Int) -> Int {
    #|  a + b
    #|}
    #|pub fn greater(a : Int, b : Int) -> Bool {
    #|  a > b
    #|}
    #|pub fn both(a : Bool, b : Bool) -> Bool {
    #|  a && b
    #|}
    #|pub fn enabled() -> Bool {
    #|  true
    #|}
  let mutations = scan_source(
    "fixtures/basic/math.mbt",
    source,
    default_project_config(),
  )
  inspect(mutations.length(), content="4")
  assert_true(has_mutation(mutations, "+", "-"))
  assert_true(has_mutation(mutations, ">", "<"))
  assert_true(has_mutation(mutations, "&&", "||"))
  assert_true(has_mutation(mutations, "true", "false"))
}

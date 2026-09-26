///|
test "finds mutations but skips comments and strings" {
  let source =
    #|fn f(a : Int, b : Int) -> Bool {
    #|  // a + b > 0
    #|  let text = "true && false"
    #|  a + b >= 1 && true
    #|}
  let mutations = scan_source("sample.mbt", source, default_project_config())
  let pairs = mutations.map(mutation => {
    (mutation.original, mutation.replacement)
  })
  inspect(pairs, content="[(+, -), (>=, <), (&&, ||), (true, false)]")
}

///|
test "does not mutate function arrow" {
  let source = "fn f(x : Int) -> Int { x - 1 }"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="1")
  inspect(mutations[0].original, content="-")
}

///|
test "nested block comments are skipped" {
  let source = "/* true /* + */ && */ false"
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="1")
  inspect(mutations[0].original, content="false")
}

///|
test "applies exact mutation" {
  let source = "pub fn enabled() -> Bool { true }"
  let mutation = scan_source("sample.mbt", source, default_project_config())[0]
  inspect(
    apply_mutation(source, mutation),
    content="pub fn enabled() -> Bool { false }",
  )
}

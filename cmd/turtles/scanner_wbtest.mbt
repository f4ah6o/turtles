///|
test "finds mutations but skips comments and strings" {
  let source =
    #|fn f(a : Int, b : Int) -> Bool {
    #|  // a + b > 0
    #|  let text = "true && false"
    #|  a + b >= 1 && true
    #|}
  let mutations = scan_source("sample.mbt", source, default_project_config())
  inspect(mutations.length(), content="4")
  inspect(mutations[0].original, content="+")
  inspect(mutations[0].replacement, content="-")
  inspect(mutations[1].original, content=">=")
  inspect(mutations[1].replacement, content="<")
  inspect(mutations[2].original, content="&&")
  inspect(mutations[2].replacement, content="||")
  inspect(mutations[3].original, content="true")
  inspect(mutations[3].replacement, content="false")
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

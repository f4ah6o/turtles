///|
test "parses turtles config" {
  let config = parse_project_config(
    (
      #|# paths
      #|include = [
      #|  "src/",
      #|  "lib/",
      #|]
      #|exclude = ["generated/", "vendor/"]
      #|operators = ["comparison", "literal"]
      #|
    ),
  )
  inspect(config.include, content="[src/, lib/]")
  inspect(config.exclude, content="[generated/, vendor/]")
  inspect(config.path_enabled("src/math.mbt"), content="true")
  inspect(config.path_enabled("src/generated/math.mbt"), content="false")
  inspect(config.operator_enabled(Comparison), content="true")
  inspect(config.operator_enabled(Arithmetic), content="false")
}

///|
test "operator aliases parse" {
  inspect(
    operator_group_from_string("comparisons") == Comparison,
    content="true",
  )
  inspect(
    operator_group_from_string("boolean-logic") == Boolean,
    content="true",
  )
  inspect(
    operator_group_from_string("boolean-literals") == Literal,
    content="true",
  )
}

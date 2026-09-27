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
  json_inspect(config.include_patterns, content=["src/", "lib/"])
  json_inspect(config.exclude_patterns, content=["generated/", "vendor/"])
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
  inspect(operator_group_from_string("condition") == Condition, content="true")
}

///|
test "boolean-logic does not enable structural condition mutations" {
  let config = parse_project_config("operators = [\"boolean-logic\"]")
  inspect(config.operator_enabled(Boolean), content="true")
  inspect(config.operator_enabled(Condition), content="false")
  let condition_config = parse_project_config("operators = [\"conditions\"]")
  inspect(condition_config.operator_enabled(Condition), content="true")
  inspect(condition_config.operator_enabled(Boolean), content="false")
}

///|
fn config_error_message(source : String) -> String {
  let mut message = ""
  try ignore(parse_project_config(source)) catch {
    error => message = "\{error}"
  } noraise {
    _ => ()
  }
  message
}

///|
fn config_fails(source : String) -> Bool {
  config_error_message(source) != ""
}

///|
test "empty and comment-only configs keep defaults" {
  for source in ["", "   \n\t\r\n", "# only a comment\n# another\n"] {
    let config = parse_project_config(source)
    inspect(config.include_patterns.is_empty(), content="true")
    inspect(config.exclude_patterns.is_empty(), content="true")
    inspect(config.operator_enabled(Comparison), content="true")
    inspect(config.operator_enabled(Condition), content="true")
    inspect(config.path_enabled("any/file.mbt"), content="true")
  }
}

///|
test "include and exclude patterns gate paths" {
  let config = parse_project_config(
    "include = [\"src/\", \"lib/\"]\nexclude = [\"gen/\"]",
  )
  inspect(config.path_enabled("src/a.mbt"), content="true")
  inspect(config.path_enabled("lib/b.mbt"), content="true")
  inspect(config.path_enabled("test/c.mbt"), content="false")
  inspect(config.path_enabled("src/gen/d.mbt"), content="false")
  inspect(config.path_enabled("gen/e.mbt"), content="false")
  let windows = parse_project_config("include = [\"src/\"]")
  inspect(windows.path_enabled("src\\dir\\a.mbt"), content="true")
  let exclude_only = parse_project_config("exclude = [\"gen/\"]")
  inspect(exclude_only.path_enabled("src/a.mbt"), content="true")
  inspect(exclude_only.path_enabled("gen/a.mbt"), content="false")
}

///|
test "an empty operators list disables every group" {
  let config = parse_project_config("operators = []")
  inspect(config.operator_enabled(Comparison), content="false")
  inspect(config.operator_enabled(Literal), content="false")
}

///|
test "config parse errors carry line and column" {
  assert_true(config_error_message("include = [\"a\"\n").contains("at 2:1"))
  assert_true(config_error_message("# c\nexclude x").contains("at 2:9"))
  assert_true(
    config_error_message("include = [\"a\", \"b\"\nx").contains("at 2:1"),
  )
}

///|
test "malformed configs are rejected" {
  assert_true(config_fails("bogus = [\"x\"]"))
  assert_true(config_fails("include = [\"a\"]\ninclude = [\"b\"]"))
  assert_true(config_fails("exclude = [\"a\"]\nexclude = [\"b\"]"))
  assert_true(config_fails("operators = [\"a\"]\noperators = [\"b\"]"))
  assert_true(config_fails("operators = [\"vibes\"]"))
  assert_true(config_fails("include [\"a\"]"))
  assert_true(config_fails("include = \"a\""))
  assert_true(config_fails("include = [\"a\""))
  assert_true(config_fails("include = [\"a\" \"b\"]"))
  assert_true(config_fails("include = [\"a]"))
  assert_true(config_fails("include = [\"a\n\"]"))
  assert_true(config_fails("include = [\"a\\q\"]"))
  assert_true(config_fails("include = [\"a\\"))
  assert_true(config_fails("= [\"a\"]"))
  assert_true(config_fails("key with space = [\"a\"]"))
  assert_true(config_fails("include = [\"a\"] trailing"))
}

///|
test "string escapes are decoded" {
  let config = parse_project_config(
    "include = [\"a\\nb\", \"c\\td\", \"e\\\\f\", \"g\\\"h\", \"i\\rj\"]",
  )
  json_inspect(config.include_patterns, content=[
    "a\nb", "c\td", "e\\f", "g\"h", "i\rj",
  ])
}

///|
test "trailing commas and dense arrays parse" {
  let config = parse_project_config("include=[\"a\",\"b\",]")
  json_inspect(config.include_patterns, content=["a", "b"])
}

///|
fn parse_args_error(args : Array[String]) -> String {
  let mut message = ""
  try ignore(parse_args(args)) catch {
    error => message = "\{error}"
  } noraise {
    _ => ()
  }
  message
}

///|
fn parse_args_fails(args : Array[String]) -> Bool {
  parse_args_error(args) != ""
}

///|
test "parse_args defaults" {
  let config = parse_args(["turtles"])
  inspect(config.dir, content=".")
  inspect(config.timeout_ms, content="60000")
  inspect(config.list, content="false")
  inspect(config.file_filter.unwrap_or("none"), content="none")
  inspect(config.json_report.unwrap_or("none"), content="none")
}

///|
test "parse_args reads every option" {
  let config = parse_args([
    "turtles", "--dir", "mod", "--timeout", "5", "--file", "src", "--json", "out.json",
    "--list",
  ])
  inspect(config.dir, content="mod")
  inspect(config.timeout_ms, content="5000")
  inspect(config.list, content="true")
  inspect(config.file_filter.unwrap_or("none"), content="src")
  inspect(config.json_report.unwrap_or("none"), content="out.json")
  let short = parse_args(["turtles", "-d", "other"])
  inspect(short.dir, content="other")
}

///|
test "parse_args rejects bad input" {
  assert_true(parse_args_fails(["turtles", "--bogus"]))
  assert_true(parse_args_fails(["turtles", "x"]))
  assert_true(parse_args_fails(["turtles", "--dir"]))
  assert_true(parse_args_fails(["turtles", "--timeout"]))
  assert_true(parse_args_fails(["turtles", "--file"]))
  assert_true(parse_args_fails(["turtles", "--json"]))
  assert_true(parse_args_fails(["turtles", "--timeout", "0"]))
  assert_true(parse_args_fails(["turtles", "--timeout", "-1"]))
  assert_true(parse_args_fails(["turtles", "--timeout", "abc"]))
}

///|
async test "load_project_config reads turtles.toml and defaults when absent" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let defaults = load_project_config(temp)
    assert_true(defaults.path_enabled("anywhere/file.mbt"))
    @fs.write_file(
      @path.Path(temp).join(@path.Path("turtles.toml")).to_string(),
      "include = [\"src/\"]\noperators = [\"boolean\"]\n",
    )
    let config = load_project_config(temp)
    assert_true(config.path_enabled("src/a.mbt"))
    assert_true(!config.path_enabled("other/a.mbt"))
    assert_true(config.operator_enabled(Boolean))
    assert_true(!config.operator_enabled(Arithmetic))
  })
}

///|
fn regression_property_kill(counterexample : String?) -> Kill {
  {
    pkg: "fixture/pkg",
    filename: "lib_test.mbt",
    index: 2,
    test_name: "prop involution",
    kind: Property,
    counterexample,
  }
}

///|
fn regression_result(
  outcome : Outcome,
  kills : Array[Kill]?,
  replacement : String,
) -> MutationResult {
  {
    mutation: { ..report_test_mutation("lib.mbt"), replacement, },
    outcome,
    duration_ms: 1L,
    reused: false,
    packages: None,
    kills,
  }
}

///|
test "counterexample_kills keeps only property kills with an example" {
  let property = regression_property_kill(Some("0"))
  let no_example = regression_property_kill(None)
  let assertion = { ..regression_property_kill(None), kind: Assertion, }
  let snapshot = { ..regression_property_kill(None), kind: Snapshot, }
  let result = regression_result(
    Killed,
    Some([property, no_example, assertion, snapshot]),
    "b",
  )
  let kills = counterexample_kills(result)
  assert_eq(kills.length(), 1)
  assert_eq(kills[0].test_name, "prop involution")
  // A kill whose attribution was unavailable has nothing to templatize,
  // and non-KILLED outcomes never emit templates.
  assert_eq(
    counterexample_kills(regression_result(Killed, None, "b")).length(),
    0,
  )
  assert_eq(
    counterexample_kills(regression_result(Survived, Some([property]), "b")).length(),
    0,
  )
}

///|
test "regression template records kill, counterexample, and mutant" {
  let result = regression_result(
    Killed,
    Some([regression_property_kill(Some("(0, -1)"))]),
    "b",
  )
  let id = mutation_id(result.mutation)
  assert_eq(
    regression_relpath(result).unwrap_or("none"),
    "regressions/\{id}.mbt",
  )
  guard regression_source(result) is Some(source) else {
    fail("expected a template for a counterexample kill")
  }
  assert_true(source.has_prefix("// turtles regression template"))
  assert_true(source.contains("test \"turtles regression \{id}-1\""))
  assert_true(source.contains("`prop involution`"))
  assert_true(source.contains("fixture/pkg/lib_test.mbt, index 2"))
  assert_true(source.contains("lib.mbt:1:1"))
  assert_true(source.contains("`a` -> `b`"))
  assert_true(source.contains("  //   (0, -1)\n"))
}

///|
test "non-counterexample kills produce no template" {
  let no_example = regression_result(
    Killed,
    Some([regression_property_kill(None)]),
    "b",
  )
  inspect(regression_relpath(no_example) is None, content="true")
  inspect(regression_source(no_example) is None, content="true")
  let assertion_only = regression_result(
    Killed,
    Some([{ ..regression_property_kill(Some("0")), kind: Assertion, }]),
    "b",
  )
  inspect(regression_source(assertion_only) is None, content="true")
}

///|
test "regression_paths lists emitted templates in report order" {
  let killed = regression_result(
    Killed,
    Some([regression_property_kill(Some("0"))]),
    "b",
  )
  let other = regression_result(
    Killed,
    Some([regression_property_kill(Some("1"))]),
    "c",
  )
  let survived = regression_result(
    Survived,
    Some([regression_property_kill(Some("2"))]),
    "d",
  )
  let paths = regression_paths([killed, survived, other])
  assert_eq(paths.length(), 2)
  assert_true(paths[0].has_prefix("regressions/m-"))
  assert_true(paths[0].has_suffix(".mbt"))
  assert_true(paths[0] != paths[1])
}

///|
async test "write_regression_templates writes and sweeps" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let killed = regression_result(
      Killed,
      Some([regression_property_kill(Some("0"))]),
      "b",
    )
    write_regression_templates(temp, [killed])
    let name = mutation_id(killed.mutation) + ".mbt"
    let path = path_join(temp, "regressions/" + name)
    assert_true(@fs.exists(path))
    // Stale templates are swept; non-template files are left alone.
    let stale = path_join(temp, "regressions/m-stale.mbt")
    let keep = path_join(temp, "regressions/notes.txt")
    write_file(stale, "// stale\n")
    write_file(keep, "notes\n")
    write_regression_templates(temp, [killed])
    assert_true(!@fs.exists(stale))
    assert_true(@fs.exists(keep))
    // A run with no qualifying kill sweeps every template.
    write_regression_templates(temp, [])
    assert_true(!@fs.exists(path))
  })
}

///|
test "build_report carries the regressions field" {
  let report = build_report(
    "module/root",
    None,
    0L,
    0L,
    0L,
    "module",
    [],
    [],
    Map([]),
    100.0,
    regressions=["regressions/m-abc.mbt"],
  )
  let output = @json.to_json(report).stringify()
  assert_true(output.contains("\"regressions\":[\"regressions/m-abc.mbt\"]"))
}

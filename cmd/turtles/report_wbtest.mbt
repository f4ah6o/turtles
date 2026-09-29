///|
fn report_test_mutation(path : String) -> Mutation {
  {
    path,
    start: 0,
    end: 1,
    line: 1,
    column: 1,
    group: Comparison,
    original: "a",
    replacement: "b",
  }
}

///|
fn report_test_result(outcome : Outcome) -> MutationResult {
  {
    mutation: report_test_mutation("m.mbt"),
    outcome,
    duration_ms: 1L,
    reused: false,
    packages: None,
    kills: None,
  }
}

///|
fn report_result_with(
  replacement : String,
  outcome : Outcome,
) -> MutationResult {
  let mutation = report_test_mutation("m.mbt")
  {
    mutation: {
      path: mutation.path,
      start: mutation.start,
      end: mutation.end,
      line: mutation.line,
      column: mutation.column,
      group: mutation.group,
      original: mutation.original,
      replacement,
    },
    outcome,
    duration_ms: 1L,
    reused: false,
    packages: None,
    kills: None,
  }
}

///|
test "count_outcomes tallies every outcome" {
  let results = [
    report_test_result(Killed),
    report_test_result(Killed),
    report_test_result(Survived),
    report_test_result(Timeout),
    report_test_result(Unviable),
  ]
  let (killed, survived, timeout, unviable) = count_outcomes(results)
  inspect(killed, content="2")
  inspect(survived, content="1")
  inspect(timeout, content="1")
  inspect(unviable, content="1")
  inspect(count_outcomes([]) == (0, 0, 0, 0), content="true")
}

///|
test "mutation_score divides killed over viable" {
  inspect(mutation_score(0, 0, 0), content="100")
  inspect(mutation_score(3, 1, 0), content="75")
  inspect(mutation_score(0, 2, 0), content="0")
  inspect(mutation_score(1, 0, 1), content="50")
}

///|
async test "write_json_report emits schema-2 JSON" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let path = path_join(temp, "nested/deep/report.json")
    let results = [report_test_result(Killed), report_test_result(Survived)]
    let report = build_report(
      "module/root",
      Some("moon 0.1.x"),
      1234L,
      100L,
      900L,
      "module",
      results,
      [],
      { "m.mbt": "hash" },
      50.0,
    )
    write_json_report(path, report)
    let content = @fs.read_file(path).text()
    assert_true(content.has_suffix("\n"))
    assert_true(content.contains("\"schema\": 2"))
    assert_true(content.contains("\"module\": \"module/root\""))
    assert_true(content.contains("\"turtles_version\""))
    assert_true(content.contains("\"moon_version\": \"moon 0.1.x\""))
    // Int64 fields serialize as JSON strings (schema-1 did the same for
    // duration_ms — parsers must accept the quoted form).
    assert_true(content.contains("\"baseline_check_ms\": \"100\""))
    assert_true(content.contains("\"baseline_test_ms\": \"900\""))
    assert_true(content.contains("\"test_scope\": \"module\""))
    assert_true(content.contains("\"killed\": 1"))
    assert_true(content.contains("\"survived\": 1"))
    assert_true(content.contains("\"reused\": 0"))
    assert_true(content.contains("\"score\": 50"))
    assert_true(content.contains("\"outcome\": \"KILLED\""))
    assert_true(content.contains("\"outcome\": \"SURVIVED\""))
    assert_true(content.contains("\"path\": \"m.mbt\""))
    assert_true(content.contains("\"group\": \"comparison\""))
    assert_true(content.contains("\"original\": \"a\""))
    assert_true(content.contains("\"replacement\": \"b\""))
    assert_true(content.contains("\"id\": \"m-"))
    assert_true(content.contains("\"offset\": 0"))
    assert_true(content.contains("\"files\": {"))
    // Rewriting to an existing directory must still succeed.
    write_json_report(path, report)
    assert_true(@fs.read_file(path).text().contains("\"killed\": 1"))
  })
}

///|
async test "write_output_dir scopes the self-ignore and diffs timeouts" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let root = path_join(temp, "module")
    @fs.mkdir(root, recursive=true)
    write_file(path_join(root, "m.mbt"), "a")
    let results = [
      report_result_with("c", Timeout),
      report_result_with("d", Survived),
      report_result_with("e", Killed),
    ]
    let report = build_report(
      root,
      None,
      0L,
      0L,
      0L,
      "module",
      results,
      [],
      Map([]),
      50.0,
    )
    // A user-chosen output dir never gets a .gitignore.
    let custom = path_join(temp, "out")
    write_output_dir(custom, root, results, report, false)
    assert_true(!@fs.exists(path_join(custom, ".gitignore")))
    // The default .turtles dir gets it once — an existing user file wins.
    let default = path_join(root, ".turtles")
    write_output_dir(default, root, results, report, true)
    assert_eq(@fs.read_file(path_join(default, ".gitignore")).text(), "*\n")
    write_file(path_join(default, ".gitignore"), "mine\n")
    write_output_dir(default, root, results, report, true)
    assert_eq(@fs.read_file(path_join(default, ".gitignore")).text(), "mine\n")
    // Timeout is an unresolved verdict: it ships a diff artifact too.
    let entries = @fs.readdir(
      path_join(default, "survivors"),
      include_hidden=false,
      sort=false,
    )
    assert_eq(entries.length(), 2)
  })
}

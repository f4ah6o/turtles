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
  { mutation: report_test_mutation("m.mbt"), outcome, duration_ms: 1L, }
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
async test "write_json_report emits schema-1 JSON" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let path = path_join(temp, "nested/deep/report.json")
    let results = [report_test_result(Killed), report_test_result(Survived)]
    write_json_report(path, "module/root", 1234L, results, 50.0)
    let content = @fs.read_file(path).text()
    assert_true(content.has_suffix("\n"))
    assert_true(content.contains("\"schema\": 1"))
    assert_true(content.contains("\"module\": \"module/root\""))
    assert_true(content.contains("\"killed\": 1"))
    assert_true(content.contains("\"survived\": 1"))
    assert_true(content.contains("\"score\": 50"))
    assert_true(content.contains("\"outcome\": \"KILLED\""))
    assert_true(content.contains("\"outcome\": \"SURVIVED\""))
    assert_true(content.contains("\"path\": \"m.mbt\""))
    assert_true(content.contains("\"original\": \"a\""))
    assert_true(content.contains("\"replacement\": \"b\""))
    // Rewriting to an existing directory must still succeed.
    write_json_report(path, "module/root", 5L, [], 100.0)
    assert_true(@fs.read_file(path).text().contains("\"killed\": 0"))
  })
}

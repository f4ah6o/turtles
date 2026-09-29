///|
test "exit code reflects survived and timed-out mutants" {
  inspect(final_exit_code(0, 0, 100.0, None), content="0")
  inspect(final_exit_code(1, 0, 50.0, None), content="1")
  inspect(final_exit_code(0, 1, 50.0, None), content="1")
  inspect(final_exit_code(3, 2, 20.0, None), content="1")
}

///|
test "fail-under compares the score against the threshold" {
  // At or above the threshold passes even with surviving mutants.
  inspect(final_exit_code(1, 0, 80.0, Some(80.0)), content="0")
  inspect(final_exit_code(2, 0, 50.0, Some(50.0)), content="0")
  inspect(final_exit_code(1, 0, 66.67, Some(50.0)), content="0")
  inspect(final_exit_code(5, 0, 0.0, Some(0.0)), content="0")
  // Strictly below the threshold fails.
  inspect(final_exit_code(1, 0, 49.9, Some(50.0)), content="1")
  inspect(final_exit_code(0, 0, 99.99, Some(100.0)), content="1")
  // Timeouts count as not-killed in the score, so a timeout-heavy run
  // cannot pass a positive threshold.
  inspect(final_exit_code(0, 2, 0.0, Some(1.0)), content="1")
  // A perfect score meets any threshold.
  inspect(final_exit_code(0, 0, 100.0, Some(100.0)), content="0")
}

///|
async test "execute_with_config lists mutations or runs the pipeline" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let module_dir = path_join(temp, "module")
    @fs.mkdir(module_dir, recursive=true)
    write_order_fixture(module_dir)
    let report = path_join(temp, "report.json")
    let base : Config = {
      dir: module_dir,
      timeout_ms: 120000,
      jobs: 1,
      fail_under: None,
      list: false,
      file_filter: None,
      json_report: Some(report),
      timeout_multiplier: None,
      iterate: false,
      output_dir: Some(path_join(temp, "out")),
      affected: false,
      operators: None,
      emit_regressions: false,
    }
    let listed = execute_with_config({ ..base, list: true, })
    inspect(listed, content="0")
    assert_true(!@fs.exists(report))
    // The order fixture leaves one survivor by design, so the pipeline exits 1.
    let code = execute_with_config(base)
    inspect(code, content="1")
    assert_true(@fs.exists(report))
    let report_text = @fs.read_file(report).text()
    assert_true(report_text.contains("\"survived\": 1"))
    assert_true(report_text.contains("\"group\": \"comparison\""))
    // Score is 50% (1 killed of 2 viable): a threshold at/below passes despite
    // the survivor, a threshold above fails.
    inspect(
      execute_with_config({ ..base, fail_under: Some(50.0), jobs: 2, }),
      content="0",
    )
    inspect(
      execute_with_config({ ..base, fail_under: Some(51.0), }),
      content="1",
    )
  })
}

///|
test "needs_attention keeps only surviving and timed-out mutants in order" {
  let results = [
    report_test_result(Killed),
    report_test_result(Survived),
    report_test_result(Unviable),
    report_test_result(Timeout),
    report_test_result(Survived),
  ]
  inspect(
    needs_attention(results)
    .map(result => outcome_name(result.outcome))
    .join(","),
    content="SURVIVED,TIMEOUT,SURVIVED",
  )
  inspect(needs_attention([]).length(), content="0")
  inspect(needs_attention([report_test_result(Killed)]).length(), content="0")
}

///|
test "describe_result renders outcome, edit, and group" {
  inspect(
    describe_result(report_test_result(Survived)),
    content="SURVIVED m.mbt:1:1: a -> b [comparison]",
  )
}

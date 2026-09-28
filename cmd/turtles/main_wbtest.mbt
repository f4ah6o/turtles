///|
test "exit code reflects survived and timed-out mutants" {
  inspect(summary_exit_code(0, 0), content="0")
  inspect(summary_exit_code(1, 0), content="1")
  inspect(summary_exit_code(0, 1), content="1")
  inspect(summary_exit_code(3, 2), content="1")
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
      list: false,
      file_filter: None,
      json_report: Some(report),
    }
    let listed = execute_with_config({ ..base, list: true, })
    inspect(listed, content="0")
    assert_true(!@fs.exists(report))
    // The order fixture leaves one survivor by design, so the pipeline exits 1.
    let code = execute_with_config(base)
    inspect(code, content="1")
    assert_true(@fs.exists(report))
    assert_true(@fs.read_file(report).text().contains("\"survived\": 1"))
  })
}

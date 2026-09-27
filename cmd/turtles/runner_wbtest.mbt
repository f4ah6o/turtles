///|
async fn write_order_fixture(dir : String) -> Unit {
  @fs.write_file(
    path_join(dir, "moon.mod"),
    "name = \"turtles_order_fixture\"\nversion = \"0.1.0\"\n",
  )
  @fs.write_file(path_join(dir, "moon.pkg"), "")
  @fs.write_file(
    path_join(dir, "order.mbt"),
    (
      #|pub fn add(a : Int, b : Int) -> Int {
      #|  a + b
      #|}
      #|pub fn pick(a : Int, b : Int) -> Bool {
      #|  a < b
      #|}
      #|
    ),
  )
  @fs.write_file(
    path_join(dir, "order_test.mbt"),
    "test \"add\" { inspect(add(1, 2), content=\"3\") }\n",
  )
}

///|
async test "mutant ordering does not change classifications" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let module_dir = path_join(temp, "module")
    @fs.mkdir(module_dir, recursive=true)
    write_order_fixture(module_dir)
    let mutations = discover_mutations(
      module_dir,
      None,
      default_project_config(),
    )
    inspect(mutations.length(), content="2")
    let forward = run_mutations(module_dir, mutations, 120000)
    let reversed : Array[Mutation] = []
    for i = mutations.length() - 1; i >= 0; i = i - 1 {
      reversed.push(mutations[i])
    }
    let backward = run_mutations(module_dir, reversed, 120000)
    let mut mismatched = false
    for result in forward {
      for other in backward {
        if same_mutation_identity(result.mutation, other.mutation) &&
          result.outcome != other.outcome {
          mismatched = true
        }
      }
    }
    assert_false(mismatched)
    inspect(
      forward.map(result => outcome_name(result.outcome)).join(","),
      content="KILLED,SURVIVED",
    )
    inspect(
      backward.map(result => outcome_name(result.outcome)).join(","),
      content="SURVIVED,KILLED",
    )
  })
}

///|
async test "pristine workspace validation failure aborts as a setup error" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let workspace = path_join(temp, "workspace")
    @fs.mkdir(workspace, recursive=true)
    let mut raised = false
    validate_workspace(workspace, 30000) catch {
      _ => raised = true
    }
    assert_true(raised)
  })
}

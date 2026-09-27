///|
async fn run_moon_command(
  root : String,
  args : Array[String],
  timeout_ms : Int,
) -> CommandResult {
  let exit_code = @async.with_timeout_opt(timeout_ms, () => {
    @process.run("moon", args, cwd=root, cancel_handler=@process.hard_cancel())
  })
  match exit_code {
    None => CommandTimeout
    Some(0) => CommandSuccess
    Some(_) => CommandFailure
  }
}

///|
async fn classify_mutant(root : String, timeout_ms : Int) -> Outcome {
  match run_moon_command(root, ["check"], timeout_ms) {
    CommandFailure => return Unviable
    CommandTimeout => return Timeout
    CommandSuccess => ()
  }
  match run_moon_command(root, ["test"], timeout_ms) {
    CommandSuccess => Survived
    CommandFailure => Killed
    CommandTimeout => Timeout
  }
}

///|
/// Run the unchanged copy before classifying mutants: divergence between the
/// original module and its temporary workspace is a setup error, not mutant
/// evidence.
async fn validate_workspace(workspace : String, timeout_ms : Int) -> Unit {
  match run_moon_command(workspace, ["check"], timeout_ms) {
    CommandSuccess => ()
    CommandFailure =>
      fail(
        "temporary workspace failed `moon check`; refusing to classify mutants",
      )
    CommandTimeout =>
      fail("temporary workspace validation timed out during `moon check`")
  }
  match run_moon_command(workspace, ["test"], timeout_ms) {
    CommandSuccess => ()
    CommandFailure =>
      fail(
        "temporary workspace failed `moon test`; refusing to classify mutants",
      )
    CommandTimeout =>
      fail("temporary workspace validation timed out during `moon test`")
  }
}

///|
/// Every mutant runs in a fresh workspace copied from a pristine reference so
/// filesystem side effects produced by `moon check`, `moon test`, or the test
/// suite itself can never leak into later classifications.
async fn run_mutations(
  root : String,
  mutations : Array[Mutation],
  timeout_ms : Int,
) -> Array[MutationResult] {
  let root = @fs.realpath(root)
  let temp = @fs.tmpdir(prefix="turtles")
  @async.with_task_group <| group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let reference = path_join(temp, "reference")
    @fs.mkdir(reference, recursive=true)
    copy_tree(root, root, reference)
    let validation = path_join(temp, "validation")
    @fs.mkdir(validation, recursive=true)
    copy_tree(reference, reference, validation)
    println("Workspace: validating pristine copy ...")
    validate_workspace(validation, timeout_ms)
    println("Workspace: ok")
    let results : Array[MutationResult] = []
    let mut index = 0
    for mutation in mutations {
      index = index + 1
      let workspace = path_join(temp, "mutant-\{index}")
      @fs.mkdir(workspace, recursive=true)
      copy_tree(reference, reference, workspace)
      let target = path_join(workspace, mutation.path)
      let original_source = @fs.read_file(target).text()
      let mutated_source = apply_mutation(original_source, mutation)
      @fs.write_file(target, mutated_source)
      let started = @async.now()
      let outcome = classify_mutant(workspace, timeout_ms)
      let duration_ms = @async.now() - started
      println(
        "[\{index}/\{mutations.length()}] \{outcome_name(outcome)} \{describe_mutation(mutation)}",
      )
      results.push({ mutation, outcome, duration_ms, })
      @fs.rmdir(workspace, recursive=true) catch {
        _ => ()
      }
    }
    results
  }
}

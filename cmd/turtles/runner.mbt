///|
async fn run_moon_command(
  root : String,
  args : Array[String],
  timeout_ms : Int,
) -> CommandResult {
  let exit_code = @async.with_timeout_opt(timeout_ms, () =>
    @process.run(
      "moon",
      args,
      cwd=root,
      cancel_handler=@process.hard_cancel(),
    )
  )
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
async fn run_mutations(
  root : String,
  mutations : Array[Mutation],
  timeout_ms : Int,
) -> Array[MutationResult] {
  let workspace = @fs.tmpdir(prefix="turtles")
  @async.with_task_group <| group => {
    group.add_defer(() => @fs.rmdir(workspace, recursive=true))
    copy_tree(root, root, workspace)
    let results : Array[MutationResult] = []
    let mut index = 0
    for mutation in mutations {
      index = index + 1
      let target = path_join(workspace, mutation.path)
      let original_source = @fs.read_file(target).text()
      let mutated_source = apply_mutation(original_source, mutation)
      @fs.write_file(target, mutated_source)
      let started = @async.now()
      let outcome = classify_mutant(workspace, timeout_ms)
      let duration_ms = @async.now() - started
      @fs.write_file(target, original_source)
      println(
        "[\{index}/\{mutations.length()}] \{outcome_name(outcome)} \{describe_mutation(mutation)}",
      )
      results.push({ mutation, outcome, duration_ms })
    }
    results
  }
}

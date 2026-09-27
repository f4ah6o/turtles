///|
async fn run_command(
  root : String,
  program : String,
  args : Array[String],
  timeout_ms : Int,
) -> CommandResult {
  let exit_code = @async.with_timeout_opt(timeout_ms, () => {
    @process.run(program, args, cwd=root, cancel_handler=@process.hard_cancel())
  })
  match exit_code {
    None => CommandTimeout
    Some(0) => CommandSuccess
    Some(_) => CommandFailure
  }
}

///|
async fn run_moon_command(
  root : String,
  args : Array[String],
  timeout_ms : Int,
) -> CommandResult {
  run_command(root, "moon", args, timeout_ms)
}

///|
/// Run each gate in order; the first failure decides the outcome and the
/// mutant is attributed to that gate. A failing "check" gate reports the
/// mutant as UNVIABLE; every other gate failure kills it.
async fn classify_mutant(
  root : String,
  gates : Array[Gate],
  timeout_ms : Int,
) -> (Outcome, String?) {
  for gate in gates {
    match run_command(root, gate.program, gate.args, timeout_ms) {
      CommandSuccess => ()
      CommandTimeout => return (Timeout, Some(gate.name))
      CommandFailure =>
        if gate.name == "check" {
          return (Unviable, Some(gate.name))
        } else {
          return (Killed, Some(gate.name))
        }
    }
  }
  (Survived, None)
}

///|
async fn run_mutations(
  root : String,
  mutations : Array[Mutation],
  gates : Array[Gate],
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
      let (outcome, gate) = classify_mutant(workspace, gates, timeout_ms)
      let duration_ms = @async.now() - started
      @fs.write_file(target, original_source)
      let gate_note = match gate {
        Some(name) => " (gate: \{name})"
        None => ""
      }
      println(
        "[\{index}/\{mutations.length()}] \{outcome_name(outcome)} \{describe_mutation(mutation)}\{gate_note}",
      )
      results.push({ mutation, outcome, gate, duration_ms, })
    }
    results
  }
}

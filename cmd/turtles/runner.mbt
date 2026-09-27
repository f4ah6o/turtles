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
/// Run an unchanged copy before classifying mutants: divergence between the
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
/// The `reference` tree is snapshotted before any test runs and the baseline
/// executes on a disposable copy of it, so baseline side effects cannot leak
/// into mutants and the module's working tree is never touched. Every mutant
/// then runs in a fresh workspace copied from the same pristine reference.
async fn run_mutations(
  root : String,
  mutations : Array[Mutation],
  timeout_ms : Int,
) -> (Int64, Array[MutationResult]) {
  let root = @fs.realpath(root)
  let temp = @fs.tmpdir(prefix="turtles")
  @async.with_task_group <| group => {
    group.add_defer(() => {
      @async.protect_from_cancel(() => force_rmdir(temp) catch { _ => () })
    })
    let reference = path_join(temp, "reference")
    @fs.mkdir(reference, recursive=true)
    copy_tree(root, root, reference)
    let baseline = path_join(temp, "baseline")
    @fs.mkdir(baseline, recursive=true)
    copy_tree(reference, reference, baseline)
    println("Baseline: moon check + moon test on pristine copy ...")
    let started = @async.now()
    validate_workspace(baseline, timeout_ms)
    let baseline_duration_ms = @async.now() - started
    println("Baseline: ok")
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
      force_rmdir(workspace) catch {
        _ => ()
      }
    }
    (baseline_duration_ms, results)
  }
}

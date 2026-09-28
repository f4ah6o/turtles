///|
async fn run_moon_command(
  root : String,
  args : Array[String],
  timeout_ms : Int,
) -> CommandResult {
  // Nested moon output must not reach our own stdout: when turtles runs
  // inside `moon test`, subprocess output interleaves with the test driver
  // protocol and corrupts result parsing. The log lives next to the
  // workspace so the copied tree stays pristine.
  let output = @process.redirect_to_file(root + "-moon-output.log")
  let exit_code = @async.with_timeout_opt(timeout_ms, () => {
    @process.run(
      "moon",
      args,
      cwd=root,
      stdout=output,
      stderr=output,
      cancel_handler=@process.hard_cancel(),
    )
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
/// Run one mutation in its own workspace copied fresh from `reference`.
/// `index` is 1-based so workspace names stay `mutant-N` in discovery order.
async fn run_one_mutant(
  reference : String,
  temp : String,
  index : Int,
  mutation : Mutation,
  timeout_ms : Int,
  classify : async (String, Int) -> Outcome,
) -> MutationResult {
  let workspace = path_join(temp, "mutant-\{index}")
  @fs.mkdir(workspace, recursive=true)
  copy_tree(reference, reference, workspace)
  let target = path_join(workspace, mutation.path)
  let original_source = @fs.read_file(target).text()
  let mutated_source = apply_mutation(original_source, mutation)
  @fs.write_file(target, mutated_source)
  let started = @async.now()
  let outcome = classify(workspace, timeout_ms)
  let duration_ms = @async.now() - started
  force_rmdir(workspace) catch {
    _ => ()
  }
  { mutation, outcome, duration_ms, }
}

///|
/// Fan mutants out to at most `jobs` workers. Each worker pulls the next
/// unclaimed mutation index, runs it in an isolated `mutant-N` workspace, and
/// writes the result into its own slot, so report order always matches
/// discovery order no matter how runs interleave. A worker failure fails the
/// task group, which cancels the remaining workers.
async fn run_mutation_pool(
  temp : String,
  reference : String,
  mutations : Array[Mutation],
  jobs : Int,
  timeout_ms : Int,
  classify : async (String, Int) -> Outcome,
) -> Array[MutationResult] {
  let total = mutations.length()
  let slots : Array[MutationResult?] = Array::make(total, None)
  let next_index = Ref(0)
  let completed = Ref(0)
  let worker_count = if jobs < total { jobs } else { total }
  @async.with_task_group(group => {
    for _ in 0..<worker_count {
      group.spawn_bg(() => {
        while true {
          let index = next_index.val
          if index >= total {
            break
          }
          next_index.val = index + 1
          let result = run_one_mutant(
            reference,
            temp,
            index + 1,
            mutations[index],
            timeout_ms,
            classify,
          )
          slots[index] = Some(result)
          completed.val = completed.val + 1
          println(
            "[\{completed.val}/\{total}] \{outcome_name(result.outcome)} \{describe_mutation(mutations[index])}",
          )
        }
      })
    }
  })
  slots.map(slot => slot.unwrap())
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
  jobs : Int,
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
    let results = run_mutation_pool(
      temp, reference, mutations, jobs, timeout_ms, classify_mutant,
    )
    (baseline_duration_ms, results)
  }
}

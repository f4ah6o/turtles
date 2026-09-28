///|
async fn execute() -> Int {
  let config = parse_args(@env.args())
  execute_with_config(config)
}

///|
async fn execute_with_config(config : Config) -> Int {
  let root = @fs.realpath(config.dir)
  ensure_moonbit_module(root)
  let project_config = load_project_config(root)
  let mutations = discover_mutations(root, config.file_filter, project_config)
  if mutations.is_empty() {
    println("No mutations found.")
  } else {
    println("Found \{mutations.length()} mutation(s).")
  }
  if config.list {
    for mutation in mutations {
      println(describe_mutation(mutation))
    }
    return 0
  }

  let (baseline_duration_ms, results) = run_mutations(
    root,
    mutations,
    config.timeout_ms,
    config.jobs,
  )
  let counts = count_outcomes(results)
  let score = mutation_score(counts.0, counts.1, counts.2)
  println("")
  println("Mutation testing complete:")
  println("  killed:    \{counts.0}")
  println("  survived:  \{counts.1}")
  println("  timeout:   \{counts.2}")
  println("  unviable:  \{counts.3}")
  println("  score:     \{score}%")
  match config.fail_under {
    Some(threshold) =>
      if score >= threshold {
        println("  threshold: >=\{threshold}% met")
      } else {
        println("  threshold: >=\{threshold}% NOT met")
      }
    None => ()
  }

  match config.json_report {
    Some(path) => {
      write_json_report(path, root, baseline_duration_ms, results, score)
      println("  json:      \{path}")
    }
    None => ()
  }

  let attention = needs_attention(results)
  if attention.length() > 0 {
    println("")
    println("Mutants needing attention:")
    for result in attention {
      println("  \{describe_result(result)}")
    }
  }

  final_exit_code(counts.1, counts.2, score, config.fail_under)
}

///|
/// The mutants a user must act on, in report order.
fn needs_attention(results : Array[MutationResult]) -> Array[MutationResult] {
  results.filter(result => {
    result.outcome == Survived || result.outcome == Timeout
  })
}

///|
/// One recap line: outcome, location and edit, and the operator group.
fn describe_result(result : MutationResult) -> String {
  "\{outcome_name(result.outcome)} \{describe_mutation(result.mutation)} [\{operator_group_name(result.mutation.group)}]"
}

///|
/// A `--fail-under` threshold replaces the default all-or-nothing verdict:
/// met → 0 even with surviving mutants, missed → 1. TIMEOUT mutants already
/// count as not-killed in the score, so timing-out code cannot hide behind a
/// threshold. Setup failures exit 2 regardless (handled by `main`).
fn final_exit_code(
  survived : Int,
  timeout : Int,
  score : Double,
  fail_under : Double?,
) -> Int {
  match fail_under {
    Some(threshold) => if score >= threshold { 0 } else { 1 }
    None => if survived > 0 || timeout > 0 { 1 } else { 0 }
  }
}

///|
async fn main {
  let exit_code = execute() catch {
    error => {
      @stdio.stderr.write("turtles: \{error}\n")
      2
    }
  }
  @sys.exit(exit_code)
}

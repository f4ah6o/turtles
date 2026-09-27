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

  match config.json_report {
    Some(path) => {
      write_json_report(path, root, baseline_duration_ms, results, score)
      println("  json:      \{path}")
    }
    None => ()
  }

  summary_exit_code(counts.1, counts.2)
}

///|
fn summary_exit_code(survived : Int, timeout : Int) -> Int {
  if survived > 0 || timeout > 0 {
    1
  } else {
    0
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

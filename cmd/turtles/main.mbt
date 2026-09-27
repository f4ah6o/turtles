///|
async fn execute() -> Int {
  let config = parse_args()
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

  println("Baseline: moon test ...")
  let baseline_started = @async.now()
  let baseline = run_moon_command(root, ["test"], config.timeout_ms)
  let baseline_duration_ms = @async.now() - baseline_started
  match baseline {
    CommandSuccess => println("Baseline: ok")
    CommandFailure =>
      fail("baseline test suite failed; refusing to classify mutants")
    CommandTimeout => fail("baseline test suite timed out")
  }

  let results = if mutations.is_empty() {
    []
  } else {
    run_mutations(root, mutations, config.timeout_ms)
  }
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

  if counts.1 > 0 || counts.2 > 0 {
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

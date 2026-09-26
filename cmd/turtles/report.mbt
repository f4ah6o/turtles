///|
fn count_outcomes(results : Array[MutationResult]) -> (Int, Int, Int, Int) {
  let mut killed = 0
  let mut survived = 0
  let mut timeout = 0
  let mut unviable = 0
  for result in results {
    match result.outcome {
      Killed => killed = killed + 1
      Survived => survived = survived + 1
      Timeout => timeout = timeout + 1
      Unviable => unviable = unviable + 1
    }
  }
  (killed, survived, timeout, unviable)
}

///|
fn mutation_score(killed : Int, survived : Int, timeout : Int) -> Double {
  let viable = killed + survived + timeout
  if viable == 0 {
    100.0
  } else {
    killed.to_double() * 100.0 / viable.to_double()
  }
}

///|
async fn write_json_report(
  path : String,
  root : String,
  baseline_duration_ms : Int64,
  results : Array[MutationResult],
  score : Double,
) -> Unit {
  let mutants : Array[JsonMutation] = []
  for result in results {
    mutants.push({
      path: result.mutation.path,
      line: result.mutation.line,
      column: result.mutation.column,
      original: result.mutation.original,
      replacement: result.mutation.replacement,
      outcome: outcome_name(result.outcome),
      duration_ms: result.duration_ms,
    })
  }
  let counts = count_outcomes(results)
  let report : JsonReport = {
    schema: 1,
    module: root,
    baseline_duration_ms,
    mutants,
    summary: {
      killed: counts.0,
      survived: counts.1,
      timeout: counts.2,
      unviable: counts.3,
      score,
    },
  }
  let parent = @path.Path(path).dirname().to_string()
  @fs.mkdir(parent, recursive=true, allow_exist=true)
  let output = @json.to_json(report).stringify(indent=2) + "\n"
  @fs.write_file(path, output)
}

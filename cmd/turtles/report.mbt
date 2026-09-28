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
fn json_mutation(result : MutationResult) -> JsonMutation {
  {
    id: mutation_id(result.mutation),
    path: result.mutation.path,
    line: result.mutation.line,
    column: result.mutation.column,
    offset: result.mutation.start,
    end: result.mutation.end,
    group: operator_group_name(result.mutation.group),
    original: result.mutation.original,
    replacement: result.mutation.replacement,
    outcome: outcome_name(result.outcome),
    duration_ms: result.duration_ms,
    reused: result.reused,
    packages: result.packages,
  }
}

///|
fn build_report(
  root : String,
  moon_version : String?,
  baseline_duration_ms : Int64,
  baseline_check_ms : Int64,
  baseline_test_ms : Int64,
  test_scope : String,
  results : Array[MutationResult],
  skipped : Array[SkippedFile],
  files : Map[String, String],
  score : Double,
) -> JsonReport {
  let mutants : Array[JsonMutation] = []
  let mut reused = 0
  for result in results {
    mutants.push(json_mutation(result))
    if result.reused {
      reused = reused + 1
    }
  }
  let counts = count_outcomes(results)
  let skipped_files : Array[JsonSkippedFile] = []
  for entry in skipped {
    skipped_files.push({ path: entry.path, error: entry.error, })
  }
  {
    schema: 2,
    module_path: root,
    turtles_version,
    moon_version,
    baseline_duration_ms,
    baseline_check_ms: Some(baseline_check_ms),
    baseline_test_ms: Some(baseline_test_ms),
    test_scope,
    mutants,
    summary: {
      killed: counts.0,
      survived: counts.1,
      timeout: counts.2,
      unviable: counts.3,
      reused,
      score,
    },
    skipped_files,
    files: Some(files),
  }
}

///|
/// Write `report.json` plus a `survivors/<id>.diff` unified hunk for every
/// survived or timed-out mutant — the artifact that makes an unresolved
/// verdict immediately actionable. Stale diffs from an earlier run are
/// removed so the directory only ever shows mutants the current run
/// produced. The `*` self-ignore is written only for the default
/// `.turtles` directory and only when absent: a custom `--output-dir` or
/// an existing `.gitignore` belongs to the user.
async fn write_output_dir(
  dir : String,
  root : String,
  results : Array[MutationResult],
  report : JsonReport,
  default_dir : Bool,
) -> Unit {
  let survivors_dir = path_join(dir, "survivors")
  @fs.mkdir(survivors_dir, recursive=true, allow_exist=true)
  if default_dir && !@fs.exists(path_join(dir, ".gitignore")) {
    @fs.write_file(path_join(dir, ".gitignore"), "*\n")
  }
  let live_diffs : Map[String, Bool] = Map([])
  for result in results {
    if result.outcome is (Survived | Timeout) {
      live_diffs[mutation_id(result.mutation) + ".diff"] = true
      let source_path = path_join(root, result.mutation.path)
      let original = @fs.read_file(source_path).text() catch { _ => continue }
      let mutated = apply_mutation(original, result.mutation) catch {
        _ => continue
      }
      let diff = unified_mutation_diff(result.mutation.path, original, mutated)
      @fs.write_file(
        path_join(survivors_dir, mutation_id(result.mutation) + ".diff"),
        diff,
      )
    }
  }
  for name in @fs.readdir(survivors_dir, include_hidden=false, sort=false) {
    if name.has_suffix(".diff") && !live_diffs.contains(name) {
      @fs.remove(path_join(survivors_dir, name)) catch {
        _ => ()
      }
    }
  }
  let output = @json.to_json(report).stringify(indent=2) + "\n"
  @fs.write_file(path_join(dir, "report.json"), output)
}

///|
async fn write_json_report(path : String, report : JsonReport) -> Unit {
  let parent = @path.Path(path).dirname().to_string()
  if parent != "" {
    @fs.mkdir(parent, recursive=true, allow_exist=true)
  }
  let output = @json.to_json(report).stringify(indent=2) + "\n"
  @fs.write_file(path, output)
}

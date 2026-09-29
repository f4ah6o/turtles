///|
/// A prior run's report, distilled for --iterate reuse decisions.
struct PriorReport {
  schema : Int
  turtles_version : String?
  moon_version : String?
  files : Map[String, String]
  mutants : Map[String, (Mutation, Outcome, Array[Kill]?)]
}

///|
fn json_string(value : Json) -> String? {
  match value {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn json_field_string(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(value) => json_string(value)
    None => None
  }
}

///|
fn outcome_from_name(name : String) -> Outcome? {
  match name {
    "KILLED" => Some(Killed)
    "SURVIVED" => Some(Survived)
    "TIMEOUT" => Some(Timeout)
    "UNVIABLE" => Some(Unviable)
    _ => None
  }
}

///|
/// Read a schema-2 report for --iterate. Older or partial reports yield
/// None rather than failing the run — reuse is an optimization, never
/// required for correctness.
async fn load_prior_report(path : String) -> PriorReport? {
  let text = @fs.read_file(path).text() catch { _ => return None }
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(top) else { return None }
  let schema = match json_field_string_or_number(top, "schema") {
    Some(n) => n
    None => return None
  }
  let files : Map[String, String] = Map([])
  match top.get("files") {
    Some(Object(entries)) =>
      for entry in entries {
        match json_string(entry.1) {
          Some(hash) => files[entry.0] = hash
          None => ()
        }
      }
    _ => ()
  }
  let mutants : Map[String, (Mutation, Outcome, Array[Kill]?)] = Map([])
  match top.get("mutants") {
    Some(Array(entries)) =>
      for entry in entries {
        match parse_prior_mutant(entry) {
          Some((mutation, outcome, kills)) =>
            mutants[mutation_identity(mutation)] = (mutation, outcome, kills)
          None => ()
        }
      }
    _ => ()
  }
  Some({
    schema,
    turtles_version: json_field_string(top, "turtles_version"),
    moon_version: json_field_string(top, "moon_version"),
    files,
    mutants,
  })
}

///|
fn json_field_string_or_number(
  fields : Map[String, Json],
  name : String,
) -> Int? {
  match fields.get(name) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
fn parse_prior_mutant(json : Json) -> (Mutation, Outcome, Array[Kill]?)? {
  guard json is Object(fields) else { return None }
  guard fields.get("path") is Some(String(path)) else { return None }
  guard fields.get("offset") is Some(Number(start, ..)) else { return None }
  guard fields.get("end") is Some(Number(end, ..)) else { return None }
  guard fields.get("group") is Some(String(group_text)) else { return None }
  guard fields.get("original") is Some(String(original)) else { return None }
  guard fields.get("replacement") is Some(String(replacement)) else {
    return None
  }
  guard fields.get("outcome") is Some(String(outcome_text)) else { return None }
  guard fields.get("line") is Some(Number(line, ..)) else { return None }
  guard fields.get("column") is Some(Number(column, ..)) else { return None }
  let group = operator_group_from_string(group_text) catch { _ => return None }
  guard outcome_from_name(outcome_text) is Some(outcome) else { return None }
  Some(
    (
      {
        path,
        start: start.to_int(),
        end: end.to_int(),
        line: line.to_int(),
        column: column.to_int(),
        group,
        original,
        replacement,
        // The parsed mutant only ever serves as an identity key; the
        // reused result reuses the current scan's mutation, whose
        // visibility is authoritative.
        visibility: Private,
      },
      outcome,
      kills_from_json(json),
    ),
  )
}

///|
/// Reuse is only ever an optimization: any doubt sends the mutant back
/// through the classifier. Reuse a prior KILLED/UNVIABLE verdict iff the
/// mutant's identity tuple matches (path + byte span + both texts +
/// operator group — never line numbers), the file's current content hash
/// equals the hash recorded for it, and the same turtles/moon toolchain
/// produced the prior report. Survived/Timeout are never reused — they are
/// exactly what an iterated run must re-examine.
fn prior_reusable_outcome(
  prior : PriorReport,
  mutation : Mutation,
  current_files : Map[String, String],
  moon_version : String?,
) -> (Outcome, Array[Kill]?)? {
  if prior.schema != 2 {
    return None
  }
  if prior.turtles_version != Some(turtles_version) {
    return None
  }
  if prior.moon_version != moon_version {
    return None
  }
  guard prior.files.get(mutation.path) is Some(recorded_hash) &&
    current_files.get(mutation.path) == Some(recorded_hash) else {
    return None
  }
  guard prior.mutants.get(mutation_identity(mutation))
    is Some((_, outcome, kills)) else {
    return None
  }
  match outcome {
    // The kill's attribution travels with the verdict: a reused row
    // keeps the prior report's killed_by rather than degrading to
    // "unavailable".
    Killed => Some((outcome, kills))
    Unviable => Some((outcome, None))
    Survived | Timeout => None
  }
}

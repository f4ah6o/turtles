///|
enum OperatorGroup {
  Comparison
  Boolean
  Arithmetic
  Literal
  Condition
} derive(Eq)

///|
fn operator_group_from_string(value : String) -> OperatorGroup raise {
  match value {
    "comparison" | "comparisons" => Comparison
    "boolean" | "boolean-logic" => Boolean
    "arithmetic" => Arithmetic
    "literal" | "boolean-literal" | "boolean-literals" => Literal
    "condition" | "conditions" => Condition
    other =>
      fail(
        "unknown operator group \{other}; expected comparison, boolean, arithmetic, literal, or condition",
      )
  }
}

///|
fn operator_group_name(group : OperatorGroup) -> String {
  match group {
    Comparison => "comparison"
    Boolean => "boolean"
    Arithmetic => "arithmetic"
    Literal => "literal"
    Condition => "condition"
  }
}

///|
struct ProjectConfig {
  include_patterns : Array[String]
  exclude_patterns : Array[String]
  operators : Array[OperatorGroup]?
}

///|
fn default_project_config() -> ProjectConfig {
  { include_patterns: [], exclude_patterns: [], operators: None, }
}

///|
fn ProjectConfig::path_enabled(self : ProjectConfig, path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  let mut included = self.include_patterns.is_empty()
  if !included {
    for pattern in self.include_patterns {
      if path.contains(pattern) {
        included = true
        break
      }
    }
  }
  if !included {
    return false
  }
  for pattern in self.exclude_patterns {
    if path.contains(pattern) {
      return false
    }
  }
  true
}

///|
fn ProjectConfig::operator_enabled(
  self : ProjectConfig,
  group : OperatorGroup,
) -> Bool {
  match self.operators {
    None => true
    Some(operators) => {
      for operator in operators {
        if operator == group {
          return true
        }
      }
      false
    }
  }
}

///|
struct Config {
  dir : String
  timeout_ms : Int
  jobs : Int
  fail_under : Double?
  list : Bool
  file_filter : String?
  json_report : String?
  timeout_multiplier : Double?
  iterate : Bool
  output_dir : String?
  affected : Bool
}

///|
struct Mutation {
  path : String
  start : Int
  end : Int
  line : Int
  column : Int
  group : OperatorGroup
  original : String
  replacement : String
} derive(Eq)

///|
enum Outcome {
  Killed
  Survived
  Timeout
  Unviable
} derive(Eq)

///|
fn outcome_name(outcome : Outcome) -> String {
  match outcome {
    Killed => "KILLED"
    Survived => "SURVIVED"
    Timeout => "TIMEOUT"
    Unviable => "UNVIABLE"
  }
}

///|
struct MutationResult {
  mutation : Mutation
  outcome : Outcome
  duration_ms : Int64
  reused : Bool
  packages : Array[String]?
}

///|
struct JsonMutation {
  id : String
  path : String
  line : Int
  column : Int
  offset : Int
  end : Int
  group : String
  original : String
  replacement : String
  outcome : String
  duration_ms : Int64
  reused : Bool
  packages : Array[String]?
} derive(ToJson)

///|
struct JsonSummary {
  killed : Int
  survived : Int
  timeout : Int
  unviable : Int
  reused : Int
  score : Double
} derive(ToJson)

///|
struct JsonSkippedFile {
  path : String
  error : String
} derive(ToJson)

///|
/// A file the scanner could not parse. Skipping keeps the rest of the
/// module scannable, but mutants in that file are silently absent — the
/// report must carry them so the gap stays visible.
struct SkippedFile {
  path : String
  error : String
}

///|
struct JsonReport {
  schema : Int
  module_path : String
  turtles_version : String
  moon_version : String?
  baseline_duration_ms : Int64
  baseline_check_ms : Int64?
  baseline_test_ms : Int64?
  test_scope : String
  mutants : Array[JsonMutation]
  summary : JsonSummary
  skipped_files : Array[JsonSkippedFile]
  files : Map[String, String]?
} derive(ToJson(fields(module_path(rename="module"))))

///|
enum CommandResult {
  CommandSuccess
  CommandFailure
  CommandTimeout
} derive(Eq)

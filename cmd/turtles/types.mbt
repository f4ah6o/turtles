///|
enum OperatorGroup {
  Comparison
  Boolean
  Arithmetic
  Literal
} derive(Eq)

///|
fn operator_group_from_string(value : String) -> OperatorGroup raise {
  match value {
    "comparison" | "comparisons" => Comparison
    "boolean" | "boolean-logic" => Boolean
    "arithmetic" => Arithmetic
    "literal" | "boolean-literal" | "boolean-literals" => Literal
    other =>
      fail(
        "unknown operator group \{other}; expected comparison, boolean, arithmetic, or literal",
      )
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
  list : Bool
  file_filter : String?
  json_report : String?
}

///|
struct Mutation {
  path : String
  start : Int
  end : Int
  line : Int
  column : Int
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
}

///|
struct JsonMutation {
  path : String
  line : Int
  column : Int
  original : String
  replacement : String
  outcome : String
  duration_ms : Int64
} derive(ToJson)

///|
struct JsonSummary {
  killed : Int
  survived : Int
  timeout : Int
  unviable : Int
  score : Double
} derive(ToJson)

///|
struct JsonReport {
  schema : Int
  module_path : String
  baseline_duration_ms : Int64
  mutants : Array[JsonMutation]
  summary : JsonSummary
} derive(ToJson(fields(module_path(rename="module"))))

///|
enum CommandResult {
  CommandSuccess
  CommandFailure
  CommandTimeout
} derive(Eq)

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
/// A named verification stage run against the mutated workspace copy.
/// Gates run in order and the first failure decides the mutant's outcome.
/// The gate named "check" additionally defines viability: its failure is
/// reported as UNVIABLE rather than KILLED.
struct Gate {
  name : String
  program : String
  args : Array[String]
}

///|
fn moon_gate(name : String) -> Gate {
  { name, program: "moon", args: [name], }
}

///|
/// The default pipeline matches the original turtles behavior: `moon check`
/// establishes viability, then `moon test` decides whether the mutant is
/// killed.
fn default_gates() -> Array[Gate] {
  [moon_gate("check"), moon_gate("test")]
}

///|
fn gate_names(gates : Array[Gate]) -> Array[String] {
  let names : Array[String] = []
  for gate in gates {
    names.push(gate.name)
  }
  names
}

///|
fn gates_has_name(gates : Array[Gate], name : String) -> Bool {
  for gate in gates {
    if gate.name == name {
      return true
    }
  }
  false
}

///|
fn describe_gates(gates : Array[Gate]) -> String {
  let mut description = ""
  for i, name in gate_names(gates) {
    if i > 0 {
      description = description + ", "
    }
    description = description + name
  }
  description
}

///|
struct ProjectConfig {
  include_patterns : Array[String]
  exclude_patterns : Array[String]
  operators : Array[OperatorGroup]?
  gates : Array[Gate]?
}

///|
fn default_project_config() -> ProjectConfig {
  { include_patterns: [], exclude_patterns: [], operators: None, gates: None, }
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
  prove : Bool
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
/// `gate` names the gate that produced the outcome: the failing gate for
/// KILLED/UNVIABLE and the gate that timed out for TIMEOUT. It is `None`
/// only for SURVIVED, where every gate passed.
struct MutationResult {
  mutation : Mutation
  outcome : Outcome
  gate : String?
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
  gate : String?
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
  gates : Array[String]
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

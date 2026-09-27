///|
test "builtin gate specs map to moon subcommands" {
  let check = gate_from_spec("check")
  inspect(check.name, content="check")
  inspect(check.program, content="moon")
  json_inspect(check.args, content=["check"])
  json_inspect(gate_from_spec("test").args, content=["test"])
  json_inspect(gate_from_spec("prove").args, content=["prove"])
  json_inspect(gate_names(default_gates()), content=["check", "test"])
}

///|
test "named gate specs split command lines" {
  let gate = gate_from_spec(
    "self-e2e=moon run cmd/turtles -- --dir fixtures/basic --timeout 60",
  )
  inspect(gate.name, content="self-e2e")
  inspect(gate.program, content="moon")
  json_inspect(
    gate.args,
    content=[
      "run", "cmd/turtles", "--", "--dir", "fixtures/basic", "--timeout", "60",
    ],
  )
}

///|
fn gate_spec_fails(spec : String) -> Bool {
  try gate_from_spec(spec) catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "invalid gate specs are rejected" {
  for spec in ["bogus", "=moon test", "gate=", "gate=   "] {
    inspect(gate_spec_fails(spec), content="true")
  }
}

///|
test "gates key parses ordered gate specs" {
  let config = parse_project_config(
    "gates = [\"check\", \"e2e=moon test --verbose\", \"prove\"]\n",
  )
  match config.gates {
    Some(gates) => {
      inspect(gates.length(), content="3")
      inspect(gates[0].name, content="check")
      inspect(gates[1].name, content="e2e")
      json_inspect(gates[1].args, content=["test", "--verbose"])
      inspect(gates[2].name, content="prove")
      inspect(describe_gates(gates), content="check, e2e, prove")
      inspect(gates_has_name(gates, "prove"), content="true")
      inspect(gates_has_name(gates, "self-e2e"), content="false")
    }
    None => fail("gates were not parsed")
  }
}

///|
test "gates default to check then test" {
  let config = parse_project_config("include = [\"src/\"]\n")
  inspect(config.gates is None, content="true")
}

///|
test "an empty gates list is rejected" {
  try parse_project_config("gates = []\n") catch {
    _ => ()
  } noraise {
    _ => fail("empty gates list unexpectedly accepted")
  }
}

///|
test "exit code reflects survivors and timeouts" {
  inspect(exit_code_for(0, 0), content="0")
  inspect(exit_code_for(2, 0), content="1")
  inspect(exit_code_for(0, 1), content="1")
  inspect(exit_code_for(3, 2), content="1")
}

///|
test "count_outcomes tallies each outcome" {
  let mutation : Mutation = {
    path: "m.mbt",
    start: 0,
    end: 0,
    line: 1,
    column: 1,
    group: Literal,
    original: "",
    replacement: "",
  }
  let results : Array[MutationResult] = [
    { mutation, outcome: Killed, gate: Some("test"), duration_ms: 1L },
    { mutation, outcome: Survived, gate: None, duration_ms: 2L },
    { mutation, outcome: Timeout, gate: Some("prove"), duration_ms: 3L },
    { mutation, outcome: Unviable, gate: Some("check"), duration_ms: 4L },
    { mutation, outcome: Killed, gate: Some("self-e2e"), duration_ms: 5L },
  ]
  let counts = count_outcomes(results)
  inspect(counts.0, content="2")
  inspect(counts.1, content="1")
  inspect(counts.2, content="1")
  inspect(counts.3, content="1")
}

///|
test "mutation_score reports the killed share of viable mutants" {
  assert_eq(mutation_score(0, 0, 0), 100.0)
  assert_eq(mutation_score(3, 0, 0), 100.0)
  assert_eq(mutation_score(0, 2, 0), 0.0)
  assert_eq(mutation_score(3, 1, 0), 75.0)
  assert_eq(mutation_score(1, 1, 2), 25.0)
}

///|
test "test sources and build directories stay excluded" {
  inspect(is_test_source("math_test.mbt"), content="true")
  inspect(is_test_source("math_wbtest.mbt"), content="true")
  inspect(is_test_source("math.mbt"), content="false")
  inspect(is_test_source("proof_spec.mbtp"), content="false")
  inspect(should_skip_dir(".git"), content="true")
  inspect(should_skip_dir("target"), content="true")
  inspect(should_skip_dir("src"), content="false")
}

///|
test "non-included and excluded paths are disabled" {
  let config = parse_project_config(
    "include = [\"src/\"]\nexclude = [\"gen/\"]\n",
  )
  inspect(config.path_enabled("src/a.mbt"), content="true")
  inspect(config.path_enabled("other/a.mbt"), content="false")
  inspect(config.path_enabled("src/gen/a.mbt"), content="false")
}

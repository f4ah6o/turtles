///|
/// Real `--test-failure-json` lines captured on moon 0.1.20260920.
fn oracle_prop_line() -> String {
  (
    #|{"package":"probe/p","filename":"lib_test.mbt","index":"0","test_name":"prop idempotent","message":"lib_test.mbt:3:3-3:71@probe/p FAILED: QuickCheck falsified after 1 test(s)\ncounterexample: 0\nsize: 0\nshrinks: 2 successful, 2 attempted"}
  )
}

///|
fn oracle_snapshot_line() -> String {
  (
    #|{"package":"probe/p","filename":"lib_test.mbt","index":"1","test_name":"example","message":"@EXPECT_FAILED {\"loc\": {\"filename\":\"p/lib_test.mbt\"}, \"expect\": \"6\", \"actual\": \"5\"}"}
  )
}

///|
fn oracle_assertion_line() -> String {
  (
    #|{"package":"probe/p","filename":"lib_test.mbt","index":"2","test_name":"plain","message":"p/lib_test.mbt:13:3-13:32@probe FAILED: `5 != 7`\ndiff:\n-5 +7"}
  )
}

///|
/// A `.mbt.md` doc test reports its own filename and an empty test name.
fn oracle_markdown_doc_line() -> String {
  (
    #|{"package":"probe/p","filename":"README.mbt.md","index":"0","test_name":"","message":"@EXPECT_FAILED {\"loc\": {\"filename\":\"p/README.mbt.md\"}, \"expect\": \"99\", \"actual\": \"1\"}"}
  )
}

///|
/// A docstring `mbt check` test reports the *source* file with an empty
/// test name — the empty name is what marks it as a doc test.
fn oracle_docstring_line() -> String {
  (
    #|{"package":"probe/p","filename":"lib.mbt","index":"0","test_name":"","message":"@EXPECT_FAILED {\"loc\": {\"filename\":\"p/lib.mbt\"}, \"expect\": \"42\", \"actual\": \"5\"}"}
  )
}

///|
test "mutant test argv always carries the oracle and never --update" {
  let plain = mutant_test_args(None)
  assert_true(plain.contains("--test-failure-json"))
  assert_eq(plain[0], "test")
  let scoped = mutant_test_args(Some(["a/b", "c/d"]))
  assert_true(scoped.contains("--test-failure-json"))
  inspect(
    scoped.iter().filter(arg => arg == "-p").collect().length(),
    content="2",
  )
  assert_true(scoped.contains("a/b"))
  assert_true(scoped.contains("c/d"))
  for arg in [plain, scoped] {
    for flag in arg {
      assert_false(flag == "--update" || flag == "-u")
    }
  }
}

///|
test "kill parsing classifies every test kind" {
  let prop = parse_kill_line(oracle_prop_line()).unwrap()
  debug_inspect(prop.kind, content="Property")
  debug_inspect(prop.counterexample, content="Some(\"0\")")
  inspect(prop.test_name, content="prop idempotent")
  let snapshot = parse_kill_line(oracle_snapshot_line()).unwrap()
  debug_inspect(snapshot.kind, content="Snapshot")
  debug_inspect(snapshot.counterexample, content="None")
  let assertion = parse_kill_line(oracle_assertion_line()).unwrap()
  debug_inspect(assertion.kind, content="Assertion")
  let markdown = parse_kill_line(oracle_markdown_doc_line()).unwrap()
  debug_inspect(markdown.kind, content="DocTest")
  let docstring = parse_kill_line(oracle_docstring_line()).unwrap()
  debug_inspect(docstring.kind, content="DocTest")
}

///|
test "failure stream skips noise and reports unavailable on no records" {
  let output = "INFO launching test executable\n" +
    oracle_prop_line() +
    "\nTotal tests: 3, passed: 1, failed: 2.\n" +
    oracle_snapshot_line() +
    "\nnot json { either\n"
  let kills = parse_test_failures(output).unwrap()
  inspect(kills.length(), content="2")
  debug_inspect(kills[0].kind, content="Property")
  debug_inspect(kills[1].kind, content="Snapshot")
  debug_inspect(parse_test_failures(""), content="None")
  debug_inspect(
    parse_test_failures("Total tests: 2, passed: 2.\n"),
    content="None",
  )
}

///|
test "unstable_kills reports the symmetric difference" {
  let prop = parse_kill_line(oracle_prop_line()).unwrap()
  let snap = parse_kill_line(oracle_snapshot_line()).unwrap()
  debug_inspect(
    unstable_kills([prop, snap], [prop]).map(kill => kill.test_name),
    content="[\"example\"]",
  )
  inspect(unstable_kills([prop], [prop]).length(), content="0")
  debug_inspect(
    unstable_kills([], [snap]).map(kill => kill.test_name),
    content="[\"example\"]",
  )
}

///|
fn oracle_result_with_kills(kills : Array[Kill]?) -> MutationResult {
  let base = report_test_result(Killed)
  {
    mutation: base.mutation,
    outcome: base.outcome,
    duration_ms: base.duration_ms,
    reused: base.reused,
    packages: base.packages,
    kills,
    witness: base.witness,
    witness_skipped: base.witness_skipped,
    amplified: base.amplified,
  }
}

///|
test "kill_counts tallies kinds and property-only mutants" {
  let prop = parse_kill_line(oracle_prop_line()).unwrap()
  let snap = parse_kill_line(oracle_snapshot_line()).unwrap()
  let assert_kill = parse_kill_line(oracle_assertion_line()).unwrap()
  let results = [
    oracle_result_with_kills(Some([prop])),
    oracle_result_with_kills(Some([prop, snap])),
    oracle_result_with_kills(Some([assert_kill])),
  ]
  let (counts, property_only) = kill_counts(results)
  debug_inspect(
    counts,
    content="{ property: 2, snapshot: 1, doc_test: 0, assertion: 1 }",
  )
  inspect(property_only, content="1")
}

///|
test "killed mutants serialize killed_by and the unavailable fallback" {
  let prop = parse_kill_line(oracle_prop_line()).unwrap()
  let attributed = json_mutation(oracle_result_with_kills(Some([prop])))
  let json = @json.to_json(attributed).stringify()
  assert_true(json.contains("\"killed_by\""))
  assert_true(json.contains("\"kind\":\"Property\""))
  assert_true(json.contains("\"counterexample\":\"0\""))
  let unattributed = json_mutation(oracle_result_with_kills(None))
  let fallback = @json.to_json(unattributed).stringify()
  assert_true(fallback.contains("\"killed_by\":[]"))
  assert_true(fallback.contains("\"attribution\":\"unavailable\""))
  // Option fields serialize absent, so non-kills carry no new keys.
  let survived = json_mutation(report_test_result(Survived))
  let clean = @json.to_json(survived).stringify()
  assert_false(clean.contains("killed_by"))
}

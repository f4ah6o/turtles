///|
fn mk_mutation(
  path : String,
  start : Int,
  end : Int,
  original : String,
  replacement : String,
) -> Mutation {
  {
    path,
    start,
    end,
    line: 1,
    column: 1,
    original,
    replacement,
    group: Arithmetic,
  }
}

///|
fn mk_prior(
  schema : Int,
  turtles : String?,
  moon : String?,
  file_hash : String,
  outcome : Outcome,
) -> PriorReport {
  let m = mk_mutation("a.mbt", 0, 1, "+", "-")
  let mutants : Map[String, (Mutation, Outcome)] = Map([])
  mutants[mutation_identity(m)] = (m, outcome)
  let files : Map[String, String] = Map([])
  files["a.mbt"] = file_hash
  { schema, turtles_version: turtles, moon_version: moon, files, mutants, }
}

///|
test "iterate reuses only identity-matched KILLED/UNVIABLE under same toolchain" {
  let current : Map[String, String] = Map([])
  current["a.mbt"] = "hash-a"
  let m = mk_mutation("a.mbt", 0, 1, "+", "-")
  let prior = mk_prior(
    2,
    Some(turtles_version),
    Some("moon x"),
    "hash-a",
    Killed,
  )
  match prior_reusable_outcome(prior, m, current, Some("moon x")) {
    Some(Killed) => ()
    _ => fail("expected reused KILLED")
  }
  // Survived and Timeout never reuse.
  let prior_survived = mk_prior(
    2,
    Some(turtles_version),
    Some("moon x"),
    "hash-a",
    Survived,
  )
  assert_eq(
    prior_reusable_outcome(prior_survived, m, current, Some("moon x")) is None,
    true,
  )
  let prior_timeout = mk_prior(
    2,
    Some(turtles_version),
    Some("moon x"),
    "hash-a",
    Timeout,
  )
  assert_eq(
    prior_reusable_outcome(prior_timeout, m, current, Some("moon x")) is None,
    true,
  )
  // Schema 1 reports never reuse.
  let old = mk_prior(1, Some(turtles_version), Some("moon x"), "hash-a", Killed)
  assert_eq(
    prior_reusable_outcome(old, m, current, Some("moon x")) is None,
    true,
  )
  // turtles or moon version drift disables reuse.
  let other_turtles = mk_prior(
    2,
    Some("0.0.0"),
    Some("moon x"),
    "hash-a",
    Killed,
  )
  assert_eq(
    prior_reusable_outcome(other_turtles, m, current, Some("moon x")) is None,
    true,
  )
  let other_moon = mk_prior(
    2,
    Some(turtles_version),
    Some("moon y"),
    "hash-a",
    Killed,
  )
  assert_eq(
    prior_reusable_outcome(other_moon, m, current, Some("moon x")) is None,
    true,
  )
}

///|
test "iterate refuses reuse when file content changed" {
  let current : Map[String, String] = Map([])
  current["a.mbt"] = "new-hash"
  let m = mk_mutation("a.mbt", 0, 1, "+", "-")
  let prior = mk_prior(
    2,
    Some(turtles_version),
    Some("moon x"),
    "old-hash",
    Killed,
  )
  assert_eq(
    prior_reusable_outcome(prior, m, current, Some("moon x")) is None,
    true,
  )
}

///|
test "identity is content-anchored, not line-anchored" {
  // Same span+texts, different recorded line -> same identity.
  let m1 = mk_mutation("a.mbt", 10, 11, "+", "-")
  let m2 = {
    path: "a.mbt",
    start: 10,
    end: 11,
    line: 99,
    column: 99,
    original: "+",
    replacement: "-",
    group: Arithmetic,
  }
  assert_eq(mutation_identity(m1), mutation_identity(m2))
  // Same line, shifted bytes -> different identity.
  let m3 = mk_mutation("a.mbt", 20, 21, "+", "-")
  assert_true(mutation_identity(m1) != mutation_identity(m3))
  // Same span, different replacement -> different identity.
  let m4 = mk_mutation("a.mbt", 10, 11, "+", "*")
  assert_true(mutation_identity(m1) != mutation_identity(m4))
}

///|
test "mutation_id is a stable m- prefixed hex digest" {
  let id = mutation_id(mk_mutation("a.mbt", 0, 1, "+", "-"))
  assert_true(id.has_prefix("m-"))
  assert_eq(id.length(), 18)
  assert_eq(id, mutation_id(mk_mutation("a.mbt", 0, 1, "+", "-")))
}

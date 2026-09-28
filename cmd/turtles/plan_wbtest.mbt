///|
/// A minimal dry-run fragment in the real moon format: library build,
/// internal test build, and a dependent package whose tests link the lib.
fn sample_plan() -> String {
  [
    "moonc build-package ./uuid/uuid.mbt -o ./_build/wasm/debug/test/uuid/uuid.core -pkg moonbitlang/x/uuid -pkg-type library -pkg-sources moonbitlang/x/uuid:./uuid -target wasm",
    "moonc build-package ./uuid/uuid.mbt ./_build/wasm/debug/test/uuid/__generated_driver_for_internal_test.mbt -o ./_build/wasm/debug/test/uuid/uuid.internal_test.core -pkg moonbitlang/x/uuid -pkg-type executable -i ./_build/wasm/debug/test/uuid/uuid.mi:uuid -pkg-sources moonbitlang/x/uuid:./uuid -test-mode",
    "moonc build-package ./uuid/uuid_test.mbt -o ./_build/wasm/debug/test/uuid/uuid.blackbox_test.core -pkg moonbitlang/x/uuid_blackbox_test -pkg-type executable -i ./_build/wasm/debug/test/uuid/uuid.mi:uuid -pkg-sources moonbitlang/x/uuid_blackbox_test:./uuid -test-mode",
    "moonc build-package ./jwt/jwt.mbt -o ./_build/wasm/debug/test/jwt/jwt.core -pkg moonbitlang/x/jwt -pkg-type library -i ./_build/wasm/debug/test/uuid/uuid.mi:uuid -pkg-sources moonbitlang/x/jwt:./jwt -target wasm",
    "moonc build-package ./jwt/jwt_test.mbt -o ./_build/wasm/debug/test/jwt/jwt.blackbox_test.core -pkg moonbitlang/x/jwt_blackbox_test -pkg-type executable -i ./_build/wasm/debug/test/jwt/jwt.mi:jwt -i ./_build/wasm/debug/test/uuid/uuid.mi:uuid -pkg-sources moonbitlang/x/jwt_blackbox_test:./jwt -test-mode",
    "moonc build-package ./codec/codec.mbt -o ./_build/wasm/debug/test/codec/codec.core -pkg moonbitlang/x/codec -pkg-type library -pkg-sources moonbitlang/x/codec:./codec -target wasm",
  ].join("\n")
}

///|
fn build_sample_plan() -> TestPlan {
  let builder = PlanBuilder::new()
  for line in sample_plan().split("\n") {
    builder.record_line(line.to_owned())
  }
  builder.build()
}

///|
test "artifact_pkg_path strips the _build prefix layout" {
  assert_eq(
    artifact_pkg_path("./_build/wasm/debug/test/uuid/uuid.core"),
    Some("uuid"),
  )
  assert_eq(
    artifact_pkg_path("_build/native/release/test/a/b/c/d.mi"),
    Some("a/b/c"),
  )
  assert_eq(artifact_pkg_path("$MOON_HOME/lib/x.mi"), None)
  assert_eq(artifact_pkg_path("./uuid/uuid.mbt"), None)
}

///|
test "plan maps a mutation to its package dir" {
  let plan = build_sample_plan()
  assert_eq(plan.package_dir_of("uuid/uuid.mbt"), Some("uuid"))
  assert_eq(plan.package_dir_of("jwt/sub/x.mbt"), Some("jwt"))
  assert_eq(plan.package_dir_of("elsewhere/x.mbt"), None)
}

///|
test "test_packages_for selects observers transitively and canonical fqns" {
  let plan = build_sample_plan()
  match plan.test_packages_for(mk_mutation("uuid/uuid.mbt", 0, 1, "+", "-")) {
    Some(pkgs) =>
      // uuid's own tests plus jwt's tests (jwt links uuid).
      assert_eq(pkgs, ["moonbitlang/x/jwt", "moonbitlang/x/uuid"])
    None => fail("expected a package selection")
  }
  // codec observes nothing but itself.
  match plan.test_packages_for(mk_mutation("codec/codec.mbt", 0, 1, "+", "-")) {
    Some(pkgs) => assert_eq(pkgs, ["moonbitlang/x/codec"])
    None => fail("expected a package selection")
  }
  // A file outside every package falls back to module-wide.
  assert_eq(
    plan.test_packages_for(mk_mutation("none/x.mbt", 0, 1, "+", "-")),
    None,
  )
}

///|
test "split_args strips quotes and squeezes whitespace" {
  assert_eq(
    split_args("moonc build-package -i '$MOON_HOME/lib/m.mi:m'  -pkg x"),
    ["moonc", "build-package", "-i", "$MOON_HOME/lib/m.mi:m", "-pkg", "x"],
  )
}

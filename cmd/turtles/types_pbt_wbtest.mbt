///|
test "prop path_enabled is invariant under backslash normalisation" {
  @quickcheck.check((input : (Array[String], Array[String], String)) => {
    let (include_patterns, exclude_patterns, path) = input
    let config : ProjectConfig = {
      include_patterns,
      exclude_patterns,
      operators: None,
    }
    config.path_enabled(path) ==
    config.path_enabled(path.replace_all(old="\\", new="/"))
  })
}

///|
test "prop path_enabled verdict is path-separator transparent" {
  // A path written with '/' separators and the same path written with
  // '\\' separators must always agree on inclusion and exclusion.
  @quickcheck.check((input : (Array[String], Array[String], String)) => {
    let (include_patterns, exclude_patterns, path) = input
    let config : ProjectConfig = {
      include_patterns,
      exclude_patterns,
      operators: None,
    }
    let forward = path.replace_all(old="\\", new="/")
    let backward = forward.replace_all(old="/", new="\\")
    config.path_enabled(forward) == config.path_enabled(backward)
  })
}

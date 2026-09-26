///|
fn path_join(left : String, right : String) -> String {
  @path.Path(left).join(@path.Path(right)).to_string()
}

///|
fn relative_path(root : String, path : String) -> String {
  @path.Path(path).relative(base=@path.Path(root)).to_string()
}

///|
fn should_skip_dir(name : String) -> Bool {
  name == ".git" ||
  name == "target" ||
  name == "_build" ||
  name == ".mooncakes" ||
  name == ".moon" ||
  name == "node_modules"
}

///|
fn is_test_source(name : String) -> Bool {
  name.has_suffix("_test.mbt") || name.has_suffix("_wbtest.mbt")
}

///|
async fn ensure_moonbit_module(root : String) -> Unit {
  let old_manifest = path_join(root, "moon.mod")
  let json_manifest = path_join(root, "moon.mod.json")
  guard @fs.exists(old_manifest) || @fs.exists(json_manifest) else {
    fail("\{root} is not a MoonBit module (moon.mod not found)")
  }
}

///|
async fn collect_moonbit_files(
  root : String,
  dir : String,
  file_filter : String?,
  project_config : ProjectConfig,
  output : Array[String],
) -> Unit {
  let names = @fs.readdir(dir, include_hidden=true, sort=true)
  for name in names {
    let full = path_join(dir, name)
    let kind = @fs.kind(full)
    if kind is Directory {
      if !should_skip_dir(name) {
        collect_moonbit_files(root, full, file_filter, project_config, output)
      }
      continue
    }
    if !(kind is Regular) || !name.has_suffix(".mbt") || is_test_source(name) {
      continue
    }
    let relative = relative_path(root, full)
    if !project_config.path_enabled(relative) {
      continue
    }
    match file_filter {
      Some(filter) if !relative.contains(filter) => continue
      _ => ()
    }
    output.push(relative)
  }
}

///|
async fn discover_mutations(
  root : String,
  file_filter : String?,
  project_config : ProjectConfig,
) -> Array[Mutation] {
  let files : Array[String] = []
  collect_moonbit_files(root, root, file_filter, project_config, files)
  let mutations : Array[Mutation] = []
  for relative in files {
    let source = @fs.read_file(path_join(root, relative)).text()
    let found = scan_source(relative, source, project_config)
    for mutation in found {
      mutations.push(mutation)
    }
  }
  mutations
}

///|
async fn copy_tree(
  root : String,
  current : String,
  destination : String,
) -> Unit {
  let names = @fs.readdir(current, include_hidden=true, sort=true)
  for name in names {
    let source = path_join(current, name)
    let kind = @fs.kind(source)
    if kind is Directory {
      if should_skip_dir(name) {
        continue
      }
      let relative = relative_path(root, source)
      let target = path_join(destination, relative)
      @fs.mkdir(target, recursive=true, allow_exist=true)
      copy_tree(root, source, destination)
    } else if kind is Regular {
      let relative = relative_path(root, source)
      let target = path_join(destination, relative)
      let parent = @path.Path(target).dirname().to_string()
      @fs.mkdir(parent, recursive=true, allow_exist=true)
      let data = @fs.read_file(source)
      @fs.write_file(target, data)
    }
  }
}

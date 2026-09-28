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
/// A child directory carrying its own module manifest is a separate MoonBit
/// module: the root module's `moon test` never reaches its code, so mutating
/// it would produce false survivors. The root itself is never checked — the
/// caller already validated it as a module.
async fn is_nested_module(dir : String) -> Bool {
  @fs.exists(path_join(dir, "moon.mod")) ||
  @fs.exists(path_join(dir, "moon.mod.json"))
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
      if !should_skip_dir(name) && !is_nested_module(full) {
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
/// The fs API exposes effective access but not raw mode bits, so copies keep
/// the caller's read/write/execute rights — the only user a private temporary
/// workspace serves. A read-only file stays unwritable and a private file
/// stays private.
async fn observed_permission(path : String) -> Int {
  let read = @fs.can_read(path) catch { _ => false }
  let write = @fs.can_write(path) catch { _ => false }
  let execute = @fs.can_execute(path) catch { _ => false }
  let mut permission = 0
  if read {
    permission = permission + 0o400
  }
  if write {
    permission = permission + 0o200
  }
  if execute {
    permission = permission + 0o100
  }
  permission
}

///|
/// Regular files keep their permission bits: the temporary workspace must
/// behave like the original module for baseline parity.
async fn copy_regular_file(source : String, target : String) -> Unit {
  let permission = observed_permission(source)
  let data = @fs.read_file(source)
  @fs.write_file(target, data, permission~)
}

///|
/// Copy a link's resolved target as plain content: used for links that escape
/// the module root and on platforms where creating a symlink is not allowed.
async fn dereference_copy(
  source : String,
  resolved : String,
  target : String,
  relative : String,
) -> Unit {
  let kind = @fs.kind(source)
  if kind is Regular {
    copy_regular_file(source, target)
  } else if kind is Directory {
    @fs.mkdir(target, recursive=true, allow_exist=true)
    copy_tree(resolved, resolved, target)
    // Restore observed permissions only after contents are in place: a
    // non-writable source directory must still accept its own copies.
    @fs.chmod(target, observed_permission(source))
  } else {
    fail("cannot preserve symbolic link \{relative}: unsupported target kind")
  }
}

///|
/// Recreate a symlink inside the workspace. A link that resolves within the
/// module root is re-pointed at the workspace copy; a link that resolves
/// outside the module root is dereference-copied so test runs cannot modify
/// files outside the workspace through it. Where symlink creation is not
/// permitted (e.g. Windows without the required privilege), the resolved
/// content is copied instead.
async fn copy_symlink(
  root : String,
  source : String,
  destination : String,
) -> Unit {
  let relative = relative_path(root, source)
  let target = path_join(destination, relative)
  let parent = @path.Path(target).dirname().to_string()
  @fs.mkdir(parent, recursive=true, allow_exist=true)
  let resolved = @fs.realpath(source) catch {
    _ =>
      fail("cannot preserve symbolic link \{relative}: target does not resolve")
  }
  let module_root = @fs.realpath(root)
  let resolved_relative = @path.Path(resolved)
    .relative(base=@path.Path(module_root))
    .to_string()
  if resolved_relative.has_prefix("..") {
    dereference_copy(source, resolved, target, relative)
  } else {
    @fs.symlink(target, target=path_join(destination, resolved_relative)) catch {
      _ => dereference_copy(source, resolved, target, relative)
    }
  }
}

///|
/// Entries inside a read-only directory cannot be unlinked until the
/// directory becomes writable, so recursive removal loosens directory
/// permissions first. Files need no chmod: unlinking them only requires a
/// writable parent.
async fn make_writable_tree(dir : String) -> Unit {
  @fs.chmod(dir, 0o700) catch {
    _ => return
  }
  let names = @fs.readdir(dir, include_hidden=true, sort=true) catch {
    _ => return
  }
  for name in names {
    let child = path_join(dir, name)
    if @fs.kind(child, follow_symlink=false) is Directory {
      make_writable_tree(child)
    }
  }
}

///|
async fn force_rmdir(path : String) -> Unit {
  make_writable_tree(path)
  @fs.rmdir(path, recursive=true)
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
    let kind = @fs.kind(source, follow_symlink=false)
    if kind is Directory {
      if should_skip_dir(name) {
        continue
      }
      let relative = relative_path(root, source)
      let target = path_join(destination, relative)
      let observed = observed_permission(source)
      @fs.mkdir(target, recursive=true, allow_exist=true)
      copy_tree(root, source, destination)
      // Restore observed permissions only after contents are in place: a
      // non-writable source directory must still accept its own copies.
      @fs.chmod(target, observed)
    } else if kind is Regular {
      let relative = relative_path(root, source)
      let target = path_join(destination, relative)
      let parent = @path.Path(target).dirname().to_string()
      @fs.mkdir(parent, recursive=true, allow_exist=true)
      copy_regular_file(source, target)
    } else if kind is SymLink {
      copy_symlink(root, source, destination)
    }
    // Other kinds (sockets, fifos, devices) are skipped: they cannot be
    // reproduced inside a temporary workspace.
  }
}

///|
async fn write_file(path : String, content : String) -> Unit {
  @fs.write_file(path, content)
}

///|
async fn make_module_tree(dir : String) -> Unit {
  @fs.mkdir(dir, recursive=true)
  write_file(
    path_join(dir, "moon.mod"),
    "name = \"turtles_copy_fixture\"\nversion = \"0.1.0\"\n",
  )
  write_file(path_join(dir, "moon.pkg"), "")
}

///|
async test "copied regular files preserve the executable bit" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let source = path_join(temp, "source")
    make_module_tree(source)
    @fs.write_file(
      path_join(source, "helper.sh"),
      "#!/bin/sh\necho helper-ok\n",
      permission=0o755,
    )
    let workspace = path_join(temp, "workspace")
    @fs.mkdir(workspace, recursive=true)
    copy_tree(source, source, workspace)
    let copied = path_join(workspace, "helper.sh")
    assert_true(@fs.can_execute(copied))
    assert_eq(@fs.read_file(copied).text(), "#!/bin/sh\necho helper-ok\n")
    let data = path_join(source, "data.txt")
    write_file(data, "plain")
    copy_tree(source, source, workspace)
    assert_true(!@fs.can_execute(path_join(workspace, "data.txt")))
  })
}

///|
#cfg(not(platform="windows"))
async test "internal symlinks are recreated inside the workspace" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let source = path_join(temp, "source")
    make_module_tree(source)
    write_file(path_join(source, "real.txt"), "linked fixture data")
    @fs.symlink(path_join(source, "link.txt"), target="real.txt")
    let workspace = path_join(temp, "workspace")
    @fs.mkdir(workspace, recursive=true)
    copy_tree(source, source, workspace)
    let copied = path_join(workspace, "link.txt")
    inspect(@fs.kind(copied, follow_symlink=false) is SymLink, content="true")
    assert_eq(@fs.read_file(copied).text(), "linked fixture data")
    // the recreated link must point inside the workspace, not back to the
    // original tree
    let target = @fs.realpath(copied)
    assert_eq(target, @fs.realpath(path_join(workspace, "real.txt")))
  })
}

///|
#cfg(not(platform="windows"))
async test "symlinks escaping the module root are dereference-copied" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let source = path_join(temp, "source")
    make_module_tree(source)
    let outside = path_join(temp, "outside.txt")
    write_file(outside, "external content")
    @fs.symlink(path_join(source, "external.txt"), target=outside)
    let workspace = path_join(temp, "workspace")
    @fs.mkdir(workspace, recursive=true)
    copy_tree(source, source, workspace)
    let copied = path_join(workspace, "external.txt")
    inspect(@fs.kind(copied, follow_symlink=false) is Regular, content="true")
    assert_eq(@fs.read_file(copied).text(), "external content")
  })
}

///|
#cfg(not(platform="windows"))
async test "dangling symlinks fail instead of being silently dropped" {
  let temp = @fs.tmpdir(prefix="turtles-test")
  @async.with_task_group(group => {
    group.add_defer(() => @fs.rmdir(temp, recursive=true))
    let source = path_join(temp, "source")
    make_module_tree(source)
    @fs.symlink(path_join(source, "missing.txt"), target="no-such-target")
    let workspace = path_join(temp, "workspace")
    @fs.mkdir(workspace, recursive=true)
    let mut raised = false
    copy_tree(source, source, workspace) catch {
      _ => raised = true
    }
    assert_true(raised)
  })
}

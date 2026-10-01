///|
/// Property suggestions (`--emit-properties`): per final survivor, write
/// `<output>/properties/<mutant-id>.mbt` — ready-to-drop QuickCheck
/// skeletons chosen by signature shape. Files only; user tests are never
/// touched. Stale files carrying the marker are swept; unmarked files are
/// never deleted.

///|
let property_marker : String = "// turtles: generated property suggestion"

///|
/// The package qualifier for generated calls: the module name's last
/// segment for the root package, else the package dir's last segment.
fn pkg_qualifier(entry : FnInfo, module_name : String?) -> String {
  let base = if entry.pkg == "." {
    match module_name {
      Some(name) => name
      None => entry.pkg
    }
  } else {
    entry.pkg
  }
  match base.rev_find("/") {
    Some(slash) => base[slash + 1:].to_owned()
    None => base
  }
}

///|
/// `f(e0, e1, ...)` honouring each parameter's label.
fn call_with(callee : String, entry : FnInfo, exprs : Array[String]) -> String {
  let args : Array[String] = []
  for i, param in entry.params {
    let expr = if i < exprs.length() { exprs[i] } else { "_" }
    match param.label {
      Some(label) => args.push("\{label} = \{expr}")
      None => args.push(expr)
    }
  }
  let joined = args.join(", ")
  "\{callee}(\{joined})"
}

///|
/// One suggested test block over an input tuple of `types`.
fn suggestion_test(
  buf : StringBuilder,
  mutid : String,
  name : String,
  types : Array[String],
  binders : Array[String],
  body : String,
) -> Unit {
  let (input_ty, destructure) = match types.length() {
    0 => ("Int", "")
    1 => (types[0], "    let \{binders[0]} = args\n")
    _ => {
      let type_list = types.join(", ")
      let binder_list = binders.join(", ")
      ("(\{type_list})", "    let (\{binder_list}) = args\n")
    }
  }
  buf.write_string("///|\ntest \"turtles suggestion \{mutid} \{name}\" {\n")
  buf.write_string("  @quickcheck.check((args : \{input_ty}) => {\n")
  buf.write_string(destructure)
  buf.write_string("    \{body}\n")
  buf.write_string("  })\n}\n\n")
}

///|
/// Round-trip pairing: `encode*`/`serialize*`/`marshal*`/`to_*` fns match a
/// `decode*`/`deserialize*`/`unmarshal*`/`parse*`/`from_*` counterpart in
/// the same package (and vice versa).
fn roundtrip_partner(pkg : PkgIndex, entry : FnInfo) -> String? {
  let forward = ["encode", "serialize", "marshal", "to_"]
  let backward = ["decode", "deserialize", "unmarshal", "parse", "from_"]
  for prefixes in [[forward, backward], [backward, forward]] {
    let from = prefixes[0]
    let to = prefixes[1]
    for prefix in from {
      if entry.name.has_prefix(prefix) {
        let rest = entry.name[prefix.length():].to_owned()
        for target in to {
          let candidate = "\{target}\{rest}"
          if candidate != entry.name && pkg.fns.contains(candidate) {
            return Some(candidate)
          }
        }
      }
    }
  }
  None
}

///|
/// The suggestion file body: marker, target record, mutant comment, then
/// shape-chosen tests.
fn suggestion_file(
  entry : FnInfo,
  pkg : PkgIndex,
  result : MutationResult,
  target : String?,
  module_name : String?,
) -> String {
  let qualifier = pkg_qualifier(entry, module_name)
  let callee = "@\{qualifier}.\{entry.name}"
  let mutid = mutation_id(result.mutation)
  let target_line = match target {
    Some(t) => "// target: \{t}"
    None => "// target: none"
  }
  let buf = StringBuilder()
  buf.write_string("\{property_marker}\n\{target_line}\n")
  buf.write_string(
    "// mutant: \{mutid} (\{describe_mutation(result.mutation)})\n// function: \{callee} in \{entry.file}\n//\n// Review before dropping into the package's tests; the checks below are\n// skeletons, not proofs.\n\n",
  )
  let types = entry.params.map(param => param.ty_text.trim().to_owned())
  let binders : Array[String] = []
  for i in 0..<types.length() {
    binders.push("arg\{i}")
  }
  let same = fn(a : String, b : String) { a.trim() == b.trim() }
  let ret_text = entry.ret_text.trim().to_owned()
  let all_same = types.length() > 0 &&
    entry.ret is Some(_) &&
    types.iter().all(t => same(t, ret_text))
  if entry.params.length() == 1 && all_same {
    suggestion_test(
      buf,
      mutid,
      "idempotent",
      types,
      binders,
      "\{call_with(callee, entry, [call_with(callee, entry, binders)])} == \{call_with(callee, entry, binders)}",
    )
    suggestion_test(
      buf,
      mutid,
      "involution",
      types,
      binders,
      "\{call_with(callee, entry, [call_with(callee, entry, binders)])} == \{binders[0]}",
    )
  } else if entry.params.length() == 2 && all_same {
    suggestion_test(
      buf,
      mutid,
      "commutative",
      types,
      binders,
      "\{call_with(callee, entry, binders)} == \{call_with(callee, entry, [binders[1], binders[0]])}",
    )
    let three = [types[0], types[0], types[0]]
    let abc = ["a", "b", "c"]
    let inner = call_with(callee, entry, ["a", "b"])
    let inner2 = call_with(callee, entry, ["b", "c"])
    let left = call_with(callee, entry, [inner, "c"])
    let right = call_with(callee, entry, ["a", inner2])
    suggestion_test(
      buf,
      mutid,
      "associative",
      three,
      abc,
      "\{left} == \{right}",
    )
  } else {
    match roundtrip_partner(pkg, entry) {
      Some(partner) => {
        let inner_call = call_with(callee, entry, binders)
        suggestion_test(
          buf,
          mutid,
          "round-trip",
          types,
          binders,
          "@\{qualifier}.\{partner}(\{inner_call}) == \{binders[0]}",
        )
      }
      None => {
        let (input_ty, destructure) = match types.length() {
          0 => ("Int", "")
          1 => (types[0], "    let arg0 = args\n")
          _ => {
            let type_list = types.join(", ")
            let binder_list = binders.join(", ")
            ("(\{type_list})", "    let (\{binder_list}) = args\n")
          }
        }
        buf.write_string(
          "///|\n// TODO: replace the body with a real property of \{callee}; the stub\n// only exercises that the call returns.\ntest \"turtles suggestion \{mutid} stub\" {\n  @quickcheck.check((args : \{input_ty}) => {\n\{destructure}    let _ = \{call_with(callee, entry, binders)}\n    true\n  })\n}\n\n",
        )
      }
    }
  }
  buf.to_string()
}

///|
/// Emit the live property files into `<output>/properties/` and sweep
/// stale marker-bearing files. Returns the sorted live list (as
/// `properties/<id>.mbt` paths) for the report.
async fn emit_property_files(
  output_dir : String,
  results : Array[MutationResult],
  index : ModuleIndex,
  module_name : String?,
  target : String?,
) -> Array[String] {
  let dir = path_join(output_dir, "properties")
  if !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  let live : Map[String, Bool] = Map([])
  for result in results {
    if !(result.outcome is Survived) {
      continue
    }
    let entry = match enclosing_fn(index, result.mutation) {
      Some(entry) => entry
      None => continue
    }
    if !suggestible(entry) {
      continue
    }
    let pkg = match index.pkgs.get(entry.pkg) {
      Some(pkg) => pkg
      None => continue
    }
    let mutid = mutation_id(result.mutation)
    let name = "\{mutid}.mbt"
    live[name] = true
    let body = suggestion_file(entry, pkg, result, target, module_name)
    @fs.write_file(path_join(dir, name), body) catch {
      _ => ()
    }
  }
  // Sweep stale marker files; anything without the marker is user content
  // and stays untouched.
  for name in @fs.readdir(dir, include_hidden=false, sort=true) {
    if !name.has_suffix(".mbt") || live.contains(name) {
      continue
    }
    let full = path_join(dir, name)
    let kind = @fs.kind(full) catch { _ => continue }
    if !(kind is Regular) {
      continue
    }
    let text = @fs.read_file(full).text() catch { _ => continue }
    if text.has_prefix(property_marker) {
      @fs.remove(full) catch {
        _ => ()
      }
    }
  }
  let listed : Array[String] = []
  for name, _ in live {
    listed.push("properties/\{name}")
  }
  listed.sort()
  listed
}

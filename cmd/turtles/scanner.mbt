///|
struct OpSpec {
  group : OperatorGroup
  original : String
  replacement : String
}

///|
fn operator_specs() -> Array[OpSpec] {
  [
    { group: Comparison, original: "==", replacement: "!=", },
    { group: Comparison, original: "!=", replacement: "==", },
    { group: Comparison, original: ">=", replacement: "<", },
    { group: Comparison, original: "<=", replacement: ">", },
    { group: Boolean, original: "&&", replacement: "||", },
    { group: Boolean, original: "||", replacement: "&&", },
    { group: Literal, original: "true", replacement: "false", },
    { group: Literal, original: "false", replacement: "true", },
    { group: Arithmetic, original: "+", replacement: "-", },
    { group: Arithmetic, original: "-", replacement: "+", },
    { group: Arithmetic, original: "*", replacement: "/", },
    { group: Arithmetic, original: "/", replacement: "*", },
    { group: Comparison, original: ">", replacement: "<", },
    { group: Comparison, original: "<", replacement: ">", },
  ]
}

///|
/// Parser locations use Unicode-scalar offsets in the default lexer mode.
/// Mutation application, however, slices UTF-8 bytes. Build an explicit
/// boundary table once so parser locations are never confused with bytes.
fn utf8_width(byte : Byte) -> Int {
  let value = byte.to_int()
  if value < 0x80 {
    1
  } else if value < 0xE0 {
    2
  } else if value < 0xF0 {
    3
  } else {
    4
  }
}

///|
fn source_byte_boundaries(bytes : Bytes) -> Array[Int] {
  let boundaries : Array[Int] = [0]
  let mut byte_index = 0
  while byte_index < bytes.length() {
    let width = utf8_width(bytes[byte_index])
    if byte_index + width > bytes.length() {
      panic()
    }
    byte_index = byte_index + width
    boundaries.push(byte_index)
  }
  boundaries
}

///|
fn source_byte_offset(boundaries : Array[Int], scalar_offset : Int) -> Int {
  if scalar_offset < 0 || scalar_offset >= boundaries.length() {
    panic()
  }
  boundaries[scalar_offset]
}

///|
fn same_mutation_identity(left : Mutation, right : Mutation) -> Bool {
  left.path == right.path &&
  left.start == right.start &&
  left.end == right.end &&
  left.replacement == right.replacement
}

///|
struct AstCandidateVisitor {
  path : String
  bytes : Bytes
  boundaries : Array[Int]
  specs : Array[OpSpec]
  project_config : ProjectConfig
  mutations : Array[Mutation]
}

///|
fn AstCandidateVisitor::append_mutation(
  self : AstCandidateVisitor,
  group : OperatorGroup,
  original : String,
  replacement : String,
  start : Int,
  end : Int,
  line : Int,
  column : Int,
) -> Unit {
  if original == replacement {
    return
  }
  let mutation = {
    path: self.path,
    start,
    end,
    line,
    column,
    group,
    original,
    replacement,
  }
  let mut duplicate = false
  for previous in self.mutations {
    if same_mutation_identity(previous, mutation) {
      duplicate = true
      break
    }
  }
  if !duplicate {
    self.mutations.push(mutation)
  }
}

///|
fn AstCandidateVisitor::record(
  self : AstCandidateVisitor,
  spec : OpSpec,
  start_scalar : Int,
  end_scalar : Int,
  line : Int,
  column : Int,
) -> Unit {
  if !self.project_config.operator_enabled(spec.group) {
    return
  }
  let start = source_byte_offset(self.boundaries, start_scalar)
  let end = source_byte_offset(self.boundaries, end_scalar)
  if end < start || end > self.bytes.length() {
    panic()
  }
  if @utf8.decode_lossy(self.bytes[start:end]) != spec.original {
    panic()
  }
  self.append_mutation(
    spec.group,
    spec.original,
    spec.replacement,
    start,
    end,
    line,
    column,
  )
}

///|
/// Record a replacement whose original text is the complete source range.
fn AstCandidateVisitor::record_range(
  self : AstCandidateVisitor,
  group : OperatorGroup,
  replacement : String,
  start_scalar : Int,
  end_scalar : Int,
  line : Int,
  column : Int,
) -> Unit {
  if !self.project_config.operator_enabled(group) {
    return
  }
  let start = source_byte_offset(self.boundaries, start_scalar)
  let end = source_byte_offset(self.boundaries, end_scalar)
  if end < start || end > self.bytes.length() {
    panic()
  }
  let original = @utf8.decode_lossy(self.bytes[start:end])
  self.append_mutation(group, original, replacement, start, end, line, column)
}

///|
fn AstCandidateVisitor::record_operator(
  self : AstCandidateVisitor,
  original : String,
  start_scalar : Int,
  end_scalar : Int,
  line : Int,
  column : Int,
) -> Unit {
  for spec in self.specs {
    if spec.original == original {
      self.record(spec, start_scalar, end_scalar, line, column)
      break
    }
  }
}

///|
impl @syntax.IterVisitor for AstCandidateVisitor with fn visit_Expr_Infix(
  self,
  op~,
  lhs~,
  rhs~,
  loc~,
) {
  match op.name {
    @syntax.LongIdent::Ident(name=original) =>
      self.record_operator(
        original,
        op.loc.start.cnum,
        op.loc.end.cnum,
        op.loc.start.lnum,
        op.loc.start.column(),
      )
    _ => ()
  }
  @syntax.IterVisitor::visit_Expr_Infix(
    @syntax.IterVisitor::base(self),
    op~,
    lhs~,
    rhs~,
    loc~,
  )
}

///|
impl @syntax.IterVisitor for AstCandidateVisitor with fn visit_Expr_Constant(
  self,
  c~,
  loc~,
) {
  match c {
    @syntax.Constant::Bool(value) => {
      let original = if value { "true" } else { "false" }
      self.record_operator(
        original,
        loc.start.cnum,
        loc.end.cnum,
        loc.start.lnum,
        loc.start.column(),
      )
    }
    _ => ()
  }
  @syntax.IterVisitor::visit_Expr_Constant(
    @syntax.IterVisitor::base(self),
    c~,
    loc~,
  )
}

///|
impl @syntax.IterVisitor for AstCandidateVisitor with fn visit_Expr_If(
  self,
  cond~,
  ifso~,
  ifnot~,
  loc~,
) {
  let condition_loc = cond.loc()
  self.record_range(
    Boolean,
    "true",
    condition_loc.start.cnum,
    condition_loc.end.cnum,
    condition_loc.start.lnum,
    condition_loc.start.column(),
  )
  self.record_range(
    Boolean,
    "false",
    condition_loc.start.cnum,
    condition_loc.end.cnum,
    condition_loc.start.lnum,
    condition_loc.start.column(),
  )
  @syntax.IterVisitor::visit_Expr_If(
    @syntax.IterVisitor::base(self),
    cond~,
    ifso~,
    ifnot~,
    loc~,
  )
}

///|
fn scan_source(
  path : String,
  source : String,
  project_config : ProjectConfig,
) -> Array[Mutation] raise {
  let bytes = @utf8.encode(source)
  let visitor = AstCandidateVisitor::{
    path,
    bytes,
    boundaries: source_byte_boundaries(bytes),
    specs: operator_specs(),
    project_config,
    mutations: [],
  }
  let (impls, reports) = @parser.parse_string(source, name=path)
  if reports.length() != 0 {
    fail(
      "parser failed for \{path}: \{reports.length()} diagnostic(s); refusing lexical fallback",
    )
  }
  impls.each(impl_ => @syntax.IterVisitor::visit_Impl(visitor, impl_))
  visitor.mutations
}

///|
fn apply_mutation(source : String, mutation : Mutation) -> String raise {
  let bytes = @utf8.encode(source)
  guard mutation.start >= 0 &&
    mutation.end >= mutation.start &&
    mutation.end <= bytes.length() else {
    fail("mutation offsets are outside the source")
  }
  guard @utf8.decode(bytes[mutation.start:mutation.end]) == mutation.original else {
    fail("source changed after mutation discovery")
  }
  let output = @buffer.Buffer(
    size_hint=bytes.length() + mutation.replacement.length(),
  )
  output.write_bytes(bytes[:mutation.start])
  output.write_string_utf8(mutation.replacement)
  output.write_bytes(bytes[mutation.end:])
  @utf8.decode(output.to_bytes())
}

///|
fn describe_mutation(mutation : Mutation) -> String {
  "\{mutation.path}:\{mutation.line}:\{mutation.column}: \{mutation.original} -> \{mutation.replacement}"
}

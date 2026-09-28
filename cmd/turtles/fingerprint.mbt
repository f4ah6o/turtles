///|
/// FNV-1a 64-bit over bytes. Not a cryptographic hash — it only answers
/// "did this file change", which is all workspace fingerprints need.
fn fnv1a(bytes : Bytes) -> UInt64 {
  let mut hash : UInt64 = 0xcbf29ce484222325
  for byte in bytes {
    hash = (hash ^ byte.to_int().to_uint64()) * 0x100000001b3
  }
  hash
}

///|
fn fingerprint_hex(hash : UInt64) -> String {
  let digits = b"0123456789abcdef"
  let output = StringBuilder(size_hint=16)
  let mut shift = 60
  while shift >= 0 {
    let nibble = ((hash >> shift) & 0xFUL).to_int()
    output.write_char(digits[nibble].to_char())
    shift = shift - 4
  }
  output.to_string()
}

///|
fn fingerprint_text(text : String) -> String {
  fingerprint_hex(fnv1a(@utf8.encode(text)))
}

///|
/// Stable, content-anchored mutant identity: the file, the exact byte span,
/// both texts, and the operator group. Line numbers are deliberately absent —
/// edits above the mutant must not change its identity. NUL separators keep
/// the concatenation unambiguous since no field can contain NUL.
fn mutation_identity(mutation : Mutation) -> String {
  "\{mutation.path}\u{0}\{mutation.start}\u{0}\{mutation.end}\u{0}\{mutation.original}\u{0}\{mutation.replacement}\u{0}\{operator_group_name(mutation.group)}"
}

///|
fn mutation_id(mutation : Mutation) -> String {
  "m-\{fingerprint_text(mutation_identity(mutation))}"
}

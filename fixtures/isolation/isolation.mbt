///|
pub fn sign(a : Int, b : Int) -> Int {
  if a > b {
    1
  } else {
    0
  }
}

///|
/// Deliberately untested: its mutants should survive. If state from a
/// previous run leaked into the workspace they would be misclassified.
pub fn pick(a : Int, b : Int) -> Int {
  if a < b {
    b
  } else {
    a
  }
}

///|
pub fn common_add(a : Int, b : Int) -> Int {
  a + b
}

///|
/// Equivalent-mutant survivor on every backend.
pub fn common_keep(x : Int) -> Int {
  x + 0
}

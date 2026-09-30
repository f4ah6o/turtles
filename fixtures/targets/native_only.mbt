///|
pub fn native_pick(a : Int, b : Int) -> Int {
  a * b
}

///|
/// `x + 0` -> `x - 0` is an equivalent mutant: it survives on native so
/// analyses emit artifacts for it, and is target-inactive elsewhere.
pub fn native_keep(x : Int) -> Int {
  x + 0
}

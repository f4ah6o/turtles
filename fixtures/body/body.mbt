///|
/// Body mutants (`a + b` replaced by `0`, `1`, `-1`) are all killed by the
/// `total` test below.
pub fn total(a : Int, b : Int) -> Int {
  a + b
}

///|
/// The `None` body mutant survives: the test pins the empty case only.
pub fn first(items : Array[Int]) -> Int? {
  if items.is_empty() {
    None
  } else {
    Some(items[0])
  }
}

///|
#turtles.skip
pub fn fragile(a : Int, b : Int) -> Int {
  a + b
}

// turtles: skip
///|
pub fn also_skipped(flag : Bool) -> Bool {
  flag && flag
}

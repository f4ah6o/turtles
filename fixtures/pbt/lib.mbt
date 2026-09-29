///|
pub fn clamp(x : Int, lo : Int, hi : Int) -> Int {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
pub fn abs_diff(a : Int, b : Int) -> Int {
  if a > b {
    a - b
  } else {
    b - a
  }
}

///|
pub fn rev_pair(pair : (Int, Int)) -> (Int, Int) {
  (pair.1, pair.0)
}

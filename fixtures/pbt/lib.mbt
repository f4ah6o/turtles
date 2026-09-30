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

///|
let tally_hits : Ref[Int] = { val: 0 }

///|
/// Reads and writes module state — never witness-eligible.
pub fn tally(x : Int) -> Int {
  tally_hits.val = tally_hits.val + 1
  x + 0
}

///|
/// Self-recursive: witness is skipped on the SCC, not the call shape.
pub fn down(n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    down(n - 1) + 0
  }
}

///|
/// Mutual recursion via `odd_to_zero`.
pub fn even_to_zero(n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    odd_to_zero(n - 1)
  }
}

///|
/// Mutual recursion via `even_to_zero`.
pub fn odd_to_zero(n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    even_to_zero(n - 1) + 0
  }
}

///|
/// Pre-existing user symbol shaped like the witness helper name — the
/// harness must still produce a witness under its own identifier.
pub fn halved__turtles_orig(x : Int) -> Int {
  x / 2
}

///|
pub fn halved(x : Int) -> Int {
  x / 2 + 0
}

///|
/// Identity function; the else branch is only reachable at x == -11 so a
/// mutation confined there survives the default 100-case budget and only
/// dies under amplification.
pub fn hole(x : Int) -> Int {
  if x != -11 {
    x
  } else {
    0 + x
  }
}

///|
/// The fixture property only observes k == 0, so mutations inside the k
/// term survive the test suite but still diverge from the original —
/// the differential witness's falsified case.
pub fn tweak(a : Int, k : Int) -> Int {
  a + k * 2
}

///|
/// Equivalent mutants (`x + 0` -> `x - 0`) survive with a `none` witness.
pub fn plus_zero(x : Int) -> Int {
  x + 0
}

///|
/// Collides with the witness helper's first candidate name for `halved`'s
/// surviving mutant (m-9244b2daa5e3b90c): the harness must retry its own
/// identifier suffix and still produce a witness — never UNVIABLE.
pub fn halved__turtles_orig__mut9244b2daa5e3b90c(x : Int) -> Int {
  x + 1
}

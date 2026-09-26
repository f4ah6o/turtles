///|
pub fn add(a : Int, b : Int) -> Int {
  a + b
}

///|
pub fn greater(a : Int, b : Int) -> Bool {
  a > b
}

///|
pub fn both(a : Bool, b : Bool) -> Bool {
  a && b
}

///|
pub fn enabled() -> Bool {
  true
}

///|
pub fn choose(flag : Bool) -> Int {
  if flag { 1 } else { 2 }
}

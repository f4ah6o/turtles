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

///|
/// One function per `body` replacement-table entry: every mutant produced
/// for these must type-check (`moon check`), never report UNVIABLE.
pub fn widen16(a : Int16) -> Int16 {
  a
}

///|
pub fn upper16(a : UInt16) -> UInt16 {
  a
}

///|
pub fn big(a : Int64) -> Int64 {
  a
}

///|
pub fn ubig(a : UInt64) -> UInt64 {
  a
}

///|
pub fn unsigned(a : UInt) -> UInt {
  a
}

///|
pub fn byte_of(a : Byte) -> Byte {
  a
}

///|
pub fn flip(flag : Bool) -> Bool {
  flag
}

///|
pub fn twice(value : Float) -> Float {
  value
}

///|
pub fn dd(value : Double) -> Double {
  value
}

///|
pub fn echo(text : String) -> String {
  text
}

///|
pub fn wrap(value : Int) -> Int? {
  Some(value)
}

///|
pub fn boxed(value : Int) -> Option[Int] {
  Some(value)
}

///|
pub fn items() -> Array[Int] {
  [1, 2]
}

///|
pub fn fixed() -> FixedArray[Int] {
  [1, 2]
}

///|
pub fn table() -> Map[String, Int] {
  { "a": 1 }
}

///|
pub fn bump(counter : Counter) -> Unit {
  counter.value = counter.value + 1
}

///|
pub fn clear(counter : Counter) -> Unit {
  counter.value = 0
}

///|
/// A `raise` body: replacement keeps the signature and simply does not raise.
pub fn risky(flag : Bool) -> Int raise {
  if flag {
    1
  } else {
    fail("boom")
  }
}

///|
pub(all) struct Counter {
  mut value : Int
}

///|
pub trait Sized {
  size(Self) -> Int
}

///|
/// Method body in an `impl` block — mutated through the same table.
pub impl Sized for Counter with size(self) {
  self.value
}

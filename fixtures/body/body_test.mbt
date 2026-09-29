///|
test "total" {
  inspect(total(2, 3), content="5")
}

///|
test "first" {
  inspect(first([]) is None, content="true")
}

///|
test "widen16" {
  inspect(widen16(7), content="7")
}

///|
test "upper16" {
  inspect(upper16(7), content="7")
}

///|
test "big" {
  inspect(big(7), content="7")
}

///|
test "ubig" {
  inspect(ubig(7), content="7")
}

///|
test "unsigned" {
  inspect(unsigned(7), content="7")
}

///|
test "byte_of" {
  inspect(byte_of(9), content="b'\\x09'")
}

///|
test "flip" {
  inspect(flip(true), content="true")
  inspect(flip(false), content="false")
}

///|
test "twice" {
  inspect(twice(2.5), content="2.5")
}

///|
test "dd" {
  inspect(dd(3.5), content="3.5")
}

///|
test "echo" {
  inspect(echo("hi"), content="hi")
}

///|
test "wrap" {
  inspect(wrap(3), content="Some(3)")
}

///|
test "boxed" {
  inspect(boxed(3), content="Some(3)")
}

///|
test "items" {
  inspect(items().length(), content="2")
}

///|
test "fixed" {
  inspect(fixed().length(), content="2")
}

///|
test "table" {
  inspect(table().length(), content="1")
}

///|
test "bump" {
  let counter : Counter = { value: 0 }
  bump(counter)
  inspect(counter.value, content="1")
}

///|
test "clear" {
  let counter : Counter = { value: 5 }
  clear(counter)
  inspect(counter.value, content="0")
}

///|
test "risky" {
  inspect(risky(true) catch { _ => -1 }, content="1")
}

///|
test "size" {
  let counter : Counter = { value: 3 }
  inspect(counter.size(), content="3")
}

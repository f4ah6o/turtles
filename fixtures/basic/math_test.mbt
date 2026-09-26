///|
test "add" {
  inspect(add(2, 3), content="5")
}

///|
test "greater" {
  inspect(greater(3, 2), content="true")
  inspect(greater(2, 3), content="false")
}

///|
test "both" {
  inspect(both(true, false), content="false")
  inspect(both(true, true), content="true")
}

///|
test "enabled" {
  inspect(enabled(), content="true")
}

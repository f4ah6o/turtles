///|
test "total" {
  inspect(total(2, 3), content="5")
}

///|
test "first" {
  inspect(first([]) is None, content="true")
}

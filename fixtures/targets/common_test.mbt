///|
test "common_add" {
  inspect(common_add(1, 2), content="3")
}

///|
test "common_keep" {
  inspect(common_keep(5), content="5")
}

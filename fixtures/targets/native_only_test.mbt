///|
test "native_pick" {
  inspect(native_pick(2, 3), content="6")
}

///|
test "native_keep" {
  inspect(native_keep(5), content="5")
}

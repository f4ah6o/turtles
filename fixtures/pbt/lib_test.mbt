///|
test "prop clamp returns x inside the range" {
  @quickcheck.check((args : (Int, Int, Int)) => {
    let (x, lo, hi) = args
    if lo > hi || x < lo || x > hi {
      true
    } else {
      @turtles_pbt_fixture.clamp(x, lo, hi) == x
    }
  })
}

///|
test "prop abs_diff is symmetric and reflexive-zero" {
  @quickcheck.check((args : (Int, Int)) => {
    let (a, b) = args
    @turtles_pbt_fixture.abs_diff(a, b) ==
    @turtles_pbt_fixture.abs_diff(b, a) &&
    (a != b || @turtles_pbt_fixture.abs_diff(a, b) == 0)
  })
}

///|
test "prop rev_pair is an involution" {
  @quickcheck.check(
    (pair : (Int, Int)) => @turtles_pbt_fixture.rev_pair(
      @turtles_pbt_fixture.rev_pair(pair),
    ) ==
    pair,
  )
}

///|
test "snapshot clamp" {
  inspect(@turtles_pbt_fixture.clamp(5, 0, 10), content="5")
  inspect(@turtles_pbt_fixture.clamp(-3, 0, 10), content="0")
  inspect(@turtles_pbt_fixture.clamp(15, 0, 10), content="10")
}

///|
test "example abs_diff" {
  assert_eq(@turtles_pbt_fixture.abs_diff(7, 0), 7)
}

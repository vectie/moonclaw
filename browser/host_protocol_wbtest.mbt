///|
test "host protocol JSON remains process portable" {
  assert_eq(Completed.to_json().stringify(), "\"Completed\"")
  assert_eq(
    Crashed("exit-17").to_json().stringify(),
    "[\"Crashed\",\"exit-17\"]",
  )
}

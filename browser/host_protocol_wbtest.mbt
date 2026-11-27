///|
test "host protocol JSON remains process portable" {
  assert_eq(ToJson::to_json(Completed).stringify(), "\"Completed\"")
  assert_eq(
    ToJson::to_json(Crashed("exit-17")).stringify(),
    "[\"Crashed\",\"exit-17\"]",
  )
}

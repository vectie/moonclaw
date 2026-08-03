///|
test "normalized_external_execution_mode trims blanks" {
  assert_eq(normalized_external_execution_mode(Some("  acp  ")), Some("acp"))
  assert_eq(normalized_external_execution_mode(Some("   ")), None)
  assert_eq(normalized_external_execution_mode(None), None)
}

///|
test "unsupported_external_execution_mode renders clear message" {
  inspect(
    unsupported_external_execution_mode("robot"),
    content="Unsupported external execution mode: robot",
  )
}

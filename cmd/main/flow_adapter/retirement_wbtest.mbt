///|
test "legacy flow-adapter CLI is a fail-closed historical boundary" {
  assert_true(retirement_message().contains("flow-adapter is retired"))
  assert_true(retirement_message().contains("exact installed-pack capability"))
}

///|
test "proposal recovery only cancels non-terminal run states" {
  assert_true(is_recoverable_run_status(Pending))
  assert_true(is_recoverable_run_status(Running))
  assert_true(is_recoverable_run_status(WaitingForInput))
  assert_false(is_recoverable_run_status(Succeeded))
  assert_false(is_recoverable_run_status(Failed))
  assert_false(is_recoverable_run_status(Cancelled))
}

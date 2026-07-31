///|
test "operator journey chooses one goal action and a safe recovery" {
  let start = operator_next_step_for(false, 0, 0, 0, 0)
  assert_eq(start.position, 1)
  assert_eq(start.action, "cowork")
  let active = operator_next_step_for(false, 1, 1, 0, 0)
  assert_eq(active.position, 4)
  assert_eq(active.action, "jobs")
  let failed = operator_next_step_for(false, 1, 0, 1, 0)
  assert_true(failed.blocked)
  assert_eq(failed.action_label, "Review blocked run")
  let retry = operator_next_step_for(true, 1, 0, 0, 0)
  assert_true(retry.blocked)
  assert_eq(retry.action, "retry")
  let result = operator_next_step_for(false, 1, 0, 0, 1)
  assert_eq(result.position, 5)
  assert_eq(result.action_label, "Inspect result")
}

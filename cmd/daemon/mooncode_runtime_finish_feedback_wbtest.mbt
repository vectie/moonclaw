///|
test "missing explicit check returns actionable finish feedback" {
  let command = completion_test_command()
  let plan : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": ([{ "tool": "finish" }] : Array[Json]),
  }
  let calls : Array[Json] = [{ "tool": "finish" }]
  let results : Array[Json] = [{ "tool": "finish", "accepted": true }]
  assert_eq(mooncode_runtime_horizon_explicit_id(command), "")
  assert_eq(mooncode_runtime_horizon_id(command), "completion-command")
  assert_true(
    mooncode_runtime_turn_recoverable_horizon_finish(
      command, plan, calls, results,
    ),
  )
  let message = mooncode_runtime_turn_horizon_finish_rejection_message(
    command, calls, results,
  )
  assert_true(message.contains("Completion was rejected"))
  assert_true(message.contains("Continue the same task"))
  assert_false(message.contains("final all-done checkpoint"))
}

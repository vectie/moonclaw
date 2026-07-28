///|
test "implicit default horizon rejected finish feedback" {
  let command = @json.parse(
    "{\"command\":\"prompt\",\"text\":\"Edit code and run tests.\",\"packet\":{\"command_id\":\"default-horizon-finish\"}}",
  )
  let plan : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": ([{ "tool": "finish" }] : Array[Json]),
  }
  let calls : Array[Json] = [{ "tool": "finish" }]
  let results : Array[Json] = [{ "tool": "finish", "accepted": true }]
  assert_true(mooncode_runtime_turn_requires_verification(command))
  assert_eq(mooncode_runtime_horizon_explicit_id(command), "")
  assert_eq(mooncode_runtime_horizon_id(command), "default-horizon-finish")
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
  assert_true(message.contains("final all-done checkpoint"))
}

///|
test "durable terminal failure takes precedence over earlier assistant answer" {
  let turn = mooncode_conversation_turn_draft(
    turn_id="cmd-1",
    client_turn_id="client-1",
    command_id="cmd-1",
    created_at="2026-09-26T00:00:00Z",
  )
  let assistant : Json = {
    "role": "assistant",
    "content": "A partial answer",
    "status": "done",
  }
  turn.status = "failed"
  assert_eq(mooncode_conversation_final_status(turn, assistant), "failed")
  turn.status = "cancelled"
  assert_eq(mooncode_conversation_final_status(turn, assistant), "cancelled")
}

///|
test "a failed tool remains visible while the same request continues" {
  let command = mooncode_claim_projection_command("/book", "live-recovery")
  let failed = mooncode_tool_result_event(
    "live-recovery",
    "/book",
    "claim-projection-command",
    "read",
    mooncode_tool_error_result("read", message="file not found"),
    now=@clock.Timestamp::from_ms(1L),
  )
  let planning : Json = {
    "command_id": "claim-projection-command",
    "kind": "runtime.planner_started",
    "status": "running",
  }
  let active = mooncode_conversation_turns([command], [], [failed, planning])[0]
  assert_eq(active.status, "running")
  assert_true(
    active.work_steps.any(step => {
      mooncode_json_string(step, "status", default="") == "failed"
    }),
  )
  let terminal : Json = {
    "command_id": "claim-projection-command",
    "kind": "runtime.turn_finished",
    "status": "failed",
  }
  let stopped = mooncode_conversation_turns([command], [], [
      failed, planning, terminal,
    ])[0]
  assert_eq(stopped.status, "failed")
}

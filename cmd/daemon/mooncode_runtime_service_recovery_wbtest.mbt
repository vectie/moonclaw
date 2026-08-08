///|
test "runtime service recovers only an unresolved valid approval checkpoint" {
  let session_id = "session-service-approval-recovery"
  let command_id = "command-service-approval-recovery"
  let tool_call : Json = {
    "tool": "shell",
    "arguments": { "cmd": "rm -rf _build/js" },
    "tool_call_id": "shell-rebuild",
    "planner": "model-tool-call",
  }
  let plan : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [tool_call],
  }
  let approval_id = mooncode_runtime_tool_approval_id(
    command_id,
    tool_call,
    occurrence=0,
  )
  let request : Json = {
    "approval_id": approval_id,
    "target_command_id": command_id,
    "state": "pending",
  }
  let checkpoint = mooncode_runtime_continuation_event(
    session_id,
    command_id,
    plan,
    [plan],
    [],
    [],
    request,
    step_index=0,
    tool_index=0,
    planner_turn_end_step=0,
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(
    mooncode_runtime_service_pending_approval([request, checkpoint]) is Some(_),
  )
  let approved : Json = {
    "approval_id": approval_id,
    "target_command_id": command_id,
    "state": "approved",
  }
  assert_true(
    mooncode_runtime_service_pending_approval([request, checkpoint, approved])
    is None,
  )
  assert_true(
    mooncode_runtime_service_pending_approval([
      request,
      mooncode_json_object_with_field(
        checkpoint,
        "tool_index",
        Json::number(1.0),
      ),
    ])
    is None,
  )
}

///|
test "runtime service journal errors retain their diagnostic payload" {
  inspect(
    mooncode_runtime_service_error_detail(InvalidJournal("bad checkpoint")),
    content="MoonCode journal invalid: bad checkpoint",
  )
}

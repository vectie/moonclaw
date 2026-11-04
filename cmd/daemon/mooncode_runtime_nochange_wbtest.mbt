///|
fn nochange_test_policy() -> Json {
  {
    "required_checks": [
      {
        "id": "required-tests",
        "tool": "shell",
        "command": "moon test --no-render",
        "cwd": ".",
      },
    ],
  }
}

///|
fn nochange_test_command(policy~ : Json = nochange_test_policy()) -> Json {
  {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "session_id": "nochange-session",
    "book_root": "/synthetic/source",
    "packet": { "command_id": "nochange-command" },
    "text": "Implement the requested behavior and run tests.",
    "payload": { "task_intent": "workspace_change", "task_contract": policy },
  }
}

///|
fn nochange_test_proposal() -> Json {
  {
    "reason": "already_satisfied",
    "observation": "The inspected implementation already contains the requested behavior.",
    "evidence_refs": ["nochange-read", "nochange-tests"],
  }
}

///|
fn nochange_test_result(
  tool : String,
  id : String,
  arguments : Json,
  metadata : Json,
) -> Json {
  let result : Json = { "ok": true, "is_error": false, "metadata": metadata }
  {
    "tool": tool,
    "accepted": true,
    "arguments": arguments,
    "result": result,
    "event": mooncode_json_object_with_field(
      mooncode_tool_result_event(
        "nochange-session",
        "/synthetic/source",
        "nochange-command",
        tool,
        result,
        now=@clock.Timestamp::from_ms(100L),
      ),
      "id",
      Json(id),
    ),
  }
}

///|
fn nochange_test_evidence() -> Array[Json] {
  [
    nochange_test_result("read", "nochange-read", { "path": "src/main.mbt" }, {
      "path": "src/main.mbt",
    }),
    nochange_test_result(
      "shell",
      "nochange-tests",
      {
        "cmd": "moon test --no-render",
        "cwd": ".",
        "verification_kind": "test",
      },
      {
        "cmd": "moon test --no-render",
        "cwd": ".",
        "exit_code": 0,
        "run_id": "run-tests",
        "approval_id": "approval-tests",
        "execution_sandbox_policy": "grant-bound",
        "sandbox_evidence": {
          "command_digest": "digest-tests",
          "cleanup_verified": true,
          "assurance": "degraded",
          "changes": [],
        },
      },
    ),
  ]
}

///|
fn nochange_test_checkpoint_arguments() -> Json {
  let milestones = mooncode_horizon_test_milestones("done", "done", "done")
  milestones[1] = mooncode_json_object_with_field(
    milestones[1],
    "resolution",
    "already_satisfied",
  )
  {
    "horizon_id": "nochange-command",
    "milestones": milestones,
    "next_action": "",
    "completion_outcome": "no_change",
    "no_change": nochange_test_proposal(),
  }
}

///|
fn nochange_test_checkpoint(
  command : Json,
  evidence : Array[Json],
  arguments~ : Json = nochange_test_checkpoint_arguments(),
) -> Json {
  mooncode_runtime_horizon_checkpoint_execution(
    command,
    "nochange-session",
    "/synthetic/source",
    "nochange-command",
    { "tool": "checkpoint", "arguments": arguments },
    evidence,
    now=@clock.Timestamp::from_ms(1000L),
  )
}

///|
fn nochange_test_finish() -> Json {
  let arguments : Json = {
    "answer": "No net source change; required checks passed.",
    "completion_outcome": "no_change",
    "no_change": nochange_test_proposal(),
  }
  let result = mooncode_tool_finish(arguments)
  {
    "tool": "finish",
    "accepted": true,
    "arguments": arguments,
    "result": result,
  }
}

///|
fn nochange_test_metadata(result : Json, key : String, value : Json) -> Json {
  let payload = mooncode_runtime_turn_result_payload(result)
  let metadata = mooncode_json_object_with_field(
    mooncode_json_object_field_or_empty(payload, "metadata"),
    key,
    value,
  )
  let payload = mooncode_json_object_with_field(payload, "metadata", metadata)
  let event = mooncode_json_object_with_field(
    mooncode_json_object_field_or_empty(result, "event"),
    "tool_result",
    payload,
  )
  mooncode_json_object_with_field(
    mooncode_json_object_with_field(result, "result", payload),
    "event",
    event,
  )
}

///|
fn nochange_test_edit(before : String, after : String) -> Json {
  {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "changed": true,
        "path": "src/main.mbt",
        "before_fingerprint": before,
        "after_fingerprint": after,
      },
    },
  }
}

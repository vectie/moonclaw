///|
fn completion_test_contract() -> Json {
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
fn completion_test_command(
  contract~ : Json = completion_test_contract(),
) -> Json {
  {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "session_id": "completion-session",
    "book_root": "/synthetic/source",
    "packet": { "command_id": "completion-command" },
    "text": "Implement the requested behavior and run tests.",
    "payload": { "task_intent": "workspace_change", "task_contract": contract },
  }
}

///|
fn completion_test_result(
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
        "completion-session",
        "/synthetic/source",
        "completion-command",
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
fn completion_test_evidence() -> Array[Json] {
  [
    completion_test_result(
      "read",
      "completion-read",
      { "path": "src/main.mbt" },
      { "path": "src/main.mbt" },
    ),
    completion_test_result(
      "shell",
      "completion-tests",
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
fn completion_test_finish() -> Json {
  let arguments : Json = {
    "answer": "The existing implementation satisfies the request; its tests passed.",
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
fn completion_test_metadata(result : Json, key : String, value : Json) -> Json {
  let payload = mooncode_tool_result_value(result)
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
fn completion_test_edit(before : String, after : String) -> Json {
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

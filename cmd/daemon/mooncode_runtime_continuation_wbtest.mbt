///|
fn mooncode_runtime_planner_checkpoint_test_plan() -> Json {
  {
    "kind": mooncode_kind_runtime_turn_planner(),
    "protocol": mooncode_protocol_version(),
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "model": "test-model",
    "tool_call_count": 1,
    "tool_calls": [
      {
        "tool": "read",
        "tool_call_id": "call-read",
        "arguments": { "path": "README.md" },
      },
    ],
    "events": [],
    "model_messages": [{ "role": "user", "content": "Inspect the book" }],
    "model_response_message": {
      "role": "assistant",
      "content": "",
      "tool_calls": [
        {
          "id": "call-read",
          "type": "function",
          "function": {
            "name": "read",
            "arguments": "{\"path\":\"README.md\"}",
          },
        },
      ],
    },
  }
}

///|
test "planner quantum checkpoint is durable resumable and contract-distinct" {
  let plan = mooncode_runtime_planner_checkpoint_test_plan()
  let result : Json = {
    "accepted": true,
    "result": { "ok": true, "output": "# Book" },
  }
  let checkpoint = mooncode_runtime_planner_continuation_event(
    "session-quantum",
    "cmd-quantum",
    plan,
    [plan],
    [result],
    [result],
    next_step_index=1,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_true(mooncode_runtime_planner_continuation_is_active(checkpoint))
  assert_false(mooncode_runtime_continuation_is_active(checkpoint))
  assert_eq(
    mooncode_json_string(checkpoint, "state", default=""),
    "planner-quantum-paused",
  )
  assert_eq(
    mooncode_json_string(checkpoint, "reason", default=""),
    "planner-step-quantum",
  )
  assert_eq(mooncode_json_string(checkpoint, "contract_id", default=""), "")
  assert_true(
    mooncode_runtime_planner_continuation_is_active(
      @json.parse(checkpoint.stringify()),
    ),
  )
}

///|
test "planner quantum checkpoint validation fails closed" {
  let plan = mooncode_runtime_planner_checkpoint_test_plan()
  let result : Json = {
    "accepted": true,
    "result": { "ok": true, "output": "# Book" },
  }
  let checkpoint = mooncode_runtime_planner_continuation_event(
    "session-quantum-invalid",
    "cmd-quantum-invalid",
    plan,
    [plan],
    [result],
    [result],
    next_step_index=1,
    now=@clock.Timestamp::from_ms(43L),
  )
  assert_false(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "state",
        "awaiting-approval".to_json(),
      ),
    ),
  )
  assert_false(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "next_step_index",
        Json::number(2.0),
      ),
    ),
  )
  assert_false(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "target_command_id",
        "other-command".to_json(),
      ),
    ),
  )
  assert_false(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "id",
        "forged-checkpoint".to_json(),
      ),
    ),
  )
  let finish_plan = mooncode_json_object_with_field(
    plan,
    "tool_calls",
    Json::array([{ "tool": "finish", "arguments": { "answer": "done" } }]),
  )
  assert_false(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_json_object_with_field(checkpoint, "plan", finish_plan),
    ),
  )
  assert_false(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "tool_results",
        Json::array([{ "accepted": false }]),
      ),
    ),
  )
}

///|
test "latest planner or approval checkpoint wins by journal order" {
  let plan = mooncode_runtime_planner_checkpoint_test_plan()
  let result : Json = { "accepted": true, "result": { "ok": true } }
  let planner = mooncode_runtime_planner_continuation_event(
    "session-order",
    "cmd-order",
    plan,
    [plan],
    [result],
    [result],
    next_step_index=1,
    now=@clock.Timestamp::from_ms(2L),
  )
  let tool_call : Json = {
    "tool": "write",
    "arguments": { "path": "result.txt", "content": "done" },
  }
  let approval_id = mooncode_runtime_tool_approval_id(
    "cmd-order",
    tool_call,
    occurrence=0,
  )
  let approval : Json = {
    "approval_id": approval_id,
    "target_command_id": "cmd-order",
  }
  let approval_plan : Json = {
    "planner_mode": "explicit-tool-calls",
    "tool_calls": [tool_call],
  }
  let waiting = mooncode_runtime_continuation_event(
    "session-order",
    "cmd-order",
    approval_plan,
    [approval_plan],
    [],
    [],
    approval,
    step_index=0,
    tool_index=0,
    planner_turn_end_step=0,
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_true(mooncode_runtime_continuation_is_active(waiting))
  let legacy : Json = @json.parse(waiting.stringify())
  guard legacy is Object(object) else { abort("approval checkpoint object") }
  object.remove("planner_turn_end_step")
  assert_true(mooncode_runtime_continuation_is_active(legacy))
  assert_true(
    mooncode_runtime_continuation_is_active(
      mooncode_runtime_continuation_for_command([planner, waiting], "cmd-order"),
    ),
  )
  assert_true(
    mooncode_runtime_planner_continuation_is_active(
      mooncode_runtime_continuation_for_command([waiting, planner], "cmd-order"),
    ),
  )
}

///|
test "planner pause compact response remains explicitly nonterminal" {
  let compact = mooncode_runtime_turn_execution_compact({
    "accepted": true,
    "completed": false,
    "paused": true,
    "pause_reason": "planner-step-quantum",
    "next_step_index": 20,
    "control": "continue",
    "planner_mode": "model-tool-calls",
  })
  assert_true(mooncode_json_bool(compact, "accepted", default=false))
  assert_false(mooncode_json_bool(compact, "completed", default=true))
  assert_true(mooncode_json_bool(compact, "paused", default=false))
  assert_eq(
    mooncode_json_string(compact, "pause_reason", default=""),
    "planner-step-quantum",
  )
  assert_eq(mooncode_json_int(compact, "next_step_index", default=0), 20)
  assert_eq(mooncode_json_string(compact, "control", default=""), "continue")
}

///|
fn mooncode_runtime_quantum_test_completion(
  call_id : String,
  tool : String,
  arguments : String,
) -> Json {
  {
    "id": "completion-\{call_id}",
    "object": "chat.completion",
    "created": 1,
    "model": "test-planner-model",
    "choices": [
      {
        "index": 0,
        "finish_reason": "tool_calls",
        "delta": {
          "role": "assistant",
          "tool_calls": [
            {
              "index": 0,
              "id": call_id,
              "function": { "name": tool, "arguments": arguments },
            },
          ],
        },
      },
    ],
    "system_fingerprint": "",
    "usage": { "prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2 },
  }
}

///|
async fn mooncode_runtime_quantum_test_daemon(book_root : String) -> Daemon {
  Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=book_root, cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
}

///|
async test "planner max steps is a resumable quantum without tool replay" {
  @fsx.with_temporary_directory("mooncode-planner-quantum-XXXXXX", async fn(
    root,
  ) {
    let model_server = @httpx.Server::new("[::1]", 0, reuse_addr=true)
    defer model_server.close()
    let calls = Ref::Ref(0)
    let router = @httpx.Router::new()
    router.add_handler(Post, "/v1/chat/completions", (_, w) => {
      let response = if calls.val == 0 {
        mooncode_runtime_quantum_test_completion(
          "call-write", "write", "{\"path\":\"quantum-result.txt\",\"content\":\"once\"}",
        )
      } else {
        mooncode_runtime_quantum_test_completion(
          "call-finish", "finish", "{\"answer\":\"quantum completed\"}",
        )
      }
      calls.val += 1
      w.header().set("Content-Type", "text/event-stream")
      w.write_header(200)
      w.write("data: " + response.stringify() + "\n\ndata: [DONE]\n\n")
    })
    let model = @model.Model::new(
      api_key="test",
      base_url="http://localhost:\{model_server.port()}/v1",
      name="test-planner",
      model_name="test-planner-model",
      safe_zone_tokens=4096,
    )
    let models_path = @moonsuite.product_artifact_for_workspace_root(
      root, "moonclaw", "models/models.json",
    )
    @fsx.make_directory(
      @pathx.dirname(models_path),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(models_path, [model].to_json().stringify(indent=2))
    @async.with_task_group(group => {
      group.spawn_bg(() => model_server.serve(router.handler()), no_wait=true)
      @async.pause()
      let session_id = "session-planner-quantum"
      let command_id = "cmd-planner-quantum"
      ignore(
        mooncode_append_session_journal(
          root,
          session_id,
          mooncode_journal_command(),
          {
            "kind": "mooncode-command",
            "protocol": mooncode_protocol_version(),
            "session_id": session_id,
            "command_id": command_id,
            "created_at": @clock.Timestamp::from_ms(1L),
            "command": {
              "protocol": mooncode_protocol_version(),
              "session_id": session_id,
              "book_root": root,
              "command": "prompt",
              "text": "Write the result exactly once, then finish.",
              "model": "test-planner",
              "packet": { "command_id": command_id },
              "payload": { "planner_max_steps": 1, "planner_timeout_ms": 5000 },
            },
          },
        ),
      )
      let first_daemon = mooncode_runtime_quantum_test_daemon(root)
      let first = first_daemon.mooncode_runtime_turn_execute(session_id, root, {
        "consumer_id": "quantum-first",
      })
      let first_execution = mooncode_json_object_field_or_empty(
        first, "execution",
      )
      assert_true(mooncode_json_bool(first, "accepted", default=false))
      assert_true(mooncode_json_bool(first_execution, "paused", default=false))
      assert_false(
        mooncode_json_bool(first_execution, "completed", default=true),
      )
      assert_eq(
        mooncode_json_int(first_execution, "next_step_index", default=0),
        1,
      )
      assert_eq(@fsx.read_file(@pathx.join(root, "quantum-result.txt")), "once")
      guard first is Object(first_object) else {
        abort("first turn response must be an object")
      }
      assert_true(first_object.get("turn_receipt") is Some(Null))
      let paused_state = first_daemon.mooncode_runtime_claim_state_payload(
        session_id, root,
      )
      assert_eq(
        mooncode_json_int(paused_state, "claimed_command_count", default=0),
        1,
      )
      assert_eq(
        mooncode_json_int(paused_state, "delivered_command_count", default=0),
        0,
      )
      let second_daemon = mooncode_runtime_quantum_test_daemon(root)
      let second = second_daemon.mooncode_runtime_turn_execute(
        session_id,
        root,
        { "consumer_id": "quantum-second" },
      )
      let second_execution = mooncode_json_object_field_or_empty(
        second, "execution",
      )
      assert_true(mooncode_json_bool(second, "accepted", default=false))
      assert_true(
        mooncode_json_bool(second_execution, "completed", default=false),
      )
      assert_false(
        mooncode_json_bool(second_execution, "paused", default=false),
      )
      assert_eq(calls.val, 2)
      assert_eq(@fsx.read_file(@pathx.join(root, "quantum-result.txt")), "once")
      let final_state = second_daemon.mooncode_runtime_claim_state_payload(
        session_id, root,
      )
      assert_eq(
        mooncode_json_int(final_state, "claimed_command_count", default=-1),
        0,
      )
      assert_eq(
        mooncode_json_int(final_state, "delivered_command_count", default=0),
        1,
      )
      let receipts = mooncode_journal_entries(
        mooncode_read_session_journal(root, session_id),
        mooncode_journal_runtime_receipt(),
      )
      assert_eq(
        receipts
        .filter(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-completed"
        })
        .length(),
        1,
      )
      assert_eq(
        receipts
        .filter(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-failed"
        })
        .length(),
        0,
      )
      group.return_immediately(())
    })
  })
}

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
test "planner empty-followup checkpoint is durable and contract-scoped" {
  let plan = mooncode_runtime_planner_checkpoint_test_plan()
  let result : Json = {
    "accepted": true,
    "result": { "ok": true, "output": "# Book" },
  }
  let checkpoint = mooncode_runtime_planner_replan_continuation_event(
    "session-replan",
    "cmd-replan",
    plan,
    finish_rejected=false,
    [plan],
    [result],
    [result],
    next_step_index=1,
    replan_count=2,
    guidance="Continue the same unfinished task.",
    now=@clock.Timestamp::from_ms(44L),
  )
  assert_true(
    mooncode_runtime_planner_replan_continuation_is_active(checkpoint),
  )
  assert_false(mooncode_runtime_planner_continuation_is_active(checkpoint))
  assert_false(
    mooncode_runtime_planner_transport_continuation_is_active(checkpoint),
  )
  assert_eq(
    mooncode_json_string(checkpoint, "state", default=""),
    "planner-replan-paused",
  )
  assert_eq(
    mooncode_json_string(checkpoint, "reason", default=""),
    "planner-empty-followup",
  )
  assert_eq(mooncode_json_int(checkpoint, "replan_count", default=0), 2)
  let rejected_finish_plan = mooncode_json_object_with_field(
    plan,
    "tool_calls",
    Json::array([
      {
        "tool": "finish",
        "tool_call_id": "call-finish-rejected",
        "arguments": { "answer": "premature" },
      },
    ]),
  )
  let rejected_finish_checkpoint = mooncode_runtime_planner_replan_continuation_event(
    "session-rejected-finish",
    "cmd-rejected-finish",
    rejected_finish_plan,
    finish_rejected=true,
    [rejected_finish_plan],
    [result],
    [result],
    next_step_index=1,
    replan_count=1,
    guidance="Continue the unfinished task without replaying completed tools.",
    now=@clock.Timestamp::from_ms(45L),
  )
  assert_true(
    mooncode_runtime_planner_replan_continuation_is_active(
      @json.parse(rejected_finish_checkpoint.stringify()),
    ),
  )
  assert_false(
    mooncode_runtime_planner_replan_continuation_is_active(
      mooncode_json_object_with_field(checkpoint, "finish_rejected", true),
    ),
  )
  assert_false(
    mooncode_runtime_planner_replan_continuation_is_active(
      mooncode_json_object_with_field(
        rejected_finish_checkpoint,
        "plan",
        mooncode_json_object_with_field(
          rejected_finish_plan,
          "tool_calls",
          Json::array([
            {
              "tool": "read",
              "tool_call_id": "call-forged-read",
              "arguments": { "path": "README.md" },
            },
            mooncode_json_array_items(rejected_finish_plan, "tool_calls")[0],
          ]),
        ),
      ),
    ),
  )
  assert_false(
    mooncode_runtime_planner_replan_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "patient_replan_guidance",
        "".to_json(),
      ),
    ),
  )
  assert_false(
    mooncode_runtime_planner_replan_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "replan_count",
        Json::number(0.0),
      ),
    ),
  )
}

///|
fn mooncode_runtime_patient_test_retained_checkpoint(status : String) -> Json {
  {
    "accepted": true,
    "tool": "checkpoint",
    "result": {
      "metadata": {
        "horizon_id": "patient-replan",
        "checkpoint": {
          "horizon_id": "patient-replan",
          "milestones": [
            {
              "id": "implementation",
              "title": "Implement the change",
              "status": status,
              "evidence_kind": "path_changed",
              "path": "patient-result.txt",
              "context_paths": [],
            },
          ],
        },
      },
    },
  }
}

///|
test "patient replanning requires retained active or pending milestones" {
  let milestone : Json = {
    "id": "implementation",
    "title": "Implement the change",
    "evidence_kind": "path_changed",
    "path": "patient-result.txt",
    "context_paths": [],
  }
  let command : Json = {
    "command": "prompt",
    "text": "Implement the requested code change.",
    "payload": {
      "horizon_id": "patient-replan",
      "task_contract": {
        "horizon_id": "patient-replan",
        "objective": "Implement the requested change",
        "milestones": [milestone],
      },
    },
  }
  assert_true(
    mooncode_runtime_horizon_checkpoint_has_unfinished_milestones(command, [
      mooncode_runtime_patient_test_retained_checkpoint("active"),
    ]),
  )
  assert_true(
    mooncode_runtime_horizon_checkpoint_has_unfinished_milestones(command, [
      mooncode_runtime_patient_test_retained_checkpoint("pending"),
    ]),
  )
  assert_false(
    mooncode_runtime_horizon_checkpoint_has_unfinished_milestones(command, [
      mooncode_runtime_patient_test_retained_checkpoint("done"),
    ]),
  )
  assert_false(
    mooncode_runtime_horizon_checkpoint_has_unfinished_milestones(
      { "command": "prompt", "text": "Answer the question." },
      [mooncode_runtime_patient_test_retained_checkpoint("active")],
    ),
  )
}

///|
test "planner transport checkpoints preserve initial and follow-up resume state" {
  let initial = mooncode_runtime_planner_transport_continuation_event(
    "session-transport",
    "cmd-transport",
    Json::object({}),
    [],
    [],
    [],
    [{ "command_id": "steer-one", "text": "Keep the scope narrow." }],
    resume_mode="initial",
    next_step_index=0,
    detail="model planner failed: ConnectionClosed",
    now=@clock.Timestamp::from_ms(44L),
  )
  assert_true(
    mooncode_runtime_planner_transport_continuation_is_active(initial),
  )
  assert_eq(
    mooncode_json_array_items(initial, "pending_live_steering").length(),
    1,
  )
  let plan = mooncode_runtime_planner_checkpoint_test_plan()
  let result : Json = {
    "accepted": true,
    "result": { "ok": true, "output": "# Book" },
  }
  let followup = mooncode_runtime_planner_transport_continuation_event(
    "session-transport",
    "cmd-transport",
    plan,
    [plan],
    [result],
    [result],
    [{ "command_id": "steer-two", "text": "Finish the same slice." }],
    resume_mode="followup",
    next_step_index=1,
    detail="model planner follow-up failed: ConnectionClosed",
    now=@clock.Timestamp::from_ms(45L),
  )
  assert_true(
    mooncode_runtime_planner_transport_continuation_is_active(followup),
  )
  assert_false(mooncode_runtime_planner_continuation_is_active(followup))
  assert_false(
    mooncode_runtime_planner_transport_continuation_is_active(
      mooncode_json_object_with_field(
        followup,
        "resume_mode",
        "initial".to_json(),
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
fn mooncode_runtime_quantum_test_empty_completion() -> Json {
  {
    "id": "completion-empty",
    "object": "chat.completion",
    "created": 1,
    "model": "test-planner-model",
    "choices": [
      {
        "index": 0,
        "finish_reason": "stop",
        "delta": { "role": "assistant", "content": "" },
      },
    ],
    "system_fingerprint": "",
    "usage": { "prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2 },
  }
}

///|
fn mooncode_runtime_patient_test_milestone(status : String) -> Json {
  {
    "id": "implementation",
    "title": "Write the patient replan result",
    "status": status,
    "evidence_kind": "path_changed",
    "path": "patient-result.txt",
    "context_paths": [],
  }
}

///|
fn mooncode_runtime_patient_test_command(
  root : String,
  session_id : String,
  command_id : String,
) -> Json {
  {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": root,
    "command": "prompt",
    "text": "Implement the code result and verify it.",
    "model": "test-planner",
    "packet": { "command_id": command_id },
    "payload": {
      "horizon_id": "patient-replan",
      "planner_timeout_ms": 5000,
      "task_contract": {
        "horizon_id": "patient-replan",
        "objective": "Write and verify the patient replan result",
        "milestones": [mooncode_runtime_patient_test_milestone("active")],
      },
    },
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

///|
async test "unfinished checkpoint patiently replans without a ceiling or claim loss" {
  @fsx.with_temporary_directory("mooncode-patient-replan-XXXXXX", async fn(
    root,
  ) {
    let model_server = @httpx.Server::new("[::1]", 0, reuse_addr=true)
    defer model_server.close()
    let calls = Ref::Ref(0)
    let request_bodies : Array[String] = []
    let router = @httpx.Router::new()
    router.add_handler(Post, "/v1/chat/completions", (r, w) => {
      let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
      let body : Json = reader.read()
      request_bodies.push(body.stringify())
      let response = match calls.val {
        0 => {
          let arguments : Json = {
            "horizon_id": "patient-replan",
            "milestones": [mooncode_runtime_patient_test_milestone("active")],
            "next_action": "Write and verify patient-result.txt.",
          }
          mooncode_runtime_quantum_test_completion(
            "call-checkpoint-active",
            "checkpoint",
            arguments.stringify(),
          )
        }
        1 =>
          mooncode_runtime_quantum_test_completion(
            "call-finish-rejected", "finish", "{\"answer\":\"premature\"}",
          )
        2 => mooncode_runtime_quantum_test_empty_completion()
        3 =>
          mooncode_runtime_quantum_test_completion(
            "call-write", "write", "{\"path\":\"patient-result.txt\",\"content\":\"once\"}",
          )
        4 =>
          mooncode_runtime_quantum_test_completion(
            "call-check", "shell", "{\"cmd\":\"test -f patient-result.txt\",\"verification_kind\":\"check\"}",
          )
        5 => {
          let arguments : Json = {
            "horizon_id": "patient-replan",
            "milestones": [mooncode_runtime_patient_test_milestone("done")],
            "next_action": "Finish.",
          }
          mooncode_runtime_quantum_test_completion(
            "call-checkpoint-done",
            "checkpoint",
            arguments.stringify(),
          )
        }
        6 =>
          mooncode_runtime_quantum_test_completion(
            "call-finish", "finish", "{\"answer\":\"patient replan completed\"}",
          )
        _ => mooncode_runtime_quantum_test_empty_completion()
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
      let session_id = "session-patient-replan"
      let command_id = "cmd-patient-replan"
      let command = mooncode_runtime_patient_test_command(
        root, session_id, command_id,
      )
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
            "command": command,
          },
        ),
      )
      let first_daemon = mooncode_runtime_quantum_test_daemon(root)
      let first = first_daemon.mooncode_runtime_service_execute(
        session_id,
        root,
        {
          "service_id": "patient-first-service",
          "consumer_id": "patient-restart-claim",
          "max_turns": 1,
          "live_wait_ms": 0,
        },
      )
      let first_loop = mooncode_json_object_field_or_empty(
        first, "runtime_loop",
      )
      let first_turns = mooncode_json_array_items(first_loop, "turns")
      assert_eq(first_turns.length(), 1)
      let first_turn = first_turns[0]
      let first_execution = mooncode_json_object_field_or_empty(
        first_turn, "execution",
      )
      assert_true(mooncode_json_bool(first_turn, "accepted", default=false))
      assert_true(mooncode_json_bool(first_execution, "paused", default=false))
      assert_false(
        mooncode_json_bool(first_execution, "completed", default=true),
      )
      assert_eq(
        mooncode_json_string(first_execution, "pause_reason", default=""),
        "planner-empty-followup",
      )
      assert_eq(
        mooncode_json_int(first_execution, "model_step_limit", default=-1),
        0,
      )
      guard first_turn is Object(first_object) else {
        abort("first patient replan response must be an object")
      }
      assert_true(first_object.get("turn_receipt") is Some(Null))
      let first_state = first_daemon.mooncode_runtime_claim_state_payload(
        session_id, root,
      )
      assert_eq(
        mooncode_json_int(first_state, "claimed_command_count", default=0),
        1,
      )
      assert_eq(
        mooncode_json_int(first_state, "delivered_command_count", default=-1),
        0,
      )
      let first_claims = mooncode_json_array_items(
        first_state, "claimed_commands",
      )
      assert_eq(first_claims.length(), 1)
      let first_claim_receipt = mooncode_json_object_field_or_empty(
        first_claims[0],
        "receipt",
      )
      let claim_id = mooncode_json_string(
        first_claim_receipt,
        "claim_id",
        default="",
      )
      assert_true(claim_id != "")
      let first_continuation = mooncode_runtime_continuation_for_command(
        mooncode_journal_entries(
          mooncode_read_session_journal(root, session_id),
          mooncode_journal_event(),
        ),
        command_id,
      )
      assert_true(
        mooncode_runtime_planner_replan_continuation_is_active(
          first_continuation,
        ),
      )
      assert_eq(
        mooncode_json_int(first_continuation, "replan_count", default=0),
        1,
      )
      assert_true(
        mooncode_json_bool(first_continuation, "finish_rejected", default=false),
      )
      let first_event_count = mooncode_journal_entries(
        mooncode_read_session_journal(root, session_id),
        mooncode_journal_event(),
      ).length()
      let rejected_plan = mooncode_json_object_field_or_empty(
        first_continuation, "plan",
      )
      let rejected_calls = mooncode_json_array_items(
        rejected_plan, "tool_calls",
      )
      assert_eq(rejected_calls.length(), 1)
      assert_eq(
        mooncode_json_string(rejected_calls[0], "tool", default=""),
        "finish",
      )
      assert_false(
        mooncode_runtime_service_continues_goal_runtime(
          first_loop, root, session_id,
        ),
      )
      let first_turns = mooncode_json_array_items(first_loop, "turns")
      let first_execution = mooncode_json_object_field_or_empty(
        first_turns[first_turns.length() - 1],
        "execution",
      )
      let approval_shaped_loop = mooncode_json_object_with_field(
        first_loop,
        "turns",
        Json::array([
          mooncode_json_object_with_field(
            first_turns[first_turns.length() - 1],
            "execution",
            mooncode_json_object_with_field(
              first_execution,
              "pause_reason",
              "approval-required".to_json(),
            ),
          ),
        ]),
      )
      assert_false(
        mooncode_runtime_service_continues_goal_runtime(
          approval_shaped_loop, root, session_id,
        ),
      )
      let second_daemon = mooncode_runtime_quantum_test_daemon(root)
      let restarted_state = second_daemon.mooncode_runtime_claim_state_payload(
        session_id, root,
      )
      let restarted_claims = mooncode_json_array_items(
        restarted_state, "claimed_commands",
      )
      assert_eq(restarted_claims.length(), 1)
      let second = second_daemon.mooncode_runtime_service_execute(
        session_id,
        root,
        {
          "service_id": "patient-second-service",
          "consumer_id": "patient-restart-claim",
          "max_turns": 1,
          "live_wait_ms": 0,
        },
      )
      assert_true(mooncode_json_bool(second, "accepted", default=false))
      let second_loop = mooncode_json_object_field_or_empty(
        second, "runtime_loop",
      )
      let second_turns = mooncode_json_array_items(second_loop, "turns")
      assert_eq(second_turns.length(), 1)
      let final_execution = mooncode_json_object_field_or_empty(
        second_turns[0],
        "execution",
      )
      assert_true(
        mooncode_json_bool(final_execution, "completed", default=false),
      )
      let final_event_count = mooncode_journal_entries(
        mooncode_read_session_journal(root, session_id),
        mooncode_journal_event(),
      ).length()
      assert_true(final_event_count > first_event_count)
      assert_false(mooncode_json_bool(final_execution, "paused", default=false))
      assert_eq(calls.val, 7)
      assert_eq(@fsx.read_file(@pathx.join(root, "patient-result.txt")), "once")
      assert_true(
        request_bodies
        .join("\n")
        .contains("previous follow-up produced no usable MoonCode tool call"),
      )
      assert_false(
        request_bodies.join("\n").contains("Planner opportunities remaining"),
      )
      let final_journal = mooncode_read_session_journal(root, session_id)
      let final_state = second_daemon.mooncode_runtime_claim_state_payload(
        session_id, root,
      )
      let delivered = mooncode_json_array_items(
        final_state, "delivered_commands",
      )
      assert_eq(delivered.length(), 1)
      assert_eq(
        mooncode_json_string(
          mooncode_json_object_field_or_empty(delivered[0], "receipt"),
          "claim_id",
          default="",
        ),
        claim_id,
      )
      let runtime_receipts = mooncode_journal_entries(
        final_journal,
        mooncode_journal_runtime_receipt(),
      )
      assert_eq(
        runtime_receipts
        .filter(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-claimed"
        })
        .length(),
        1,
      )
      let final_events = mooncode_journal_entries(
        final_journal,
        mooncode_journal_event(),
      )
      assert_eq(
        final_events
        .filter(event => {
          mooncode_json_string(event, "kind", default="") ==
          "runtime.planner_replan_requested"
        })
        .length(),
        1,
      )
      assert_eq(
        final_events
        .filter(event => {
          mooncode_json_string(event, "kind", default="") ==
          "runtime.planner_failed"
        })
        .length(),
        0,
      )
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
        final_journal,
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
      let terminal_plan = mooncode_json_object_with_field(
        mooncode_runtime_planner_checkpoint_test_plan(),
        "model",
        "test-planner".to_json(),
      )
      let terminal_result : Json = {
        "accepted": true,
        "tool": "read",
        "result": { "ok": true, "output": "# Book" },
      }
      let terminal = second_daemon.mooncode_runtime_turn_model_followup_plan(
        {
          "protocol": mooncode_protocol_version(),
          "session_id": "session-terminal-empty",
          "book_root": root,
          "command": "prompt",
          "text": "Answer the question.",
          "model": "test-planner",
          "packet": { "command_id": "cmd-terminal-empty" },
          "payload": { "planner_timeout_ms": 5000 },
        },
        terminal_plan,
        mooncode_json_array_items(terminal_plan, "tool_calls"),
        [terminal_result],
        [terminal_result],
        now=@clock.Timestamp::from_ms(8L),
      )
      assert_true(mooncode_json_bool(terminal, "failed", default=false))
      assert_false(
        mooncode_json_bool(terminal, "patient_replan", default=false),
      )
      assert_eq(calls.val, 8)
      group.return_immediately(())
    })
  })
}

///|
async test "cancel settles a claim paused for patient replanning" {
  @fsx.with_temporary_directory("mooncode-patient-replan-cancel-XXXXXX", async fn(
    root,
  ) {
    let model_server = @httpx.Server::new("[::1]", 0, reuse_addr=true)
    defer model_server.close()
    let calls = Ref::Ref(0)
    let router = @httpx.Router::new()
    router.add_handler(Post, "/v1/chat/completions", (_, w) => {
      let response = if calls.val == 0 {
        let arguments : Json = {
          "horizon_id": "patient-replan",
          "milestones": [mooncode_runtime_patient_test_milestone("active")],
          "next_action": "Write patient-result.txt.",
        }
        mooncode_runtime_quantum_test_completion(
          "call-checkpoint-active",
          "checkpoint",
          arguments.stringify(),
        )
      } else {
        mooncode_runtime_quantum_test_empty_completion()
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
      let session_id = "session-patient-replan-cancel"
      let command_id = "cmd-patient-replan-cancel"
      let command = mooncode_runtime_patient_test_command(
        root, session_id, command_id,
      )
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
            "command": command,
          },
        ),
      )
      let daemon = mooncode_runtime_quantum_test_daemon(root)
      let paused = daemon.mooncode_runtime_turn_execute(session_id, root, {
        "consumer_id": "patient-cancel-pause",
      })
      assert_true(mooncode_json_bool(paused, "accepted", default=false))
      assert_true(
        mooncode_json_bool(
          mooncode_json_object_field_or_empty(paused, "execution"),
          "paused",
          default=false,
        ),
      )
      let cancelled = daemon.mooncode_submit_cancel_control(session_id, root, {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": root,
        "command": "cancel",
        "model": "test-planner",
        "packet": { "command_id": "cmd-cancel-patient-replan" },
        "payload": { "target_command_id": command_id },
      })
      assert_eq(
        mooncode_json_string(cancelled, "target_command_id", default=""),
        command_id,
      )
      let final_state = daemon.mooncode_runtime_claim_state_payload(
        session_id, root,
      )
      assert_eq(
        mooncode_json_int(final_state, "claimed_command_count", default=-1),
        0,
      )
      let receipts = mooncode_journal_entries(
        mooncode_read_session_journal(root, session_id),
        mooncode_journal_runtime_receipt(),
      )
      assert_true(
        receipts.any(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-cancelled"
        }),
      )
      assert_eq(calls.val, 2)
      group.return_immediately(())
    })
  })
}

///|
async test "transient planner close resumes through runtime service without replay" {
  @fsx.with_temporary_directory("mooncode-planner-transport-resume-XXXXXX", async fn(
    root,
  ) {
    let model_server = @httpx.Server::new("[::1]", 0, reuse_addr=true)
    defer model_server.close()
    let calls = Ref::Ref(0)
    let request_bodies : Array[String] = []
    let router = @httpx.Router::new()
    router.add_handler(Post, "/v1/chat/completions", (r, w) => {
      let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
      let body : Json = reader.read()
      request_bodies.push(body.stringify())
      let response = if calls.val == 0 {
        mooncode_runtime_quantum_test_completion(
          "call-write", "write", "{\"path\":\"transport-result.txt\",\"content\":\"once\"}",
        )
      } else {
        mooncode_runtime_quantum_test_completion(
          "call-finish", "finish", "{\"answer\":\"transport continuation completed\"}",
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
      let session_id = "session-planner-transport"
      let command_id = "cmd-planner-transport"
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
        "consumer_id": "transport-first",
      })
      assert_true(mooncode_json_bool(first, "accepted", default=false))
      assert_eq(
        @fsx.read_file(@pathx.join(root, "transport-result.txt")),
        "once",
      )
      let events = mooncode_journal_entries(
        mooncode_read_session_journal(root, session_id),
        mooncode_journal_event(),
      )
      let quantum = mooncode_runtime_continuation_for_command(
        events, command_id,
      )
      assert_true(mooncode_runtime_planner_continuation_is_active(quantum))
      let started = mooncode_event(
        session_id~,
        command_id~,
        lane="runtime",
        kind="runtime.planner_started",
        title="continued",
        status="running",
        detail="continued",
        now=@clock.Timestamp::from_ms(2L),
      )
      let interrupted = mooncode_runtime_turn_transient_transport_result(
        "test-planner", "model planner follow-up failed: ConnectionClosed", started,
      )
      assert_true(
        mooncode_json_bool(
          interrupted,
          "transient_transport_close",
          default=false,
        ),
      )
      let transport = mooncode_runtime_planner_transport_continuation_event(
        session_id,
        command_id,
        mooncode_json_object_field_or_empty(quantum, "plan"),
        mooncode_json_array_items(quantum, "planner_steps"),
        mooncode_json_array_items(quantum, "tool_results"),
        mooncode_json_array_items(quantum, "step_results"),
        [
          {
            "command_id": "steer-transport",
            "steering_text": "KEEP_TRANSPORT_SCOPE",
          },
        ],
        resume_mode="followup",
        next_step_index=1,
        detail=mooncode_json_string(interrupted, "message", default=""),
        now=@clock.Timestamp::from_ms(4L),
      )
      assert_true(
        mooncode_runtime_planner_transport_continuation_is_active(transport),
      )
      ignore(
        mooncode_append_session_journal(
          root,
          session_id,
          mooncode_journal_event(),
          transport,
        ),
      )
      let service_daemon = mooncode_runtime_quantum_test_daemon(root)
      let service = service_daemon.mooncode_runtime_service_execute_under_runtime_gates(
        session_id,
        root,
        {
          "service_id": "transport-service",
          "consumer_id": "transport-service",
          "max_turns": 1,
          "live_wait_ms": 0,
          "poll_ms": 25,
        },
      )
      assert_true(mooncode_json_bool(service, "accepted", default=false))
      assert_eq(calls.val, 2)
      assert_eq(
        @fsx.read_file(@pathx.join(root, "transport-result.txt")),
        "once",
      )
      let request_text = request_bodies.join("\n")
      assert_eq(request_text.split("KEEP_TRANSPORT_SCOPE").length(), 2)
      let final_journal = mooncode_read_session_journal(root, session_id)
      let final_events = mooncode_journal_entries(
        final_journal,
        mooncode_journal_event(),
      )
      assert_eq(
        final_events
        .filter(event => {
          mooncode_json_string(event, "kind", default="") == "tool_result" &&
          mooncode_json_string(event, "tool", default="") == "write"
        })
        .length(),
        1,
      )
      assert_eq(
        final_events
        .filter(event => {
          mooncode_json_string(event, "kind", default="") ==
          "runtime.planner_failed"
        })
        .length(),
        0,
      )
      let receipts = mooncode_journal_entries(
        final_journal,
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

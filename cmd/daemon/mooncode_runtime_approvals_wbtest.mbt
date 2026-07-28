///|
async fn mooncode_control_test_daemon(book_root : String) -> Daemon {
  Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
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
fn mooncode_control_test_approval_request(events : Array[Json]) -> Json {
  for event in events {
    if mooncode_json_string(event, "kind", default="") ==
      "tool.approval_requested" {
      return event
    }
  }
  Json::object({})
}

///|
async test "invalid approval is rejected before durable queueing" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-invalid-approval-XXXXXX"),
  )
  let session_id = "session-invalid-approval"
  let daemon = mooncode_control_test_daemon(book_root)
  @async.with_task_group(group => {
    let result : Result[Json, String] = Ok(
      daemon.mooncode_submit_turn_response(group~, session_id, {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "approve_tool",
        "model": "codex/gpt-5.6-sol",
        "text": "Invalid approval",
        "payload": {
          "approval_id": "mooncode-approval-missing",
          "target_command_id": "cmd-missing",
        },
        "packet": { "command_id": "cmd-invalid-approval" },
      }),
    ) catch {
      error => Err("\{error}")
    }
    assert_true(result is Err(_))
    group.return_immediately(())
  })
  assert_false(
    @fsx.exists(mooncode_session_journal_path(book_root, session_id)),
  )
}

///|
test "mooncode approval classifier gates hosted run reruns" {
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "read",
      "arguments": { "path": "moon.mod" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_ide",
      "arguments": { "action": "outline", "path": "cmd/daemon" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_check",
      "arguments": { "target": "all" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_cmd",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": { "command": "fmt", "target": "native" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_cmd",
      "planner": "model-tool-call",
      "approval": "operator",
      "arguments": { "command": "test", "target": "native" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_cmd",
      "requires_approval": true,
      "arguments": { "command": "fmt" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_cmd",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": {
        "command": "test",
        "args": ["--update"],
        "test_update_kind": "snapshot",
        "test_update_reason": "accepted change",
      },
    }),
  )
  let update_argument_cases : Array[Json] = [
    {
      "command": "test",
      "arg": "-u",
      "test_update_kind": "snapshot",
      "test_update_reason": "accepted change",
    },
    {
      "command": "test",
      "args": ["-u"],
      "test_update_kind": "snapshot",
      "test_update_reason": "accepted change",
    },
  ]
  for update_arguments in update_argument_cases {
    assert_true(
      mooncode_runtime_tool_requires_approval({
        "tool": "moon_cmd",
        "planner": "model-tool-call",
        "requires_approval": true,
        "arguments": update_arguments,
      }),
    )
  }
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "requires_approval": true,
      "arguments": { "cmd": "git status --short" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": { "cmd": "git status --short" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": { "cmd": "sort -o output.txt input.txt" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": { "cmd": "sed -e 'w output.txt' input.txt" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": {
        "cmd": "set -o pipefail; rg -n 'runtime-turn' cmd/daemon; git diff --check",
      },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": {
        "cmd": "set -o pipefail; test \"$(grep -RFl 'workspace preview handles text image virtual and missing entries' internal/moonwiki --include='*_wbtest.mbt' | wc -l | tr -d ' ')\" = 1; test \"$(git diff --numstat -- internal/moonwiki/moonwiki_request_wbtest.mbt | awk '{print $1\":\"$2}')\" = '0:60'; printf 'Preserved totals\\n'",
      },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": {
        "cmd": "test \"$(grep value file | unknown-inspector)\" = clean",
      },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "moon test cmd/daemon --target native" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": {
        "cmd": "gh run rerun 30277114085 --repo vectie/moondesk --failed",
      },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": {
        "cmd": "gh run view 30277114085 --repo vectie/moondesk --log-failed",
      },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "git commit -m 'validated change'" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "git -C . commit -m 'validated change'" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "git commit-tree HEAD^{tree}" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "echo 'git commit -m only-prose'" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "git status --short" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "npm ci --include=optional --ignore-scripts" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "npm ci --help | sed -n '1,120p'" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "git restore --source=HEAD --worktree -- ui" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": { "cmd": "echo 'npm ci and git restore are risky'" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "arguments": {
        "cmd": "set -o pipefail; find . -name package.json -print; grep -RInE 'npm ci|npm install|registry|git push' .github package-lock.json | head -n 300",
      },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "read",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": { "path": "moon.mod" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_ide",
      "planner": "model-tool-call",
      "approval": "operator",
      "arguments": { "action": "outline", "path": "cmd/daemon" },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_cmd",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": {
        "command": "test",
        "path": "cmd/daemon",
        "timeout_ms": 120000,
      },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "approval": "operator",
      "arguments": {
        "cmd": "/usr/bin/time -p moon test cmd/daemon --target native",
      },
    }),
  )
  assert_false(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "planner": "model-tool-call",
      "requires_approval": true,
      "arguments": {
        "cmd": "set -o pipefail; git status --short; git diff --check",
      },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "write",
      "requires_approval": true,
      "arguments": { "path": "changed.txt", "content": "changed" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "shell",
      "requires_approval": true,
      "arguments": { "cmd": "touch changed.txt" },
    }),
  )
  assert_true(
    mooncode_runtime_tool_requires_approval({
      "tool": "moon_cmd",
      "requires_approval": true,
      "arguments": {
        "command": "test",
        "args": ["--update"],
        "test_update_kind": "snapshots",
        "test_update_reason": "accepted output update",
      },
    }),
  )
}

///|
test "mooncode continuation stores one current planner transcript" {
  let tool_call : Json = {
    "tool": "write",
    "arguments": { "path": "approved.txt", "content": "approved" },
  }
  let plan : Json = {
    "kind": "mooncode-runtime-turn-planner",
    "tool_calls": [tool_call],
    "model_messages": [
      { "role": "system", "content": "large reconstructible transcript" },
    ],
    "model_response_message": {
      "role": "assistant",
      "content": "selected write",
    },
  }
  let approval_id = mooncode_runtime_tool_approval_id(
    "cmd-compact",
    tool_call,
    occurrence=0,
  )
  let approval : Json = {
    "approval_id": approval_id,
    "target_command_id": "cmd-compact",
  }
  let checkpoint = mooncode_runtime_continuation_event(
    "session-compact",
    "cmd-compact",
    plan,
    [plan],
    [],
    [],
    approval,
    step_index=0,
    tool_index=0,
    planner_turn_end_step=0,
    now=@clock.Timestamp::from_ms(1L),
  )
  let stored_plan = mooncode_json_object_field_or_empty(checkpoint, "plan")
  assert_true(stored_plan.stringify().contains("model_messages"))
  assert_true(stored_plan.stringify().contains("model_response_message"))
  let stored_steps = mooncode_json_array_items(checkpoint, "planner_steps")
  assert_eq(stored_steps.length(), 1)
  assert_false(stored_steps[0].stringify().contains("model_messages"))
  assert_true(mooncode_runtime_continuation_is_active(checkpoint))
  let after_step = mooncode_runtime_continuation_event(
    "session-compact",
    "cmd-compact",
    plan,
    [plan],
    [],
    [],
    Json::object({}),
    step_index=0,
    tool_index=1,
    planner_turn_end_step=0,
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_eq(mooncode_json_string(after_step, "state", default=""), "after-step")
  assert_true(mooncode_runtime_continuation_is_active(after_step))
}

///|
async fn mooncode_control_test_queue(
  book_root : String,
  session_id : String,
  command : Json,
  now~ : @clock.Timestamp,
) -> Unit {
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": mooncode_command_id(command),
        "created_at": now,
        "command": command,
      },
    ),
  )
}

///|
async test "mooncode runtime keeps an approval-gated command claimed until approved" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-approval-XXXXXX"),
  )
  let session_id = "session-approval"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "model": "codex/gpt-5.6-sol",
    "text": "Create the approved file",
    "packet": {
      "command_id": "cmd-approval",
      "client_turn_id": "client-approval",
    },
    "payload": { "approval_wait_ms": 0 },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "requires_approval": true,
        "arguments": { "path": "approved.txt", "content": "approved" },
      },
      { "tool": "finish", "arguments": { "answer": "created" } },
    ],
  }
  mooncode_control_test_queue(
    book_root,
    session_id,
    command,
    now=@clock.Timestamp::from_ms(10L),
  )
  let daemon = mooncode_control_test_daemon(book_root)
  let waiting = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "approval-test",
  })
  assert_true(mooncode_json_bool(waiting, "ran", default=false))
  let waiting_execution = mooncode_json_object_field_or_empty(
    waiting, "execution",
  )
  assert_true(
    mooncode_json_bool(waiting_execution, "waiting_approval", default=false),
  )
  assert_false(@fsx.exists(@pathx.join(book_root, "approved.txt")))
  let journal = mooncode_read_session_journal(book_root, session_id)
  let receipts = mooncode_journal_entries(
    journal,
    mooncode_journal_runtime_receipt(),
  )
  assert_eq(receipts.length(), 1)
  assert_eq(
    mooncode_json_string(receipts[0], "status", default=""),
    "runtime-claimed",
  )
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  let request = mooncode_control_test_approval_request(events)
  let approval_id = mooncode_json_string(request, "approval_id", default="")
  assert_true(approval_id.has_prefix("mooncode-approval-"))
  @async.with_task_group(group => {
    let approved = daemon.mooncode_submit_turn_response(group~, session_id, {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "approve_tool",
      "model": "codex/gpt-5.6-sol",
      "text": "Approve the selected tool",
      "payload": {
        "approval_id": approval_id,
        "target_command_id": "cmd-approval",
        "tool_call_id": mooncode_json_string(
          request,
          "tool_call_id",
          default="",
        ),
      },
      "packet": { "command_id": "cmd-approve" },
    })
    assert_true(mooncode_json_bool(approved, "accepted", default=false))
    let binding = daemon.mooncode_binding_for_session(session_id)
    let mut attempts = 0
    while binding.runtime_service_running && attempts < 200 {
      @async.sleep(10)
      attempts += 1
    }
    assert_false(binding.runtime_service_running)
    group.return_immediately(())
  })
  assert_eq(@fsx.read_file(@pathx.join(book_root, "approved.txt")), "approved")
  let after = daemon.mooncode_runtime_claim_state_payload(session_id, book_root)
  assert_eq(mooncode_json_int(after, "delivered_command_count", default=0), 2)
  let record = daemon.mooncode_session_record(session_id, book_root).unwrap()
  let conversation = mooncode_json_object_field_or_empty(
    record, "mooncode_conversation",
  )
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(turns.length(), 1)
  let work = mooncode_json_object_field_or_empty(turns[0], "work")
  let steps = mooncode_json_array_items(work, "steps")
  assert_true(
    steps.any(step => {
      mooncode_json_string(step, "kind", default="") == "approval" &&
      mooncode_json_string(
        mooncode_json_object_field_or_empty(step, "evidence"),
        "state",
        default="",
      ) ==
      "approved"
    }),
  )
}

///|
async test "runtime service yields pending approval and approval control resumes one claim" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-service-approval-XXXXXX"),
  )
  let session_id = "session-service-approval"
  let command_id = "cmd-service-approval"
  mooncode_control_test_queue(
    book_root,
    session_id,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "model": "codex/gpt-5.6-sol",
      "text": "Create the approved service file",
      "packet": { "command_id": command_id },
      "runtime_tool_calls": [
        {
          "tool": "write",
          "requires_approval": true,
          "arguments": {
            "path": "service-approved.txt",
            "content": "approved once",
          },
        },
        { "tool": "finish", "arguments": { "answer": "service approved" } },
      ],
    },
    now=@clock.Timestamp::from_ms(10L),
  )
  let daemon = mooncode_control_test_daemon(book_root)
  let first = daemon.mooncode_runtime_service_execute(session_id, book_root, {
    "service_id": "service-approval-first",
    "max_turns": 1,
    "live_wait_ms": 0,
  })
  assert_true(mooncode_json_bool(first, "accepted", default=false))
  let first_journal = mooncode_read_session_journal(book_root, session_id)
  let first_receipts = mooncode_journal_entries(
    first_journal,
    mooncode_journal_runtime_receipt(),
  )
  assert_eq(
    first_receipts
    .filter(receipt => {
      mooncode_json_string(receipt, "status", default="") == "runtime-claimed"
    })
    .length(),
    1,
  )
  let first_events = mooncode_journal_entries(
    first_journal,
    mooncode_journal_event(),
  )
  assert_eq(
    first_events
    .filter(event => {
      mooncode_json_string(event, "kind", default="") ==
      "tool.approval_requested"
    })
    .length(),
    1,
  )
  let request = mooncode_control_test_approval_request(first_events)
  let approval_id = mooncode_json_string(request, "approval_id", default="")
  assert_true(approval_id.has_prefix("mooncode-approval-"))
  assert_false(@fsx.exists(@pathx.join(book_root, "service-approved.txt")))
  let claimed = daemon.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  assert_eq(mooncode_json_int(claimed, "claimed_command_count", default=-1), 1)
  @async.with_task_group(group => {
    let approved = daemon.mooncode_submit_turn_response(group~, session_id, {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "approve_tool",
      "model": "codex/gpt-5.6-sol",
      "text": "Approve the selected tool",
      "payload": {
        "approval_id": approval_id,
        "target_command_id": command_id,
        "tool_call_id": mooncode_json_string(
          request,
          "tool_call_id",
          default="",
        ),
      },
      "packet": { "command_id": "cmd-service-approve" },
    })
    assert_true(mooncode_json_bool(approved, "accepted", default=false))
    let binding = daemon.mooncode_binding_for_session(session_id)
    let mut attempts = 0
    while binding.runtime_service_running && attempts < 200 {
      @async.sleep(10)
      attempts += 1
    }
    assert_false(binding.runtime_service_running)
    group.return_immediately(())
  })
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "service-approved.txt")),
    "approved once",
  )
  let final_journal = mooncode_read_session_journal(book_root, session_id)
  let final_receipts = mooncode_journal_entries(
    final_journal,
    mooncode_journal_runtime_receipt(),
  )
  assert_eq(
    final_receipts
    .filter(receipt => {
      mooncode_json_string(receipt, "status", default="") == "runtime-claimed"
    })
    .length(),
    1,
  )
  let final_state = daemon.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  assert_eq(
    mooncode_json_int(final_state, "claimed_command_count", default=-1),
    0,
  )
}

///|
async test "mooncode rejected approval never executes the tool" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-rejection-XXXXXX"),
  )
  let session_id = "session-rejection"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "model": "codex/gpt-5.6-sol",
    "text": "Create the rejected file",
    "packet": { "command_id": "cmd-rejection" },
    "payload": { "approval_wait_ms": 0 },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "requires_approval": true,
        "arguments": { "path": "rejected.txt", "content": "no" },
      },
      {
        "tool": "finish",
        "arguments": { "answer": "The operation was rejected." },
      },
    ],
  }
  mooncode_control_test_queue(
    book_root,
    session_id,
    command,
    now=@clock.Timestamp::from_ms(10L),
  )
  let daemon = mooncode_control_test_daemon(book_root)
  ignore(
    daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "rejection-test",
    }),
  )
  let events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  let request = mooncode_control_test_approval_request(events)
  let decision = mooncode_runtime_tool_approval_event(
    session_id,
    "cmd-rejection",
    {
      "approval_id": mooncode_json_string(request, "approval_id", default=""),
      "tool_call_id": mooncode_json_string(request, "tool_call_id", default=""),
      "tool": "write",
      "arguments": mooncode_json_object_field_or_empty(request, "arguments"),
    },
    occurrence=0,
    state="rejected",
    tool_call_id=mooncode_json_string(request, "tool_call_id", default=""),
    control_command_id="cmd-reject",
    decision_reason="The proposed change lacks causal evidence.",
    now=@clock.Timestamp::from_ms(20L),
  )
  assert_eq(
    mooncode_json_string(decision, "decision_reason", default=""),
    "The proposed change lacks causal evidence.",
  )
  let rejected_execution = mooncode_runtime_rejected_tool_execution(
    session_id,
    book_root,
    "cmd-rejection",
    {
      "tool": "write",
      "arguments": { "path": "rejected.txt", "content": "no" },
    },
    decision,
  )
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(rejected_execution, "result"),
      "output",
      default="",
    ).contains("lacks causal evidence"),
  )
  let resumed_message = mooncode_runtime_turn_model_tool_result_message(
    {
      "tool": "write",
      "tool_call_id": mooncode_json_string(
        request,
        "tool_call_id",
        default="rejected-tool",
      ),
    },
    rejected_execution,
  )
  assert_true(
    mooncode_json_string(resumed_message, "content", default="").contains(
      "lacks causal evidence",
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      rejected_execution,
    ),
  )
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      decision,
    ),
  )
  let completed = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "rejection-test",
  })
  assert_true(mooncode_json_bool(completed, "accepted", default=false))
  assert_false(@fsx.exists(@pathx.join(book_root, "rejected.txt")))
}

///|
async test "mooncode cancel control interrupts an active process and stays hidden" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-cancel-XXXXXX"),
  )
  let session_id = "session-cancel"
  let daemon = mooncode_control_test_daemon(book_root)
  goal_gate_write_snapshot(
    book_root,
    session_id,
    false,
    goal_gate_snapshot(session_id, book_root),
  )
  assert_eq(
    mooncode_goal_runtime_api_put_internal(
      book_root,
      session_id,
      goal_runtime_test_body(session_id),
      1L,
    ).status_code,
    201,
  )
  @async.with_task_group(group => {
    let submitted = daemon.mooncode_submit_turn_response(group~, session_id, {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "model": "codex/gpt-5.6-sol",
      "text": "Run a long task",
      "packet": { "command_id": "cmd-long", "client_turn_id": "client-long" },
      "runtime_tool_calls": [
        {
          "tool": "shell",
          "arguments": {
            "cmd": "sleep 20; printf done > should-not-exist.txt",
            "timeout_ms": 30000,
          },
        },
        { "tool": "finish", "arguments": { "answer": "finished" } },
      ],
    })
    assert_true(mooncode_json_bool(submitted, "accepted", default=false))
    let binding = daemon.mooncode_binding_for_session(session_id)
    let mut attempts = 0
    while binding.active_command_id == "" && attempts < 100 {
      @async.sleep(10)
      attempts += 1
    }
    assert_eq(binding.active_command_id, "cmd-long")
    let cancelled = daemon.mooncode_submit_turn_response(group~, session_id, {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "cancel",
      "model": "codex/gpt-5.6-sol",
      "text": "Cancel the current work",
      "packet": { "command_id": "cmd-cancel" },
      "payload": { "target_command_id": "cmd-long" },
    })
    let control = mooncode_json_object_field_or_empty(cancelled, "service")
    assert_eq(
      mooncode_json_string(control, "target_command_id", default=""),
      "cmd-long",
    )
    assert_eq(mooncode_json_string(control, "status", default=""), "cancelled")
    group.return_immediately(())
  })
  let goal = mooncode_goal_runtime_api_get_internal(book_root, session_id)
  assert_eq(goal.status_code, 200)
  guard goal.body is Object(goal_body) &&
    goal_body["status"] is Object(goal_status) else {
    abort("goal runtime status")
  }
  assert_eq(goal_status["terminal"], true)
  assert_eq(goal_status["outcome"], ("cancelled" : Json))
  assert_false(@fsx.exists(@pathx.join(book_root, "should-not-exist.txt")))
  let claim = daemon.mooncode_runtime_claim_state_payload(session_id, book_root)
  assert_eq(mooncode_json_int(claim, "delivered_command_count", default=0), 2)
  let record = daemon.mooncode_session_record(session_id, book_root).unwrap()
  let turns = mooncode_json_array_items(
    mooncode_json_object_field_or_empty(record, "mooncode_conversation"),
    "turns",
  )
  assert_eq(turns.length(), 1)
  assert_eq(mooncode_json_string(turns[0], "status", default=""), "cancelled")
}

///|
async test "mooncode cancel control rejects a stale turn target" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-stale-cancel-XXXXXX"),
  )
  let daemon = mooncode_control_test_daemon(book_root)
  @async.with_task_group(group => {
    let submitted = daemon.mooncode_submit_turn_response(
      group~,
      "session-stale-cancel",
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-stale-cancel",
        "book_root": book_root,
        "command": "prompt",
        "model": "codex/gpt-5.6-sol",
        "text": "Run a long task",
        "packet": { "command_id": "cmd-active" },
        "runtime_tool_calls": [
          {
            "tool": "shell",
            "arguments": {
              "cmd": "sleep 20; printf done > stale-cancel-must-not-finish.txt",
              "timeout_ms": 30000,
            },
          },
          { "tool": "finish", "arguments": { "answer": "finished" } },
        ],
      },
    )
    assert_true(mooncode_json_bool(submitted, "accepted", default=false))
    let binding = daemon.mooncode_binding_for_session("session-stale-cancel")
    let mut attempts = 0
    while binding.active_command_id == "" && attempts < 100 {
      @async.sleep(10)
      attempts += 1
    }
    assert_eq(binding.active_command_id, "cmd-active")
    let rejected = try {
      ignore(
        daemon.mooncode_submit_cancel_control(
          "session-stale-cancel",
          book_root,
          {
            "protocol": mooncode_protocol_version(),
            "session_id": "session-stale-cancel",
            "book_root": book_root,
            "command": "cancel",
            "model": "codex/gpt-5.6-sol",
            "packet": { "command_id": "cmd-stale-cancel" },
            "payload": { "target_command_id": "command-no-longer-active" },
          },
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_true(binding.runtime_service_running)
    assert_eq(binding.active_command_id, "cmd-active")
    let cancelled = daemon.mooncode_submit_cancel_control(
      "session-stale-cancel",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-stale-cancel",
        "book_root": book_root,
        "command": "cancel",
        "model": "codex/gpt-5.6-sol",
        "packet": { "command_id": "cmd-correct-cancel" },
        "payload": { "target_command_id": "cmd-active" },
      },
    )
    assert_eq(
      mooncode_json_string(cancelled, "target_command_id", default=""),
      "cmd-active",
    )
    group.return_immediately(())
  })
  assert_false(
    @fsx.exists(@pathx.join(book_root, "stale-cancel-must-not-finish.txt")),
  )
}

///|
async test "mooncode approval resumes from durable checkpoint after daemon restart" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-approval-restart-XXXXXX"),
  )
  let session_id = "session-approval-restart"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "model": "codex/gpt-5.6-sol",
    "text": "Resume the approved write after restart",
    "packet": { "command_id": "cmd-approval-restart" },
    "payload": { "approval_wait_ms": 0 },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": { "path": "pre-approval-count.txt", "content": "once" },
      },
      {
        "tool": "write",
        "requires_approval": true,
        "arguments": {
          "path": "approved-after-restart.txt",
          "content": "approved",
        },
      },
      {
        "tool": "finish",
        "arguments": { "answer": "approval restart completed" },
      },
    ],
  }
  mooncode_control_test_queue(
    book_root,
    session_id,
    command,
    now=@clock.Timestamp::from_ms(10L),
  )
  let first_daemon = mooncode_control_test_daemon(book_root)
  let waiting = first_daemon.mooncode_runtime_turn_execute(
    session_id,
    book_root,
    { "consumer_id": "approval-restart-before" },
  )
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(waiting, "execution"),
      "waiting_approval",
      default=false,
    ),
  )
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "pre-approval-count.txt")),
    "once",
  )
  let before_events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  let request = mooncode_control_test_approval_request(before_events)
  let approval_id = mooncode_json_string(request, "approval_id", default="")
  assert_true(approval_id != "")
  assert_eq(
    before_events
    .filter(event => {
      mooncode_json_string(event, "kind", default="") ==
      mooncode_runtime_continuation_kind()
    })
    .length(),
    1,
  )
  let checkpoint = mooncode_runtime_continuation_for_command(
    before_events, "cmd-approval-restart",
  )
  assert_true(mooncode_runtime_continuation_is_active(checkpoint))
  assert_false(
    mooncode_runtime_continuation_is_active(
      mooncode_json_object_with_field(
        checkpoint,
        "tool_index",
        Json::number(99.0),
      ),
    ),
  )
  let restarted_daemon = mooncode_control_test_daemon(book_root)
  @async.with_task_group(group => {
    let approved = restarted_daemon.mooncode_submit_turn_response(
      group~,
      session_id,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "approve_tool",
        "model": "codex/gpt-5.6-sol",
        "packet": { "command_id": "cmd-approve-after-restart" },
        "payload": {
          "approval_id": approval_id,
          "target_command_id": "cmd-approval-restart",
          "tool_call_id": mooncode_json_string(
            request,
            "tool_call_id",
            default="",
          ),
        },
      },
    )
    assert_true(mooncode_json_bool(approved, "accepted", default=false))
    let binding = restarted_daemon.mooncode_binding_for_session(session_id)
    let mut attempts = 0
    while binding.runtime_service_running && attempts < 200 {
      @async.sleep(10)
      attempts += 1
    }
    assert_false(binding.runtime_service_running)
    group.return_immediately(())
  })
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "pre-approval-count.txt")),
    "once",
  )
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "approved-after-restart.txt")),
    "approved",
  )
  let after_events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  assert_eq(
    after_events
    .filter(event => {
      mooncode_json_string(event, "kind", default="") == "runtime.turn_started"
    })
    .length(),
    1,
  )
  let record = restarted_daemon
    .mooncode_session_record(session_id, book_root)
    .unwrap()
  let turns = mooncode_json_array_items(
    mooncode_json_object_field_or_empty(record, "mooncode_conversation"),
    "turns",
  )
  assert_eq(turns.length(), 1)
  assert_eq(mooncode_json_string(turns[0], "status", default=""), "done")
}

///|
async test "mooncode rejection resumes from durable checkpoint after daemon restart" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-reject-restart-XXXXXX"),
  )
  let session_id = "session-reject-restart"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "model": "codex/gpt-5.6-sol",
    "text": "Reject the write after restart",
    "packet": { "command_id": "cmd-reject-restart" },
    "payload": { "approval_wait_ms": 0 },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": { "path": "pre-reject-count.txt", "content": "once" },
      },
      {
        "tool": "write",
        "requires_approval": true,
        "arguments": {
          "path": "rejected-after-restart.txt",
          "content": "must-not-exist",
        },
      },
      {
        "tool": "finish",
        "arguments": { "answer": "rejection restart completed" },
      },
    ],
  }
  mooncode_control_test_queue(
    book_root,
    session_id,
    command,
    now=@clock.Timestamp::from_ms(10L),
  )
  let first_daemon = mooncode_control_test_daemon(book_root)
  ignore(
    first_daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "reject-restart-before",
    }),
  )
  let events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  let request = mooncode_control_test_approval_request(events)
  let approval_id = mooncode_json_string(request, "approval_id", default="")
  let restarted_daemon = mooncode_control_test_daemon(book_root)
  @async.with_task_group(group => {
    let rejected = restarted_daemon.mooncode_submit_turn_response(
      group~,
      session_id,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "reject_tool",
        "model": "codex/gpt-5.6-sol",
        "packet": { "command_id": "cmd-reject-after-restart" },
        "payload": {
          "approval_id": approval_id,
          "target_command_id": "cmd-reject-restart",
          "decision_reason": "The proposed mutation lacks causal evidence.",
          "tool_call_id": mooncode_json_string(
            request,
            "tool_call_id",
            default="",
          ),
        },
      },
    )
    assert_true(mooncode_json_bool(rejected, "accepted", default=false))
    let binding = restarted_daemon.mooncode_binding_for_session(session_id)
    let mut attempts = 0
    while binding.runtime_service_running && attempts < 200 {
      @async.sleep(10)
      attempts += 1
    }
    assert_false(binding.runtime_service_running)
    group.return_immediately(())
  })
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "pre-reject-count.txt")),
    "once",
  )
  assert_false(
    @fsx.exists(@pathx.join(book_root, "rejected-after-restart.txt")),
  )
  let after_events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  assert_true(
    after_events.any(event => {
      mooncode_json_string(event, "kind", default="") ==
      "tool.approval_rejected" &&
      mooncode_json_string(event, "decision_reason", default="") ==
      "The proposed mutation lacks causal evidence."
    }),
  )
  let state = restarted_daemon.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  assert_eq(mooncode_json_int(state, "delivered_command_count", default=0), 2)
}

///|
async fn Daemon::mooncode_runtime_loop(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_string()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime loop requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let result = self.mooncode_runtime_loop_execute(session_id, book_root, body)
  w.header().set("Content-Type", "application/json")
  w.write_header(
    if mooncode_json_int(result, "ran_turn_count", default=0) > 0 {
      202
    } else {
      200
    },
    reason=if mooncode_json_int(result, "ran_turn_count", default=0) > 0 {
      "Accepted"
    } else {
      "OK"
    },
  )
  w.write(result.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_loop_execute(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let max_turns = mooncode_runtime_loop_max_turns(payload)
  let consumer_id = mooncode_json_string(
    payload,
    "consumer_id",
    default="moonclaw-native-runtime-loop",
  )
  let before = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let turns : Array[Json] = []
  let mut ran_turn_count = 0
  let mut failed_turn_count = 0
  let mut stopped_by = "max_turns"
  for index in 0..<max_turns {
    if @async.is_being_cancelled() {
      stopped_by = "cancelled"
      break
    }
    let turn = self.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": consumer_id,
      "runtime_loop": true,
      "loop_index": index,
      "max_turns": max_turns,
    })
    turns.push(turn)
    if !mooncode_json_bool(turn, "ran", default=false) {
      stopped_by = "idle"
      break
    }
    ran_turn_count += 1
    if !mooncode_json_bool(turn, "accepted", default=false) {
      failed_turn_count += 1
      stopped_by = "failed"
      break
    }
    let execution = mooncode_json_object_field_or_empty(turn, "execution")
    let control = mooncode_json_string(execution, "control", default="")
    if control == "cancel" {
      stopped_by = "cancelled"
      break
    }
    let claim_state = mooncode_json_object_field_or_empty(turn, "claim_state")
    if !mooncode_json_bool(claim_state, "claim_ready", default=false) &&
      mooncode_json_int(claim_state, "claimed_command_count", default=0) == 0 {
      stopped_by = "idle"
      break
    }
  }
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  {
    "kind": "mooncode-runtime-loop",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": ran_turn_count > 0 && failed_turn_count == 0,
    "session_id": session_id,
    "book_root": book_root,
    "consumer_id": consumer_id,
    "max_turns": max_turns,
    "ran_turn_count": ran_turn_count,
    "failed_turn_count": failed_turn_count,
    "turn_count": turns.length(),
    "stopped_by": stopped_by,
    "message": mooncode_runtime_loop_message(
      stopped_by, ran_turn_count, failed_turn_count,
    ),
    "turns": Json::array(turns),
    "claim_state": after,
    "previous_claim_state": before,
  }
}

///|
fn mooncode_runtime_loop_max_turns(payload : Json) -> Int {
  let requested = mooncode_json_int(payload, "max_turns", default=8)
  if requested < 1 {
    1
  } else if requested > 32 {
    32
  } else {
    requested
  }
}

///|
fn mooncode_runtime_loop_message(
  stopped_by : String,
  ran_turn_count : Int,
  failed_turn_count : Int,
) -> String {
  match stopped_by {
    "idle" =>
      if ran_turn_count == 0 {
        "MoonClaw native runtime loop found no claimable MoonCode commands."
      } else {
        "MoonClaw native runtime loop completed \{ran_turn_count} turn(s) and reached an idle queue."
      }
    "failed" =>
      "MoonClaw native runtime loop stopped after \{failed_turn_count} failed turn(s)."
    "cancelled" =>
      "MoonClaw native runtime loop stopped after a cancel command."
    _ =>
      "MoonClaw native runtime loop reached its max_turns limit after \{ran_turn_count} turn(s)."
  }
}

///|
async test "mooncode native runtime loop drains queued commands" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-loop-XXXXXX"),
  )
  let session_id = "session-runtime-loop"
  let first_command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "packet": { "command_id": "cmd-loop-1" },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": { "path": "tools/loop-proof/one.txt", "content": "one" },
      },
      { "tool": "finish", "arguments": { "answer": "first done" } },
    ],
  }
  let second_command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "packet": { "command_id": "cmd-loop-2" },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": { "path": "tools/loop-proof/two.txt", "content": "two" },
      },
      { "tool": "finish", "arguments": { "answer": "second done" } },
    ],
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": "cmd-loop-1",
    "created_at": @clock.Timestamp::from_ms(10L),
    "command": first_command,
  })
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": "cmd-loop-2",
    "created_at": @clock.Timestamp::from_ms(20L),
    "command": second_command,
  })
  let daemon = Daemon::{
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
  let result = daemon.mooncode_runtime_loop_execute(session_id, book_root, {
    "consumer_id": "test-runtime-loop",
    "max_turns": 5,
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  assert_eq(mooncode_json_int(result, "ran_turn_count", default=0), 2)
  assert_eq(mooncode_json_string(result, "stopped_by", default=""), "idle")
  assert_eq(mooncode_json_array_items(result, "turns").length(), 2)
  assert_true(@fsx.exists(@pathx.join(book_root, "tools/loop-proof/one.txt")))
  assert_true(@fsx.exists(@pathx.join(book_root, "tools/loop-proof/two.txt")))
  let dispatch_log = @fsx.read_file(
    mooncode_runtime_dispatches_path(book_root, session_id),
  )
  assert_true(dispatch_log.contains("cmd-loop-1"))
  assert_true(dispatch_log.contains("cmd-loop-2"))
  assert_true(dispatch_log.contains("\"runtime-completed\""))
  let state = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_eq(mooncode_json_int(state, "delivered_command_count", default=0), 2)
}

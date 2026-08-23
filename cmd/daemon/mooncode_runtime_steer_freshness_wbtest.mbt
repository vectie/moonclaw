///|
fn mooncode_runtime_steer_freshness_completion(
  call_id : String,
  tool : String,
  arguments : String,
) -> Json {
  {
    "id": "completion-\{call_id}",
    "object": "chat.completion",
    "created": 1,
    "model": "test-steer-freshness-model",
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
async fn mooncode_runtime_steer_freshness_append(
  book_root : String,
  session_id : String,
  command_id : String,
  text : String,
  created_at : Int64,
) -> Unit {
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": command_id,
      "created_at": @clock.Timestamp::from_ms(created_at),
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "steer",
        "text": text,
        "packet": { "command_id": command_id },
      },
    },
  )
}

///|
async fn mooncode_runtime_steer_freshness_daemon(book_root : String) -> Daemon {
  {
    clock: @clock.epoch,
    models: @model.Loader::new(home=book_root, cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
async test "live steer arriving during replan supersedes stale mutation" {
  @fsx.with_temporary_directory("mooncode-steer-freshness-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-steer-freshness"
    let prompt_id = "prompt-steer-freshness"
    let first_steer_id = "steer-before-replan"
    let second_steer_id = "steer-during-replan"
    let stale_path = @pathx.join(root, "stale-plan.txt")
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": prompt_id,
        "created_at": @clock.Timestamp::from_ms(1L),
        "command": {
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "book_root": root,
          "command": "prompt",
          "text": "Answer only after applying all live steering.",
          "model": "test-steer-freshness",
          "packet": { "command_id": prompt_id },
          "payload": { "planner_timeout_ms": 5000 },
        },
      },
    )
    let model_server = @httpx.Server::new("[::1]", 0, reuse_addr=true)
    defer model_server.close()
    let calls = Ref::Ref(0)
    let router = @httpx.Router::new()
    router.add_handler(Post, "/v1/chat/completions", (_, w) => {
      let response = if calls.val == 0 {
        mooncode_runtime_steer_freshness_append(
          root, session_id, first_steer_id, "The current plan is stale; replan before executing it.",
          3L,
        )
        mooncode_runtime_steer_freshness_completion(
          "call-stale-initial", "write", "{\"path\":\"stale-plan.txt\",\"content\":\"initial stale plan executed\"}",
        )
      } else if calls.val == 1 {
        mooncode_runtime_steer_freshness_append(
          root, session_id, second_steer_id, "A newer correction arrived during replanning; do not execute the prior mutation.",
          4L,
        )
        mooncode_runtime_steer_freshness_completion(
          "call-stale-replan", "write", "{\"path\":\"stale-plan.txt\",\"content\":\"stale replan executed\"}",
        )
      } else {
        mooncode_runtime_steer_freshness_completion(
          "call-current", "finish", "{\"answer\":\"Applied both live steering corrections.\"}",
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
      name="test-steer-freshness",
      model_name="test-steer-freshness-model",
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
      let daemon = mooncode_runtime_steer_freshness_daemon(root)
      let result = daemon.mooncode_runtime_turn_execute(session_id, root, {
        "consumer_id": "steer-freshness-test",
      })
      assert_true(mooncode_json_bool(result, "accepted", default=false))
      assert_eq(calls.val, 3)
      assert_false(@fsx.exists(stale_path))
      let execution = mooncode_json_object_field_or_empty(result, "execution")
      let applied = mooncode_json_array_items(
        execution, "applied_live_steering",
      )
      assert_eq(applied.length(), 2)
      assert_eq(
        mooncode_json_string(applied[0], "command_id", default=""),
        first_steer_id,
      )
      assert_eq(
        mooncode_json_string(applied[1], "command_id", default=""),
        second_steer_id,
      )
      let records = mooncode_read_session_journal(root, session_id)
      let mut first_receipts = 0
      let mut second_receipts = 0
      for
        receipt in mooncode_journal_entries(
          records,
          mooncode_journal_runtime_receipt(),
        ) {
        let command_id = mooncode_json_string(receipt, "command_id", default="")
        let control = mooncode_json_string(receipt, "control", default="")
        if command_id == first_steer_id && control == "steer_applied" {
          first_receipts += 1
        } else if command_id == second_steer_id && control == "steer_applied" {
          second_receipts += 1
        }
      }
      assert_eq(first_receipts, 1)
      assert_eq(second_receipts, 1)
      group.return_immediately(())
    })
  })
}

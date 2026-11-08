///|
test "finish has no language, mutation or successful-tool quota" {
  for
    text in [
      "Explain the word fix", "请解释 fix 的含义", "Implement the already satisfied behavior and run tests",
    ] {
    let command = completion_test_command(contract={})
      |> mooncode_json_object_with_field("text", Json(text))
    assert_true(
      mooncode_runtime_turn_completion_verdict(command, [
        completion_test_finish(),
      ]).accepted,
    )
    assert_true(
      mooncode_runtime_turn_completion_verdict(command, [
        { "tool": "read", "accepted": false, "result": { "ok": false } },
        completion_test_finish(),
      ]).accepted,
    )
  }
}

///|
async test "one model loop repairs edits, repeats observations and retries a transient check" {
  @fsx.with_temporary_directory("mooncode-agent-repair-XXXXXX", async fn(root) {
    @fsx.write_to_file(root + "/source.txt", "before")
    let session_id = "agent-repair"
    let command_id = "repair-command"
    let command : Json = {
      "protocol": mooncode_protocol_version(),
      "command": "prompt",
      "session_id": session_id,
      "book_root": root,
      "model": "test-agent-repair",
      "text": "Update source.txt and verify the environment is ready.",
      "packet": { "command_id": command_id },
      "payload": {
        "task_contract": {
          "required_checks": [
            {
              "id": "ready",
              "tool": "shell",
              "command": "test -f ready",
              "cwd": ".",
              "input_paths": ["source.txt", "ready"],
            },
          ],
        },
      },
    }
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
    )
    let model_server = @httpx.Server::new("[::1]", 0, reuse_addr=true)
    defer model_server.close()
    let calls = Ref::Ref(0)
    let actions : Array[(String, Json)] = [
      ("read", { "path": "source.txt" }),
      (
        "edit",
        {
          "path": "source.txt",
          "edits": [{ "old_string": "missing", "new_string": "after" }],
        },
      ),
      (
        "edit",
        {
          "path": "source.txt",
          "edits": [{ "old_string": "before", "new_string": "after" }],
        },
      ),
      ("read", { "path": "source.txt" }),
      ("read", { "path": "source.txt" }),
      (
        "shell",
        { "cmd": "test -f ready", "cwd": ".", "verification_kind": "check" },
      ),
      (
        "shell",
        { "cmd": "test -f ready", "cwd": ".", "verification_kind": "check" },
      ),
      ("finish", { "answer": "Updated source.txt and verified readiness." }),
    ]
    let router = @httpx.Router::new()
    router.add_handler(Post, "/v1/chat/completions", (_, w) => {
      let index = calls.val
      assert_true(index < actions.length())
      // A transient external condition clears without a source edit or an
      // extra "successful recovery" tool action imposed by the runtime.
      if index == 6 {
        @fsx.write_to_file(root + "/ready", "ready")
      }
      let (tool, arguments) = actions[index]
      let response = mooncode_runtime_steer_freshness_completion(
        "repair-\{index}",
        tool,
        arguments.stringify(),
      )
      calls.val += 1
      w.header().set("Content-Type", "text/event-stream")
      w.write_header(200)
      w.write("data: " + response.stringify() + "\n\ndata: [DONE]\n\n")
    })
    let model = @model.Model::new(
      api_key="test",
      base_url="http://localhost:\{model_server.port()}/v1",
      name="test-agent-repair",
      model_name="test-agent-repair-model",
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
    @fsx.write_to_file(models_path, Json([model]).stringify())
    mooncode_with_fixture_moonfort(root, async fn(_config) {
      @async.with_task_group(group => {
        group.spawn_bg(() => model_server.serve(router.handler()), no_wait=true)
        @async.pause()
        let daemon = mooncode_runtime_steer_freshness_daemon(root)
        let result = daemon.mooncode_runtime_turn_execute(session_id, root, {
          "consumer_id": "repair-test",
        })
        assert_true(
          mooncode_json_bool(result, "accepted", default=false),
          msg=result.stringify(),
        )
        assert_eq(calls.val, actions.length())
        let execution = mooncode_json_object_field_or_empty(result, "execution")
        let results = mooncode_json_array_items(execution, "tool_results")
        assert_eq(results.length(), actions.length())
        for index, result in results {
          assert_eq(
            mooncode_json_string(result, "tool", default=""),
            actions[index].0,
          )
          assert_eq(
            mooncode_json_bool(result, "accepted", default=false),
            index != 1 && index != 5,
          )
        }
        assert_eq(@fsx.read_file(root + "/source.txt"), "after")
        assert_eq(
          mooncode_runtime_required_check_evidence(command, results).length(),
          1,
        )
        group.return_immediately(())
      })
    })
  })
}

///|
test "task corrections retain constraints and do not rewrite earlier revisions" {
  let command = completion_test_command()
  let first = mooncode_runtime_task_with_update(command, {
    "command_id": "u1",
    "steering_text": "Only explain the current implementation.",
  })
  let saved = first.stringify()
  let second = mooncode_runtime_task_with_update(first, {
    "command_id": "u2",
    "steering_text": "Also inspect the related caller.",
  })
  assert_eq(first.stringify(), saved)
  assert_eq(mooncode_json_array_items(command, "task_updates").length(), 0)
  assert_eq(mooncode_json_array_items(first, "task_updates").length(), 1)
  assert_eq(mooncode_json_array_items(second, "task_updates").length(), 2)
  assert_eq(
    mooncode_runtime_horizon_task_contract(second),
    mooncode_runtime_horizon_task_contract(command),
  )
  assert_true(
    mooncode_runtime_horizon_contract(second) !=
    mooncode_runtime_horizon_contract(first),
  )
}

///|
test "task input retains long constraints and an explicitly supplied objective" {
  let text = "Inspect this task.\nFull authoritative plan follows:\n" +
    "中🚀".repeat(5000) +
    "\nPreserve the user's final constraint."
  let command : Json = { "command": "prompt", "text": text }
  assert_eq(
    mooncode_json_string(
      mooncode_runtime_horizon_contract(command),
      "objective",
      default="",
    ),
    text,
  )
  let explicit = mooncode_json_object_with_field(command, "task_contract", {
    "objective": "Inspect the plan",
    "constraints": ["Keep the existing files"],
  })
  let task = mooncode_runtime_horizon_contract(explicit)
  assert_eq(
    mooncode_json_string(task, "objective", default=""),
    "Inspect the plan",
  )
  assert_eq(mooncode_json_array_string_items(task, "constraints"), [
    "Keep the existing files",
  ])
  assert_true(mooncode_runtime_turn_model_prompt(explicit).contains(text))
}

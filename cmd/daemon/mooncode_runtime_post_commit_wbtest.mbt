///|
async test "raw shell commit retains exact changed paths" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-post-commit-paths-XXXXXX"),
  )
  let setup_operations : Array[@trusted_host_process.GitOperation] = [Init]
  for operation in setup_operations {
    assert_true(
      mooncode_json_bool(
        mooncode_runtime_turn_git(
          book_root,
          operation,
          timeout_ms=10000,
          max_output_chars=4000,
        ),
        "ok",
        default=false,
      ),
    )
  }
  @fsx.make_directory(
    @pathx.join(book_root, "docs"),
    recursive=true,
    exists_ok=true,
  )
  let proof_path = "docs/PREVIEW_RELEASE_PROOF_2026-07-27.md"
  let plan_path = "docs/MOONDESK_PRODUCTIZATION_UPGRADE_PLAN.md"
  @fsx.write_to_file(@pathx.join(book_root, proof_path), "proof\n")
  @fsx.write_to_file(@pathx.join(book_root, plan_path), "plan\n")
  mooncode_with_fixture_moonfort(book_root, async fn(config) {
    let commit = mooncode_fixture_execute_tool_call(
      config,
      "phase2-release-gate",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "phase2-release-gate",
        "book_root": book_root,
        "tool": "shell",
        "command_id": "phase2-evidence-doc-closeout",
        "arguments": {
          "cmd": "set -o pipefail; git add -- \{proof_path} \{plan_path} && git commit -m \"docs: close release evidence\"",
          "timeout_ms": 10000,
          "verification_kind": "check",
        },
      },
      now=@clock.Timestamp::from_ms(1L),
    )
    assert_true(mooncode_json_bool(commit, "accepted", default=false))
    let result = mooncode_json_object_field_or_empty(commit, "result")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    assert_true(
      mooncode_json_bool(metadata, "post_commit_capture_valid", default=false),
    )
    let changed_paths = mooncode_json_array_string_items(
      metadata, "changed_paths",
    )
    assert_eq(changed_paths.length(), 2)
    assert_true(changed_paths.contains(proof_path))
    assert_true(changed_paths.contains(plan_path))
    let event = mooncode_json_object_field_or_empty(commit, "event")
    assert_eq(
      mooncode_json_array_string_items(event, "changed_paths"),
      changed_paths,
    )
    let event_metadata = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(event, "tool_result"),
      "metadata",
    )
    assert_eq(
      mooncode_json_array_string_items(event_metadata, "changed_paths"),
      changed_paths,
    )
    assert_true(mooncode_runtime_turn_result_is_mutation(commit))
    assert_true(mooncode_runtime_turn_result_is_mutation(event))
    let verification = mooncode_fixture_execute_tool_call(
      config,
      "phase2-release-gate",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "phase2-release-gate",
        "book_root": book_root,
        "tool": "shell",
        "command_id": "phase2-evidence-doc-closeout",
        "arguments": {
          "cmd": "git status --short",
          "verification_kind": "check",
        },
      },
      now=@clock.Timestamp::from_ms(2L),
    )
    assert_true(mooncode_json_bool(verification, "accepted", default=false))
  })
}

///|
async test "same command repairs and verifies after a commit without another user turn" {
  @fsx.with_temporary_directory("mooncode-commit-repair-XXXXXX", async fn(
    root,
  ) {
    assert_true(
      mooncode_json_bool(
        mooncode_runtime_turn_git(
          root,
          Init,
          timeout_ms=10000,
          max_output_chars=4000,
        ),
        "ok",
        default=false,
      ),
    )
    @fsx.write_to_file(@pathx.join(root, "tracked.txt"), "initial\n")
    let session_id = "commit-repair-session"
    let command_id = "commit-repair-command"
    let check = "test \"$(cat tracked.txt)\" = repaired"
    let command : Json = {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": root,
      "command": "prompt",
      "model": "codex/gpt-5.6-sol",
      "text": "Repair the file and verify its content.",
      "packet": { "command_id": command_id },
      "payload": {
        "task_intent": "workspace_change",
        "task_contract": {
          "required_checks": [
            {
              "id": "content",
              "tool": "shell",
              "command": check,
              "cwd": ".",
              "input_paths": ["tracked.txt"],
            },
          ],
        },
      },
      "runtime_tool_calls": [
        {
          "tool": "shell",
          "arguments": {
            "cmd": "git add tracked.txt && git commit -m initial && git status --short",
          },
        },
        { "tool": "read", "arguments": { "path": "tracked.txt" } },
        {
          "tool": "edit",
          "arguments": {
            "path": "tracked.txt",
            "old_string": "initial",
            "new_string": "repaired",
          },
        },
        {
          "tool": "shell",
          "arguments": {
            "cmd": check,
            "cwd": ".",
            "verification_kind": "check",
          },
        },
        {
          "tool": "finish",
          "arguments": { "answer": "Repaired and verified tracked.txt." },
        },
      ],
    }
    mooncode_with_fixture_moonfort(root, async fn(config) {
      let command = mooncode_fixture_authorized_runtime_command(
        config, root, command,
      )
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
      mooncode_fixture_approve_runtime_commands(root, command)
      let daemon = mooncode_control_test_daemon(root)
      let receipt = daemon.mooncode_runtime_turn_execute(session_id, root, {
        "consumer_id": "commit-repair-test",
      })
      let execution = mooncode_json_object_field_or_empty(receipt, "execution")
      let results = mooncode_json_array_items(execution, "tool_results")
      assert_eq(results.length(), 5)
      for result in results {
        assert_true(mooncode_json_bool(result, "accepted", default=false))
      }
      assert_true(mooncode_json_bool(execution, "completed", default=false))
      assert_eq(@fsx.read_file(@pathx.join(root, "tracked.txt")), "repaired\n")
      assert_eq(mooncode_runtime_finish_input_error(root, command, results), "")
      @fsx.write_to_file(
        @pathx.join(root, "tracked.txt"),
        "changed after check\n",
      )
      assert_true(
        mooncode_runtime_finish_input_error(root, command, results) != "",
      )
    })
  })
}

///|
async test "native ABI rejects malformed arguments before effects" {
  @fsx.with_temporary_directory("mooncode-abi-XXXXXX", async fn(root) {
    @fsx.write_to_file(root + "/file.txt", "keep")
    let calls : Array[(String, Json)] = [
      ("write", { "path": "file.txt", "content": 42 }),
      ("write", { "path": "file.txt" }),
      ("edit", { "path": "file.txt", "edits": [{ "old_string": "keep" }] }),
      ("shell", { "cmd": "touch marker", "timeout_ms": "1000" }),
      (
        "apply_patch",
        {
          "path": "file.txt",
          "before": "keep",
          "after": "lost",
          "verification_command": "touch marker",
        },
      ),
    ]
    for (tool, arguments) in calls {
      let result = mooncode_execute_tool_call(
        "abi",
        root,
        { "tool": tool, "command_id": "abi", "arguments": arguments },
        now=@clock.Timestamp::from_ms(1L),
      )
      assert_false(
        mooncode_json_bool(result, "accepted", default=true),
        msg=result.stringify(),
      )
      assert_true(
        mooncode_json_string(
          mooncode_json_object_field_or_empty(result, "result"),
          "message",
          default="",
        ).contains("arguments"),
      )
    }
    assert_eq(@fsx.read_file(root + "/file.txt"), "keep")
    assert_false(@fsx.exists(root + "/marker"))
    let session_id = "invalid-before-approval"
    let command : Json = {
      "protocol": mooncode_protocol_version(),
      "command": "prompt",
      "session_id": session_id,
      "book_root": root,
      "model": "fixture/mooncode",
      "text": "Write the file",
      "packet": { "command_id": "invalid-before-approval" },
      "runtime_tool_calls": [
        {
          "tool": "write",
          "requires_approval": true,
          "arguments": { "path": "file.txt", "content": 42 },
        },
      ],
    }
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": "invalid-before-approval",
        "created_at": @clock.Timestamp::from_ms(1L),
        "command": command,
      },
    )
    let daemon = mooncode_control_test_daemon(root)
    let receipt = daemon.mooncode_runtime_turn_execute(session_id, root, {
      "consumer_id": "abi-test",
    })
    let execution = mooncode_json_object_field_or_empty(receipt, "execution")
    assert_false(
      mooncode_json_bool(execution, "waiting_approval", default=true),
    )
    let results = mooncode_json_array_items(execution, "tool_results")
    assert_eq(results.length(), 1, msg=receipt.stringify())
    assert_false(mooncode_json_bool(results[0], "accepted", default=true))
    assert_eq(@fsx.read_file(root + "/file.txt"), "keep")
  })
}

///|
async test "workspace aliases share scope identity and escaping symlinks cannot write" {
  @fsx.with_temporary_directory("mooncode-alias-XXXXXX", async fn(root) {
    @fsx.make_directory(root + "/actual")
    @fsx.write_to_file(root + "/actual/file.txt", "old")
    @fs.symlink(target=root + "/actual", root + "/alias")
    let real = mooncode_workspace_path(root, "actual/file.txt")
    let alias = mooncode_workspace_path(root, "alias/file.txt")
    assert_eq(real, alias)
    assert_true(
      mooncode_moon_fmt_path_is_requested(
        root,
        root,
        ["alias/file.txt"],
        "actual/file.txt",
      ),
    )
    assert_eq(
      mooncode_task_scope_preflight_error(root, Some(["alias"]), "write", {
        "path": "actual/file.txt",
      }),
      None,
    )
    let first : Json = {
      "tool": "read",
      "arguments": { "path": "actual/file.txt" },
    }
    let second : Json = {
      "tool": "read",
      "arguments": { "path": "alias/file.txt" },
    }
    assert_eq(
      mooncode_runtime_parallel_read_identity(root, first),
      mooncode_runtime_parallel_read_identity(root, second),
    )
    let version = mooncode_tool_content_fingerprint("old", exists=true)
    let changed = mooncode_tool_write(root, {
      "path": "alias/file.txt",
      "content": "new",
      "expected_fingerprint": version,
    })
    assert_true(
      mooncode_json_bool(changed, "ok", default=false),
      msg=changed.stringify(),
    )
    assert_true(@fs.kind(root + "/alias", follow_symlink=false) is SymLink)
    let stale = mooncode_tool_write(root, {
      "path": "actual/file.txt",
      "content": "lost",
      "expected_fingerprint": version,
    })
    assert_false(mooncode_json_bool(stale, "ok", default=true))
    assert_eq(@fsx.read_file(root + "/actual/file.txt"), "new")
    @fsx.make_directory(root + "/other")
    @fsx.write_to_file(root + "/other/file.txt", "new")
    let command : Json = {
      "command": "prompt",
      "packet": { "command_id": "alias-check" },
      "task_contract": {
        "required_checks": [{ "input_paths": ["alias/file.txt"] }],
      },
    }
    let inputs = mooncode_runtime_check_inputs(root, command, [])
    let checked = mooncode_runtime_bind_check_inputs(
      {
        "tool": "moon_cmd",
        "accepted": true,
        "arguments": { "command": "test" },
        "result": {},
      },
      inputs,
      command,
    )
    @fs.remove(root + "/alias")
    @fs.symlink(target=root + "/other", root + "/alias")
    assert_true(
      mooncode_runtime_finish_input_error(root, command, [checked]).contains(
        "identity changed",
      ),
    )
    @fsx.with_temporary_directory("mooncode-outside-XXXXXX", async fn(outside) {
      @fsx.write_to_file(outside + "/keep.txt", "keep")
      @fs.symlink(target=outside, root + "/escape")
      assert_false(
        mooncode_json_bool(
          mooncode_tool_write(root, {
            "path": "escape/keep.txt",
            "content": "lost",
          }),
          "ok",
          default=true,
        ),
      )
      assert_eq(@fsx.read_file(outside + "/keep.txt"), "keep")
      @fs.symlink(target=outside + "/absent", root + "/dangling")
      assert_false(
        mooncode_json_bool(
          mooncode_workspace_path(root, "dangling/new.txt"),
          "ok",
          default=true,
        ),
      )
    })
  })
}

///|
async test "conditional writes serialize one resource without blocking other files" {
  @fsx.with_temporary_directory("mooncode-file-cas-XXXXXX", async fn(root) {
    let root = @fsx.resolve(root)
    let path = root + "/file.txt"
    @fsx.write_to_file(path, "old")
    @fs.chmod(path, 0o775)
    @async.with_task_group(group => {
      let lock = mooncode_workspace_file_lock(root, path)
      defer lock.close()
      let pending = group.spawn(
        () => mooncode_workspace_replace(root, path, Some("old"), Some("new")),
        no_wait=true,
      )
      mooncode_workspace_replace(
        root,
        root + "/independent.txt",
        None,
        Some("independent"),
      )
      assert_eq(@fsx.read_file(path), "old")
      lock.unlock()
      pending.wait()
      assert_eq(@fsx.read_file(path), "new")
      assert_true(@fs.can_execute(path))
      assert_eq(@moonclaw_fsx.stat(path).mode(), 0o775)
      let first = group.spawn(
        () => {
          Ok(mooncode_workspace_replace(root, path, Some("new"), Some("first"))) catch {
            error => Err("\{error}")
          }
        },
        no_wait=true,
      )
      let second = group.spawn(
        () => {
          Ok(
            mooncode_workspace_replace(root, path, Some("new"), Some("second")),
          ) catch {
            error => Err("\{error}")
          }
        },
        no_wait=true,
      )
      let a = first.wait()
      let b = second.wait()
      assert_true((a is Ok(_)) != (b is Ok(_)))
      assert_true(["first", "second"].contains(@fsx.read_file(path)))
    })
  })
}

///|
async test "patch rollback preserves subsequent external edits and unattempted files" {
  @fsx.with_temporary_directory("mooncode-patch-race-XXXXXX", async fn(root) {
    let root = @fsx.resolve(root)
    for path in ["a.txt", "b.txt", "c.txt"] {
      @fsx.write_to_file(root + "/" + path, "old\n")
    }
    let diff = ["a.txt", "b.txt", "c.txt"]
      .map(path => "--- a/\{path}\n+++ b/\{path}\n@@\n-old\n+new\n")
      .join("")
    @async.with_task_group(group => {
      let lock = mooncode_workspace_file_lock(root, root + "/b.txt")
      defer lock.close()
      let pending = group.spawn(
        () => mooncode_tool_apply_patch(root, { "diff": diff }),
        no_wait=true,
      )
      for _ in 0..<300 {
        if @fsx.read_file(root + "/a.txt") == "new\n" {
          break
        }
        @async.sleep(10)
      }
      assert_eq(@fsx.read_file(root + "/a.txt"), "new\n")
      @fsx.write_to_file(root + "/a.txt", "external a\n")
      @fsx.write_to_file(root + "/b.txt", "external b\n")
      lock.unlock()
      let result = pending.wait()
      assert_false(mooncode_json_bool(result, "ok", default=true))
      let metadata = mooncode_json_object_field_or_empty(result, "metadata")
      assert_false(mooncode_json_bool(metadata, "rolled_back", default=true))
      assert_true(
        mooncode_json_bool(metadata, "outcome_unknown", default=false),
      )
      assert_eq(@fsx.read_file(root + "/a.txt"), "external a\n")
      assert_eq(@fsx.read_file(root + "/b.txt"), "external b\n")
      assert_eq(@fsx.read_file(root + "/c.txt"), "old\n")
    })
  })
}

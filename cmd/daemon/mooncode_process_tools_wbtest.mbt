///|
async test "mooncode native shell tool runs inside book root" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-shell-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-shell",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-shell",
      "book_root": book_root,
      "tool": "shell",
      "command_id": "cmd-shell",
      "arguments": { "cmd": "pwd", "timeout_ms": 5000 },
    },
    now=@clock.Timestamp::from_ms(45L),
  )
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(mooncode_json_bool(result, "ok", default=false))
  assert_true(
    mooncode_json_string(result, "output", default="").contains(book_root),
  )
}

///|
async test "mooncode shell retains complete and partial local file observations" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-shell-observation-XXXXXX"),
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "observed.txt"),
    "one\ntwo\nthree\n",
  )
  let partial = mooncode_tool_shell(book_root, {
    "cmd": "sed -n '1,2p' observed.txt",
    "timeout_ms": 5000,
  })
  let partial_metadata = mooncode_json_object_field_or_empty(
    partial, "metadata",
  )
  let partial_observation = mooncode_json_object_field_or_empty(
    partial_metadata, "file_observation",
  )
  assert_eq(
    mooncode_json_string(partial_observation, "path", default=""),
    "observed.txt",
  )
  assert_eq(
    mooncode_json_string(partial_observation, "scope", default=""),
    "partial",
  )
  let complete = mooncode_tool_shell(book_root, {
    "cmd": "sed -n '1,99p' observed.txt",
    "timeout_ms": 5000,
  })
  let complete_observation = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(complete, "metadata"),
    "file_observation",
  )
  assert_eq(
    mooncode_json_string(complete_observation, "scope", default=""),
    "complete",
  )
  let cat_complete = mooncode_tool_shell(book_root, {
    "cmd": "cat observed.txt",
    "timeout_ms": 5000,
  })
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(cat_complete, "metadata"),
        "file_observation",
      ),
      "scope",
      default="",
    ),
    "complete",
  )
  for transformed in ["grep two observed.txt", "cat -n observed.txt"] {
    let result = mooncode_tool_shell(book_root, {
      "cmd": transformed,
      "timeout_ms": 5000,
    })
    let observation = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(result, "metadata"),
      "file_observation",
    )
    assert_eq(mooncode_json_string(observation, "scope", default=""), "partial")
  }
  let outside_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-shell-observation-outside-XXXXXX"),
  )
  let outside_path = @pathx.join(outside_root, "outside.txt")
  @fsx.write_to_file(outside_path, "outside\n")
  let outside = mooncode_shell_file_observation(
    book_root,
    book_root,
    "cat \{outside_path}",
    "outside\n",
    false,
  )
  assert_eq(mooncode_json_string(outside, "path", default=""), "")
}

///|
async test "mooncode shell timeout cancels children and permits cleanup traps" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-shell-timeout-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-shell-timeout",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-shell-timeout",
      "book_root": book_root,
      "tool": "shell",
      "command_id": "cmd-shell-timeout",
      "arguments": {
        "cmd": "printf partial-output; trap 'printf cleanup-ran >&2; exit 0' TERM; sleep 10",
        "timeout_ms": 20,
      },
    },
    now=@clock.Timestamp::from_ms(45L),
  )
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(mooncode_json_bool(result, "is_error", default=false))
  assert_eq(
    mooncode_json_string(result, "message", default=""),
    "shell timed out after 20ms",
  )
  let output = mooncode_json_string(result, "output", default="")
  assert_true(output.contains("partial-output"))
  assert_true(output.contains("cleanup-ran"))
}

///|
async test "mooncode native shell rejects explicit paths outside book root" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-shell-boundary-XXXXXX"),
  )
  for
    cmd in [
      "sed -n '1,20p' /Users/example/.moon/lib/core/json.mbt", "find ../outside -type f",
      "cat $HOME/.config/example",
    ] {
    let execution = mooncode_execute_tool_call(
      "session-shell-boundary",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-shell-boundary",
        "book_root": book_root,
        "tool": "shell",
        "command_id": "cmd-shell-boundary",
        "arguments": { "cmd": cmd, "timeout_ms": 5000 },
      },
      now=@clock.Timestamp::from_ms(45L),
    )
    let result = mooncode_json_object_field_or_empty(execution, "result")
    assert_true(mooncode_json_bool(result, "is_error", default=false))
    assert_true(
      mooncode_json_string(result, "message", default="").contains(
        "outside the selected MoonBook",
      ),
    )
  }
}

///|
async test "mooncode native shell allows read-only inline interpreter inspection" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-shell-inline-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-shell-inline",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-shell-inline",
      "book_root": book_root,
      "tool": "shell",
      "command_id": "cmd-shell-inline",
      "arguments": {
        "cmd": "node -e \"console.log(JSON.stringify({answer: 42}))\"",
        "timeout_ms": 5000,
      },
    },
    now=@clock.Timestamp::from_ms(45L),
  )
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(mooncode_json_bool(result, "ok", default=false))
  assert_true(
    mooncode_json_string(result, "output", default="").contains(
      "{\"answer\":42}",
    ),
  )
}

///|
test "MoonCode planner reserves authored mutations for reviewable tools" {
  let messages = mooncode_runtime_turn_model_initial_messages({
    "command": "prompt",
    "text": "Update the workspace",
  })
  let system = mooncode_json_string(messages[0], "content", default="")
  assert_true(system.contains("write/edit/apply_patch"))
  assert_true(
    system.contains(
      "Never use shell, an interpreter, or an inline script to author workspace files",
    ),
  )
  assert_true(
    system.contains(
      "all authored mutations must use edit, write, or apply_patch",
    ),
  )
}

///|
async test "mooncode rejects legacy and JSON-shaped MoonBit manifests" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-manifest-XXXXXX"),
  )
  async fn write(path : String, content : String) -> Json {
    mooncode_execute_tool_call(
      "session-manifest",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-manifest",
        "book_root": book_root,
        "tool": "write",
        "command_id": "cmd-manifest",
        "arguments": { "path": path, "content": content },
      },
      now=@clock.Timestamp::from_ms(46L),
    )
  }
  for
    item in [
      ("tools/demo/moon.mod.json", "{}"),
      ("tools/demo/moon.pkg.json", "{}"),
      ("tools/demo/moon.mod", "{}"),
      ("tools/demo/moon.pkg", "[]"),
      ("tools/demo/moon.mod", "deps = { \"moonbitlang/x\": \"*\" }"),
      ("tools/demo/moon.mod", "import = [\"moonbitlang/x\"]"),
      ("tools/demo/moon.mod", "moonbitlang/x = \"0.4.46\""),
      ("tools/demo/moon.mod", "supported_targets = [\"native\"]"),
    ] {
    let (path, content) = item
    let result = mooncode_json_object_field_or_empty(
      write(path, content),
      "result",
    )
    assert_true(mooncode_json_bool(result, "is_error", default=false))
    assert_false(@fsx.exists(@pathx.join(book_root, path)))
  }
  let accepted = mooncode_json_object_field_or_empty(
    write("tools/demo/moon.mod", "name = \"example/demo\"\n"),
    "result",
  )
  assert_true(mooncode_json_bool(accepted, "ok", default=false))
}

///|
async test "mooncode moon_check records reusable watcher state" (t : @test.Test) {
  ignore(t)
  let suite_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-check-watch-suite-XXXXXX"),
  )
  let book_root = suite_root |> @pathx.join("books/research-demo")
  @fsx.make_directory(book_root, recursive=true, exists_ok=true)
  mooncode_prepare_eval_fixture(book_root)
  let first = mooncode_execute_tool_call(
    "session-check-watch",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-check-watch",
      "book_root": book_root,
      "tool": "moon_check",
      "command_id": "cmd-check-start",
      "arguments": { "timeout_ms": 30000 },
    },
    now=@clock.Timestamp::from_ms(61L),
  )
  let first_result = mooncode_json_object_field_or_empty(first, "result")
  assert_true(mooncode_json_bool(first_result, "ok", default=false))
  let first_metadata = mooncode_json_object_field_or_empty(
    first_result, "metadata",
  )
  assert_eq(
    mooncode_json_string(first_metadata, "watcher", default=""),
    "started",
  )
  assert_eq(
    mooncode_json_string(first_metadata, "status", default=""),
    "running",
  )
  assert_eq(mooncode_json_int(first_metadata, "seq", default=0), 1)
  let state_path = mooncode_moon_check_state_path(book_root)
  assert_eq(
    state_path,
    suite_root
    |> @pathx.join(
      ".moonsuite/products/moonclaw/mooncode/watchers/moon-check.json",
    ),
  )
  assert_true(@fsx.exists(state_path))
  assert_false(state_path.contains("/books/research-demo/.moonsuite"))
  let second = mooncode_execute_tool_call(
    "session-check-watch",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-check-watch",
      "book_root": book_root,
      "tool": "moon_check",
      "command_id": "cmd-check-reuse",
      "arguments": { "timeout_ms": 30000 },
    },
    now=@clock.Timestamp::from_ms(62L),
  )
  let second_metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(second, "result"),
    "metadata",
  )
  assert_eq(
    mooncode_json_string(second_metadata, "watcher", default=""),
    "reused",
  )
  assert_eq(mooncode_json_int(second_metadata, "seq", default=0), 2)
  let third = mooncode_execute_tool_call(
    "session-check-watch",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-check-watch",
      "book_root": book_root,
      "tool": "moon_check",
      "command_id": "cmd-check-replace",
      "arguments": { "target": "native", "timeout_ms": 30000 },
    },
    now=@clock.Timestamp::from_ms(63L),
  )
  let third_metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(third, "result"),
    "metadata",
  )
  assert_eq(
    mooncode_json_string(third_metadata, "watcher", default=""),
    "replaced",
  )
  assert_eq(mooncode_json_int(third_metadata, "restart_count", default=0), 1)
  assert_eq(mooncode_json_int(third_metadata, "seq", default=0), 3)
}

///|
test "mooncode moon_ide qualifies line-column locations with path" {
  let book_root = "/tmp/mooncode-loc-book"
  assert_eq(
    mooncode_moon_ide_loc(
      { "path": "cmd/daemon/mooncode_runtime_turn.mbt", "loc": "1031:4" },
      book_root,
      book_root,
    ),
    "cmd/daemon/mooncode_runtime_turn.mbt:1031:4",
  )
  assert_eq(
    mooncode_moon_ide_loc(
      {
        "path": "cmd/daemon/mooncode_runtime_turn.mbt",
        "loc": "cmd/daemon/mooncode_runtime_turn.mbt:1031:4",
      },
      book_root,
      book_root,
    ),
    "cmd/daemon/mooncode_runtime_turn.mbt:1031:4",
  )
  assert_eq(
    mooncode_moon_ide_loc({ "loc": "1031:4" }, book_root, book_root),
    "1031:4",
  )
}

///|
async test "mooncode executes moon_ide and moon_cmd tools in book root" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-moon-tools-XXXXXX"),
  )
  mooncode_prepare_eval_fixture(book_root)
  let ide_execution = mooncode_execute_tool_call(
    "session-moon-tools",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-moon-tools",
      "book_root": book_root,
      "tool": "moon_ide",
      "command_id": "cmd-moon-ide",
      "arguments": {
        "action": "outline",
        "path": ".",
        "target": "all",
        "timeout_ms": 30000,
      },
    },
    now=@clock.Timestamp::from_ms(71L),
  )
  assert_true(mooncode_json_bool(ide_execution, "accepted", default=false))
  let ide_result = mooncode_json_object_field_or_empty(ide_execution, "result")
  assert_true(mooncode_json_bool(ide_result, "ok", default=false))
  assert_true(
    mooncode_json_string(ide_result, "output", default="").contains("answer"),
  )
  let ide_metadata = mooncode_json_object_field_or_empty(ide_result, "metadata")
  assert_eq(
    mooncode_json_string(ide_metadata, "command", default=""),
    "moon ide outline .",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(ide_execution, "event"),
      "kind",
      default="",
    ),
    "moon_ide.finished",
  )
  let cmd_execution = mooncode_execute_tool_call(
    "session-moon-tools",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-moon-tools",
      "book_root": book_root,
      "tool": "moon_cmd",
      "command_id": "cmd-moon-cmd",
      "arguments": {
        "command": "check",
        "target": "native",
        "timeout_ms": 30000,
      },
    },
    now=@clock.Timestamp::from_ms(72L),
  )
  assert_true(mooncode_json_bool(cmd_execution, "accepted", default=false))
  let cmd_result = mooncode_json_object_field_or_empty(cmd_execution, "result")
  assert_true(mooncode_json_bool(cmd_result, "ok", default=false))
  let cmd_metadata = mooncode_json_object_field_or_empty(cmd_result, "metadata")
  assert_eq(
    mooncode_json_string(cmd_metadata, "command", default=""),
    "moon check --target native",
  )
  assert_eq(mooncode_json_int(cmd_metadata, "status", default=-1), 0)
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(cmd_execution, "event"),
      "lane",
      default="",
    ),
    "test",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(cmd_execution, "event"),
      "kind",
      default="",
    ),
    "moon_cmd.finished",
  )
}

///|
test "mooncode moon_cmd supports explicit negative-path exit expectations" {
  assert_true(mooncode_moon_cmd_exit_expected({}, 0))
  assert_false(mooncode_moon_cmd_exit_expected({}, 1))
  assert_true(mooncode_moon_cmd_exit_expected({ "expected_exit_code": 1 }, 1))
  assert_false(mooncode_moon_cmd_exit_expected({ "expected_exit_code": 1 }, 0))
}

///|
test "mooncode normalizes command-specific moon arguments" {
  assert_true(
    mooncode_moon_fmt_has_malformed_selector(["--package", "--check"]),
  )
  assert_false(
    mooncode_moon_fmt_has_malformed_selector([
      "--package", "example/demo/src", "--check",
    ]),
  )
  assert_true(
    mooncode_moon_cmd_is_test_update({ "command": "test", "arg": "-u" }),
  )
  assert_true(
    mooncode_moon_cmd_is_test_update({ "command": "test", "args": ["-u"] }),
  )
  assert_true(
    mooncode_moon_cmd_args(
      {
        "command": "fmt",
        "target": "native",
        "args": ["--package", "example/demo/src", "--target=native", "--check"],
        "path": "tools/demo/src",
      },
      "fmt",
      selector_root="/book",
      cwd_path="/book/tools/demo",
    ) ==
    ["fmt", "--check", "src"],
  )
  assert_true(
    mooncode_moon_cmd_args(
      {
        "command": "check",
        "target": "native",
        "args": ["--warn-list", "+73"],
        "path": "tools/demo/src",
      },
      "check",
      selector_root="/book",
      cwd_path="/book/tools/demo",
    ) ==
    ["check", "--target", "native", "--warn-list", "+73", "src"],
  )
  assert_true(
    mooncode_moon_cmd_args(
      {
        "command": "test",
        "target": "native",
        "args": ["--package", "example/demo/src"],
      },
      "test",
      selector_root="/book",
      cwd_path="/book/tools/demo",
    ) ==
    ["test", "--target", "native", "--package", "example/demo/src"],
  )
  assert_true(
    mooncode_moon_cmd_args(
      { "command": "info", "target": "all", "path": "tools/demo/src/main.mbt" },
      "info",
      selector_root="/book",
      cwd_path="/book/tools/demo",
    ) ==
    ["info", "--target", "all", "src/main.mbt"],
  )
  assert_true(
    mooncode_moon_cmd_args(
      { "command": "check", "path": "src" },
      "check",
      selector_root="/book/tools/demo",
      cwd_path="/book/tools/demo",
    ) ==
    ["check", "src"],
  )
  let fallback = mooncode_runtime_turn_moon_cmd_arguments({
    "command": "run_tests",
    "payload": { "moon_cmd_command": "test", "moon_cmd_target": "native" },
  })
  assert_eq(mooncode_json_string(fallback, "target", default=""), "native")
  assert_eq(
    mooncode_json_string(fallback, "path", default="missing"),
    "missing",
  )
}

///|
async test "mooncode validates moon_ide and moon_cmd arguments before process spawn" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-tool-validation-XXXXXX"),
  )
  let nested_module = @pathx.join(book_root, "tools/demo")
  @fsx.make_directory(
    @pathx.join(nested_module, "src"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(nested_module, "moon.mod"),
    "name = \"example/demo\"\n",
  )
  @fsx.write_to_file(@pathx.join(nested_module, "src/moon.pkg"), "")
  @fsx.write_to_file(
    @pathx.join(nested_module, "src/main.mbt"),
    "///|\npub fn nested_answer()->Int{42}\n",
  )
  @fsx.write_to_file(
    @pathx.join(nested_module, "src/main_wbtest.mbt"),
    "///|\ntest \"nested answer\" {\n  assert_eq(nested_answer(), 42)\n}\n",
  )
  let inferred = mooncode_moon_ide_cwd(book_root, {
    "path": "tools/demo/src/main.mbt",
  })
  assert_eq(
    mooncode_json_string(inferred, "relative_path", default=""),
    "tools/demo",
  )
  let nested_outline = mooncode_execute_tool_call(
    "session-tool-validation",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-tool-validation",
      "book_root": book_root,
      "tool": "moon_ide",
      "command_id": "cmd-nested-outline",
      "arguments": {
        "action": "outline",
        "path": "tools/demo/src/main.mbt",
        "target": "native",
      },
    },
    now=@clock.Timestamp::from_ms(72L),
  )
  let nested_result = mooncode_json_object_field_or_empty(
    nested_outline, "result",
  )
  assert_true(mooncode_json_bool(nested_result, "ok", default=false))
  assert_true(
    mooncode_json_string(nested_result, "output", default="").contains(
      "nested_answer",
    ),
  )
  let nested_metadata = mooncode_json_object_field_or_empty(
    nested_result, "metadata",
  )
  assert_eq(
    mooncode_json_string(nested_metadata, "cwd", default=""),
    "tools/demo",
  )
  assert_eq(
    mooncode_json_string(nested_metadata, "command", default=""),
    "moon ide outline --target native src/main.mbt",
  )
  assert_true(mooncode_moon_check_args("") == ["check"])
  assert_true(
    mooncode_moon_check_args("native") == ["check", "--target", "native"],
  )
  let missing_ide_input = mooncode_execute_tool_call(
    "session-tool-validation",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-tool-validation",
      "book_root": book_root,
      "tool": "moon_ide",
      "command_id": "cmd-bad-ide",
      "arguments": { "action": "hover", "query": "answer" },
    },
    now=@clock.Timestamp::from_ms(73L),
  )
  assert_false(mooncode_json_bool(missing_ide_input, "accepted", default=true))
  let ide_result = mooncode_json_object_field_or_empty(
    missing_ide_input, "result",
  )
  assert_false(mooncode_json_bool(ide_result, "ok", default=true))
  assert_eq(
    mooncode_json_string(ide_result, "message", default=""),
    "moon_ide hover requires loc",
  )
  let invalid_target = mooncode_execute_tool_call(
    "session-tool-validation",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-tool-validation",
      "book_root": book_root,
      "tool": "moon_ide",
      "command_id": "cmd-bad-target",
      "arguments": { "action": "outline", "path": ".", "target": "python" },
    },
    now=@clock.Timestamp::from_ms(74L),
  )
  let target_result = mooncode_json_object_field_or_empty(
    invalid_target, "result",
  )
  assert_false(mooncode_json_bool(target_result, "ok", default=true))
  assert_eq(
    mooncode_json_string(target_result, "message", default=""),
    "unsupported moon_ide target: python",
  )
  let nested_commands : Array[(String, Json, String)] = [
    (
      "check",
      { "command": "check", "target": "native", "path": "tools/demo/src" },
      "moon check --target native src",
    ),
    (
      "test",
      { "command": "test", "target": "native", "path": "tools/demo/src" },
      "moon test --target native src",
    ),
    (
      "info",
      { "command": "info", "target": "native", "path": "tools/demo/src" },
      "moon info --target native src",
    ),
    (
      "fmt",
      {
        "command": "fmt",
        "target": "native",
        "args": ["--package", "example/demo/src", "--target", "native"],
        "path": "tools/demo/src",
      },
      "moon fmt src",
    ),
  ]
  for item in nested_commands {
    let (command, arguments, expected_command) = item
    let execution = mooncode_execute_tool_call(
      "session-tool-validation",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-tool-validation",
        "book_root": book_root,
        "tool": "moon_cmd",
        "command_id": "cmd-nested-\{command}",
        "arguments": arguments,
      },
      now=@clock.Timestamp::from_ms(75L),
    )
    let result = mooncode_json_object_field_or_empty(execution, "result")
    assert_true(mooncode_json_bool(result, "ok", default=false))
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    assert_eq(mooncode_json_string(metadata, "cwd", default=""), "tools/demo")
    assert_eq(
      mooncode_json_string(metadata, "command", default=""),
      expected_command,
    )
  }
  assert_true(
    @fsx.read_file(@pathx.join(nested_module, "src/main.mbt")).contains(
      "pub fn nested_answer() -> Int",
    ),
  )
  let malformed_fmt = mooncode_execute_tool_call(
    "session-tool-validation",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-tool-validation",
      "book_root": book_root,
      "tool": "moon_cmd",
      "command_id": "cmd-malformed-fmt",
      "arguments": { "command": "fmt", "args": ["--package", "--check"] },
    },
    now=@clock.Timestamp::from_ms(75L),
  )
  let malformed_fmt_result = mooncode_json_object_field_or_empty(
    malformed_fmt, "result",
  )
  assert_false(mooncode_json_bool(malformed_fmt_result, "ok", default=true))
  assert_eq(
    mooncode_json_string(malformed_fmt_result, "message", default=""),
    "moon fmt selector options require a non-option value",
  )
  let sibling_module = @pathx.join(book_root, "tools/other")
  @fsx.make_directory(
    @pathx.join(sibling_module, "src"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(sibling_module, "moon.mod"),
    "name = \"example/other\"\n",
  )
  @fsx.write_to_file(@pathx.join(sibling_module, "src/moon.pkg"), "")
  let mixed_modules = mooncode_execute_tool_call(
    "session-tool-validation",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-tool-validation",
      "book_root": book_root,
      "tool": "moon_cmd",
      "command_id": "cmd-mixed-modules",
      "arguments": {
        "command": "fmt",
        "paths": ["tools/demo/src", "tools/other/src"],
      },
    },
    now=@clock.Timestamp::from_ms(75L),
  )
  let mixed_modules_result = mooncode_json_object_field_or_empty(
    mixed_modules, "result",
  )
  assert_false(mooncode_json_bool(mixed_modules_result, "ok", default=true))
  assert_eq(
    mooncode_json_string(mixed_modules_result, "message", default=""),
    "moon_cmd paths must belong to one Moon module",
  )
  let invalid_program_args = mooncode_execute_tool_call(
    "session-tool-validation",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-tool-validation",
      "book_root": book_root,
      "tool": "moon_cmd",
      "command_id": "cmd-bad-program-args",
      "arguments": { "command": "test", "program_args": ["--bad"] },
    },
    now=@clock.Timestamp::from_ms(76L),
  )
  let cmd_result = mooncode_json_object_field_or_empty(
    invalid_program_args, "result",
  )
  assert_false(mooncode_json_bool(cmd_result, "ok", default=true))
  assert_eq(
    mooncode_json_string(cmd_result, "message", default=""),
    "moon_cmd program_args are only valid for moon run",
  )
}

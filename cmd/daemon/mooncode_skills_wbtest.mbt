///|
async test "mooncode discovers and fully loads arbitrary installed skills" (
  t : @test.Test,
) {
  ignore(t)
  let suite_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-skills-suite-XXXXXX"),
  )
  let book_root = @pathx.join(suite_root, "books/demo")
  @fsx.make_directory(book_root, recursive=true, exists_ok=true)
  @fsx.make_directory(@pathx.join(book_root, ".git"), exists_ok=true)
  let skills_root = @moonsuite.product_artifact_for_workspace_root(
    book_root, "moonclaw", "skills",
  )
  let skill_root = @pathx.join(skills_root, "fixture-review")
  @fsx.make_directory(
    @pathx.join(skill_root, "references"),
    recursive=true,
    exists_ok=true,
  )
  let body =
    #|---
    #|name: fixture-review
    #|description: Review fixture files using the installed fixture procedure.
    #|allowed-tools: moon_ide apply_patch
    #|---
    #|
    #|Read references/checklist.md only when a review is requested.
    #|
  @fsx.write_to_file(@pathx.join(skill_root, "SKILL.md"), body)
  @fsx.write_to_file(
    @pathx.join(skill_root, "references/checklist.md"),
    "fixture checklist",
  )
  let catalog = mooncode_runtime_turn_skill_catalog(book_root)
  let listing = catalog
    .split("<available_skills>\n")
    .nth(1)
    .unwrap()
    .split("\n</available_skills>")
    .head()
    .unwrap()
  guard @json.parse(listing) is Array(entries) else { fail("skill listing") }
  assert_true(entries.contains(Json("fixture-review")))
  let full = mooncode_tool_read_skill(book_root, {})
  guard @json.parse(mooncode_json_string(full, "output", default=""))
    is { "skills": Array(entries), .. } else {
    fail("descriptions")
  }
  assert_true(
    entries.any(entry => {
      entry
      is {
        "id": "fixture-review",
        "name": "fixture-review",
        "description": "Review fixture files using the installed fixture procedure.",
        ..
      }
    }),
  )
  let loaded = mooncode_execute_tool_call(
    "session-skills",
    book_root,
    {
      "tool": "read_skill",
      "command_id": "cmd-load-skill",
      "arguments": { "name": "fixture-review" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(mooncode_json_bool(loaded, "accepted", default=false))
  let result = mooncode_json_object_field_or_empty(loaded, "result")
  assert_eq(mooncode_json_string(result, "output", default=""), body)
  let command : Json = {
    "command": "prompt",
    "task_context": { "available_mcp_integrations": [] },
  }
  let initial = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command),
  )
  assert_false(initial.contains("moon_ide"))
  assert_false(initial.contains("apply_patch"))
  let selected = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command, skill_results=[
      loaded,
    ]),
  )
  assert_true(selected.contains("moon_ide"))
  assert_true(selected.contains("apply_patch"))
  let durable = mooncode_runtime_operation_finished(
    "skill-load",
    { "tool": "read_skill", "arguments": { "name": "fixture-review" } },
    loaded,
    step=0,
    index=0,
  )
  mooncode_append_session_journal(
    book_root,
    "session-skills",
    mooncode_journal_event(),
    mooncode_json_object_field_or_empty(durable, "event"),
  )
  let restored = mooncode_tool_execution_from_event(
    mooncode_journal_entries(
      mooncode_read_session_journal(book_root, "session-skills"),
      mooncode_journal_event(),
    )[0],
  )
  assert_eq(
    selected,
    mooncode_test_model_tool_names(
      mooncode_runtime_turn_model_tools_for_command(command, skill_results=[
        restored,
      ]),
    ),
  )
  let additional = mooncode_execute_tool_call(
    "session-skills",
    book_root,
    { "tool": "read_skill", "arguments": { "name": "mooncode-tools" } },
    now=@clock.Timestamp::from_ms(2L),
  )
  let all = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command, skill_results=[
      additional,
    ]),
  )
  for
    name in ["view_image", "moon_ide", "moon_cmd", "apply_patch", "checkpoint"] {
    assert_true(all.contains(name))
  }
  assert_false(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(result, "metadata"),
      "truncated",
      default=true,
    ),
  )
  let reference = mooncode_execute_tool_call(
    "session-skills",
    book_root,
    {
      "tool": "read_skill",
      "command_id": "cmd-load-reference",
      "arguments": {
        "name": "fixture-review",
        "path": "references/checklist.md",
      },
    },
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(reference, "result"),
      "output",
      default="",
    ),
    "fixture checklist",
  )
  let escaped = mooncode_execute_tool_call(
    "session-skills",
    book_root,
    {
      "tool": "read_skill",
      "command_id": "cmd-escape-skill",
      "arguments": { "name": "fixture-review", "path": "../outside.md" },
    },
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_false(mooncode_json_bool(escaped, "accepted", default=true))
}

///|
async test "mooncode retains one full skill through repeated context compilation" {
  let body = "# Instructions\nUse the exact source and [reference](references/a.md).\n"
  let front = "---\nname: example\ndescription: routing only\nlicense: Apache-2.0\nallowed-tools: read\n---\n"
  let full = front + body
  assert_eq(mooncode_skill_instruction_text(full, "SKILL.md"), body)
  assert_eq(mooncode_skill_instruction_text(full, "references/a.md"), full)
  let custom = front.replace(
      old="license:",
      new="compatibility: Preserve this constraint\nlicense:",
    ) +
    body
  assert_eq(mooncode_skill_instruction_text(custom, "SKILL.md"), custom)
  assert_eq(
    mooncode_skill_instruction_text(
      full.split("\n").collect().join("\r\n"),
      "SKILL.md",
    ),
    body.split("\n").collect().join("\r\n"),
  )
  let long_body = "a".repeat(6000)
  let execution : Json = {
    "accepted": true,
    "tool": "read_skill",
    "result": {
      "output": long_body,
      "metadata": {
        "name": "fixture-review",
        "path": "SKILL.md",
        "location": "/installed/fixture-review/SKILL.md",
        "content_sha256_base64": "fixture-digest",
        "content_chars": 6000,
      },
    },
  }
  let content = mooncode_runtime_turn_model_tool_result_content(execution)
  assert_eq(
    mooncode_json_object_field_or_empty(@json.parse(content), "metadata"),
    { "location": "/installed/fixture-review/SKILL.md" },
  )
  assert_false(content.contains(long_body))
  assert_false(content.contains("truncated for planner context"))
  let retained = mooncode_runtime_turn_loaded_skill_messages([execution])
  assert_eq(retained.length(), 1)
  assert_true(
    mooncode_json_string(retained[0], "content", default="").contains(long_body),
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "result"),
      "output",
      default="",
    ),
    long_body,
  )
  let command : Json = {
    "command": "prompt",
    "text": "complete the original task",
  }
  let projected = mooncode_runtime_turn_model_followup_base_messages(
    command,
    { "model_messages": Json(context_test_messages()) },
    [],
    all_tool_results=[execution],
  )
  let first = mooncode_runtime_turn_compile_context(
    command,
    projected,
    [],
    2000,
    128,
  )
  assert_true(mooncode_json_bool(first.metrics, "applied", default=false))
  let resumed = mooncode_runtime_turn_model_followup_base_messages(
    command,
    { "model_messages": Json(first.messages) },
    [],
    all_tool_results=[execution],
  )
  let second = mooncode_runtime_turn_compile_context(
    command,
    resumed,
    [],
    2000,
    128,
  )
  for messages in [first.messages, second.messages] {
    let visible = Json(mooncode_runtime_context_visible_messages(messages)).stringify()
    assert_eq(visible.split(long_body).count(), 2)
    assert_false(visible.contains("Loaded-skill receipt:"))
  }
}

///|
test "skill catalog classifies source and MoonClaw authority" {
  let book_skill = mooncode_skill_catalog_row(
    "review", "Review a MoonBook change", "/tmp/book/skills/review/SKILL.md", "/tmp/book",
  )
  assert_eq(mooncode_json_string(book_skill, "source", default=""), "moonbook")
  assert_eq(
    mooncode_json_string(book_skill, "authority", default=""),
    "moonclaw",
  )
  assert_eq(
    mooncode_json_string(book_skill, "description", default=""),
    "Review a MoonBook change",
  )
  let installed = mooncode_skill_catalog_row(
    "moonbit-agent-guide", "MoonBit guide", "/home/user/.codex/skills/moonbit-agent-guide/SKILL.md",
    "/tmp/book",
  )
  assert_eq(mooncode_json_string(installed, "source", default=""), "installed")
}

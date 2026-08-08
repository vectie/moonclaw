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
  assert_true(catalog.contains("<name>fixture-review</name>"))
  assert_true(catalog.contains("must call `read_skill`"))
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
test "mooncode retains full loaded skill instructions across checkpoints" {
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
  assert_true(content.length() > 6000)
  assert_false(content.contains("truncated for planner context"))
  let retained = mooncode_runtime_turn_loaded_skill_messages([execution])
  assert_eq(retained.length(), 1)
  assert_true(
    mooncode_json_string(retained[0], "content", default="").contains(long_body),
  )
  let receipts = mooncode_runtime_turn_loaded_skill_receipt_messages([execution])
  assert_eq(receipts.length(), 1)
  let receipt = mooncode_json_string(receipts[0], "content", default="")
  assert_true(receipt.contains("loaded completely earlier"))
  assert_true(receipt.contains("fixture-review/SKILL.md"))
  assert_true(receipt.contains("fixture-digest"))
  assert_true(receipt.contains("A missing or empty filesystem result"))
  assert_true(receipt.contains("Do not select read, shell, glob, grep"))
  assert_false(receipt.contains(long_body))
}

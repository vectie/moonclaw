///|
test "mooncode planner exposes glob/grep always and gates web_search/web_fetch by command toggle" {
  let with_web : Json = { "command": "prompt", "web_search": true }
  let names_with_web = mooncode_runtime_turn_model_tools_for_command(with_web).map(tool => {
      mooncode_json_string(
        mooncode_json_object_field_or_empty(tool.to_json(), "function"),
        "name",
        default="",
      )
    },
  )
  assert_true(names_with_web.contains("glob"))
  assert_true(names_with_web.contains("grep"))
  assert_true(names_with_web.contains("web_search"))
  assert_true(names_with_web.contains("web_fetch"))

  let without_web : Json = { "command": "prompt", "web_search": false }
  let names_without_web = mooncode_runtime_turn_model_tools_for_command(
    without_web,
  ).map(tool => {
    mooncode_json_string(
      mooncode_json_object_field_or_empty(tool.to_json(), "function"),
      "name",
      default="",
    )
  })
  assert_true(names_without_web.contains("glob"))
  assert_true(names_without_web.contains("grep"))
  assert_false(names_without_web.contains("web_search"))
  assert_false(names_without_web.contains("web_fetch"))
}

///|
test "mooncode conversation projection accumulates live reasoning and emits search tool evidence" {
  let commands : Array[Json] = [
    {
      "command_id": "cmd-live-1",
      "created_at": "2026-11-25T10:00:00Z",
      "command": {
        "command": "prompt",
        "text": "Search for main entry",
        "client_turn_id": "turn-live-1",
      },
    },
  ]
  let events : Array[Json] = [
    {
      "id": "evt-r1",
      "command_id": "cmd-live-1",
      "lane": "runtime",
      "kind": "reasoning_delta",
      "event": "reasoning_delta",
      "content": "Let me locate ",
      "live_reasoning": true,
      "created_at": "2026-11-25T10:00:01Z",
    },
    {
      "id": "evt-r2",
      "command_id": "cmd-live-1",
      "lane": "runtime",
      "kind": "reasoning_delta",
      "event": "reasoning_delta",
      "content": "the main files first.",
      "live_reasoning": true,
      "created_at": "2026-11-25T10:00:02Z",
    },
    {
      "id": "evt-glob",
      "command_id": "cmd-live-1",
      "lane": "tool",
      "kind": "tool_result",
      "event": "tool_result",
      "tool": "glob",
      "status": "done",
      "tool_call_id": "call-glob-1",
      "tool_result": {
        "ok": true,
        "output": "src/main.mbt",
        "metadata": { "pattern": "**/*.mbt", "path": "**/*.mbt" },
      },
      "created_at": "2026-11-25T10:00:03Z",
    },
  ]
  let conversation = mooncode_session_conversation(
    { "session_id": "sess-live-1" },
    commands,
    [],
    events,
    journal_sequence=MoonCodeJournalSequence::zero(),
  )
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(turns.length(), 1)
  let work = mooncode_json_object_field_or_empty(turns[0], "work")
  assert_eq(
    mooncode_json_string(work, "reasoning", default=""),
    "Let me locate the main files first.",
  )
  let steps = mooncode_json_array_items(work, "steps")
  assert_eq(steps.length(), 1)
  assert_eq(mooncode_json_string(steps[0], "title", default=""), "Found files")
  let evidence = mooncode_json_object_field_or_empty(steps[0], "evidence")
  assert_eq(mooncode_json_string(evidence, "kind", default=""), "tool")
  assert_eq(mooncode_json_string(evidence, "tool", default=""), "glob")
  assert_eq(mooncode_json_string(evidence, "path", default=""), "**/*.mbt")
  assert_eq(
    mooncode_json_string(evidence, "output", default=""),
    "src/main.mbt",
  )
}

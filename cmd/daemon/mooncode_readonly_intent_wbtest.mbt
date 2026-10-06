///|
fn readonly_intent_command(request : String, intent? : String = "") -> Json {
  {
    "command": "prompt",
    "text": request,
    "packet": { "command_id": "readonly-intent" },
    "payload": { "task_intent": intent },
  }
}

///|
fn readonly_intent_results() -> Array[Json] {
  let results : Array[Json] = []
  for index in 0..<13 {
    results.push({
      "tool": "read",
      "accepted": true,
      "arguments": { "path": "src/file-" + index.to_string() + ".mbt" },
      "result": { "ok": true, "output": "source evidence" },
    })
  }
  results.push({
    "tool": "finish",
    "accepted": true,
    "result": { "ok": true, "output": "Review findings with source references" },
  })
  results
}

///|
test "read-only natural requests permit discovery and a model finish without mutation" {
  for
    request in [
      "Review this code; do not edit or fix any files", "Audit only; do not fix the code",
      "Inspect the code; no edits", "Review this code; don't modify code", "Review this code; do not modify code",
      "Audit this code", "Audit the implementation", "Review `src/parser.mbt`; don't edit or fix files",
      "Audit only. Do not edit, fix, or modify code", "Review this example:\n```\nfix the code\nimplement new code\n```",
      "Review the code; do not edit! Report findings", "Inspect this app", "Do not edit any files",
    ] {
    let command = readonly_intent_command(request)
    assert_false(
      mooncode_runtime_turn_model_needs_coding_tools(
        command,
        request.to_lower().to_string(),
      ),
      msg=request,
    )
    assert_false(
      mooncode_runtime_turn_requires_verification(command),
      msg=request,
    )
    assert_true(
      mooncode_runtime_horizon_required_milestones(command).is_empty(),
      msg=request,
    )
    let results = readonly_intent_results()
    assert_false(
      mooncode_runtime_turn_discovery_saturated(
        command,
        { "tool": "read", "arguments": { "path": "src/next.mbt" } },
        results,
      ),
      msg=request,
    )
    assert_true(
      mooncode_runtime_turn_completion_verdict(
        command,
        results,
        require_horizon=mooncode_runtime_turn_requires_verification(command),
      ).accepted,
      msg=request,
    )
    let names = mooncode_runtime_turn_model_tools_for_command(command).map(tool => {
      mooncode_json_string(
        mooncode_json_object_field_or_empty(tool.to_json(), "function"),
        "name",
        default="",
      )
    })
    assert_true(names.contains("read"), msg=request)
    assert_true(names.contains("moon_ide"), msg=request)
    assert_false(
      mooncode_runtime_turn_recoverable_horizon_finish(
        command,
        { "planner_mode": "model-tool-calls" },
        [{ "tool": "finish" }],
        results,
      ),
      msg=request,
    )
    assert_false(names.contains("shell"), msg=request)
    assert_false(names.contains("write"), msg=request)
    assert_false(names.contains("edit"), msg=request)
  }
}

///|
test "coding and scoped restrictions retain mutation completion requirements" {
  for
    request in [
      "Review this code and fix the bug", "Review this code and modify the parser",
      "Implement the parser and explain it", "Edit `src/parser.mbt` and explain it",
      "Fix `src/parser.mbt`; explain the result", "Modify code and explain the change",
      "Implement the parser; do not merely explain it", "Fix source but do not edit generated files",
      "Do not edit generated files; fix source code", "Fix the code, but do not change generated files",
    ] {
    let command = readonly_intent_command(request)
    assert_true(
      mooncode_runtime_turn_model_needs_coding_tools(
        command,
        request.to_lower().to_string(),
      ),
      msg=request,
    )
    assert_true(
      mooncode_runtime_turn_requires_verification(command),
      msg=request,
    )
    assert_false(
      mooncode_runtime_turn_completion_verdict(
        command,
        readonly_intent_results(),
      ).accepted,
      msg=request,
    )
    assert_true(
      mooncode_runtime_horizon_required_milestones(command).any(item => {
        mooncode_json_string(item, "evidence_kind", default="") == "mutation"
      }),
      msg=request,
    )
  }
}

///|
test "explicit read-only intent permits model completion without a synthetic checkpoint" {
  let command = readonly_intent_command(
    "Review this code; do not edit or fix any files",
    intent="read_only",
  )
  assert_false(mooncode_runtime_turn_requires_verification(command))
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      readonly_intent_results(),
      require_horizon=mooncode_runtime_turn_requires_verification(command),
    ).accepted,
  )
}

///|
test "quoted examples do not choose task purpose and explicit modes retain precedence" {
  for
    request in [
      "Review documentation for `fix code`", "Explain the example \"implement the app\"",
      "Audit the documentation with 'fix the code' as an example",
    ] {
    let command = readonly_intent_command(request)
    assert_false(
      mooncode_runtime_turn_requires_verification(command),
      msg=request,
    )
  }
  for
    request in [
      "Implement the example text \"do not edit or fix any files\"", "Fix the string `audit only; do not fix`",
    ] {
    assert_true(
      mooncode_runtime_turn_requires_verification(
        readonly_intent_command(request),
      ),
      msg=request,
    )
  }
  assert_false(
    mooncode_runtime_turn_requires_verification(
      readonly_intent_command("Implement the parser", intent="read_only"),
    ),
  )
  assert_true(
    mooncode_runtime_turn_requires_verification(
      readonly_intent_command(
        "Review code; do not edit",
        intent="workspace_change",
      ),
    ),
  )
}

///|
test "explicit mutation actions retain their existing verification requirement" {
  for action in ["apply_patch", "revert_patch", "package"] {
    assert_true(
      mooncode_runtime_turn_requires_verification({
        "command": action,
        "text": "Review code",
      }),
    )
  }
}

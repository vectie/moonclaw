///|
fn mooncode_harness_benchmark_case(
  name : String,
  text : String,
  task_intent : String,
) -> Json {
  let baseline : Json = {
    "command": "prompt",
    "text": text,
    "payload": { "task_intent": task_intent },
  }
  let dynamic : Json = {
    "command": "prompt",
    "text": text,
    "payload": {
      "task_intent": task_intent,
      "planner_dynamic_tool_bundles": true,
    },
  }
  let baseline_tools = mooncode_runtime_turn_model_tools_for_command(baseline)
  let dynamic_tools = mooncode_runtime_turn_model_tools_for_command(dynamic)
  let baseline_chars = baseline_tools.to_json().stringify().length()
  let dynamic_chars = dynamic_tools.to_json().stringify().length()
  {
    "case": name,
    "baseline_tool_count": baseline_tools.length(),
    "dynamic_tool_count": dynamic_tools.length(),
    "baseline_tool_schema_chars": baseline_chars,
    "dynamic_tool_schema_chars": dynamic_chars,
    "schema_chars_saved": baseline_chars - dynamic_chars,
    "schema_reduction_basis_points": if baseline_chars == 0 {
      0
    } else {
      (baseline_chars - dynamic_chars) * 10_000 / baseline_chars
    },
  }
}

///|
test "mooncode harness benchmark covers representative tool bundles" {
  let cases = [
    mooncode_harness_benchmark_case(
      "read-only", "Read README.md and summarize it.", "read_only",
    ),
    mooncode_harness_benchmark_case(
      "generic-edit", "Fix the parser and run tests.", "workspace_change",
    ),
    mooncode_harness_benchmark_case(
      "moonbit", "Refactor the MoonBit package and run moon test.", "workspace_change",
    ),
    mooncode_harness_benchmark_case(
      "ui-browser", "Test the web app UI in the browser and fix the interaction.",
      "workspace_change",
    ),
    mooncode_harness_benchmark_case(
      "delegated-workers", "Delegate independent checks to workers and implement the fix.",
      "workspace_change",
    ),
  ]
  for item in cases {
    let baseline = mooncode_json_int(
      item,
      "baseline_tool_schema_chars",
      default=0,
    )
    let dynamic = mooncode_json_int(
      item,
      "dynamic_tool_schema_chars",
      default=0,
    )
    assert_true(baseline > 0)
    assert_true(dynamic > 0)
    assert_true(dynamic <= baseline)
  }
  println(
    (
      {
        "contract": "moonclaw.harness-benchmark.v1",
        "cases": Json::array(cases),
      } : Json).stringify(),
  )
}

///|
fn mooncode_harness_regression_command(
  text : String,
  task_intent : String,
  dynamic : Bool,
) -> Json {
  {
    "command": "prompt",
    "text": text,
    "payload": {
      "task_intent": task_intent,
      "planner_dynamic_tool_bundles": dynamic,
    },
  }
}

///|
fn mooncode_harness_regression_tool_names(command : Json) -> Array[String] {
  mooncode_runtime_turn_model_tools_for_command(command).map(tool => {
    let function = mooncode_json_object_field_or_empty(
      tool.to_json(),
      "function",
    )
    mooncode_json_string(function, "name", default="")
  })
}

///|
fn mooncode_harness_regression_contains_in_order(
  actual : ArrayView[String],
  expected : ArrayView[String],
) -> Bool {
  let mut next = 0
  for name in actual {
    if next < expected.length() && name == expected[next] {
      next += 1
    }
  }
  next == expected.length()
}

///|
fn mooncode_harness_regression_results(
  requires_verification : Bool,
  failure_first : Bool,
) -> Array[Json] {
  let results : Array[Json] = []
  if failure_first {
    results.push({
      "tool": "shell",
      "accepted": false,
      "result": { "ok": false, "message": "transient provider fixture" },
    })
  }
  if requires_verification {
    results.push({
      "tool": "edit",
      "accepted": true,
      "result": {
        "ok": true,
        "metadata": {
          "changed": true,
          "file_path": "src/main.mbt",
          "before_fingerprint": "fixture-before",
          "after_fingerprint": "fixture-after",
        },
      },
    })
    results.push({
      "tool": "moon_cmd",
      "accepted": true,
      "arguments": { "command": "test" },
      "result": { "ok": true },
    })
  } else {
    results.push({
      "tool": "read",
      "accepted": true,
      "result": { "ok": true, "output": "fixture inspection" },
    })
  }
  results.push({ "tool": "finish", "accepted": true, "result": { "ok": true } })
  results
}

///|
fn mooncode_harness_regression_case(
  name : String,
  text : String,
  task_intent : String,
  required_tools : ArrayView[String],
  requires_verification : Bool,
  retry_count : Int,
  tool_call_count : Int,
) -> Json raise {
  let baseline = mooncode_harness_regression_command(text, task_intent, false)
  let dynamic = mooncode_harness_regression_command(text, task_intent, true)
  let baseline_tools = mooncode_runtime_turn_model_tools_for_command(baseline)
  let dynamic_tools = mooncode_runtime_turn_model_tools_for_command(dynamic)
  let baseline_names = mooncode_harness_regression_tool_names(baseline)
  let dynamic_names = mooncode_harness_regression_tool_names(dynamic)
  let repeated_names = mooncode_harness_regression_tool_names(dynamic)
  assert_eq(dynamic_names, repeated_names)
  assert_true(
    mooncode_harness_regression_contains_in_order(dynamic_names, required_tools),
  )
  for required in required_tools {
    assert_true(baseline_names.contains(required))
    assert_true(dynamic_names.contains(required))
  }
  let deferred_search_expected = task_intent == "workspace_change"
  if deferred_search_expected {
    assert_true(dynamic_names.contains("tool_search"))
  }
  assert_eq(
    mooncode_runtime_turn_requires_verification(baseline),
    requires_verification,
  )
  assert_eq(
    mooncode_runtime_turn_requires_verification(dynamic),
    requires_verification,
  )
  let results = mooncode_harness_regression_results(
    requires_verification,
    retry_count > 0,
  )
  let baseline_verdict = mooncode_runtime_turn_completion_verdict(
    baseline, results,
  )
  let dynamic_verdict = mooncode_runtime_turn_completion_verdict(
    dynamic, results,
  )
  assert_true(baseline_verdict.accepted)
  assert_eq(dynamic_verdict.accepted, baseline_verdict.accepted)
  assert_eq(dynamic_verdict.reason, baseline_verdict.reason)
  let messages = mooncode_runtime_turn_model_initial_messages(dynamic)
  let request : Json = {
    "messages": Json::array(messages),
    "tools": Json::array(dynamic_tools.map(tool => tool.to_json())),
  }
  let calls : Array[Json] = if tool_call_count > 0 {
    [{ "id": "fixture-call", "function": { "name": "read" } }]
  } else {
    []
  }
  let metrics = mooncode_runtime_turn_planner_metrics(
    request,
    {
      "usage": {
        "prompt_tokens": 1000,
        "completion_tokens": 120,
        "total_tokens": 1120,
        "prompt_tokens_details": { "cached_tokens": 700 },
      },
    },
    messages,
    calls,
  )
  let observed_metrics = mooncode_json_object_with_field(
    metrics,
    "model_retry_count",
    retry_count.to_json(),
  )
  let latency_fixture_ms = 10 + name.length()
  let exported = mooncode_planner_metrics_export_payload(
    observed_metrics,
    planner_latency_ms=latency_fixture_ms,
  )
  let expected_outcome = if tool_call_count > 0 {
    "selected"
  } else {
    "no_tool_calls"
  }
  assert_eq(
    mooncode_json_string(exported, "contract", default=""),
    "moonclaw.planner.metrics.v1",
  )
  assert_true(
    mooncode_json_int(exported, "configured_request_chars", default=0) > 0,
  )
  assert_true(
    mooncode_json_int(exported, "effective_request_chars", default=0) > 0,
  )
  assert_true(mooncode_json_int(exported, "tool_schema_chars", default=0) > 0)
  assert_eq(mooncode_json_int(exported, "prompt_tokens", default=0), 1000)
  assert_eq(mooncode_json_int(exported, "cache_read_tokens", default=0), 700)
  assert_eq(mooncode_json_int(exported, "fresh_input_tokens", default=0), 300)
  assert_eq(
    mooncode_json_int(exported, "cache_read_ratio_ppm", default=0),
    700000,
  )
  assert_eq(
    mooncode_json_int(exported, "planner_latency_ms", default=-1),
    latency_fixture_ms,
  )
  assert_eq(
    mooncode_json_int(exported, "model_retry_count", default=-1),
    retry_count,
  )
  assert_eq(
    mooncode_json_string(exported, "outcome", default=""),
    expected_outcome,
  )
  let baseline_schema_chars = Json::array(
      baseline_tools.map(tool => tool.to_json()),
    )
    .stringify()
    .length()
  let dynamic_schema_chars = Json::array(
      dynamic_tools.map(tool => tool.to_json()),
    )
    .stringify()
    .length()
  let dynamic_prompt_chars = Json::array(messages).stringify().length()
  assert_true(baseline_schema_chars > 0)
  assert_true(dynamic_schema_chars > 0)
  assert_true(dynamic_prompt_chars > text.length())
  assert_true(dynamic_schema_chars <= baseline_schema_chars)
  {
    "case": name,
    "required_capabilities_available": true,
    "deferred_search_available": !deferred_search_expected ||
    dynamic_names.contains("tool_search"),
    "deterministic_tool_order": true,
    "verification_result_equivalent": true,
    "baseline_tool_schema_chars": baseline_schema_chars,
    "dynamic_tool_schema_chars": dynamic_schema_chars,
    "dynamic_prompt_chars": dynamic_prompt_chars,
    "cache_read_tokens": mooncode_json_int(
      exported,
      "cache_read_tokens",
      default=0,
    ),
    "planner_latency_ms": latency_fixture_ms,
    "model_retry_count": retry_count,
    "outcome": expected_outcome,
  }
}

///|
test "mooncode harness regression gates representative production cohorts" {
  let cases = [
    mooncode_harness_regression_case(
      "read-only-inspection",
      "Read README.md and summarize the current architecture.",
      "read_only",
      ["read", "finish", "read_skill"],
      false,
      0,
      1,
    ),
    mooncode_harness_regression_case(
      "generic-edit",
      "Fix the parser and run tests.",
      "workspace_change",
      [
        "read", "write", "edit", "shell", "finish", "apply_patch", "checkpoint",
        "read_skill",
      ],
      true,
      0,
      1,
    ),
    mooncode_harness_regression_case(
      "moonbit-validation",
      "Refactor the MoonBit package and run moon test.",
      "workspace_change",
      [
        "read", "write", "edit", "shell", "moon_ide", "moon_cmd", "moon_check", "finish",
        "apply_patch", "checkpoint", "read_skill",
      ],
      true,
      0,
      1,
    ),
    mooncode_harness_regression_case(
      "ui-browser",
      "Test the web app UI in the browser, inspect a screenshot, and fix the interaction.",
      "workspace_change",
      [
        "read", "view_image", "write", "edit", "shell", "browser", "finish", "apply_patch",
        "checkpoint", "read_skill",
      ],
      true,
      0,
      1,
    ),
    mooncode_harness_regression_case(
      "delegated-workers",
      "Delegate independent checks to workers and implement the fix.",
      "workspace_change",
      [
        "read", "write", "edit", "shell", "finish", "apply_patch", "checkpoint",
        "read_skill", "spawn_workers", "wait_workers",
      ],
      true,
      0,
      1,
    ),
    mooncode_harness_regression_case(
      "long-context-follow-up",
      "Continue the long-running implementation, retain the original requirements, and run tests.",
      "workspace_change",
      [
        "read", "write", "edit", "shell", "finish", "apply_patch", "checkpoint",
        "read_skill",
      ],
      true,
      0,
      1,
    ),
    mooncode_harness_regression_case(
      "failure-retry",
      "Fix the parser after a transient model failure and run tests.",
      "workspace_change",
      [
        "read", "write", "edit", "shell", "finish", "apply_patch", "checkpoint",
        "read_skill",
      ],
      true,
      2,
      0,
    ),
  ]
  assert_eq(cases.length(), 7)
  println(
    (
      {
        "contract": "moonclaw.harness-regression.v1",
        "gate_order": [
          "task_success", "verifier_success", "safety_recovery", "tokens_cache_bytes",
          "latency",
        ],
        "cases": Json::array(cases),
      } : Json).stringify(),
  )
}

///|
test "mooncode long-context benchmark retains task and latest verification evidence" {
  let original_task = "Implement the complete harness; preserve user work; run the focused verifier."
  let messages : Array[Json] = [
    { "role": "system", "content": "planner contract" },
    { "role": "user", "content": original_task },
  ]
  for index in 0..<32 {
    messages.push({
      "role": "assistant",
      "content": if index == 0 {
        "obsolete discovery"
      } else {
        "bounded planner step \{index}"
      },
      "tool_calls": [
        {
          "id": "harness-call-\{index}",
          "type": "function",
          "function": { "name": "read", "arguments": "{}" },
        },
      ],
    })
    messages.push({
      "role": "tool",
      "tool_call_id": "harness-call-\{index}",
      "content": if index == 31 {
        "latest focused verifier passed"
      } else {
        "inspection \{index}"
      },
    })
  }
  let compacted = mooncode_runtime_turn_compact_followup_transcript(
    messages,
    task_contract=original_task,
  )
  let repeated = mooncode_runtime_turn_compact_followup_transcript(
    messages,
    task_contract=original_task,
  )
  assert_eq(compacted, repeated)
  let before_chars = Json::array(messages).stringify().length()
  let after_text = Json::array(compacted).stringify()
  assert_true(after_text.length() < before_chars)
  assert_true(after_text.contains(original_task))
  assert_true(after_text.contains("latest focused verifier passed"))
  assert_false(after_text.contains("obsolete discovery"))
}

///|
test "planner metrics export is explicit opt in" {
  for enabled in ["1", "true", "TRUE", " yes ", "on"] {
    assert_true(
      mooncode_planner_metrics_export_enabled_from_value(Some(enabled)),
    )
  }
  for disabled in ["", "0", "false", "off", "enabled"] {
    assert_false(
      mooncode_planner_metrics_export_enabled_from_value(Some(disabled)),
    )
  }
  assert_false(mooncode_planner_metrics_export_enabled_from_value(None))
}

///|
test "planner metrics export payload is privacy bounded" {
  let payload = mooncode_planner_metrics_export_payload(
    {
      "contract": "moonclaw.planner.metrics.v1",
      "prompt_tokens": 100,
      "cache_read_tokens": 70,
      "model_retry_count": 2,
      "request_compacted": true,
      "tool_call_count": 1,
      "selected_tool_names": ["read", "shell"],
      "session_id": "private-session",
      "prompt": "private prompt",
      "tool_arguments": { "command": "private command" },
    },
    planner_latency_ms=25,
  )
  assert_eq(
    mooncode_json_string(payload, "contract", default=""),
    "moonclaw.planner.metrics.v1",
  )
  assert_eq(mooncode_json_int(payload, "prompt_tokens", default=0), 100)
  assert_eq(mooncode_json_int(payload, "planner_latency_ms", default=0), 25)
  assert_eq(mooncode_json_int(payload, "model_retry_count", default=0), 2)
  assert_eq(mooncode_json_string(payload, "outcome", default=""), "selected")
  assert_true(mooncode_json_bool(payload, "request_compacted", default=false))
  assert_false(payload.stringify().contains("private"))
  assert_false(payload.stringify().contains("shell"))
  assert_false(payload.stringify().contains("selected_tool_names"))
}

///|
test "planner metrics outcome cannot create arbitrary cardinality" {
  let payload = mooncode_planner_metrics_export_payload({
    "contract": "moonclaw.planner.metrics.v1",
    "outcome": "session-owned-value",
  })
  assert_eq(mooncode_json_string(payload, "outcome", default=""), "unknown")
  assert_false(payload.stringify().contains("session-owned-value"))
}

///|
async test "planner metrics export drops disabled and undiscoverable observations" {
  @fsx.with_temporary_directory("moonclaw-planner-export-XXXXXX", root => {
    let metrics : Json = { "contract": "moonclaw.planner.metrics.v1" }
    assert_false(
      mooncode_export_planner_metrics_if_enabled(false, root, metrics),
    )
    assert_false(
      mooncode_export_planner_metrics_if_enabled(true, root, metrics),
    )
  })
}

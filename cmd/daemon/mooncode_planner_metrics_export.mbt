///|
const MOONCODE_PLANNER_METRICS_EXPORT_ENV : String = "MOONCLAW_PLANNER_METRICS_EXPORT"

///|
const MOONCODE_PLANNER_METRICS_EXPORT_TIMEOUT_MS : Int = 300

///|
fn mooncode_planner_metrics_export_enabled_from_value(value : String?) -> Bool {
  match value {
    Some(raw) => {
      let normalized = raw.trim().to_lower()
      normalized == "1" ||
      normalized == "true" ||
      normalized == "yes" ||
      normalized == "on"
    }
    None => false
  }
}

///|
fn mooncode_planner_metrics_export_enabled() -> Bool {
  mooncode_planner_metrics_export_enabled_from_value(
    @os.getenv(MOONCODE_PLANNER_METRICS_EXPORT_ENV) catch {
      _ => None
    },
  )
}

///|
/// Keep the transport payload deliberately narrower than the session record.
/// In particular, selected tool names, prompts, paths, identifiers, and tool
/// arguments never cross the MoonClaw-to-MoonGate metrics boundary.
fn mooncode_planner_metrics_export_payload(
  metrics : Json,
  planner_latency_ms? : Int = 0,
) -> Json {
  let tool_call_count = mooncode_json_int(metrics, "tool_call_count", default=0).max(
    0,
  )
  let outcome = match
    mooncode_json_string(
      metrics,
      "outcome",
      default=if tool_call_count > 0 { "selected" } else { "no_tool_calls" },
    ) {
    "selected" => "selected"
    "no_tool_calls" => "no_tool_calls"
    _ => "unknown"
  }
  let model_transport = match
    mooncode_json_string(metrics, "model_transport", default="") {
    "responses" => "responses"
    "chat_completions" => "chat_completions"
    "chat_fallback" => "chat_fallback"
    _ => "unknown"
  }
  {
    "contract": mooncode_json_string(metrics, "contract", default=""),
    "configured_request_chars": mooncode_json_int(
      metrics,
      "configured_request_chars",
      default=0,
    ).max(0),
    "effective_request_chars": mooncode_json_int(
      metrics,
      "effective_request_chars",
      default=0,
    ).max(0),
    "request_message_count": mooncode_json_int(
      metrics,
      "request_message_count",
      default=0,
    ).max(0),
    "request_message_chars": mooncode_json_int(
      metrics,
      "request_message_chars",
      default=0,
    ).max(0),
    "system_prompt_chars": mooncode_json_int(
      metrics,
      "system_prompt_chars",
      default=0,
    ).max(0),
    "tool_schema_chars": mooncode_json_int(
      metrics,
      "tool_schema_chars",
      default=0,
    ).max(0),
    "tool_count": mooncode_json_int(metrics, "tool_count", default=0).max(0),
    "tool_call_count": tool_call_count,
    "prompt_tokens": mooncode_json_int(metrics, "prompt_tokens", default=0).max(
      0,
    ),
    "completion_tokens": mooncode_json_int(
      metrics,
      "completion_tokens",
      default=0,
    ).max(0),
    "total_tokens": mooncode_json_int(metrics, "total_tokens", default=0).max(0),
    "cache_read_tokens": mooncode_json_int(
      metrics,
      "cache_read_tokens",
      default=0,
    ).max(0),
    "cache_write_tokens": mooncode_json_int(
      metrics,
      "cache_write_tokens",
      default=0,
    ).max(0),
    "fresh_input_tokens": mooncode_json_int(
      metrics,
      "fresh_input_tokens",
      default=0,
    ).max(0),
    "cache_read_ratio_ppm": mooncode_json_int(
      metrics,
      "cache_read_ratio_ppm",
      default=0,
    ).max(0),
    "planner_latency_ms": planner_latency_ms.max(0),
    "model_retry_count": mooncode_json_int(
      metrics,
      "model_retry_count",
      default=0,
    ).max(0),
    "model_transport": model_transport,
    "request_compacted": mooncode_json_bool(
      metrics,
      "request_compacted",
      default=false,
    ),
    "outcome": outcome,
  }
}

///|
/// Export is opt-in and observational. Discovery, timeout, transport, parse,
/// and rejection failures all become a dropped observation and never alter a
/// planner result or retry a model/tool operation.
async fn mooncode_export_planner_metrics(
  workspace_root : String,
  metrics : Json,
  planner_latency_ms? : Int = 0,
) -> Bool {
  mooncode_export_planner_metrics_if_enabled(
    mooncode_planner_metrics_export_enabled(),
    workspace_root,
    metrics,
    planner_latency_ms~,
  )
}

///|
async fn mooncode_export_planner_metrics_if_enabled(
  enabled : Bool,
  workspace_root : String,
  metrics : Json,
  planner_latency_ms? : Int = 0,
) -> Bool {
  if !enabled {
    return false
  }
  guard @moongate.discover_from_suite_status_for_workspace_root(workspace_root)
    is Some(client) else {
    return false
  }
  let payload = mooncode_planner_metrics_export_payload(
    metrics,
    planner_latency_ms~,
  )
  let posted = @async.with_timeout(MOONCODE_PLANNER_METRICS_EXPORT_TIMEOUT_MS, () => {
    client.record_planner_metrics(payload)
  }) catch {
    _ => return false
  }
  posted is Ok(_)
}

///|
async fn mooncode_export_planner_metrics_for_plan(
  workspace_root : String,
  plan : Json,
  planner_latency_ms : Int,
) -> Bool {
  let metrics = mooncode_json_object_field_or_empty(plan, "planner_metrics")
  if mooncode_json_string(metrics, "contract", default="") !=
    "moonclaw.planner.metrics.v1" {
    return false
  }
  mooncode_export_planner_metrics(workspace_root, metrics, planner_latency_ms~)
}

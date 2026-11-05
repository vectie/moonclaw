///|
/// Record the actual compiled request and provider usage. Missing usage remains
/// unmeasured; these observations never decide execution or completion.
fn mooncode_runtime_turn_planner_metrics(
  request : Json,
  response : Json,
  tool_calls : Array[Json],
  model_transport~ : String = "chat_completions",
  model_retry_count~ : Int32 = 0,
  planner_latency_ms~ : Int32 = 0,
) -> Json {
  let tools = mooncode_json_array_items(request, "tools")
  let usage = mooncode_json_object_field_or_empty(response, "usage")
  let prompt = mooncode_json_int(usage, "prompt_tokens", default=-1)
  let completion = mooncode_json_int(usage, "completion_tokens", default=-1)
  let observed = prompt >= 0 && completion >= 0
  let prompt_details = mooncode_json_object_field_or_empty(
    usage, "prompt_tokens_details",
  )
  {
    "contract": "moonclaw.planner.metrics.v1",
    "usage_observed": observed,
    "model_transport": model_transport,
    "request_chars": request.stringify().length(),
    "request_message_count": mooncode_json_array_items(request, "messages").length(),
    "tool_schema_chars": Json(tools).stringify().length(),
    "tool_count": tools.length(),
    "tool_call_count": tool_calls.length(),
    "prompt_tokens": prompt.max(0),
    "completion_tokens": completion.max(0),
    "cache_read_tokens": mooncode_json_int(
      prompt_details,
      "cached_tokens",
      default=0,
    )
    .max(0)
    .min(prompt.max(0)),
    "cache_write_tokens": mooncode_json_int(
      prompt_details,
      "cache_write_tokens",
      default=0,
    ).max(0),
    "model_retry_count": model_retry_count,
    "planner_latency_ms": planner_latency_ms,
  }
}

///|
/// Attach the observation to the existing final planner event. No extra append,
/// exporter call or task phase is needed, including for an empty model response.
fn mooncode_planner_observed(
  plan : Json,
  metrics : Json,
  observation_id : String,
) -> Json {
  let events = mooncode_json_array_items(plan, "events").copy()
  if !events.is_empty() {
    let last = events.length() - 1
    events[last] = mooncode_json_object_with_field(
      events[last],
      "planner_metrics",
      metrics,
    )
    // Reuse the daemon UUID source; distinct responses can share a timestamp.
    events[last] = mooncode_json_object_with_field(
      events[last],
      "id",
      Json(
        mooncode_json_string(events[last], "id", default="planner") +
        "-" +
        observation_id,
      ),
    )
  }
  mooncode_json_object_with_field(plan, "events", Json(events))
  |> mooncode_json_object_with_field("planner_metrics", metrics)
}

///|
fn mooncode_runtime_turn_message_content_chars(message : Json) -> Int {
  let content = match message {
    Object(object) => object.get("content")
    _ => None
  }
  match content {
    Some(String(text)) => text.length()
    Some(value) => value.stringify().length()
    None => 0
  }
}

///|
fn mooncode_runtime_turn_system_prompt_chars(messages : Array[Json]) -> Int {
  let mut chars = 0
  for message in messages {
    if mooncode_json_string(message, "role", default="") == "system" {
      chars += mooncode_runtime_turn_message_content_chars(message)
    }
  }
  chars
}

///|
fn mooncode_runtime_turn_planner_tool_names(request : Json) -> Array[String] {
  mooncode_json_array_items(request, "tools").filter_map(tool => {
    let function = mooncode_json_object_field_or_empty(tool, "function")
    match mooncode_json_string(function, "name", default="") {
      "" => None
      name => Some(name)
    }
  })
}

///|
fn mooncode_runtime_turn_planner_metrics(
  configured_request : Json,
  response : Json,
  effective_messages : Array[Json],
  tool_calls : Array[Json],
  model_transport? : String = "chat_completions",
) -> Json {
  let configured_messages = mooncode_json_array_items(
    configured_request, "messages",
  )
  let effective_provider_messages = mooncode_runtime_context_visible_messages(
    effective_messages,
  )
  let tools = mooncode_json_array_items(configured_request, "tools")
  let usage = mooncode_json_object_field_or_empty(response, "usage")
  let prompt_details = mooncode_json_object_field_or_empty(
    usage, "prompt_tokens_details",
  )
  let prompt_tokens = mooncode_json_int(usage, "prompt_tokens", default=0).max(
    0,
  )
  let completion_tokens = mooncode_json_int(
    usage,
    "completion_tokens",
    default=0,
  ).max(0)
  let total_tokens = mooncode_json_int(
    usage,
    "total_tokens",
    default=prompt_tokens + completion_tokens,
  ).max(0)
  let cache_read_tokens = mooncode_json_int(
      prompt_details,
      "cached_tokens",
      default=0,
    )
    .max(0)
    .min(prompt_tokens)
  let cache_write_tokens = mooncode_json_int(
    prompt_details,
    "cache_write_tokens",
    default=0,
  ).max(0)
  let fresh_input_tokens = prompt_tokens - cache_read_tokens
  let cache_read_ratio_ppm = if prompt_tokens == 0 {
    0
  } else {
    cache_read_tokens * 1_000_000 / prompt_tokens
  }
  let configured_message_chars = Json::array(configured_messages)
    .stringify()
    .length()
  let effective_message_chars = Json::array(effective_provider_messages)
    .stringify()
    .length()
  let configured_request_chars = configured_request.stringify().length()
  let effective_request_chars = (configured_request_chars -
  configured_message_chars +
  effective_message_chars).max(0)
  let tool_names = mooncode_runtime_turn_planner_tool_names(configured_request)
  {
    "contract": "moonclaw.planner.metrics.v1",
    "model_transport": model_transport,
    "configured_request_chars": configured_request_chars,
    "effective_request_chars": effective_request_chars,
    "request_message_count": effective_provider_messages.length(),
    "request_message_chars": effective_message_chars,
    "system_prompt_chars": mooncode_runtime_turn_system_prompt_chars(
      effective_messages,
    ),
    "tool_schema_chars": Json::array(tools).stringify().length(),
    "tool_count": tools.length(),
    "selected_tool_names": Json::array(tool_names.map(Json::string)),
    "tool_call_count": tool_calls.length(),
    "prompt_tokens": prompt_tokens,
    "completion_tokens": completion_tokens,
    "total_tokens": total_tokens,
    "cache_read_tokens": cache_read_tokens,
    "cache_write_tokens": cache_write_tokens,
    "fresh_input_tokens": fresh_input_tokens,
    "cache_read_ratio_ppm": cache_read_ratio_ppm,
    "request_compacted": effective_message_chars < configured_message_chars,
  }
}

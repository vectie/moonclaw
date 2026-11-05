///|
/// One execution envelope for native tools and synthetic batch results. The
/// canonical result is shared by journal, model and presentation adapters.
fn mooncode_tool_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool : String,
  arguments : Json,
  result : Json,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "accepted": !mooncode_json_bool(result, "is_error", default=false),
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      tool,
      result,
      now~,
    ),
  }
}

///|
/// Adapt the execution envelope or its durable event at their common boundary.
fn mooncode_tool_result_value(execution : Json) -> Json {
  match execution {
    { "result": Object(_) as result, .. } => result
    { "tool_result": Object(_) as result, .. } => result
    _ => Json::object({})
  }
}

///|
/// The committed event owns both the result and its execution header. Recovery
/// and continuation hydration use this same projection, without another copy.
fn mooncode_tool_execution_from_event(event : Json) -> Json {
  mooncode_json_object_field_or_empty(event, "execution")
  |> mooncode_json_object_with_field(
    "result",
    mooncode_tool_result_value(event),
  )
  |> mooncode_json_object_with_field("event", event)
}

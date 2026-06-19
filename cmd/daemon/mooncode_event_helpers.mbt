///|
fn mooncode_task_event_lane(msg : String) -> String {
  match msg {
    "PreConversation" | "PostConversation" => "runtime"
    "AssistantMessage" | "AssistantMessageDelta" => "transcript"
    "PreToolCall" | "PostToolCall" => "tool"
    "ContextPruned" | "Pruned" => "runtime"
    "Cancelled" | "Failed" => "review"
    _ => "runtime"
  }
}

///|
fn mooncode_task_event_kind(msg : String) -> String {
  match msg {
    "PreConversation" => "conversation_started"
    "AssistantMessageDelta" => "assistant_delta"
    "AssistantMessage" => "assistant_message"
    "PreToolCall" => mooncode_event_tool_call()
    "PostToolCall" => mooncode_event_tool_result()
    "PostConversation" => "conversation_finished"
    "ContextPruned" => "context_pruned"
    "Pruned" => "context_event_pruned"
    "Cancelled" => "runtime_aborted"
    "Failed" => "runtime_aborted"
    _ => "runtime.\{msg}"
  }
}

///|
fn mooncode_task_event_title(msg : String) -> String {
  match msg {
    "PreConversation" => "Conversation started"
    "AssistantMessageDelta" => "Assistant streaming"
    "AssistantMessage" => "Assistant message"
    "PreToolCall" => "Tool call started"
    "PostToolCall" => "Tool result"
    "PostConversation" => "Conversation finished"
    "ContextPruned" => "Context pruned"
    "Pruned" => "Context event pruned"
    "Cancelled" => "MoonClaw task cancelled"
    "Failed" => "MoonClaw task failed"
    _ => "MoonClaw runtime event"
  }
}

///|
fn mooncode_task_event_status(msg : String) -> String {
  match msg {
    "PreConversation" | "AssistantMessageDelta" | "PreToolCall" => "running"
    "Cancelled" => "cancelled"
    "Failed" => "failed"
    _ => "done"
  }
}

///|
fn mooncode_task_event_detail(desc : Json) -> String {
  let msg = mooncode_json_string(desc, "msg", default="")
  match msg {
    "PreConversation" => "MoonClaw task conversation started"
    "AssistantMessageDelta" | "AssistantMessage" =>
      mooncode_json_string(desc, "content", default="")
    "PreToolCall" | "PostToolCall" =>
      mooncode_json_string(desc, "name", default="tool")
    "PostConversation" => "MoonClaw task conversation finished"
    "ContextPruned" =>
      "Context pruned from \{mooncode_json_int(desc, "origin_token_count", default=0)} to \{mooncode_json_int(desc, "pruned_token_count", default=0)} tokens"
    "Pruned" => "Pruned event \{mooncode_json_string(desc, "id", default="")}"
    "Failed" => "MoonClaw task failed"
    "Cancelled" => "MoonClaw task was cancelled"
    _ => msg
  }
}

///|
fn mooncode_task_event_rendered_text(desc : Json) -> String {
  mooncode_json_string(desc, "text", default="")
}

///|
fn mooncode_task_event_structured_result(desc : Json) -> Json {
  match desc {
    Object(object) =>
      match object.get("result") {
        Some(value) => value
        None =>
          match object.get("error") {
            Some(value) => value
            None => Json::object({})
          }
      }
    _ => Json::object({})
  }
}

///|
fn mooncode_event(
  session_id~ : String,
  command_id~ : String,
  lane~ : String,
  kind~ : String,
  title~ : String,
  status~ : String,
  detail~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{session_id}-\{command_id}-\{kind}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": lane,
    "kind": kind,
    "title": title,
    "status": status,
    "detail": detail,
    "created_at": now,
    "source": "moonclaw-native-mooncode",
  }
}

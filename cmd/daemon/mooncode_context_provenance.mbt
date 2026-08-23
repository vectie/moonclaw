///|
const MOONCODE_CONTEXT_PROVENANCE_FIELD : String = "_moonclaw_context"

///|
const MOONCODE_CONTEXT_PROVENANCE_CONTRACT : String = "moonclaw.context-fragment.v1"

///|
priv enum MoonCodeContextKind {
  SystemContext
  SkillContext
  EnvironmentContext
  WarningContext
  ToolResultContext
  UserContext
  AssistantContext
  UnknownContext(String)
} derive(Debug, Eq)

///|
fn mooncode_runtime_context_kind_from_key(key : String) -> MoonCodeContextKind {
  match key {
    "system" => SystemContext
    "skill" => SkillContext
    "environment" => EnvironmentContext
    "warning" => WarningContext
    "tool_result" => ToolResultContext
    "user" => UserContext
    "assistant" => AssistantContext
    unknown => UnknownContext(unknown)
  }
}

///|
fn mooncode_runtime_context_kind_key(kind : MoonCodeContextKind) -> String {
  match kind {
    SystemContext => "system"
    SkillContext => "skill"
    EnvironmentContext => "environment"
    WarningContext => "warning"
    ToolResultContext => "tool_result"
    UserContext => "user"
    AssistantContext => "assistant"
    UnknownContext(key) => key
  }
}

///|
fn mooncode_runtime_context_token_valid(
  value : String,
  max_chars : Int,
) -> Bool {
  if value == "" || value.length() > max_chars {
    return false
  }
  for ch in value {
    if !((ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '-' ||
      ch == '.' ||
      ch == ':') {
      return false
    }
  }
  true
}

///|
fn mooncode_runtime_context_provenance(message : Json) -> Json {
  mooncode_json_object_field_or_empty(
    message,
    MOONCODE_CONTEXT_PROVENANCE_FIELD,
  )
}

///|
fn mooncode_runtime_context_provenance_valid(metadata : Json) -> Bool {
  metadata is Object(_) &&
  mooncode_json_string(metadata, "contract", default="") ==
  MOONCODE_CONTEXT_PROVENANCE_CONTRACT &&
  mooncode_runtime_context_token_valid(
    mooncode_json_string(metadata, "kind", default=""),
    64,
  ) &&
  mooncode_runtime_context_token_valid(
    mooncode_json_string(metadata, "source", default=""),
    160,
  )
}

///|
fn mooncode_runtime_context_metadata(
  kind : MoonCodeContextKind,
  source : String,
) -> Json {
  {
    "contract": MOONCODE_CONTEXT_PROVENANCE_CONTRACT,
    "kind": mooncode_runtime_context_kind_key(kind),
    "source": source,
  }
}

///|
fn mooncode_runtime_context_message(
  message : Json,
  kind : MoonCodeContextKind,
  source : String,
) -> Json {
  mooncode_json_object_with_field(
    message,
    MOONCODE_CONTEXT_PROVENANCE_FIELD,
    mooncode_runtime_context_metadata(kind, source),
  )
}

///|
fn mooncode_runtime_context_text_message(
  role : String,
  content : String,
  kind : MoonCodeContextKind,
  source : String,
) -> Json {
  mooncode_runtime_context_message(
    { "role": role, "content": content },
    kind,
    source,
  )
}

///|
fn mooncode_runtime_context_visible_message(message : Json) -> Json {
  let visible : Map[String, Json] = Map([])
  match message {
    Object(fields) =>
      for key, value in fields.iter2() {
        if key != MOONCODE_CONTEXT_PROVENANCE_FIELD {
          visible[key] = value
        }
      }
    _ => return message
  }
  Json::object(visible)
}

///|
fn mooncode_runtime_context_visible_messages(
  messages : Array[Json],
) -> Array[Json] {
  messages.map(message => mooncode_runtime_context_visible_message(message))
}

///|
fn mooncode_runtime_context_inferred_kind(
  message : Json,
) -> MoonCodeContextKind {
  let role = mooncode_json_string(message, "role", default="")
  let visible = mooncode_runtime_context_visible_message(message).stringify()
  if visible.contains("MoonCode compacted") ||
    visible.contains("Context checkpoint: MoonClaw compacted") ||
    visible.contains("Earlier model-authored reasoning anchors") {
    return EnvironmentContext
  }
  if visible.contains("Visual evidence from MoonBook path") ||
    visible.contains("image evidence item(s)") {
    return ToolResultContext
  }
  match role {
    "system" => SystemContext
    "tool" => ToolResultContext
    "user" => UserContext
    "assistant" => AssistantContext
    _ => EnvironmentContext
  }
}

///|
fn mooncode_runtime_context_normalize_message(
  message : Json,
  fallback_kind? : MoonCodeContextKind,
  fallback_source? : String = "legacy.inferred",
) -> Json {
  let metadata = mooncode_runtime_context_provenance(message)
  if mooncode_runtime_context_provenance_valid(metadata) {
    return message
  }
  let kind = match fallback_kind {
    Some(kind) => kind
    None => mooncode_runtime_context_inferred_kind(message)
  }
  let source = if mooncode_runtime_context_token_valid(fallback_source, 160) {
    fallback_source
  } else {
    "legacy.inferred"
  }
  mooncode_runtime_context_message(message, kind, source)
}

///|
fn mooncode_runtime_context_kind(message : Json) -> MoonCodeContextKind {
  let normalized = mooncode_runtime_context_normalize_message(message)
  let metadata = mooncode_runtime_context_provenance(normalized)
  mooncode_runtime_context_kind_from_key(
    mooncode_json_string(metadata, "kind", default="environment"),
  )
}

///|
fn mooncode_runtime_context_copy_provenance(
  message : Json,
  source : Json,
) -> Json {
  let normalized_source = mooncode_runtime_context_normalize_message(source)
  let metadata = mooncode_runtime_context_provenance(normalized_source)
  mooncode_json_object_with_field(
    message,
    MOONCODE_CONTEXT_PROVENANCE_FIELD,
    metadata,
  )
}

///|
fn mooncode_runtime_context_tool_call_id(message : Json) -> String {
  mooncode_json_string(message, "tool_call_id", default="")
}

///|
fn mooncode_runtime_context_exact_alignment_index(
  provider_message : Json,
  source_messages : Array[Json],
  start : Int,
  used : Array[Int],
) -> Int {
  let visible = mooncode_runtime_context_visible_message(provider_message).stringify()
  for index in start..<source_messages.length() {
    if !used.contains(index) &&
      mooncode_runtime_context_visible_message(source_messages[index]).stringify() ==
      visible {
      return index
    }
  }
  -1
}

///|
fn mooncode_runtime_context_tool_alignment_index(
  provider_message : Json,
  source_messages : Array[Json],
  start : Int,
  used : Array[Int],
) -> Int {
  let tool_call_id = mooncode_runtime_context_tool_call_id(provider_message)
  if tool_call_id == "" {
    return -1
  }
  for index in start..<source_messages.length() {
    if !used.contains(index) &&
      mooncode_runtime_context_tool_call_id(source_messages[index]) ==
      tool_call_id {
      return index
    }
  }
  -1
}

///|
/// Reattach out-of-band provenance after typed provider request conversion.
/// Exact visible-message matching handles the ordinary path. Tool-call ids
/// keep alignment when overload shaping truncates tool output, and any newly
/// inserted or otherwise unmatched provider message receives a conservative
/// inferred kind. Length changes and unknown kinds never reject content.
fn mooncode_runtime_context_merge_messages(
  provider_messages : Array[Json],
  source_messages : Array[Json],
) -> Array[Json] {
  if source_messages.is_empty() {
    return provider_messages.map(message => {
      mooncode_runtime_context_normalize_message(message)
    })
  }
  let merged : Array[Json] = []
  let used : Array[Int] = []
  let mut source_cursor = 0
  for provider_message in provider_messages {
    let mut match_index = mooncode_runtime_context_exact_alignment_index(
      provider_message, source_messages, source_cursor, used,
    )
    if match_index < 0 {
      match_index = mooncode_runtime_context_tool_alignment_index(
        provider_message, source_messages, source_cursor, used,
      )
    }
    if match_index >= 0 {
      used.push(match_index)
      source_cursor = match_index + 1
      merged.push(
        mooncode_runtime_context_copy_provenance(
          provider_message,
          source_messages[match_index],
        ),
      )
    } else {
      merged.push(mooncode_runtime_context_normalize_message(provider_message))
    }
  }
  merged
}

///|
/// Roles that may appear in streamed completion deltas.
#derive(ToJson)
pub(all) enum ChatCompletionRole {
  Developer
  System
  User
  Assistant
  Tool
}

///|
impl @json.FromJson for ChatCompletionRole with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ChatCompletionRole {
  guard json is String(role) else {
    raise JsonDecodeError((json_path, "Expected a string"))
  }
  match role {
    "developer" => Developer
    "system" => System
    "user" => User
    "assistant" => Assistant
    "tool" => Tool
    role => raise JsonDecodeError((json_path, "Unknown role: \{role}"))
  }
}

///|
pub extend ChatCompletionRole with ToJson::{to_json}

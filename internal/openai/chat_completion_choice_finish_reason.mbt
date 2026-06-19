///|
/// Reason why the model stopped generating tokens.
pub(all) enum ChatCompletionChoiceFinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  FunctionCall
} derive(Debug)

///|
impl ToJson for ChatCompletionChoiceFinishReason with fn to_json(
  self : ChatCompletionChoiceFinishReason,
) -> Json {
  match self {
    Stop => "stop"
    Length => "length"
    ToolCalls => "tool_calls"
    ContentFilter => "content_filter"
    FunctionCall => "function_call"
  }
}

///|
impl @json.FromJson for ChatCompletionChoiceFinishReason with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ChatCompletionChoiceFinishReason {
  guard json is String(reason) else {
    raise JsonDecodeError((json_path, "Expected a string"))
  }
  match reason {
    "stop" => Stop
    "length" => Length
    "tool_calls" => ToolCalls
    "content_filter" => ContentFilter
    "function_call" => FunctionCall
    _ => raise JsonDecodeError((json_path, "Unknown finish reason: \{reason}"))
  }
}

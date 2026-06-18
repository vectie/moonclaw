///|
/// Message author roles reflected in completion responses.
pub enum ChatCompletionMessageRole {
  Assistant
} derive(Debug)

///|
pub impl ToJson for ChatCompletionMessageRole with fn to_json(
  self : ChatCompletionMessageRole,
) -> Json {
  match self {
    Assistant => "assistant"
  }
}

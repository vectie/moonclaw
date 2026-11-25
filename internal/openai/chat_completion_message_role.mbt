///|
/// Message author roles reflected in completion responses.
#derive(Debug)
pub enum ChatCompletionMessageRole {
  Assistant
}

///|
pub impl ToJson for ChatCompletionMessageRole with fn to_json(
  self : ChatCompletionMessageRole,
) -> Json {
  match self {
    Assistant => "assistant"
  }
}

///|
pub extend ChatCompletionMessageRole with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend ChatCompletionMessageRole with ToJson::{to_json}

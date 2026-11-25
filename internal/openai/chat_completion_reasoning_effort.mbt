///|
/// Reasoning effort control for reasoning models.
#derive(Debug)
pub(all) enum ChatCompletionReasoningEffort {
  None_
  Minimal
  Low
  Medium
  High
  Xhigh
}

///|
impl ToJson for ChatCompletionReasoningEffort with fn to_json(
  self : ChatCompletionReasoningEffort,
) -> Json {
  match self {
    None_ => "none"
    Minimal => "minimal"
    Low => "low"
    Medium => "medium"
    High => "high"
    Xhigh => "xhigh"
  }
}

///|
pub extend ChatCompletionReasoningEffort with @moonbitlang/core/debug.Debug::{
  to_repr,
}

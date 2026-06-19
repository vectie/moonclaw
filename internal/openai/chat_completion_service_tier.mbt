///|
/// Service tier override for chat completion requests.
pub(all) enum ChatCompletionServiceTier {
  Auto
  Default
  Flex
  Scale
  Priority
} derive(Debug)

///|
impl @json.FromJson for ChatCompletionServiceTier with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ChatCompletionServiceTier {
  guard json is String(tier) else {
    raise JsonDecodeError((json_path, "Expected a string"))
  }
  match tier {
    "auto" => Auto
    "default" => Default
    "flex" => Flex
    "scale" => Scale
    "priority" => Priority
    _ => raise JsonDecodeError((json_path, "Unknown service tier: \{tier}"))
  }
}

///|
impl ToJson for ChatCompletionServiceTier with fn to_json(
  self : ChatCompletionServiceTier,
) -> Json {
  match self {
    Auto => "auto"
    Default => "default"
    Flex => "flex"
    Scale => "scale"
    Priority => "priority"
  }
}

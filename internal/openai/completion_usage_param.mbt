///|
/// Controls whether the API returns usage statistics.
pub struct CompletionUsageParam {
  include_ : Bool
}

///|
impl ToJson for CompletionUsageParam with fn to_json(
  self : CompletionUsageParam,
) -> Json {
  { "include": Json::boolean(self.include_) }
}

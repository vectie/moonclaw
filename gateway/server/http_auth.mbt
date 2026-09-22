///|
// Authentication applies to every API request, not just RPC connect. Health,
// static UI and channel webhooks keep their existing independent semantics.
fn gateway_http_authorized(
  path : StringView,
  headers : Map[String, String],
  token : String?,
) -> Bool {
  if !path.has_prefix("/v1/") {
    return true
  }
  match token {
    None => true
    Some(expected) =>
      !expected.is_empty() &&
      headers.get("authorization") == Some("Bearer " + expected)
  }
}

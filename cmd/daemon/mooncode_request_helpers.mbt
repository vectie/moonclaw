///|
fn mooncode_request_book_root(r : @httpx.RequestReader) -> String {
  mooncode_request_string(r, "book_root", default="")
}

///|
fn mooncode_request_string(
  r : @httpx.RequestReader,
  key : String,
  default~ : String,
) -> String {
  let parts = r.path.split("?").to_array()
  if parts.length() < 2 {
    return default
  }
  let query = @codex.parse_query_string(parts[1])
  query.get(key).unwrap_or(default)
}

///|
fn mooncode_request_int(
  r : @httpx.RequestReader,
  key : String,
  default~ : Int,
) -> Int {
  let value = mooncode_request_string(r, key, default="")
  if value == "" {
    return default
  }
  @string.parse_int(value) catch {
    _ => default
  }
}

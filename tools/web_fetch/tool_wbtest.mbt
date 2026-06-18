///|
test "extracted_fetch_text prefers html body over head content" {
  let (text, title) = extracted_fetch_text(
    "<html><head><title>Site Page</title><script>ignore()</script></head><body><h1>Hello</h1><p>World</p></body></html>",
    Some("text/html; charset=utf-8"),
  )
  inspect(title.unwrap_or(""), content="Site Page")
  inspect(text, content="Hello World")
}

///|
test "parse_fetch_uri extracts scheme host and default path" {
  let uri = parse_fetch_uri("https://example.com") catch {
    error => fail("\{to_repr(error)}")
  }
  inspect(uri.scheme, content="https")
  inspect(uri.host, content="example.com")
  inspect(uri.path, content="/")
}

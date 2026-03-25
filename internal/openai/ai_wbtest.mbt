///|
test "codex_request_headers use openclaw attribution" {
  let headers = codex_request_headers("test-token")
  assert_eq(headers["Authorization"], "Bearer test-token")
  assert_eq(headers["Content-Type"], "application/json")
  assert_eq(headers["Accept"], "text/event-stream")
  assert_eq(headers["originator"], "openclaw")
  assert_eq(headers["User-Agent"], "openclaw/0.1.0")
}

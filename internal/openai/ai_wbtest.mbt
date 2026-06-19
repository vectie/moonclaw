///|
test "codex_request_headers use moonclaw attribution" {
  let headers = codex_request_headers("test-token")
  assert_eq(headers["Authorization"], "Bearer test-token")
  assert_eq(headers["Content-Type"], "application/json")
  assert_eq(headers["Accept"], "text/event-stream")
  assert_eq(headers["originator"], "moonclaw")
  assert_eq(headers["User-Agent"], "moonclaw/0.1.0")
}

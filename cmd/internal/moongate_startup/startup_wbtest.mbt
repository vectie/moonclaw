///|
test "moongate startup messages describe MoonClaw routing and standalone fallback" {
  assert_eq(
    ready_message("http://127.0.0.1:15721"),
    "MoonGate available at http://127.0.0.1:15721; MoonClaw routing and usage/statistics bridge enabled",
  )
  assert_eq(
    unavailable_message(
      "http://127.0.0.1:15721", "request error: connection refused",
    ),
    "MoonGate unavailable at http://127.0.0.1:15721; continuing as standalone MoonClaw: request error: connection refused",
  )
}

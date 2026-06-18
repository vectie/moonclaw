///|
test "moonstat startup messages describe OpenClaw bridge and standalone fallback" {
  assert_eq(
    ready_message("http://127.0.0.1:15721"),
    "Moonstat available at http://127.0.0.1:15721; OpenClaw routing and usage/statistics bridge enabled",
  )
  assert_eq(
    unavailable_message(
      "http://127.0.0.1:15721", "request error: connection refused",
    ),
    "Moonstat unavailable at http://127.0.0.1:15721; continuing as standalone MoonClaw: request error: connection refused",
  )
}

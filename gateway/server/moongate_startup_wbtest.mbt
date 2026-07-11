///|
test "moongate startup messages describe bridge and standalone fallback" {
  assert_eq(
    moongate_startup_ready_message("http://127.0.0.1:15721"),
    "MoonGate available at http://127.0.0.1:15721; gateway usage/statistics bridge enabled",
  )
  assert_eq(
    moongate_startup_unavailable_message(
      "http://127.0.0.1:15721", "request error: connection refused",
    ),
    "MoonGate unavailable at http://127.0.0.1:15721; continuing without usage/statistics bridge: request error: connection refused",
  )
}

///|
test "MoonGate route status exposes only qualified routed models" {
  let status = moonclaw_moongate_route_status_json(
    "http://127.0.0.1:15721",
    ["kimi-k3", "", "kimi-k3", "deepseek-v4"],
    "",
  )
  assert_eq(
    mooncode_json_string(status, "contract", default=""),
    "moonclaw.moongate-route.v1",
  )
  assert_true(mooncode_json_bool(status, "ready", default=false))
  assert_eq(
    mooncode_json_string(status, "default_model", default=""),
    "moongate/kimi-k3",
  )
  let models = mooncode_json_array_items(status, "models")
  assert_eq(models.length(), 2)
  assert_eq(
    mooncode_json_string(models[1], "name", default=""),
    "moongate/deepseek-v4",
  )
}

///|
test "MoonGate route status fails closed without live catalog" {
  let missing = moonclaw_moongate_route_status_json(
    "",
    [],
    "MoonGate suite status is unavailable",
  )
  assert_false(mooncode_json_bool(missing, "ready", default=true))
  assert_eq(
    mooncode_json_string(missing, "default_model", default="missing"),
    "",
  )
  let failed = moonclaw_moongate_route_status_json(
    "http://127.0.0.1:15721",
    ["kimi-k3"],
    "connection refused",
  )
  assert_false(mooncode_json_bool(failed, "ready", default=true))
}

///|
test "daemon health is a lightweight stable contract" {
  let health = moonclaw_health_json(61234)
  assert_eq(mooncode_json_bool(health, "ok", default=false), true)
  assert_eq(mooncode_json_string(health, "status", default=""), "ready")
  assert_eq(mooncode_json_string(health, "service", default=""), "moonclaw")
  assert_eq(mooncode_json_int(health, "port", default=0), 61234)
}

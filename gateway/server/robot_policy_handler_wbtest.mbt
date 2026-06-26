///|
test "robot policy joins Moonrobo base URL and route" {
  assert_eq(
    robot_policy_join_url(" http://127.0.0.1:5192/ ", "/api/moonclaw/context"),
    "http://127.0.0.1:5192/api/moonclaw/context",
  )
  assert_eq(
    robot_policy_join_url("http://127.0.0.1:5192", "api/moonrobo/ask"),
    "http://127.0.0.1:5192/api/moonrobo/ask",
  )
  assert_eq(
    robot_policy_join_url(
      "http://127.0.0.1:5192", "http://127.0.0.1:5193/api/moonclaw/context",
    ),
    "http://127.0.0.1:5193/api/moonclaw/context",
  )
}

///|
test "robot policy request requires Moonrobo URL" {
  let params = robot_policy_decode_request_text(
    "{\"moonrobo_url\":\"http://127.0.0.1:5192\",\"now_ms\":42}",
  )
  match params {
    Ok(decoded) => {
      assert_eq(decoded.moonrobo_url, "http://127.0.0.1:5192")
      assert_true(decoded.now_ms is Some(42L))
    }
    Err(message) => abort("expected valid robot policy request: \{message}")
  }
  let missing = robot_policy_decode_request_text(
    { "moonrobo_url": " " }.to_json().stringify(),
  )
  assert_true(missing is Err(_))
}

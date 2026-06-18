///|
test "moonstat client resolves manifest base url" {
  let status = { "manifest": { "base_url": "http://127.0.0.1:18081" } }.to_json()
  assert_true(
    moonstat_base_url_from_status(status) == Some("http://127.0.0.1:18081"),
  )
}

///|
test "moonstat client falls back to health url" {
  let status = { "health_url": "http://127.0.0.1:18082/health" }.to_json()
  assert_true(
    moonstat_base_url_from_status(status) == Some("http://127.0.0.1:18082"),
  )
}

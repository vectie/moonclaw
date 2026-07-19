///|
test "model listing puts the executable default first and removes duplicates" {
  let default_model = @model.new(
    api_key="",
    base_url="https://chatgpt.com/backend-api",
    name="codex/gpt-5.6-sol",
    model_name="gpt-5.6-sol",
    safe_zone_tokens=400000,
  )
  let optional_model = @model.new(
    api_key="local",
    base_url="http://127.0.0.1:15721/openclaw/v1",
    name="gpt-5.6-sol",
    model_name="gpt-5.6-sol",
    safe_zone_tokens=400000,
  )
  let listing = mooncode_model_listing_json(Some(default_model), [
    default_model, optional_model,
  ])
  assert_eq(
    mooncode_json_string(listing, "default_model", default=""),
    "codex/gpt-5.6-sol",
  )
  assert_true(mooncode_json_bool(listing, "ready", default=false))
  let models = mooncode_json_array_items(listing, "models")
  assert_eq(models.length(), 2)
  assert_eq(
    mooncode_json_string(models[0], "name", default=""),
    "codex/gpt-5.6-sol",
  )
  assert_true(mooncode_json_bool(models[0], "default", default=false))
  assert_eq(mooncode_json_string(models[1], "name", default=""), "gpt-5.6-sol")
  assert_false(mooncode_json_bool(models[1], "default", default=true))
}

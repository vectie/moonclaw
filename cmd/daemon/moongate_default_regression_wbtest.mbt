///|
test "MoonGate route cannot invent a default from catalog order" {
  let status = moonclaw_moongate_route_status_json(
    "http://gate.invalid",
    ["first", "chosen"],
    "",
  )
  assert_false(mooncode_json_bool(status, "ready", default=true))
  assert_eq(
    mooncode_json_string(status, "default_model", default="missing"),
    "",
  )
}

///|
test "MoonGate catalog survives a missing configured default for explicit callers" {
  for configured_default in [None, Some(""), Some("absent")] {
    let status = moonclaw_moongate_route_status_json(
      "http://gate.invalid",
      ["first", "chosen"],
      "",
      configured_default?,
    )
    assert_false(mooncode_json_bool(status, "ready", default=true))
    assert_false(mooncode_json_bool(status, "default_ready", default=true))
    assert_true(mooncode_json_bool(status, "catalog_ready", default=false))
    assert_eq(
      mooncode_json_string(status, "default_model", default="missing"),
      "",
    )
    let models = mooncode_json_array_items(status, "models")
    assert_eq(models.length(), 2)
    for model in models {
      assert_false(mooncode_json_bool(model, "default", default=true))
    }
    assert_true(mooncode_json_string(status, "error", default="") != "")
  }
}

///|
test "MoonGate unavailable or empty catalog cannot advertise a default" {
  for
    (ids, error) in [
      ([], ""),
      (["", " ", " chosen "], ""),
      (["chosen"], "offline"),
    ] {
    let status = moonclaw_moongate_route_status_json(
      "http://gate.invalid",
      ids,
      error,
      configured_default="chosen",
    )
    assert_false(mooncode_json_bool(status, "ready", default=true))
    assert_false(mooncode_json_bool(status, "catalog_ready", default=true))
    assert_eq(
      mooncode_json_string(status, "default_model", default="missing"),
      "",
    )
    assert_eq(mooncode_json_array_items(status, "models").length(), 0)
  }
}

///|
test "MoonGate configured default and modality follow exact catalog identity" {
  let catalog = @moongate.moongate_models_from_json({
    "models": [
      { "id": "first" },
      { "id": "chosen/id", "input_modalities": ["text", "image"] },
    ],
  }).unwrap()
  let status = moonclaw_moongate_route_status_json(
    "http://gate.invalid",
    ["first", "", "chosen/id", "chosen/id"],
    "",
    configured_default="chosen/id",
    catalog~,
  )
  assert_true(mooncode_json_bool(status, "ready", default=false))
  assert_eq(
    mooncode_json_string(status, "default_model", default=""),
    "moongate/chosen/id",
  )
  let models = mooncode_json_array_items(status, "models")
  assert_eq(models.length(), 2)
  assert_false(mooncode_json_bool(models[0], "default", default=true))
  assert_true(mooncode_json_bool(models[1], "default", default=false))
  json_inspect(mooncode_json_array_items(models[1], "input_modalities"), content=[
    "text", "image",
  ])
}

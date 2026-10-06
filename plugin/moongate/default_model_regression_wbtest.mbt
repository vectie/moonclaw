///|
test "MoonGate configured default rejects missing empty and malformed values" {
  for value in [Json::null(), "", "  ", 42, [], {}] {
    let status : Json = {
      "contract": "moon.suite.status.v2",
      "service": "moongate",
      "manifest": {
        "contract": "moon.suite.service.v1",
        "service": "moongate",
        "defaultModel": value,
      },
    }
    assert_eq(moongate_default_models_from_status(status).length(), 0)
  }
  let missing : Json = {
    "contract": "moon.suite.status.v2",
    "service": "moongate",
    "manifest": { "contract": "moon.suite.service.v1", "service": "moongate" },
  }
  assert_eq(moongate_default_models_from_status(missing).length(), 0)
}

///|
test "MoonGate configured default preserves nested catalog identity" {
  let status : Json = {
    "contract": "moon.suite.status.v2",
    "service": "moongate",
    "manifest": {
      "contract": "moon.suite.service.v1",
      "service": "moongate",
      "defaultModel": "configured/exact-id",
    },
  }
  let models = moongate_default_models_from_status(status)
  assert_eq(models.length(), 1)
  assert_eq(models[0].id(), "configured/exact-id")
}

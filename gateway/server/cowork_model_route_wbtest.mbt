///|
async test "Cowork route uses exact workspace and configured default rather than first live model" {
  let observed : Array[String] = []
  let route = cowork_native_route(
    "/trusted/book",
    configured=cwd => {
      observed.push(cwd)
      Some("chosen")
    },
    catalog=cwd => {
      observed.push(cwd)
      Ok(["other", "chosen"])
    },
  )
  assert_eq(observed, ["/trusted/book", "/trusted/book"])
  assert_true(
    route
    is { "default_ready": True, "default_model": String("moongate/chosen"), .. },
  )
  assert_true(
    gateway_http_authorized(
      "/v1/cowork/model-route",
      { "authorization": "Bearer fixture" },
      Some("fixture"),
    ),
  )
  assert_false(
    gateway_http_authorized("/v1/cowork/model-route", {}, Some("fixture")),
  )
}

///|
test "Cowork catalog remains usable for exact explicit native choice without automatic default" {
  let route = cowork_native_route_json("/book", None, ["explicit"], "")
  assert_true(
    route
    is {
      "catalog_ready": True,
      "default_ready": False,
      "default_model": String(""),
      ..
    },
  )
  let absent = cowork_native_route_json("/book", Some("missing"), ["other"], "")
  assert_true(
    absent is { "default_ready": False, "default_model": String(""), .. },
  )
  let failed = cowork_native_route_json(
    "/book",
    Some("chosen"),
    ["chosen"],
    "unavailable",
  )
  assert_true(failed is { "catalog_ready": False, "default_ready": False, .. })
}

///|
test "actual Cowork config assignment preserves exact native and deliberate legacy protocol" {
  assert_eq(
    cowork_config_model_override(None, Some("moongate/chosen")),
    Some("moongate/chosen"),
  )
  assert_eq(
    cowork_config_model_override(Some("moongate/chosen"), Some("codex/manual")),
    Some("codex/manual"),
  )
  assert_eq(
    cowork_config_model_override(Some("codex/manual"), None),
    Some("codex/manual"),
  )
  assert_eq(
    cowork_config_model_override(Some("moongate/chosen"), Some("")),
    None,
  )
}

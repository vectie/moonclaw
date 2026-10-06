///|
async test "reserved MoonGate selector rejects configured provider collision" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let product = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
    let _ = product.add_file(
      "providers.json",
      content=(
        {
          "providers": {
            "moongate": {
              "baseUrl": "https://other-provider.invalid/v1",
              "api": "openai",
              "apiKey": "dummy-key",
              "models": [{ "id": "chosen/catalog-id" }],
            },
          },
        } : Json).stringify(),
    )
    let loader = Loader::new(home=mock.cwd.path(), cwd=mock.cwd.path())
    assert_true(loader.get_model(name="moongate/chosen/catalog-id") is None)
  })
}

///|
async test "reserved MoonGate selector ignores cached model name collision" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let collision = Model::new(
      api_key="dummy-key",
      base_url="https://other.invalid",
      name="moongate/chosen",
      model_name="other",
      safe_zone_tokens=1000,
    )
    let _ = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
      .add_directory("models")
      .add_file("models.json", content=[collision].to_json().stringify())
    let loader = Loader::new(home=mock.cwd.path(), cwd=mock.cwd.path())
    assert_true(loader.get_model(name="moongate/chosen") is None)
    assert_eq(loader.get_model().unwrap().name, "moongate/chosen")
  })
}

///|
async test "MoonGate route uses exact live catalog selection and never invokes fallback" {
  let catalog = @moongate.moongate_models_from_json({
    "models": [
      { "id": "first" },
      {
        "id": "chosen/catalog-id",
        "context_window": 99000,
        "input_modalities": ["text", "image"],
      },
    ],
  }).unwrap()
  let gate_calls : Array[String] = []
  let fallback_calls : Array[String?] = []
  let chosen = resolve_model_route(
    Some("moongate/chosen/catalog-id"),
    moongate=selector => {
      gate_calls.push(selector)
      select_moongate_catalog_model(selector, "http://gate.invalid", catalog)
    },
    legacy=selector => {
      fallback_calls.push(selector)
      None
    },
  ).unwrap()
  assert_eq(chosen.selector(), "moongate/chosen/catalog-id")
  assert_eq(chosen.model_name, "chosen/catalog-id")
  assert_eq(chosen.base_url, "http://gate.invalid/openclaw/v1")
  assert_eq(chosen.safe_zone_tokens, 99000)
  assert_true(chosen.input_modalities.contains("image"))
  for
    name in [
      "moongate/missing", "moongate/", " moongate/chosen/catalog-id", "moongate/chosen/catalog-id ",
    ] {
    assert_true(
      resolve_model_route(
        Some(name),
        moongate=selector => {
          gate_calls.push(selector)
          select_moongate_catalog_model(
            selector, "http://gate.invalid", catalog,
          )
        },
        legacy=selector => {
          fallback_calls.push(selector)
          Some(chosen)
        },
      )
      is None,
    )
  }
  for _ in ["offline", "empty"] {
    assert_true(
      resolve_model_route(
        Some("moongate/chosen/catalog-id"),
        moongate=selector => {
          gate_calls.push(selector)
          None
        },
        legacy=selector => {
          fallback_calls.push(selector)
          Some(chosen)
        },
      )
      is None,
    )
  }
  assert_eq(gate_calls.length(), 7)
  assert_eq(fallback_calls.length(), 0)
}

///|
async test "MoonGate dispatch preserves every explicit legacy route and unqualified selection" {
  let gate_calls : Array[String] = []
  let legacy_calls : Array[String?] = []
  let names : Array[String?] = [
    None,
    Some("haiku"),
    Some("codex/gpt-5.6-sol"),
    Some("codex/gpt-5.4"),
    Some("copilot/claude-sonnet-4.5"),
    Some("qwen/qwen3-coder-plus"),
    Some("kimi/kimi-k2.5"),
    Some("kimi-coding/k2p5"),
    Some("custom-provider/nested/model"),
  ]
  for name in names {
    ignore(
      resolve_model_route(
        name,
        moongate=selector => {
          gate_calls.push(selector)
          None
        },
        legacy=selector => {
          legacy_calls.push(selector)
          None
        },
      ),
    )
  }
  assert_eq(gate_calls.length(), 0)
  assert_eq(legacy_calls, names)
}

///|
async test "reserved MoonGate selector stays unavailable with OpenRouter configured" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let product = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
    let _ = product.add_file(
      "moonclaw.json",
      content=({ "api_key": "dummy-openrouter-key" } : Json).stringify(),
    )
    let loader = Loader::new(home=mock.cwd.path(), cwd=mock.cwd.path())
    assert_true(
      loader.load_openrouter_model(Some("moongate/missing")) is Some(_),
    )
    assert_true(loader.get_model(name="moongate/missing") is None)
  })
}

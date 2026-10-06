///|
async test "Loader" (t : @test.Test) {
  @mock.run(t, mock => {
    let api_key = "test-api-key"
    let model = @model.new(
      api_key~,
      base_url="https://openrouter.ai/api/v1",
      name="haiku",
      model_name="anthropic/claude-haiku-4.5",
      safe_zone_tokens=200000,
    )
    let models = [model]
    let models_file = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
      .add_directory("models")
      .add_file("models.json")
    models_file.write_string(models.to_json().stringify(indent=2))
    json_inspect(mock.json(@json.parse(models_file.read())), content=[
      {
        "name": "haiku",
        "model_name": "anthropic/claude-haiku-4.5",
        "model_type": "saas/openai",
        "api_key": "test-api-key",
        "base_url": "https://openrouter.ai/api/v1",
        "safe_zone_tokens": 200000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
        "input_modalities": ["text"],
      },
    ])
    let loader = @model.Loader::new(home=mock.cwd.path(), cwd=mock.cwd.path())
    json_inspect(mock.json(loader.get_model(name="haiku")), content=[
      {
        "name": "haiku",
        "model_name": "anthropic/claude-haiku-4.5",
        "model_type": "saas/openai",
        "api_key": "test-api-key",
        "base_url": "https://openrouter.ai/api/v1",
        "safe_zone_tokens": 200000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
        "input_modalities": ["text"],
      },
    ])
  })
}

///|
async test "Loader reads canonical product providers manifest" (t : @test.Test) {
  @mock.run(t, mock => {
    let providers_file = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
      .add_file("providers.json")
    providers_file.write_string(
      (
        {
          "providers": {
            "custom-provider": {
              "baseUrl": "https://configured-provider.invalid/v1",
              "api": "openai",
              "apiKey": "dummy-provider-key",
              "models": [
                {
                  "id": "gpt-5.5",
                  "name": "custom-provider/gpt-5.5",
                  "reasoning": true,
                  "input": ["text", "image"],
                },
              ],
            },
          },
        } : Json).stringify(indent=2),
    )
    let loader = @model.Loader::new(home=mock.cwd.path(), cwd=mock.cwd.path())
    let loaded = loader.get_model(name="custom-provider/gpt-5.5")
    guard loaded is Some(model) else {
      fail("expected canonical provider model")
    }
    inspect(model.name, content="custom-provider/gpt-5.5")
    inspect(model.model_name, content="gpt-5.5")
    inspect(model.base_url, content="https://configured-provider.invalid/v1")
  })
}

///|
async test "load" (t : @test.Test) {
  @mock.run(t, mock => {
    let api_key = "test-api-key"
    let model = @model.new(
      api_key~,
      base_url="https://openrouter.ai/api/v1",
      name="haiku",
      model_name="anthropic/claude-haiku-4.5",
      safe_zone_tokens=200000,
    )
    let models = [model]
    let models_file = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
      .add_directory("models")
      .add_file("models.json")
    models_file.write_string(models.to_json().stringify(indent=2))
    json_inspect(mock.json(@json.parse(models_file.read())), content=[
      {
        "name": "haiku",
        "model_name": "anthropic/claude-haiku-4.5",
        "model_type": "saas/openai",
        "api_key": "test-api-key",
        "base_url": "https://openrouter.ai/api/v1",
        "safe_zone_tokens": 200000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
        "input_modalities": ["text"],
      },
    ])
    json_inspect(
      mock.json(
        @model.load(home=mock.cwd.path(), cwd=mock.cwd.path(), name="haiku"),
      ),
      content=[
        {
          "name": "haiku",
          "model_name": "anthropic/claude-haiku-4.5",
          "model_type": "saas/openai",
          "api_key": "test-api-key",
          "base_url": "https://openrouter.ai/api/v1",
          "safe_zone_tokens": 200000,
          "supports_anthropic_prompt_caching": false,
          "supports_apply_patch": false,
          "input_modalities": ["text"],
        },
      ],
    )
  })
}

///|
async test "removes-old-models" (t : @test.Test) {
  @mock.run(t, mock => {
    let old_model = @model.new(
      api_key="old_api_key",
      base_url="https://old-base-url.com",
      name="old_model",
      model_name="old/model-name",
      safe_zone_tokens=100000,
    )
    let models_file = mock.cwd
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
      .add_directory("models")
      .add_file("models.json")
    let models = [old_model]
    models_file.write_string(models.to_json().stringify(indent=2))
    let loader = @model.Loader::new(home=mock.cwd.path(), cwd=mock.cwd.path())
    json_inspect(loader.get_model(), content=[
      {
        "name": "old_model",
        "model_name": "old/model-name",
        "model_type": "saas/openai",
        "api_key": "old_api_key",
        "base_url": "https://old-base-url.com",
        "safe_zone_tokens": 100000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
        "input_modalities": ["text"],
      },
    ])
    let new_model = @model.new(
      api_key="new_api_key",
      base_url="https://openrouter.ai/api/v1",
      name="new_model",
      model_name="anthropic/claude-haiku-4.5",
      safe_zone_tokens=200000,
    )
    let models = [new_model]
    models_file.write_string(models.to_json().stringify(indent=2))
    json_inspect(loader.get_model(), content=[
      {
        "name": "new_model",
        "model_name": "anthropic/claude-haiku-4.5",
        "model_type": "saas/openai",
        "api_key": "new_api_key",
        "base_url": "https://openrouter.ai/api/v1",
        "safe_zone_tokens": 200000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
        "input_modalities": ["text"],
      },
    ])
  })
}

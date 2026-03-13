///|
async test "load" (t : @test.Test) {
  @mock.run(t, mock => {
    let home = mock.cwd
    let home_models : Json = [
      {
        "name": "anthropic/claude-sonnet-4",
        "description": "claude sonnet model for general tasks",
        "model_name": "anthropic/claude-sonnet-4",
        "model_type": "saas/openai",
        "base_url": "https://openrouter.ai/api/v1",
        "is_reasoning": false,
        "input_price": 21.0,
        "output_price": 105.0,
        "average_speed": 0,
        "safe_zone_tokens": 128000,
        "max_output_tokens": 24288,
        "api_key": "sk-test",
        "supports_anthropic_prompt_caching": true,
      },
      {
        "name": "qwen/qwen3-coder",
        "description": "qwen coder",
        "model_name": "qwen/qwen3-coder",
        "model_type": "saas/openai",
        "base_url": "https://openrouter.ai/api/v1",
        "is_reasoning": false,
        "input_price": 21.0,
        "output_price": 105.0,
        "average_speed": 0,
        "safe_zone_tokens": 256000,
        "max_output_tokens": 24288,
        "api_key": "sk-test",
      },
      {
        "name": "google/gemini-2.5-pro",
        "description": "google gemini 2.5 pro for translate or long-context complex task",
        "model_name": "google/gemini-2.5-pro",
        "model_type": "saas/openai",
        "base_url": "https://openrouter.ai/api/v1",
        "is_reasoning": false,
        "input_price": 21.0,
        "output_price": 105.0,
        "average_speed": 0,
        "safe_zone_tokens": 1000000,
        "max_output_tokens": 24288,
        "api_key": "sk-test",
      },
    ]
    let _ = home
      .add_directory(".moonclaw")
      .add_directory("models")
      .add_file(
        "models.json",
        content=home_models.to_json().stringify(indent=2),
      )
    let project = home.add_directory("project")
    let project_models : Json = [
      {
        "name": "google/gemini-2.5-flash",
        "description": "google gemini 2.5 flash for long-context simple task",
        "model_name": "google/gemini-2.5-flash",
        "model_type": "saas/openai",
        "base_url": "https://openrouter.ai/api/v1",
        "is_reasoning": false,
        "input_price": 21.0,
        "output_price": 105.0,
        "average_speed": 0,
        "safe_zone_tokens": 1000000,
        "max_output_tokens": 24288,
        "api_key": "sk-test",
        "supports_anthropic_prompt_caching": true,
      },
      {
        "name": "deepseek/deepseek-chat-v3.1",
        "description": "deepseek chat v3.1 for general tasks",
        "model_name": "deepseek-chat",
        "model_type": "saas/openai",
        "base_url": "https://api.deepseek.com",
        "is_reasoning": false,
        "safe_zone_tokens": 131000,
        "max_output_tokens": 8192,
        "api_key": "sk-test",
      },
    ]
    let _ = project
      .add_directory(".moonclaw")
      .add_directory("models")
      .add_file(
        "models.json",
        content=project_models.to_json().stringify(indent=2),
      )
    let loader = Loader::new(home=home.path(), cwd=project.path())
    json_inspect(mock.json(loader.get_model()), content=[
      {
        "name": "google/gemini-2.5-flash",
        "description": "google gemini 2.5 flash for long-context simple task",
        "model_name": "google/gemini-2.5-flash",
        "model_type": "saas/openai",
        "api_key": "sk-test",
        "base_url": "https://openrouter.ai/api/v1",
        "safe_zone_tokens": 1000000,
        "supports_anthropic_prompt_caching": true,
        "supports_apply_patch": false,
      },
    ])
    json_inspect(
      mock.json(loader.get_model(name="anthropic/claude-sonnet-4")),
      content=[
        {
          "name": "anthropic/claude-sonnet-4",
          "description": "claude sonnet model for general tasks",
          "model_name": "anthropic/claude-sonnet-4",
          "model_type": "saas/openai",
          "api_key": "sk-test",
          "base_url": "https://openrouter.ai/api/v1",
          "safe_zone_tokens": 128000,
          "supports_anthropic_prompt_caching": true,
          "supports_apply_patch": false,
        },
      ],
    )
    json_inspect(mock.json(loader.get_model(name="qwen/qwen3-coder")), content=[
      {
        "name": "qwen/qwen3-coder",
        "description": "qwen coder",
        "model_name": "qwen/qwen3-coder",
        "model_type": "saas/openai",
        "api_key": "sk-test",
        "base_url": "https://openrouter.ai/api/v1",
        "safe_zone_tokens": 256000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
      },
    ])
  })
}

///|
async test "load providers from moonclaw root config" (t : @test.Test) {
  @mock.run(t, mock => {
    let home = mock.cwd
    let project = home.add_directory("project")
    let config : Json = {
      "models": {
        "providers": {
          "bailian": {
            "baseUrl": "https://coding.dashscope.aliyuncs.com/v1",
            "apiKey": "sk-bailian",
            "api": "openai-completions",
            "models": [
              {
                "id": "qwen3.5-plus",
                "name": "qwen3.5-plus",
                "contextWindow": 1000000,
              },
            ],
          },
        },
      },
    }
    let _ = home.add_file("moonclaw.json", content=config.stringify(indent=2))
    let loader = Loader::new(home=home.path(), cwd=project.path())
    json_inspect(mock.json(loader.get_model(name="bailian/qwen3.5-plus")), content=[
      {
        "name": "bailian/qwen3.5-plus",
        "model_name": "qwen3.5-plus",
        "model_type": "saas/openai",
        "api_key": "sk-bailian",
        "base_url": "https://coding.dashscope.aliyuncs.com/v1",
        "safe_zone_tokens": 1000000,
        "supports_anthropic_prompt_caching": false,
        "supports_apply_patch": false,
      },
    ])
  })
}

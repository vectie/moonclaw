///|
test "model selector preserves provider identity" {
  let codex = codex_oauth_model(
    access_token="access",
    account_id="account",
    refresh_token="refresh",
  )
  assert_eq(codex.selector(), "codex/gpt-5.6-sol")
  let qwen = qwen_model(api_key="key", name=Qwen3CoderPlus)
  assert_eq(qwen.selector(), "qwen/qwen3-coder-plus")
  let configured = Model::new(
    api_key="key",
    base_url="https://example.test/v1",
    name="team/custom-model",
    model_name="custom-model",
    safe_zone_tokens=128000,
  )
  assert_eq(configured.selector(), "team/custom-model")
}

///|
test "explicit legacy Codex 5.4 selector is compatibility-only" {
  let legacy = codex_oauth_model(
    access_token="access",
    account_id="account",
    refresh_token="refresh",
    name=Gpt5_4,
  )
  assert_eq(legacy.selector(), "codex/gpt-5.4")
  assert_eq(legacy.model_name, "gpt-5.4")
}

///|
test "JSON-decoded GPT 5.4 and 5.6 models default to apply_patch support" {
  let current : Model = @json.from_json({
    "name": "codex/gpt-5.6-sol",
    "model_name": "gpt-5.6-sol",
    "model_type": "saas/codex_oauth",
  })
  assert_true(current.supports_apply_patch)
  let legacy : Model = @json.from_json({
    "name": "codex/gpt-5.4",
    "model_name": "gpt-5.4",
    "model_type": "saas/codex_oauth",
  })
  assert_true(legacy.supports_apply_patch)
}

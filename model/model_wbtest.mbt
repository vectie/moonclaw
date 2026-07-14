///|
test "model selector preserves provider identity" {
  let codex = codex_oauth_model(
    access_token="access",
    account_id="account",
    refresh_token="refresh",
    name=Gpt5_4,
  )
  assert_eq(codex.selector(), "codex/gpt-5.4")
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

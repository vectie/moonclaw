///|
test "channel_model_session_name stores provider-qualified codex name" {
  let model = @model.codex_oauth_model(
    access_token="access",
    account_id="account",
    refresh_token="refresh",
    name=@model.CodexModels::Gpt5_4,
  )
  inspect(channel_model_provider_override(model).unwrap_or(""), content="codex")
  inspect(channel_model_session_name(model), content="codex/gpt-5.4")
}

///|
test "resolve_channel_model_override prefers configured primary when session is empty" {
  inspect(
    resolve_channel_model_override(None, None, Some("codex/gpt-5.4")).unwrap_or(
      "",
    ),
    content="codex/gpt-5.4",
  )
}

///|
test "resolve_channel_model_override upgrades legacy bare model name" {
  inspect(
    resolve_channel_model_override(Some("gpt-5.4"), None, Some("codex/gpt-5.4")).unwrap_or(
      "",
    ),
    content="codex/gpt-5.4",
  )
}

///|
test "resolve_channel_model_override prefers configured primary over stale bare session model" {
  inspect(
    resolve_channel_model_override(
      Some("qwen3.5-plus"),
      None,
      Some("codex/gpt-5.4"),
    ).unwrap_or(""),
    content="codex/gpt-5.4",
  )
}

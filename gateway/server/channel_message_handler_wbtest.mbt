///|
test "channel_model_session_name stores provider-qualified codex name" {
  let model = @model.codex_oauth_model(
    access_token="access",
    account_id="account",
    refresh_token="refresh",
    name=Gpt5_6Sol,
  )
  inspect(channel_model_provider_override(model).unwrap_or(""), content="codex")
  inspect(channel_model_session_name(model), content="codex/gpt-5.6-sol")
}

///|
test "resolve_channel_model_override prefers configured primary when session is empty" {
  inspect(
    resolve_channel_model_override(None, None, Some("codex/gpt-5.6-sol")).unwrap_or(
      "",
    ),
    content="codex/gpt-5.6-sol",
  )
}

///|
test "resolve_channel_model_override ignores bare session model name" {
  inspect(
    resolve_channel_model_override(
      Some("gpt-5.6-sol"),
      None,
      Some("codex/gpt-5.6-sol"),
    ).unwrap_or(""),
    content="codex/gpt-5.6-sol",
  )
}

///|
test "resolve_channel_model_override keeps configured primary over bare session model" {
  inspect(
    resolve_channel_model_override(
      Some("qwen3.5-plus"),
      None,
      Some("codex/gpt-5.6-sol"),
    ).unwrap_or(""),
    content="codex/gpt-5.6-sol",
  )
}

///|
test "is_non_text_attachment_message recognizes Feishu file uploads" {
  inspect(
    is_non_text_attachment_message({
      id: "msg-1",
      channel: "feishu",
      from: "user-1",
      to: "chat-1",
      content: "[file] parcel.pdf",
      content_type: "file",
      timestamp: 1,
      thread_id: Some("thread-1"),
      reply_to: None,
      attachments: [
        {
          id: "file-1",
          mime_type: "application/pdf",
          url: "https://example.test/parcel.pdf",
          filename: Some("parcel.pdf"),
          size: Some(42),
        },
      ],
    }),
    content="true",
  )
}

///|
test "is_non_text_attachment_message does not treat text with attachments as file-only upload" {
  inspect(
    is_non_text_attachment_message({
      id: "msg-2",
      channel: "feishu",
      from: "user-1",
      to: "chat-1",
      content: "/resume use these assumptions",
      content_type: "text",
      timestamp: 1,
      thread_id: Some("thread-1"),
      reply_to: None,
      attachments: [
        {
          id: "file-1",
          mime_type: "application/pdf",
          url: "https://example.test/parcel.pdf",
          filename: Some("parcel.pdf"),
          size: Some(42),
        },
      ],
    }),
    content="false",
  )
}

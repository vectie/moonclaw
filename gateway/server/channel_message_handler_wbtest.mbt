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

///|
test "is_non_text_attachment_message recognizes Feishu file uploads" {
  inspect(
    is_non_text_attachment_message(@channel.Message::{
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
        @channel.Attachment::{
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
    is_non_text_attachment_message(@channel.Message::{
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
        @channel.Attachment::{
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

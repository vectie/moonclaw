///|
test "session route helpers preserve direct, channel, and orchestration key formats" {
  inspect(direct_session_key(None, "run-1"), content="run-1")
  inspect(
    direct_session_key(Some("chat-session"), "run-1"),
    content="chat-session",
  )
  inspect(
    channel_session_key("feishu", "acct-1", "chat-9", None),
    content="feishu:acct-1:chat-9",
  )
  inspect(
    channel_session_key("feishu", "acct-1", "chat-9", Some("thread-3")),
    content="feishu:acct-1:chat-9:thread-3",
  )
  inspect(
    channel_session_key(
      "feishu",
      "acct-1",
      "chat-9",
      Some("thread-3"),
      dm_scope="per-channel-peer",
    ),
    content="feishu:chat-9:thread-3",
  )
  inspect(
    channel_session_key(
      "feishu",
      "acct-1",
      "chat-9",
      Some("thread-3"),
      dm_scope="main",
    ),
    content="feishu:acct-1:main",
  )
  inspect(
    coordination_session_key("coord-7", "task-2"),
    content="coord:coord-7:task-2",
  )
  inspect(
    pipeline_stage_session_key("pipe-4", "write"),
    content="pipeline:pipe-4:write",
  )
}

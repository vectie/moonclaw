///|
test "parse_acp_chat_action recognizes control commands" {
  inspect(parse_acp_chat_action("/acp-targets"), content="Some(Targets)")
  inspect(
    parse_acp_chat_action("/acp-attach codex-main"),
    content="Some(Attach(\"codex-main\"))",
  )
  inspect(
    parse_acp_chat_action("/acp-run review this repo"),
    content="Some(Run(\"review this repo\"))",
  )
}

///|
test "render_acp_status reports missing and attached sessions" {
  inspect(
    render_acp_status("channel:feishu:chat-1", [], []),
    content="No ACP session is bound to this chat.\nUse /acp-attach <target_id>.",
  )
  inspect(
    render_acp_status(
      "channel:feishu:chat-1",
      [
        AcpSession::{
          id: "acp-session-1",
          target_id: "codex-main",
          session_key: "channel:feishu:chat-1",
          status: "attached",
          cwd: Some("/tmp/project"),
          workspace: None,
          created_at: 1,
          updated_at: 2,
          last_error: None,
          metadata: {},
        },
      ],
      [
        AcpRun::{
          id: "acp-run-1",
          session_id: "acp-session-1",
          session_key: "channel:feishu:chat-1",
          target_id: "codex-main",
          backend: "codex",
          status: "completed",
          created_at: 3,
          updated_at: 4,
          request: { "message": "Review repo" },
          plan: {},
          result: Some({
            "content": "repo reviewed",
            "stdout": "repo reviewed",
            "stderr": "",
          }),
          error: None,
        },
      ],
    ),
    content="ACP sessions for channel:feishu:chat-1:\nacp-session-1 -> codex-main [attached] @ /tmp/project | run acp-run-1 [completed] repo reviewed\n  stdout=repo reviewed",
  )
}

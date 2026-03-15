///|
async test "security runtime loads config and pairing state" {
  @fsx.with_temporary_directory("security-runtime-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      dir |> @pathx.join("moonclaw.json"),
      (
        {
          "session": { "dmScope": "main" },
          "commands": {
            "native": "off",
            "nativeSkills": "auto",
            "restart": false,
            "ownerDisplay": "raw",
          },
        } : Json).stringify(),
    )
    let runtime = SecurityRuntime::new(home=dir, cwd=dir)
    inspect(runtime.session_dm_scope(), content="main")
    inspect(runtime.command_policy().native, content="off")
    inspect(runtime.allows_native_commands(true), content="false")
    ignore(runtime.approve_pairing("feishu", "default", "chat-1", 10))
    inspect(runtime.is_paired("feishu", "default", "chat-1"), content="true")
  })
}

///|
test "security command parsing recognizes pairing and approval commands" {
  inspect(
    match parse_security_chat_action("/pair") {
      Some(SecurityChatAction::Pair) => "pair"
      _ => ""
    },
    content="pair",
  )
  inspect(
    match parse_security_chat_action("/approve tok-1") {
      Some(SecurityChatAction::Approve(token)) => token
      _ => ""
    },
    content="tok-1",
  )
}

///|
async test "security runtime tracks approval lifecycle" {
  @fsx.with_temporary_directory("security-runtime-XXXXXX", async fn(dir) {
    let runtime = SecurityRuntime::new(home=dir, cwd=dir)
    ignore(
      runtime.request_approval(
        "tok-1", "job.force_stop", "run-1", "feishu:default:chat-1", 10,
      ),
    )
    inspect(
      runtime
      .matching_pending_approval(
        "job.force_stop", "run-1", "feishu:default:chat-1",
      )
      .map(fn(record) { record.token })
      .unwrap_or(""),
      content="tok-1",
    )
    ignore(runtime.approve_token("tok-1", 11))
    inspect(
      runtime.consume_approval(
        "job.force_stop", "run-1", "feishu:default:chat-1",
      ),
      content="true",
    )
  })
}

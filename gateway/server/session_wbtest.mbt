///|
async test "SessionManager persists and reloads sessions" {
  @fsx.with_temporary_directory("gateway-session-XXXXXX", dir => {
    let session_dir = @path.Path(dir).join(@path.Path("sessions")).to_string()
    let manager = SessionManager::{ sessions: {}, session_dir }
    let entry = SessionEntry::{
      session_id: "conversation-1",
      updated_at: 42,
      channel: Some("feishu"),
      model_override: Some("default"),
      provider_override: None,
      cwd: Some("/repo"),
    }
    manager.save_entry("feishu:acct:chat", entry)

    let reloaded = SessionManager::{ sessions: {}, session_dir }
    reloaded.load()

    let loaded = match reloaded.get("feishu:acct:chat") {
      Some(loaded) => loaded
      None => fail("expected persisted session entry")
    }
    inspect(loaded.session_id, content="conversation-1")
    inspect(loaded.channel.unwrap_or(""), content="feishu")
    inspect(loaded.cwd.unwrap_or(""), content="/repo")
  })
}

///|
async test "SessionManager reset_and_save removes persisted sessions" {
  @fsx.with_temporary_directory("gateway-session-XXXXXX", dir => {
    let session_dir = @path.Path(dir).join(@path.Path("sessions")).to_string()
    let manager = SessionManager::{ sessions: {}, session_dir }
    manager.save_entry("session-1", SessionEntry::{
      session_id: "conversation-1",
      updated_at: 1,
      channel: None,
      model_override: None,
      provider_override: None,
      cwd: Some("/repo"),
    })
    inspect(manager.reset_and_save("session-1"), content="true")

    let reloaded = SessionManager::{ sessions: {}, session_dir }
    reloaded.load()

    inspect(reloaded.count(), content="0")
  })
}

///|
async test "SessionManager preserves unrelated persisted sessions across updates and reset" {
  @fsx.with_temporary_directory("gateway-session-XXXXXX", dir => {
    let session_dir = @path.Path(dir).join(@path.Path("sessions")).to_string()
    let manager = SessionManager::{ sessions: {}, session_dir }
    manager.save_entry("direct:user:1", SessionEntry::{
      session_id: "conversation-1",
      updated_at: 1,
      channel: None,
      model_override: Some("sonnet"),
      provider_override: None,
      cwd: Some("/repo/a"),
    })
    manager.save_entry("channel:feishu:default:chat-1", SessionEntry::{
      session_id: "conversation-2",
      updated_at: 2,
      channel: Some("feishu"),
      model_override: None,
      provider_override: Some("openai"),
      cwd: Some("/repo/b"),
    })
    inspect(manager.reset_and_save("direct:user:1"), content="true")

    let reloaded = SessionManager::{ sessions: {}, session_dir }
    reloaded.load()

    inspect(reloaded.count(), content="1")
    let preserved = match reloaded.get("channel:feishu:default:chat-1") {
      Some(entry) => entry
      None => fail("expected preserved channel session")
    }
    inspect(preserved.session_id, content="conversation-2")
    inspect(preserved.channel.unwrap_or(""), content="feishu")
    inspect(preserved.provider_override.unwrap_or(""), content="openai")
    inspect(reloaded.get("direct:user:1") is None, content="true")
  })
}

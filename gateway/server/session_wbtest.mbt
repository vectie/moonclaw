///|
async test "SessionManager persists and reloads sessions" {
  @fsx.with_temporary_directory("gateway-session-XXXXXX", dir => {
    let session_dir = @path.Path(dir).join(@path.Path("sessions")).to_string()
    let manager = SessionManager::{ sessions: {}, session_dir }
    let entry = SessionEntry::{
      session_id: "conversation-1",
      title: None,
      updated_at: 42,
      channel: Some("feishu"),
      model_override: Some("default"),
      provider_override: None,
      cwd: Some("/repo"),
      plan_mode: None,
      messages: [],
      linked_proposal_id: None,
      linked_run_id: None,
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
      title: None,
      updated_at: 1,
      channel: None,
      model_override: None,
      provider_override: None,
      cwd: Some("/repo"),
      plan_mode: None,
      messages: [],
      linked_proposal_id: None,
      linked_run_id: None,
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
      title: None,
      updated_at: 1,
      channel: None,
      model_override: Some("sonnet"),
      provider_override: None,
      cwd: Some("/repo/a"),
      plan_mode: None,
      messages: [],
      linked_proposal_id: None,
      linked_run_id: None,
    })
    manager.save_entry("channel:feishu:default:chat-1", SessionEntry::{
      session_id: "conversation-2",
      title: None,
      updated_at: 2,
      channel: Some("feishu"),
      model_override: None,
      provider_override: Some("openai"),
      cwd: Some("/repo/b"),
      plan_mode: None,
      messages: [],
      linked_proposal_id: None,
      linked_run_id: None,
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

///|
async test "SessionManager persists plan mode state" {
  @fsx.with_temporary_directory("gateway-session-XXXXXX", dir => {
    let session_dir = @path.Path(dir).join(@path.Path("sessions")).to_string()
    let manager = SessionManager::{ sessions: {}, session_dir }
    manager.save_entry("channel:feishu:default:chat-1:thread-1", SessionEntry::{
      session_id: "conversation-2",
      title: None,
      updated_at: 2,
      channel: Some("feishu"),
      model_override: None,
      provider_override: Some("openai"),
      cwd: Some("/repo/b"),
      plan_mode: Some(PlanModeState::{
        request_text: "Analyze the parcel.",
        notes: ["Focus on land comps."],
        latest_candidate: @job.draft_job_proposal(
          "plan-preview", "Analyze the parcel.", 1,
        ),
        updated_at: 2,
      }),
      messages: [],
      linked_proposal_id: None,
      linked_run_id: None,
    })
    let reloaded = SessionManager::{ sessions: {}, session_dir }
    reloaded.load()
    let preserved = match
      reloaded.get("channel:feishu:default:chat-1:thread-1") {
      Some(entry) => entry
      None => fail("expected preserved channel session")
    }
    inspect(
      preserved.plan_mode.map(fn(state) { state.request_text }).unwrap_or(""),
      content="Analyze the parcel.",
    )
    inspect(
      preserved.plan_mode.map(fn(state) { state.notes.join(",") }).unwrap_or(""),
      content="Focus on land comps.",
    )
  })
}

///|
async test "SessionManager persists cowork messages and linked ids" {
  @fsx.with_temporary_directory("gateway-session-XXXXXX", dir => {
    let session_dir = @path.Path(dir).join(@path.Path("sessions")).to_string()
    let manager = SessionManager::{ sessions: {}, session_dir }
    manager.save_entry("cowork:session-1", SessionEntry::{
      session_id: "conversation-9",
      title: Some("Parcel Planning"),
      updated_at: 9,
      channel: None,
      model_override: Some("default"),
      provider_override: None,
      cwd: Some("/repo/c"),
      plan_mode: None,
      messages: [
        SessionMessage::{
          id: "msg-1",
          role: "user",
          kind: "user",
          content: "Please draft a plan.",
          timestamp: 9,
          metadata: {},
        },
      ],
      linked_proposal_id: Some("proposal-9"),
      linked_run_id: Some("run-9"),
    })
    let reloaded = SessionManager::{ sessions: {}, session_dir }
    reloaded.load()
    let preserved = match reloaded.get("cowork:session-1") {
      Some(entry) => entry
      None => fail("expected preserved cowork session")
    }
    inspect(preserved.messages.length(), content="1")
    inspect(preserved.messages[0].content, content="Please draft a plan.")
    inspect(preserved.linked_proposal_id.unwrap_or(""), content="proposal-9")
    inspect(preserved.linked_run_id.unwrap_or(""), content="run-9")
  })
}

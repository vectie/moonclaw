///|
test "goal journal record identity uses canonical event_id" {
  let a = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "a",
    "timestamp": 1,
  })
  let b = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "b",
    "timestamp": 1,
  })
  inspect(a, content="event:a")
  inspect(b, content="event:b")
}

///|
test "goal journal record identity is timestamp independent" {
  let first = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "same",
    "timestamp": 1,
  })
  let second = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "same",
    "timestamp": 2,
  })
  inspect(first == second, content="true")
  inspect(first, content="event:same")
}

///|
test "goal journal record identity rejects blank event_id" {
  try
    mooncode_journal_record_id(mooncode_journal_goal_event(), {
      "kind": "mooncode.goal.changed",
      "event_id": "",
      "timestamp": 1,
    })
  catch {
    InvalidJournal(_) => ()
  } noraise {
    _ => fail("expected InvalidJournal")
  }
}

///|
test "goal journal record identity rejects padded event_id" {
  try
    mooncode_journal_record_id(mooncode_journal_goal_event(), {
      "kind": "mooncode.goal.changed",
      "event_id": " padded ",
      "timestamp": 1,
    })
  catch {
    InvalidJournal(_) => ()
  } noraise {
    _ => fail("expected InvalidJournal")
  }
}

///|
test "unrelated event retains timestamp fallback identity" {
  let id = mooncode_journal_record_id(mooncode_journal_event(), {
    "kind": "other.event",
    "timestamp": "2025-01-01T00:00:00Z",
  })
  inspect(id, content="event::other.event:null")
}

///|
fn goal_gate_snapshot(session_id : String, root : String) -> Json {
  let binding = MoonCodeSessionBinding::{
    session_id,
    book_root: root,
    workspace_id: "book-code-lab",
    workspace_name: "Code Lab",
    model: "",
    model_workspace: "",
    command_count: 2,
    first_user_prompt: "Build a durable MoonCode tool",
    custom_title: "",
    last_command_id: "cmd-2",
    last_updated: @clock.Timestamp::from_ms(42L),
    runtime_service_running: false,
    runtime_service_wake_pending: false,
    runtime_service_task: None,
    active_command_id: "",
    events: @broadcast.Broadcast::new(),
  }
  mooncode_session_snapshot(binding)
}

///|
fn goal_gate_dir(root : String, id : String, archived : Bool) -> String {
  mooncode_session_dir_by_safe_id(root, mooncode_safe_session_id(id), archived~)
}

///|
async fn goal_gate_write_snapshot(
  root : String,
  id : String,
  archived : Bool,
  snapshot : Json,
) -> Unit {
  let dir = goal_gate_dir(root, id, archived)
  @fsx.make_directory(dir, recursive=true, exists_ok=true)
  @fsx.write_to_file(dir + "/session.json", snapshot.stringify())
}

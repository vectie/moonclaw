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
    runtime: MoonCodeSessionRuntime::new(),
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

///|
fn mooncode_parse_journal_text(
  text : String,
  path : String,
) -> Array[Json] raise MoonCodeJournalError {
  let records : Array[Json] = []
  // An empty committed prefix contains no records. This must be handled before
  // splitting because split produces one empty line, while blank lines in any
  // nonempty journal remain corruption.
  if text.is_empty() {
    return records
  }
  let lines = text.split("\n").collect()
  let line_count = if text.has_suffix("\n") {
    lines.length() - 1
  } else {
    lines.length()
  }
  let mut cursor = MoonCodeJournalSequence::zero()
  for index = 0; index < line_count; index = index + 1 {
    let line = lines[index]
    if line.is_empty() {
      raise InvalidJournal(
        "Invalid journal `\{path}` line \{index + 1}: blank line",
      )
    }
    try {
      let (record, next) = mooncode_journal_stream_record(
        line.to_owned(),
        cursor,
      )
      records.push(record)
      cursor = next
    } catch {
      error =>
        raise InvalidJournal(
          "Invalid journal `\{path}` line \{index + 1}: \{error}",
        )
    }
  }
  records
}

///|
/// Compatibility projection for the legacy goal-supervisor contract, whose
/// basis sequence remains an Int.
fn mooncode_journal_last_sequence(
  records : Array[Json],
) -> Int32 raise MoonCodeJournalError {
  let text = mooncode_journal_last_sequence_exact(records).text()
  @string.parse_int(text) catch {
    _ =>
      raise InvalidJournal(
        "MoonCode goal supervisor sequence exceeds its legacy Int contract",
      )
  }
}

///|
#warnings("-unused_value")
fn mooncode_journal_checked_next_sequence(
  last_sequence : Int32,
) -> Int32 raise MoonCodeJournalError {
  if last_sequence == 2147483647 {
    raise InvalidJournal("MoonCode journal sequence is exhausted")
  }
  last_sequence + 1
}

///|
fn mooncode_journal_sequence(record : Json) -> Int32 raise MoonCodeJournalError {
  match mooncode_journal_json_field(record, "sequence") {
    Some(Number(value, ..)) => {
      if value != value || value < 1.0 || value > 2147483647.0 {
        raise InvalidJournal("MoonCode journal record has invalid sequence")
      }
      let sequence = value.to_int()
      if sequence.to_double() != value {
        raise InvalidJournal("MoonCode journal record has invalid sequence")
      }
      sequence
    }
    Some(String(text)) => {
      let sequence = @string.parse_int(text) catch {
        _ => raise InvalidJournal("test sequence exceeds Int range")
      }
      if sequence < 1 || sequence.to_string() != text {
        raise InvalidJournal("MoonCode journal record has invalid sequence")
      }
      sequence
    }
    _ => raise InvalidJournal("MoonCode journal record has invalid sequence")
  }
}

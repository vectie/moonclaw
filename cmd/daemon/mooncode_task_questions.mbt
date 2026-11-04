///|
fn mooncode_task_pending_questions(records : Array[Json]) -> Array[Json] raise {
  let events = mooncode_journal_entries(records, mooncode_journal_event())
  let receipts = mooncode_journal_entries(
    records,
    mooncode_journal_runtime_receipt(),
  )
  events.filter(event => {
    let id = mooncode_json_string(event, "question_id", default="")
    mooncode_json_string(event, "kind", default="") == "session.question.asked" &&
    !receipts.any(receipt => {
      mooncode_json_string(receipt, "command_id", default="") ==
      mooncode_json_string(event, "command_id", default="") &&
      mooncode_runtime_receipt_status_delivered(
        mooncode_json_string(receipt, "status", default=""),
      )
    }) &&
    !events.any(answer => {
      mooncode_json_string(answer, "kind", default="") ==
      "session.question.answered" &&
      mooncode_json_string(answer, "question_id", default="") == id
    })
  })
}

///|
async fn mooncode_task_ask_user(
  session_id : String,
  root : String,
  command_id : String,
  arguments : Json,
  now : @clock.Timestamp,
) -> Json {
  let question = mooncode_json_string(arguments, "question", default="")
    .trim()
    .to_owned()
  let key = mooncode_json_string(arguments, "id", default="").trim().to_owned()
  if question == "" || key == "" {
    return mooncode_tool_error_result(
      "ask_user",
      message="Provide a stable question id and a question",
    )
  }
  let id = command_id + ":" + key
  let existing = mooncode_journal_entries(
    mooncode_read_session_journal(root, session_id),
    mooncode_journal_event(),
  )
  if !existing.any(event => {
      mooncode_json_string(event, "id", default="") == "question:" + id
    }) {
    ignore(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "question:" + id,
          "kind": "session.question.asked",
          "question_id": id,
          "session_id": session_id,
          "command_id": command_id,
          "question": question,
          "options": Json::array(
            mooncode_json_array_items(arguments, "options"),
          ),
          "title": "Your input is needed",
          "detail": question,
          "lane": "session",
          "status": "waiting",
          "created_at": now,
        },
      ),
    )
  }
  for ;; {
    let journal = mooncode_read_session_journal(root, session_id)
    let events = mooncode_journal_entries(journal, mooncode_journal_event())
    for event in events {
      if mooncode_json_string(event, "kind", default="") ==
        "session.question.answered" &&
        mooncode_json_string(event, "question_id", default="") == id {
        return mooncode_tool_ok_result(
          "ask_user",
          message="User answered",
          output=mooncode_json_string(event, "answer", default=""),
          metadata={ "question_id": id },
        )
      }
    }
    let commands = mooncode_journal_entries(journal, mooncode_journal_command())
    let mut saw_current = false
    let mut cancelled = false
    for item in commands {
      if mooncode_runtime_command_entry_id(item) == command_id {
        saw_current = true
      }
      let body = mooncode_json_object_field_or_empty(item, "command")
      if saw_current &&
        mooncode_json_string(body, "command", default="") == "cancel" {
        cancelled = true
      }
    }
    if cancelled {
      return mooncode_tool_error_result(
        "ask_user",
        message="Task cancellation requested",
      )
    }
    @async.sleep(750)
  }
}

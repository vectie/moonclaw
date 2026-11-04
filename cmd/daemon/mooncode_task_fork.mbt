///|
fn mooncode_task_fork_identity(
  value : Json,
  source : String,
  target : String,
) -> Json {
  match value {
    Object(fields) => {
      let result : Map[String, Json] = Map([])
      for key, item in fields {
        result[key] = if key == "session_id" &&
          item is String(id) &&
          id == source {
          Json(target)
        } else {
          mooncode_task_fork_identity(item, source, target)
        }
      }
      Json::object(result)
    }
    Array(items) =>
      Json::array(
        items.map(item => mooncode_task_fork_identity(item, source, target)),
      )
    _ => value
  }
}

///|
/// Forks copy settled turns, preserving their native receipts and tool evidence.
/// Queued/running commands are never replayed in the new conversation.
async fn Daemon::mooncode_task_fork(
  self : Daemon,
  source : String,
  root : String,
  body : Json,
) -> Json {
  let journal = mooncode_read_session_journal(root, source)
  let receipts = mooncode_journal_entries(
    journal,
    mooncode_journal_runtime_receipt(),
  )
  let settled = receipts
    .filter(item => {
      mooncode_runtime_receipt_status_delivered(
        mooncode_json_string(item, "status", default=""),
      )
    })
    .map(item => mooncode_json_string(item, "command_id", default=""))
  let commands = mooncode_journal_entries(journal, mooncode_journal_command())
  let before = mooncode_json_string(body, "before_command_id", default="")
  let retained : Array[String] = []
  let mut draft = ""
  let mut draft_images : Array[Json] = []
  for item in commands {
    let id = mooncode_runtime_command_entry_id(item)
    if id == before {
      let command = mooncode_json_object_field_or_empty(item, "command")
      draft = mooncode_conversation_command_message(
        command,
        mooncode_json_object_field_or_empty(command, "packet"),
      )
      draft_images = mooncode_json_array_items(command, "content_parts").filter(part => {
          mooncode_json_string(part, "type", default="") == "image"
        },
      )
      break
    }
    if settled.contains(id) {
      retained.push(id)
    }
  }
  if before != "" &&
    !commands.any(item => mooncode_runtime_command_entry_id(item) == before) {
    raise mooncode_session_management_error(
      404, "Not Found", "The selected turn is no longer available", source,
    )
  }
  let target = "fork-" + self.uuid.v4().to_string()
  for record in journal {
    let payload = mooncode_json_object_field_or_empty(record, "payload")
    let kind = mooncode_json_string(record, "record_kind", default="")
    let command_id = mooncode_json_string(payload, "command_id", default="")
    let event_kind = mooncode_json_string(payload, "kind", default="")
    if command_id != "" &&
      retained.contains(command_id) &&
      !event_kind.has_prefix("mooncode.goal.") &&
      event_kind != mooncode_worker_record_kind() {
      let mut copied = payload
      if kind == mooncode_journal_command() {
        for command in commands {
          if mooncode_runtime_command_entry_id(command) == command_id {
            copied = command
          }
        }
      }
      mooncode_append_session_journal(
        root,
        target,
        kind,
        mooncode_task_fork_identity(copied, source, target),
      )
    }
  }
  mooncode_append_session_journal(root, target, mooncode_journal_event(), {
    "id": "fork-origin-" + target,
    "kind": "session.forked",
    "session_id": target,
    "source_session_id": source,
    "created_at": self.clock.now(),
    "lane": "session",
    "status": "done",
    "title": "Conversation forked",
    "detail": "Continues from the completed turns in the original chat.",
    "inherited_context": if before == "" {
      let context = match mooncode_task_conversation_context(journal) {
        Array(items) => items
        _ => []
      }
      Json::array(
        context.filter(item => {
          let id = mooncode_json_string(item, "command_id", default="")
          !retained.contains(id) &&
          receipts.any(receipt => {
            mooncode_json_string(receipt, "command_id", default="") == id
          })
        }),
      )
    } else {
      Json::null()
    },
  })
  let parent = self.mooncode_binding_for_session(source)
  ignore(parent.bind_book_root(root))
  parent.restore_session_metadata()
  let child = self.mooncode_binding_for_session(target)
  child.book_root = root
  child.workspace_id = parent.workspace_id
  child.workspace_name = parent.workspace_name
  child.model = parent.model
  child.model_workspace = parent.model_workspace
  child.command_count = retained.length()
  child.first_user_prompt = parent.first_user_prompt
  child.custom_title = mooncode_json_string(
    body,
    "title",
    default="Another approach",
  )
  child.last_updated = self.clock.now()
  self.mooncode_persist_session(child)
  self.mooncode_task_controls_projection(target, root)
  |> mooncode_json_object_with_field("forked_from", Json(source))
  |> mooncode_json_object_with_field("draft", Json(draft))
  |> mooncode_json_object_with_field("draft_images", Json::array(draft_images))
}

///|
fn mooncode_task_conversation_context(journal : Array[Json]) -> Json raise {
  let turns = mooncode_conversation_turns(
    mooncode_journal_entries(journal, mooncode_journal_command()),
    mooncode_journal_entries(journal, mooncode_journal_runtime_receipt()),
    mooncode_journal_entries(journal, mooncode_journal_event()),
  )
  let messages : Array[Json] = []
  for index, turn in turns {
    if mooncode_conversation_turn_visible(turn) {
      let canonical = mooncode_conversation_turn_json(turn, ordinal=index)
      messages.push({
        "user": turn.user,
        "assistant": mooncode_json_object_field_or_empty(canonical, "assistant"),
        "status": mooncode_json_string(canonical, "status", default=""),
        "command_id": turn.command_id,
        "usage": turn.usage,
      })
    }
  }
  Json::array(messages)
}

///|
async fn mooncode_task_attach_context(
  root : String,
  session_id : String,
  command : Json,
) -> Json {
  let journal = mooncode_read_session_journal(root, session_id)
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  let mut plan = ""
  let mut inherited = Json::null()
  let mut recap = ""
  let mut anchor = ""
  for event in events {
    match mooncode_json_string(event, "kind", default="") {
      "session.task.plan" =>
        plan = mooncode_json_string(event, "plan", default="")
      "session.task.recap" => {
        recap = mooncode_json_string(event, "message", default="")
        anchor = mooncode_json_string(event, "recap_anchor", default="")
      }
      "session.forked" =>
        inherited = match event {
          Object(fields) =>
            fields.get("inherited_context").unwrap_or(Json::null())
          _ => Json::null()
        }
      _ => ()
    }
  }
  let current = mooncode_command_id(command)
  let conversation = mooncode_task_conversation_context(journal)
  let mut after_anchor = anchor == ""
  let history = match conversation {
    Array(items) =>
      Json::array(
        items.filter(item => {
          let id = mooncode_json_string(item, "command_id", default="")
          if id == anchor {
            after_anchor = true
            false
          } else {
            after_anchor && id != current
          }
        }),
      )
    _ => Json::null()
  }
  mooncode_json_object_with_field(command, "task_context", {
    "plan": plan,
    "previous_turns": history,
    "fork_context": if recap == "" {
      inherited
    } else {
      Json::null()
    },
    "recap": recap,
    "questions_and_answers": Json::array(
      events.filter(event => {
        let kind = mooncode_json_string(event, "kind", default="")
        kind == "session.question.asked" || kind == "session.question.answered"
      }),
    ),
  })
}

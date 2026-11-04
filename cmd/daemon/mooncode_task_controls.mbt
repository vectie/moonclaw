///|
/// Queue changes are journal events, so the runtime, replay and task panel all
/// consume the same order and content. Accepted command identities stay stable.
fn mooncode_task_controls_project_commands(
  entries : Array[Json],
  records : Array[Json],
) -> Array[Json] {
  let mut result = entries.copy()
  for record in records {
    if mooncode_json_string(record, "record_kind", default="") != "event" {
      continue
    }
    let event = mooncode_json_object_field_or_empty(record, "payload")
    if mooncode_json_string(event, "kind", default="") !=
      "session.queue.changed" {
      continue
    }
    let id = mooncode_json_string(event, "target_command_id", default="")
    match mooncode_json_string(event, "action", default="") {
      "remove" =>
        result = result.filter(item => {
          mooncode_runtime_command_entry_id(item) != id
        })
      "edit" | "guide_now" =>
        result = result.map(item => {
          if mooncode_runtime_command_entry_id(item) != id {
            item
          } else {
            let text = mooncode_json_string(event, "message", default="")
            let command = mooncode_json_object_field_or_empty(item, "command")
            let packet = mooncode_json_object_field_or_empty(command, "packet")
              |> mooncode_json_object_with_field("message", Json(text))
            let payload = mooncode_json_object_field_or_empty(
                command, "payload",
              )
              |> mooncode_json_object_with_field("message", Json(text))
            let parts = mooncode_json_array_items(command, "content_parts").filter(part => {
                mooncode_json_string(part, "type", default="") != "text"
              },
            )
            if !parts.is_empty() {
              parts.insert(0, { "type": "text", "text": text })
            }
            let updated = command
              |> mooncode_json_object_with_field("text", Json(text))
              |> mooncode_json_object_with_field("packet", packet)
              |> mooncode_json_object_with_field("payload", payload)
            let updated = if mooncode_json_string(event, "action", default="") ==
              "guide_now" {
              mooncode_json_object_with_field(updated, "command", Json("steer"))
            } else {
              updated
            }
            let updated = if parts.is_empty() {
              updated
            } else {
              mooncode_json_object_with_field(
                updated,
                "content_parts",
                Json::array(parts),
              )
            }
            mooncode_json_object_with_field(item, "command", updated)
          }
        })
      "reorder" => {
        let order = mooncode_json_array_items(event, "order")
        let moved = result.filter(item => {
          order.any(id => {
            id is String(value) &&
            value == mooncode_runtime_command_entry_id(item)
          })
        })
        result = result.filter(item => {
          !order.any(id => {
            id is String(value) &&
            value == mooncode_runtime_command_entry_id(item)
          })
        })
        for id in order {
          for item in moved {
            if id is String(value) &&
              value == mooncode_runtime_command_entry_id(item) {
              result.push(item)
            }
          }
        }
      }
      _ => ()
    }
  }
  result
}

///|
fn mooncode_task_controls_pending(records : Array[Json]) -> Array[Json] raise {
  let receipts = mooncode_journal_entries(
    records,
    mooncode_journal_runtime_receipt(),
  )
  mooncode_journal_entries(records, mooncode_journal_command()).filter(item => {
    let id = mooncode_runtime_command_entry_id(item)
    let command = mooncode_json_object_field_or_empty(item, "command")
    mooncode_json_string(command, "command", default="prompt") == "prompt" &&
    !receipts.any(receipt => {
      mooncode_json_string(receipt, "command_id", default="") == id
    })
  })
}

///|
async fn Daemon::mooncode_task_controls(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read()
  if mooncode_json_string(body, "action", default="") == "generate_image" {
    self.mooncode_start_image_job(group, session_id.to_owned(), body)
  }
  if mooncode_json_string(body, "action", default="") == "guide_worker" ||
    mooncode_json_string(body, "action", default="") == "stop_worker" {
    self.mooncode_task_control_worker(group, session_id.to_owned(), body)
  }
  let body = if mooncode_json_string(body, "action", default="") ==
    "generate_image" ||
    mooncode_json_string(body, "action", default="") == "guide_worker" ||
    mooncode_json_string(body, "action", default="") == "stop_worker" {
    mooncode_json_object_with_field(body, "action", Json("inspect"))
  } else {
    body
  }
  let result = self.mooncode_task_controls_response(session_id.to_owned(), body) catch {
    InvalidJournal(message) =>
      raise mooncode_session_management_error(
        409,
        "Conflict",
        message,
        session_id.to_owned(),
      )
    error => raise error
  }
  if mooncode_json_string(body, "action", default="") == "answer_question" {
    ignore(
      self.mooncode_start_runtime_service(
        group~,
        session_id.to_owned(),
        mooncode_json_string(body, "book_root", default=""),
        {},
      ),
    )
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}

///|
async fn Daemon::mooncode_task_control_worker(
  self : Daemon,
  group : @async.TaskGroup[Unit],
  parent : String,
  body : Json,
) -> Unit {
  let root = mooncode_json_string(body, "book_root", default="")
  let worker_id = mooncode_json_string(body, "worker_id", default="")
  let records = mooncode_worker_records(root, parent)
  let selected = records.filter(record => {
    mooncode_json_string(record, "worker_id", default="") == worker_id
  })
  guard selected.length() == 1 else {
    raise mooncode_session_management_error(
      404, "Not Found", "Agent not found in this task", parent,
    )
  }
  let record = selected[0]
  let child = mooncode_json_string(record, "child_session_id", default="")
  let child_root = mooncode_json_string(record, "child_book_root", default="")
  let binding = self.mooncode_binding_for_session(child)
  ignore(binding.bind_book_root(child_root))
  binding.restore_session_metadata()
  let stop = mooncode_json_string(body, "action", default="") == "stop_worker"
  let message = mooncode_json_string(body, "message", default="")
    .trim()
    .to_owned()
  if !stop && message == "" {
    raise mooncode_session_management_error(
      400, "Bad Request", "Enter guidance for this agent", parent,
    )
  }
  let command_id = "worker-control-" + self.uuid.v4().to_string()
  ignore(
    self.mooncode_queue_command_response(
      session_id=child,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": child,
        "book_root": child_root,
        "command": if stop {
          "cancel"
        } else {
          "steer"
        },
        "model": binding.model,
        "model_workspace": binding.model_workspace,
        "text": message,
        "packet": { "command_id": command_id },
      },
      queue_source="moondesk-agent-team",
    ),
  )
  ignore(self.mooncode_start_runtime_service(group~, child, child_root, {}))
}

///|
async fn Daemon::mooncode_task_controls_response(
  self : Daemon,
  session_id : String,
  body : Json,
) -> Json {
  let root = mooncode_json_string(body, "book_root", default="")
  guard self.mooncode_session_record(session_id, root) is Some(_) else {
    raise mooncode_session_management_error(
      404, "Not Found", "Chat not found", session_id,
    )
  }
  let action = mooncode_json_string(body, "action", default="inspect")
  if action == "load_image" {
    let path = mooncode_json_string(body, "path", default="")
    let events = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_event(),
    )
    guard events.any(event => {
      mooncode_json_string(event, "kind", default="") == "session.image.job" &&
      mooncode_json_array_items(event, "paths").contains(Json(path))
    }) else {
      raise mooncode_session_management_error(
        404, "Not Found", "Image not found in this conversation", session_id,
      )
    }
    let bytes = @fs.read_file(@pathx.join(root, path))
    return {
      "path": path,
      "media_type": "image/png",
      "data_base64": @base64.encode(bytes.binary()),
    }
  }
  if action == "fork" {
    return self.mooncode_task_fork(session_id, root, body)
  }
  if action == "answer_question" {
    let id = mooncode_json_string(body, "question_id", default="")
    let answer = mooncode_json_string(body, "answer", default="")
      .trim()
      .to_owned()
    let answered_at = self.clock.now()
    let _ : Unit = mooncode_session_journal_transaction(root, session_id, fn(
      records,
    ) raise {
      guard answer != "" &&
        mooncode_task_pending_questions(records).any(item => {
          mooncode_json_string(item, "question_id", default="") == id
        }) else {
        raise InvalidJournal("Enter an answer to a pending question")
      }
      Append(
        mooncode_journal_event(),
        {
          "id": "answer:" + id,
          "kind": "session.question.answered",
          "question_id": id,
          "session_id": session_id,
          "answer": answer,
          "title": "Question answered",
          "detail": answer,
          "lane": "session",
          "status": "done",
          "created_at": answered_at,
        },
        (),
      )
    })
  } else if action == "save_memory" {
    let path = mooncode_personal_memory_path(self.home)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    @fsx.write_to_file(path, mooncode_json_string(body, "memory", default=""))
  } else if action == "set_goal" {
    let response = mooncode_goal_runtime_api_put_internal(
      root,
      session_id,
      {
        "protocol": mooncode_goal_runtime_protocol_v1,
        "contract": mooncode_goal_runtime_contract_v1,
        "session_id": session_id,
        "goal_id": "goal-" + session_id,
        "objective": mooncode_json_string(body, "objective", default=""),
        "criteria": Json::array(mooncode_json_array_items(body, "criteria")),
      },
      self.clock.now().truncate_to_s(),
    )
    if response.status_code >= 400 {
      raise mooncode_session_management_error(
        response.status_code,
        "Goal unavailable",
        response.body.stringify(),
        session_id,
      )
    }
  } else if action == "edit" ||
    action == "guide_now" ||
    action == "remove" ||
    action == "reorder" ||
    action == "set_plan" ||
    action == "save_recap" {
    let event_id = "task-control-" + self.uuid.v4().to_string()
    let now = self.clock.now()
    let _ : Unit = mooncode_session_journal_transaction(root, session_id, fn(
      records,
    ) raise {
      let pending = mooncode_task_controls_pending(records)
      let target = mooncode_json_string(body, "target_command_id", default="")
      let mut recap_anchor = ""
      if action == "save_recap" &&
        mooncode_json_string(body, "message", default="").trim() != "" {
        let receipts = mooncode_journal_entries(
          records,
          mooncode_journal_runtime_receipt(),
        )
        for
          command in mooncode_journal_entries(
            records,
            mooncode_journal_command(),
          ) {
          let id = mooncode_runtime_command_entry_id(command)
          if receipts.any(receipt => {
              mooncode_json_string(receipt, "command_id", default="") == id &&
              mooncode_runtime_receipt_status_delivered(
                mooncode_json_string(receipt, "status", default=""),
              )
            }) {
            recap_anchor = id
          }
        }
      }
      if action == "edit" || action == "remove" || action == "guide_now" {
        guard pending.any(item => {
          mooncode_runtime_command_entry_id(item) == target
        }) else {
          raise InvalidJournal(
            "That message has already started. Refresh the queue or guide the running task.",
          )
        }
        if (action == "edit" || action == "guide_now") &&
          mooncode_json_string(body, "message", default="").trim().is_empty() {
          raise InvalidJournal("Enter a message before saving")
        }
      }
      if action == "guide_now" {
        let control = mooncode_runtime_control_state_from_logs(
          session_id,
          root,
          mooncode_journal_entries(records, mooncode_journal_command()),
          mooncode_journal_entries(records, mooncode_journal_runtime_receipt()),
          journal_path=mooncode_session_journal_path(root, session_id),
        )
        if mooncode_json_string(control, "active_turn_id", default="") == "" {
          raise InvalidJournal(
            "No task is running. Use Send next to prioritize this message.",
          )
        }
        let selected = pending.filter(item => {
            mooncode_runtime_command_entry_id(item) == target
          })[0]
        if mooncode_json_array_items(
            mooncode_json_object_field_or_empty(selected, "command"),
            "content_parts",
          ).any(part => {
            mooncode_json_string(part, "type", default="") == "image"
          }) {
          raise InvalidJournal(
            "Image messages must run as their own turn. Use Send next to keep the attachments.",
          )
        }
      }
      if action == "reorder" {
        let order = mooncode_json_array_items(body, "order")
        guard order.length() == pending.length() &&
          pending.all(item => {
            let id = mooncode_runtime_command_entry_id(item)
            order.filter(value => value is String(text) && text == id).length() ==
            1
          }) else {
          raise InvalidJournal("The queue changed. Refresh it and try again.")
        }
      }
      let event : Json = {
        "id": event_id,
        "session_id": session_id,
        "kind": if action == "set_plan" {
          "session.task.plan"
        } else if action == "save_recap" {
          "session.task.recap"
        } else {
          "session.queue.changed"
        },
        "lane": "session",
        "status": "done",
        "created_at": now,
        "action": action,
        "target_command_id": target,
        "message": mooncode_json_string(body, "message", default=""),
        "order": Json::array(mooncode_json_array_items(body, "order")),
        "plan": mooncode_json_string(body, "plan", default=""),
        "recap_anchor": recap_anchor,
        "title": if action == "set_plan" {
          "Task plan updated"
        } else if action == "save_recap" {
          "Conversation recap saved"
        } else {
          "Queued message updated"
        },
      }
      Append(mooncode_journal_event(), event, ())
    })
  } else if action != "inspect" {
    raise mooncode_session_management_error(
      400, "Bad Request", "Unknown task action", session_id,
    )
  }
  self.mooncode_task_controls_projection(session_id, root)
}

///|
async fn Daemon::mooncode_task_controls_projection(
  self : Daemon,
  session_id : String,
  root : String,
) -> Json {
  let journal = mooncode_read_session_journal(root, session_id)
  let pending : Array[Json] = mooncode_task_controls_pending(journal).map(item => {
    let command = mooncode_json_object_field_or_empty(item, "command")
    {
      "id": mooncode_runtime_command_entry_id(item),
      "message": mooncode_conversation_command_message(
        command,
        mooncode_json_object_field_or_empty(command, "packet"),
      ),
      "context_path": mooncode_json_string(command, "context_path", default=""),
      "image_count": mooncode_json_array_items(command, "content_parts")
      .filter(part => mooncode_json_string(part, "type", default="") == "image")
      .length(),
    }
  })
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  let mut plan = ""
  let mut recap = ""
  for event in events {
    if mooncode_json_string(event, "kind", default="") == "session.task.plan" {
      plan = mooncode_json_string(event, "plan", default="")
    }
    if mooncode_json_string(event, "kind", default="") == "session.task.recap" {
      recap = mooncode_json_string(event, "message", default="")
    }
  }
  let workers : Array[Json] = []
  for worker in mooncode_worker_records(root, session_id) {
    workers.push(mooncode_worker_result_projection(worker))
  }
  let goal = mooncode_goal_runtime_api_get_internal(root, session_id)
  let control = mooncode_runtime_control_state_from_logs(
    session_id,
    root,
    mooncode_journal_entries(journal, mooncode_journal_command()),
    mooncode_journal_entries(journal, mooncode_journal_runtime_receipt()),
    journal_path=mooncode_session_journal_path(root, session_id),
  )
  let binding = self.mooncode_binding_for_session(session_id)
  ignore(binding.bind_book_root(root))
  binding.restore_session_metadata()
  {
    "owner": "moonclaw",
    "session_id": session_id,
    "queue": Json::array(pending),
    "plan": plan,
    "recap": recap,
    "goal": if goal.status_code == 200 {
      goal.body
    } else {
      Json::null()
    },
    "workers": Json::array(workers),
    "image_jobs": Json::array(mooncode_image_job_projection(events)),
    "personal_memory": mooncode_personal_memory_read(self.home),
    "questions": Json::array(mooncode_task_pending_questions(journal)),
    "context": {
      "book_root": root,
      "workspace_id": binding.workspace_id,
      "model": binding.model,
      "active_command_id": mooncode_json_string(
        control,
        "active_turn_id",
        default="",
      ),
      "message_count": mooncode_journal_entries(
        journal,
        mooncode_journal_command(),
      ).length(),
      "conversation": mooncode_task_conversation_context(journal),
    },
  }
}

///|
fn mooncode_personal_memory_path(home : String) -> String {
  @pathx.join(home, ".moonclaw/personal-memory.md")
}

///|
async fn mooncode_personal_memory_read(home : String) -> String {
  let path = mooncode_personal_memory_path(home)
  if @fsx.exists(path) {
    @fsx.read_file(path)
  } else {
    ""
  }
}

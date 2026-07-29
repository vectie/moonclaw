///|
fn mooncode_worker_record_kind() -> String {
  "mooncode.worker.link.v1"
}

///|
fn mooncode_worker_specs(arguments : Json) -> Array[Json] {
  mooncode_json_array_items(arguments, "workers")
}

///|
fn mooncode_worker_roots_overlap(first : String, second : String) -> Bool {
  first == second ||
  first.has_prefix(second + "/") ||
  second.has_prefix(first + "/")
}

///|
async fn mooncode_worker_records(
  parent_book_root : String,
  parent_session_id : String,
) -> Array[Json] {
  mooncode_journal_entries(
    mooncode_read_session_journal(parent_book_root, parent_session_id),
    mooncode_journal_event(),
  ).filter(record => {
    mooncode_json_string(record, "kind", default="") ==
    mooncode_worker_record_kind()
  })
}

///|
async fn mooncode_validate_spawn_workers(
  parent_book_root : String,
  existing_records : Array[Json],
  arguments : Json,
) -> Json {
  let workers = mooncode_worker_specs(arguments)
  let errors : Array[Json] = []
  let seen_ids : Map[String, Bool] = {}
  let seen_roots : Map[String, Bool] = {}
  let normalized_parent_root = @pathx.normalize(parent_book_root)
  let parent_root = @fsx.resolve(normalized_parent_root) catch {
    _ => normalized_parent_root
  }
  for record in existing_records {
    let worker_id = mooncode_json_string(record, "worker_id", default="")
    if worker_id != "" {
      seen_ids[worker_id] = true
    }
  }
  if workers.length() == 0 {
    errors.push("workers must be a non-empty array".to_json())
  }
  for index, worker in workers {
    let worker_id = mooncode_json_string(worker, "id", default="")
    let raw_root = mooncode_json_string(worker, "book_root", default="")
    let normalized_child_root = @pathx.normalize(raw_root)
    let child_root = if @fsx.exists(normalized_child_root) {
      @fsx.resolve(normalized_child_root) catch {
        _ => normalized_child_root
      }
    } else {
      normalized_child_root
    }
    let mut overlaps_seen_root = false
    for existing_root, _ in seen_roots {
      if mooncode_worker_roots_overlap(existing_root, child_root) {
        overlaps_seen_root = true
      }
    }
    let prompt = mooncode_json_string(worker, "prompt", default="")
    let task_intent = mooncode_json_string(
      worker,
      "task_intent",
      default="workspace_change",
    )
    if worker_id == "" {
      errors.push("workers[\{index}].id must be non-empty".to_json())
    } else if seen_ids.contains(worker_id) {
      errors.push(
        "workers[\{index}].id duplicates existing worker `\{worker_id}`".to_json(),
      )
    } else {
      seen_ids[worker_id] = true
    }
    if raw_root == "" ||
      !@pathx.is_absolute(raw_root) ||
      !@fsx.exists(child_root) {
      errors.push(
        "workers[\{index}].book_root must be an existing absolute path".to_json(),
      )
    } else if mooncode_worker_roots_overlap(parent_root, child_root) {
      errors.push(
        "workers[\{index}].book_root must be isolated from the parent".to_json(),
      )
    } else if overlaps_seen_root {
      errors.push(
        "workers[\{index}].book_root overlaps another worker root".to_json(),
      )
    } else {
      seen_roots[child_root] = true
    }
    if prompt == "" {
      errors.push("workers[\{index}].prompt must be non-empty".to_json())
    }
    if task_intent != "workspace_change" && task_intent != "read_only" {
      errors.push(
        "workers[\{index}].task_intent must be `workspace_change` or `read_only`".to_json(),
      )
    }
  }
  {
    "ok": errors.length() == 0,
    "errors": Json::array(errors),
    "message": if errors.length() == 0 {
      "worker batch is valid"
    } else {
      "worker batch validation failed"
    },
  }
}

///|
fn mooncode_worker_command(
  parent_session_id : String,
  worker : Json,
  parent_model : String,
  child_session_id : String,
  child_command_id : String,
) -> Json {
  let worker_id = mooncode_json_string(worker, "id", default="")
  let selected_model = mooncode_json_string(
    worker,
    "model",
    default=parent_model,
  )
  {
    "protocol": mooncode_protocol_version(),
    "session_id": child_session_id,
    "book_root": @pathx.normalize(
      mooncode_json_string(worker, "book_root", default=""),
    ),
    "command": "prompt",
    "model": selected_model,
    "text": mooncode_json_string(worker, "prompt", default=""),
    "packet": { "command_id": child_command_id },
    "payload": {
      "task_intent": mooncode_json_string(
        worker,
        "task_intent",
        default="workspace_change",
      ),
      "parent_session_id": parent_session_id,
      "worker_id": worker_id,
    },
  }
}

///|
fn mooncode_worker_record(
  parent_session_id : String,
  parent_book_root : String,
  worker : Json,
  child_session_id : String,
  child_command_id : String,
  service_id : String,
  command_id : String,
  created_at : @clock.Timestamp,
) -> Json {
  let worker_id = mooncode_json_string(worker, "id", default="")
  {
    "id": "link:\{parent_session_id}:\{worker_id}",
    "protocol": mooncode_protocol_version(),
    "session_id": parent_session_id,
    "kind": mooncode_worker_record_kind(),
    "command_id": command_id,
    "lane": "runtime",
    "title": "Worker session linked",
    "detail": "MoonCode parent linked an ordinary child prompt session.",
    "source": "moonclaw-native-mooncode",
    "created_at": created_at,
    "parent_session_id": parent_session_id,
    "parent_book_root": parent_book_root,
    "worker_id": worker_id,
    "child_session_id": child_session_id,
    "child_book_root": @pathx.normalize(
      mooncode_json_string(worker, "book_root", default=""),
    ),
    "child_command_id": child_command_id,
    "service_id": service_id,
    "status": "queued",
  }
}

///|
async fn Daemon::mooncode_tool_spawn_workers(
  self : Daemon,
  group : @async.TaskGroup[Unit],
  parent_session_id : String,
  parent_book_root : String,
  command_id : String,
  arguments : Json,
) -> Json {
  let existing = mooncode_worker_records(parent_book_root, parent_session_id)
  let validation = mooncode_validate_spawn_workers(
    parent_book_root, existing, arguments,
  )
  if !mooncode_json_bool(validation, "ok", default=false) {
    return mooncode_tool_error_result(
      "spawn_workers",
      message="worker batch validation failed before side effects",
      metadata=validation,
    )
  }
  let parent_model = self.mooncode_binding_for_session(parent_session_id).model
  let prepared : Array[Json] = []
  for worker in mooncode_worker_specs(arguments) {
    let worker_id = mooncode_json_string(worker, "id", default="")
    let child_session_id = mooncode_safe_session_id(
      "\{parent_session_id}-worker-\{worker_id}-\{self.uuid.v4()}",
    )
    let child_command_id = "worker-prompt-\{self.uuid.v4()}"
    let service_id = "worker-\{child_session_id}"
    prepared.push({
      "record": mooncode_worker_record(
        parent_session_id,
        parent_book_root,
        worker,
        child_session_id,
        child_command_id,
        service_id,
        command_id,
        self.clock.now(),
      ),
      "command": mooncode_worker_command(
        parent_session_id, worker, parent_model, child_session_id, child_command_id,
      ),
      "service_id": service_id,
    })
  }
  // Persist the complete parent-child plan before any child can begin.
  for item in prepared {
    mooncode_append_session_journal(
      parent_book_root,
      parent_session_id,
      mooncode_journal_event(),
      mooncode_json_object_field_or_empty(item, "record"),
    )
  }
  let spawned : Array[Json] = []
  for item in prepared {
    let child_command = mooncode_json_object_field_or_empty(item, "command")
    let child_session_id = mooncode_json_string(
      child_command,
      "session_id",
      default="",
    )
    let child_book_root = mooncode_json_string(
      child_command,
      "book_root",
      default="",
    )
    let queue = self.mooncode_queue_command_response(
      session_id=child_session_id,
      child_command,
      queue_source="mooncode-parent-worker",
    )
    let service = self.mooncode_start_runtime_service(
      group~,
      child_session_id,
      child_book_root,
      { "service_id": mooncode_json_string(item, "service_id", default="") },
    )
    spawned.push({
      "worker": mooncode_json_object_field_or_empty(item, "record"),
      "queue": queue,
      "service": service,
    })
  }
  let metadata : Json = { "workers": Json::array(spawned) }
  mooncode_tool_ok_result(
    "spawn_workers",
    message="spawned \{spawned.length()} worker sessions",
    output=metadata.stringify(),
    metadata~,
  )
}

///|
async fn Daemon::mooncode_tool_wait_workers(
  self : Daemon,
  parent_session_id : String,
  parent_book_root : String,
  arguments : Json,
) -> Json {
  ignore(self)
  mooncode_wait_workers_projection(
    parent_session_id, parent_book_root, arguments,
  )
}

///|
async fn mooncode_worker_runtime_service_events(
  child_session_id : String,
  child_book_root : String,
) -> Array[Json] {
  let journal = mooncode_read_session_journal(child_book_root, child_session_id)
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  events.filter(event => {
    let kind = mooncode_json_string(event, "kind", default="")
    kind == "runtime.service_started" ||
    kind == "runtime.service_finished" ||
    kind == "runtime.service_failed"
  })
}

///|
async fn mooncode_wait_workers_projection(
  parent_session_id : String,
  parent_book_root : String,
  arguments : Json,
) -> Json {
  let mode = mooncode_json_string(arguments, "mode", default="all")
  if mode != "all" && mode != "any" {
    return mooncode_tool_error_result(
      "wait_workers",
      message="mode must be `any` or `all`",
    )
  }
  let requested = mooncode_json_array_items(arguments, "worker_ids")
  let records = mooncode_worker_records(parent_book_root, parent_session_id)
  let projected : Array[Json] = []
  let found : Map[String, Bool] = {}
  for record in records {
    let worker_id = mooncode_json_string(record, "worker_id", default="")
    let selected = requested.length() == 0 ||
      requested.any(item => item is String(id) && id == worker_id)
    if selected {
      found[worker_id] = true
      let child_session_id = mooncode_json_string(
        record,
        "child_session_id",
        default="",
      )
      let child_book_root = mooncode_json_string(
        record,
        "child_book_root",
        default="",
      )
      let service_id = mooncode_json_string(record, "service_id", default="")
      let state = mooncode_runtime_service_state_payload(
        child_session_id,
        child_book_root,
        mooncode_worker_runtime_service_events(
          child_session_id, child_book_root,
        ),
        service_id~,
      )
      let status = mooncode_json_string(state, "status", default="idle")
      let terminal = status != "idle" &&
        !mooncode_json_bool(state, "running", default=false)
      projected.push({
        "worker_id": worker_id,
        "child_session_id": child_session_id,
        "child_book_root": child_book_root,
        "status": status,
        "running": mooncode_json_bool(state, "running", default=false),
        "terminal": terminal,
        "terminal_evidence": mooncode_json_object_field_or_empty(
          state, "latest_event",
        ),
      })
    }
  }
  let missing : Array[Json] = []
  for item in requested {
    match item {
      String(worker_id) =>
        if !found.contains(worker_id) {
          missing.push(worker_id.to_json())
        }
      _ => ()
    }
  }
  let terminal_ready = if mode == "any" {
    projected.any(item => mooncode_json_bool(item, "terminal", default=false))
  } else {
    projected.length() > 0 &&
    projected.all(item => mooncode_json_bool(item, "terminal", default=false))
  }
  let ready = missing.length() == 0 && terminal_ready
  let metadata : Json = {
    "mode": mode,
    "ready": ready,
    "missing_worker_ids": Json::array(missing),
    "workers": Json::array(projected),
  }
  mooncode_tool_ok_result(
    "wait_workers",
    message=if ready {
      "worker wait condition satisfied"
    } else {
      "workers are still running or missing"
    },
    output=metadata.stringify(),
    metadata~,
  )
}

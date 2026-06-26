///|
// MoonClaw-native executable-book lifecycle evidence over durable sidecars.

///|
fn mooncode_executable_book_lifecycle_report(
  record : Json,
  commands : Array[Json],
  receipts : Array[Json],
  events : Array[Json],
  package_results : Array[Json],
  book_results : Array[Json],
) -> Json {
  let steps = [
    for step_id in mooncode_executable_book_lifecycle_steps() => {
      mooncode_lifecycle_step_report(
        step_id, record, commands, receipts, events, package_results, book_results,
      )
    }
  ]
  let completed = mooncode_lifecycle_completed_count(steps)
  let first_blocker = mooncode_first_blocked_lifecycle_step(steps)
  let ready = steps.length() > 0 && completed == steps.length()
  {
    "kind": "mooncode-executable-book-lifecycle-report",
    "protocol": mooncode_protocol_version(),
    "contract_id": mooncode_executable_book_lifecycle_contract_id(),
    "owner": "moonclaw",
    "session_id": mooncode_json_string(record, "session_id", default=""),
    "book_root": mooncode_json_string(record, "book_root", default=""),
    "ready": ready,
    "status": if ready {
      "complete"
    } else {
      "blocked"
    },
    "completed_step_count": completed,
    "step_count": steps.length(),
    "blocked_step_count": steps.length() - completed,
    "first_blocker_id": mooncode_json_string(first_blocker, "id", default=""),
    "first_blocker_label": mooncode_json_string(
      first_blocker,
      "label",
      default="",
    ),
    "first_blocker_evidence": mooncode_json_string(
      first_blocker,
      "evidence",
      default="",
    ),
    "steps": Json::array(steps),
    "rule": "MoonClaw reports executable-book lifecycle status from durable book-local sidecars only. Bookkeeper/MoonBook acceptance evidence is required for accept_result; UI state is not evidence.",
  }
}

///|
fn mooncode_lifecycle_step_report(
  step_id : String,
  record : Json,
  commands : Array[Json],
  receipts : Array[Json],
  events : Array[Json],
  package_results : Array[Json],
  book_results : Array[Json],
) -> Json {
  let ok = mooncode_lifecycle_step_ok(
    step_id, record, commands, receipts, events, package_results, book_results,
  )
  {
    "id": step_id,
    "label": mooncode_lifecycle_step_label(step_id),
    "owner": mooncode_lifecycle_step_owner(step_id),
    "ok": ok,
    "evidence": mooncode_lifecycle_step_evidence(
      step_id, record, commands, receipts, events, package_results, book_results,
    ),
  }
}

///|
fn mooncode_lifecycle_step_ok(
  step_id : String,
  record : Json,
  commands : Array[Json],
  receipts : Array[Json],
  events : Array[Json],
  package_results : Array[Json],
  book_results : Array[Json],
) -> Bool {
  match step_id {
    "select_book" => mooncode_json_string(record, "book_root", default="") != ""
    "start_session" =>
      mooncode_json_string(record, "session_id", default="") != "" &&
      commands.length() > 0 &&
      receipts.length() > 0 &&
      mooncode_json_string(record, "resume_state", default="") != "missing"
    "propose_change" =>
      mooncode_lifecycle_has_command(commands, "prompt") ||
      mooncode_lifecycle_has_command(commands, "steer") ||
      commands.length() > 0
    "edit_code" =>
      mooncode_lifecycle_has_event_kind(events, "tool.write") ||
      mooncode_lifecycle_has_event_kind(events, "tool.edit") ||
      mooncode_lifecycle_has_event_kind(events, "runtime.patch_applied") ||
      mooncode_lifecycle_has_event_lane(events, "diff")
    "verify_code" =>
      mooncode_lifecycle_has_event_name(events, mooncode_event_test_result()) ||
      mooncode_lifecycle_has_event_kind(events, "test_result") ||
      mooncode_lifecycle_has_event_kind(events, "eval_report.manifest") ||
      mooncode_lifecycle_has_event_lane(events, "test")
    "review_diff" =>
      mooncode_lifecycle_has_event_kind(events, "receipt.") ||
      mooncode_lifecycle_has_event_lane(events, "review")
    "accept_result" =>
      mooncode_lifecycle_has_event_kind(events, "receipt.accept") ||
      mooncode_lifecycle_has_accepted_book_result(book_results)
    "package_output" =>
      package_results.length() > 0 ||
      mooncode_lifecycle_has_event_name(events, mooncode_event_package_built()) ||
      mooncode_lifecycle_has_event_name(
        events,
        mooncode_event_package_verified(),
      )
    "resume_session" =>
      mooncode_json_string(record, "resume_state", default="") == "durable" ||
      mooncode_json_string(record, "resume_state", default="") == "live"
    _ => false
  }
}

///|
fn mooncode_lifecycle_step_evidence(
  step_id : String,
  record : Json,
  commands : Array[Json],
  receipts : Array[Json],
  events : Array[Json],
  package_results : Array[Json],
  book_results : Array[Json],
) -> String {
  match step_id {
    "select_book" =>
      if mooncode_json_string(record, "book_root", default="") == "" {
        "no selected book_root"
      } else {
        "book_root selected"
      }
    "start_session" =>
      "commands \{commands.length()}, receipts \{receipts.length()}, resume \{mooncode_json_string(record, "resume_state", default="unknown")}"
    "propose_change" => "commands \{commands.length()}"
    "edit_code" =>
      "diff/edit event present \{mooncode_lifecycle_step_ok(step_id, record, commands, receipts, events, package_results, book_results)}"
    "verify_code" =>
      "test/eval event present \{mooncode_lifecycle_step_ok(step_id, record, commands, receipts, events, package_results, book_results)}"
    "review_diff" =>
      "review event present \{mooncode_lifecycle_step_ok(step_id, record, commands, receipts, events, package_results, book_results)}"
    "accept_result" =>
      "accepted receipt/book result present \{mooncode_lifecycle_step_ok(step_id, record, commands, receipts, events, package_results, book_results)}"
    "package_output" =>
      "package results \{package_results.length()}, package events \{mooncode_lifecycle_count_package_events(events)}"
    "resume_session" =>
      "resume_state \{mooncode_json_string(record, "resume_state", default="unknown")}"
    _ => "unknown lifecycle step"
  }
}

///|
fn mooncode_lifecycle_step_label(step_id : String) -> String {
  match step_id {
    "select_book" => "Select MoonBook"
    "start_session" => "Start durable runtime session"
    "propose_change" => "Propose executable change"
    "edit_code" => "Edit code in the selected book"
    "verify_code" => "Verify code"
    "review_diff" => "Review diff"
    "accept_result" => "Accept result"
    "package_output" => "Package output"
    "resume_session" => "Resume session"
    _ => step_id
  }
}

///|
fn mooncode_lifecycle_step_owner(step_id : String) -> String {
  match step_id {
    "select_book" => "host"
    "start_session"
    | "propose_change"
    | "edit_code"
    | "verify_code"
    | "resume_session" => "moonclaw"
    "review_diff" | "accept_result" => "bookkeeper"
    "package_output" => "moonbook"
    _ => "mooncode"
  }
}

///|
fn mooncode_lifecycle_has_command(
  commands : Array[Json],
  command : String,
) -> Bool {
  for item in commands {
    if mooncode_json_string(item, "command", default="") == command {
      return true
    }
  }
  false
}

///|
fn mooncode_lifecycle_has_event_kind(
  events : Array[Json],
  needle : String,
) -> Bool {
  for event in events {
    if mooncode_json_string(event, "kind", default="").contains(needle) {
      return true
    }
  }
  false
}

///|
fn mooncode_lifecycle_has_event_lane(
  events : Array[Json],
  lane : String,
) -> Bool {
  for event in events {
    if mooncode_json_string(event, "lane", default="") == lane {
      return true
    }
  }
  false
}

///|
fn mooncode_lifecycle_has_event_name(
  events : Array[Json],
  name : String,
) -> Bool {
  for event in events {
    if mooncode_json_string(event, "event", default="") == name ||
      mooncode_json_string(event, "kind", default="") == name {
      return true
    }
  }
  false
}

///|
fn mooncode_lifecycle_has_accepted_book_result(
  book_results : Array[Json],
) -> Bool {
  for result in book_results {
    if !mooncode_json_bool(result, "requires_review", default=true) ||
      mooncode_json_string(result, "event_type", default="") ==
      "knowledge_accepted" {
      return true
    }
    let nested = mooncode_json_object_field_or_empty(
      result, "executable_book_event",
    )
    if !mooncode_json_bool(nested, "requires_review", default=true) ||
      mooncode_json_string(nested, "event_type", default="") ==
      "knowledge_accepted" {
      return true
    }
  }
  false
}

///|
fn mooncode_lifecycle_count_package_events(events : Array[Json]) -> Int {
  let mut count = 0
  for event in events {
    if mooncode_json_string(event, "event", default="") ==
      mooncode_event_package_built() ||
      mooncode_json_string(event, "event", default="") ==
      mooncode_event_package_verified() {
      count += 1
    }
  }
  count
}

///|
fn mooncode_lifecycle_completed_count(steps : Array[Json]) -> Int {
  let mut completed = 0
  for step in steps {
    if mooncode_json_bool(step, "ok", default=false) {
      completed += 1
    }
  }
  completed
}

///|
fn mooncode_first_blocked_lifecycle_step(steps : Array[Json]) -> Json {
  for step in steps {
    if !mooncode_json_bool(step, "ok", default=false) {
      return step
    }
  }
  {}
}

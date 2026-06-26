///|
fn mooncode_executable_book_event_protocol() -> String {
  "moonbook.executable_event.v1"
}

///|
async fn mooncode_runtime_turn_book_results(
  session_id : String,
  book_root : String,
  command : Json,
  execution : Json,
  package_results : Array[Json],
  now~ : @clock.Timestamp,
) -> Array[Json] {
  if package_results.is_empty() {
    return []
  }
  let command_id = mooncode_command_id(command)
  let safe_session = mooncode_safe_session_id(session_id)
  let safe_command = mooncode_safe_session_id(command_id)
  let result_path = "portable/app-tool/mooncode/\{safe_session}/book-result-\{safe_command}.json"
  let artifacts = mooncode_runtime_turn_book_result_artifacts(
    package_results,
    result_path~,
  )
  let result_id = mooncode_runtime_turn_book_result_id(session_id, command_id)
  let summary = mooncode_runtime_turn_book_result_summary(
    command, execution, artifacts,
  )
  let book_id = mooncode_runtime_turn_book_result_book_id(command, book_root)
  let event_id = "book-event-\{book_id}-mooncode-\{safe_session}-\{safe_command}"
  let event : Json = {
    "protocol": mooncode_executable_book_event_protocol(),
    "id": event_id,
    "source": "moonclaw",
    "book_id": book_id,
    "command_id": command_id,
    "result_id": result_id,
    "run_id": session_id,
    "event_type": "review_required",
    "accepted": false,
    "requires_review": true,
    "notify_town": true,
    "summary": summary,
    "artifacts": Json::array(mooncode_runtime_turn_string_json_array(artifacts)),
    "evidence_id": "mooncode-\{safe_session}-\{safe_command}",
    "review_path": null,
  }
  let result : Json = {
    "kind": "mooncode-book-result",
    "protocol": mooncode_executable_book_event_protocol(),
    "owner": "moonclaw",
    "source": "moonclaw-native-mooncode",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "result_id": result_id,
    "result_path": result_path,
    "created_at": now,
    "book_result": {
      "result_id": result_id,
      "summary": summary,
      "artifacts": Json::array(
        mooncode_runtime_turn_string_json_array(artifacts),
      ),
      "memory_candidates": Json::array([]),
      "requires_review": true,
      "notify_town": true,
    },
    "executable_book_event": event,
    "package_results": Json::array(package_results),
  }
  mooncode_runtime_turn_write_json_manifest(book_root, result_path, result)
  [result]
}

///|
fn mooncode_runtime_turn_book_result_artifacts(
  package_results : Array[Json],
  result_path~ : String,
) -> Array[String] {
  let artifacts : Array[String] = []
  mooncode_runtime_turn_push_unique_artifact(artifacts, result_path)
  for package_result in package_results {
    mooncode_runtime_turn_push_unique_artifact(
      artifacts,
      mooncode_package_result_path(package_result),
    )
    let manifest = mooncode_json_object_field_or_empty(
      package_result, "package_manifest",
    )
    mooncode_runtime_turn_push_unique_artifact(
      artifacts,
      mooncode_json_string(manifest, "manifest_path", default=""),
    )
    for candidate in mooncode_json_array_items(manifest, "candidate_paths") {
      match candidate {
        String(path) =>
          mooncode_runtime_turn_push_unique_artifact(artifacts, path)
        _ => ()
      }
    }
    for source in mooncode_json_array_items(manifest, "source_inventory") {
      mooncode_runtime_turn_push_unique_artifact(
        artifacts,
        mooncode_json_string(source, "path", default=""),
      )
      mooncode_runtime_turn_push_unique_artifact(
        artifacts,
        mooncode_json_string(source, "promoted_path", default=""),
      )
    }
    let index = mooncode_json_object_field_or_empty(
      package_result, "package_index",
    )
    mooncode_runtime_turn_push_unique_artifact(
      artifacts,
      mooncode_json_string(index, "manifest_path", default=""),
    )
  }
  artifacts
}

///|
fn mooncode_runtime_turn_push_unique_artifact(
  artifacts : Array[String],
  artifact : String,
) -> Unit {
  if artifact != "" &&
    !mooncode_runtime_turn_string_array_contains(artifacts, artifact) {
    artifacts.push(artifact)
  }
}

///|
fn mooncode_runtime_turn_book_result_id(
  session_id : String,
  command_id : String,
) -> String {
  "mooncode-\{mooncode_safe_session_id(session_id)}-\{mooncode_safe_session_id(command_id)}"
}

///|
fn mooncode_runtime_turn_book_result_book_id(
  command : Json,
  book_root : String,
) -> String {
  let direct = mooncode_json_string(command, "book_id", default="")
  if direct != "" {
    return direct
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let packet_book = mooncode_json_string(packet, "book_id", default="")
  if packet_book != "" {
    return packet_book
  }
  let workspace = mooncode_json_string(command, "workspace_id", default="")
  if workspace != "" {
    workspace
  } else {
    @pathx.basename(book_root).to_owned()
  }
}

///|
fn mooncode_runtime_turn_book_result_summary(
  command : Json,
  execution : Json,
  artifacts : Array[String],
) -> String {
  let answer = mooncode_runtime_turn_finish_answer(execution)
  if answer != "" {
    return answer
  }
  "MoonClaw produced \{artifacts.length()} executable MoonBook artifact(s) for command `\{mooncode_command_id(command)}`."
}

///|
fn mooncode_runtime_turn_finish_answer(execution : Json) -> String {
  for result in mooncode_json_array_items(execution, "tool_results") {
    if mooncode_json_string(result, "tool", default="") != "finish" {
      continue
    }
    let tool_result = mooncode_json_object_field_or_empty(result, "result")
    let output = mooncode_json_string(tool_result, "output", default="")
    if output != "" {
      return output
    }
    let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
    let answer = mooncode_json_string(metadata, "answer", default="")
    if answer != "" {
      return answer
    }
  }
  ""
}

///|
async fn Daemon::mooncode_persist_book_result(
  self : Daemon,
  result : Json,
  binding : MoonCodeSessionBinding,
) -> Unit {
  if binding.book_root == "" {
    return
  }
  self.mooncode_persist_session(binding)
  mooncode_append_jsonl(
    mooncode_book_results_path(binding.book_root, binding.session_id),
    result,
  )
}

///|
fn mooncode_runtime_turn_test_results(
  session_id : String,
  book_root : String,
  command : Json,
  tool_results : Array[Json],
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let results : Array[Json] = []
  let command_id = mooncode_command_id(command)
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  for index, execution in tool_results {
    if mooncode_json_string(execution, "tool", default="") != "moon_check" {
      continue
    }
    let result = mooncode_json_object_field_or_empty(execution, "result")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    let accepted = mooncode_json_bool(execution, "accepted", default=false)
    let target = mooncode_json_string(metadata, "target", default="")
    let exit_status = mooncode_json_int(metadata, "exit_status", default=-1)
    let elapsed_ms = mooncode_json_int(metadata, "elapsed_ms", default=0)
    let output = mooncode_json_string(result, "output", default="")
    let detail = mooncode_json_string(result, "message", default="")
    results.push({
      "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-test-result-\{index}-\{now}",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command_id": command_id,
      "command_packet": packet,
      "lane": "test",
      "kind": mooncode_event_test_result(),
      "event": mooncode_event_test_result(),
      "title": if accepted {
        "MoonCode tests passed"
      } else {
        "MoonCode tests failed"
      },
      "status": if accepted {
        "done"
      } else {
        "failed"
      },
      "test_status": if accepted {
        "passed"
      } else {
        "failed"
      },
      "detail": detail,
      "content": output,
      "output": output,
      "tool": "moon_check",
      "target": target,
      "exit_status": exit_status,
      "elapsed_ms": elapsed_ms,
      "tool_result": result,
      "created_at": now,
      "source": "moonclaw-native-runtime-turn",
    })
  }
  results
}

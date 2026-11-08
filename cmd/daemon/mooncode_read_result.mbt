///|
/// Read saved output lines, or details=true for canonical JSON. A result range
/// returns an index. Recall never executes the original operation.
async fn mooncode_tool_read_result(
  book_root : String,
  session_id : String,
  arguments : Json,
) -> Json {
  let reference = mooncode_json_string(arguments, "evidence_ref", default="")
  let end_ref = mooncode_json_string(arguments, "end_ref", default="")
  if reference == "" {
    return mooncode_tool_error_result(
      "read",
      message="A result reference is required.",
    )
  }
  let events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  let selected : Array[Json] = []
  let mut found = false
  let mut ended = false
  for event in events {
    let id = mooncode_json_string(event, "id", default="")
    let has_result = mooncode_journal_json_field(event, "tool_result")
      is Some(Object(_))
    if id == reference && has_result {
      found = true
    }
    if found && has_result {
      if end_ref == "" {
        selected.push(mooncode_tool_result_value(event))
        break
      }
      let result = mooncode_tool_result_value(event)
      selected.push({
        "evidence_ref": id,
        "tool": mooncode_json_string(event, "tool", default=""),
        "ok": mooncode_json_bool(result, "ok", default=false),
        "message": mooncode_json_string(result, "message", default=""),
      })
    }
    if found && id == end_ref {
      ended = true
      break
    }
  }
  if selected.is_empty() || (end_ref != "" && !ended) {
    return mooncode_tool_error_result(
      "read",
      message="Result reference is not available in this session.",
      metadata={ "evidence_ref": reference },
    )
  }
  let value = if end_ref == "" { selected[0] } else { Json(selected) }
  let details = mooncode_json_bool(arguments, "details", default=false)
  let text = if end_ref == "" && !details {
    mooncode_json_string(value, "output", default="")
  } else {
    value.stringify(indent=2)
  }
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  let start = mooncode_json_int(arguments, "start_line", default=1)
  let end = mooncode_json_int(arguments, "end_line", default=lines.length()).min(
    lines.length(),
  )
  if start < 1 || end < start {
    return mooncode_tool_error_result(
      "read",
      message="Result line range is outside the retained result.",
    )
  }
  let text = lines[start - 1:end].to_owned().join("\n")
  let capped = mooncode_cap_tool_output(
    text,
    mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  mooncode_tool_ok_result(
    "read",
    message="Retained result read without execution.",
    output=mooncode_json_string(capped, "output", default=""),
    metadata={
      "evidence_ref": reference,
      "end_ref": end_ref,
      "result_count": selected.length(),
      "source": if end_ref == "" && !details {
        {
          "ok": mooncode_json_bool(value, "ok", default=false),
          "message": mooncode_json_string(value, "message", default=""),
          "truncated": mooncode_json_bool(
            mooncode_json_object_field_or_empty(value, "metadata"),
            "truncated",
            default=false,
          ),
        }
      } else {
        Json::null()
      },
      "start_line": start,
      "end_line": end,
      "line_count": lines.length(),
      "truncated": mooncode_json_bool(capped, "truncated", default=false),
    },
  )
}

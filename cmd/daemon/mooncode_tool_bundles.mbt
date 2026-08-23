///|
fn mooncode_runtime_turn_dynamic_tool_bundles_enabled(command : Json) -> Bool {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_bool(payload, "planner_dynamic_tool_bundles", default=false)
}

///|
fn mooncode_runtime_turn_text_contains_any(
  text : String,
  terms : ArrayView[String],
) -> Bool {
  terms.any(term => text.contains(term))
}

///|
fn mooncode_runtime_turn_dynamic_coding_tool_names(
  request : String,
) -> Array[String] {
  let names = [
    "read", "write", "edit", "shell", "finish", "apply_patch", "checkpoint", "read_skill",
  ]
  if mooncode_runtime_turn_text_contains_any(request, [
      "moonbit", ".mbt", "moon.mod", "moon.pkg", "moon check", "moon test", "moon fmt",
      "moon info", "moon build", "moon ide",
    ]) {
    names.push("moon_ide")
    names.push("moon_cmd")
    names.push("moon_check")
  }
  if mooncode_runtime_turn_text_contains_any(request, [
      " ui", "ui ", "browser", "frontend", "front-end", "screenshot", "visual", "website",
      "web app", "page", "css", "html", "dom",
    ]) {
    names.push("browser")
    names.push("view_image")
  }
  if mooncode_runtime_turn_text_contains_any(request, [
      "worker", "subagent", "sub-agent", "delegate", "parallel agent", "parallelize agents",
    ]) {
    names.push("spawn_workers")
    names.push("wait_workers")
  }
  names
}

///|
fn mooncode_runtime_turn_active_tool_bundle_message(command : Json) -> String {
  if !mooncode_runtime_turn_dynamic_tool_bundles_enabled(command) {
    return ""
  }
  let names = mooncode_runtime_turn_model_tools_for_command(command)
    .map(tool => {
      let function = mooncode_json_object_field_or_empty(
        tool.to_json(),
        "function",
      )
      mooncode_json_string(function, "name", default="")
    })
    .filter(name => name != "")
  let guidance = if names.contains("tool_search") &&
    mooncode_runtime_turn_explicit_allowed_tool_names(command).is_empty() {
    ". This supplied bundle is authoritative. Use tool_search when a required capability is omitted; matched tools become available only in the next planner request."
  } else {
    ". This supplied bundle is authoritative; use only these tools."
  }
  " Active tool bundle for this request: " + names.join(", ") + guidance
}

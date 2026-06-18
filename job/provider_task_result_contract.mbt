///|
/// Provider-task JSON/result contract helpers.
///
/// The executor should either receive a valid `ProviderTaskResult` or produce a
/// structured blocker. Planning-shaped responses are parsed only to support
/// safe decomposition, not as successful provider completion.
fn extract_first_json_object(content : String) -> String? {
  let trimmed = content.trim().to_owned()
  if trimmed.is_blank() {
    return None
  }
  if trimmed.has_prefix("{") {
    return Some(trimmed)
  }
  let buf = StringBuilder::new()
  let mut started = false
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for c in content.to_array() {
    if !started {
      if c == '{' {
        started = true
        depth = 1
        buf.write_char(c)
      }
      continue
    }
    buf.write_char(c)
    if in_string {
      if escaped {
        escaped = false
        continue
      }
      if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
      continue
    }
    match c {
      '"' => in_string = true
      '{' => depth += 1
      '}' => {
        depth -= 1
        if depth == 0 {
          return Some(buf.to_string())
        }
      }
      _ => ()
    }
  }
  None
}

///|
fn parse_provider_task_result(
  content : String,
) -> Result[ProviderTaskResult, String] {
  let trimmed = match extract_first_json_object(content) {
    Some(payload) => payload.trim().to_owned()
    None => return Err("Provider task analysis must return a JSON object")
  }
  if trimmed.is_blank() || !trimmed.has_prefix("{") {
    return Err("Provider task analysis must return a JSON object")
  }
  let json = match parse_provider_task_payload(trimmed, "analysis") {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskResult = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task analysis returned invalid ProviderTaskResult: \{error}",
      )
  }
  Ok(decoded)
}

///|
fn provider_task_json_string_field(json : Json, key : String) -> String? {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) if !value.trim().to_owned().is_blank() =>
          Some(value.trim().to_owned())
        _ => None
      }
    _ => None
  }
}

///|
fn provider_task_json_bool_field(json : Json, key : String) -> Bool? {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn provider_task_json_string_array_field(
  json : Json,
  key : String,
) -> Array[String] {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(values)) => {
          let items : Array[String] = []
          for value in values {
            guard value is String(text) else { continue }
            let trimmed = text.trim().to_owned()
            if !trimmed.is_blank() {
              items.push(trimmed)
            }
          }
          items
        }
        _ => []
      }
    _ => []
  }
}

///|
fn plan_summary_from_json(json : Json) -> String? {
  let keys = ["plan", "steps"]
  for key in keys {
    guard json is Object(obj) else { break }
    guard obj.get(key) is Some(Array(items)) else { continue }
    let titles : Array[String] = []
    for item in items {
      let title = provider_task_json_string_field(item, "title").unwrap_or(
        provider_task_json_string_field(item, "step").unwrap_or(""),
      )
      if !title.is_blank() {
        titles.push(title)
      }
      if titles.length() >= 3 {
        break
      }
    }
    if !titles.is_empty() {
      let joined_titles = titles.join(", ")
      return Some("Completed provider task using plan steps: \{joined_titles}.")
    }
  }
  None
}

///|
fn provider_task_plan_substeps_from_json(
  json : Json,
) -> Array[AdaptiveSubstepPayload] {
  let keys = ["plan", "steps", "suggested_substeps", "substeps"]
  for key in keys {
    guard json is Object(obj) else { break }
    guard obj.get(key) is Some(Array(items)) else { continue }
    let substeps : Array[AdaptiveSubstepPayload] = []
    for item in items {
      guard item is Object(step) else { continue }
      let title = provider_task_json_string_field(item, "title").unwrap_or(
        provider_task_json_string_field(item, "step").unwrap_or(
          provider_task_json_string_field(item, "name").unwrap_or(""),
        ),
      )
      if title.is_blank() {
        continue
      }
      let prompt = provider_task_json_string_field(item, "prompt").unwrap_or(
        provider_task_json_string_field(item, "instruction").unwrap_or(
          provider_task_json_string_field(item, "detail").unwrap_or(title),
        ),
      )
      let kind = match step.get("kind") {
        Some(String(kind)) if !kind.trim().to_owned().is_blank() =>
          Some(kind.trim().to_owned())
        _ => None
      }
      substeps.push(AdaptiveSubstepPayload::{ title, prompt, kind })
    }
    if !substeps.is_empty() {
      return substeps
    }
  }
  []
}

///|
fn provider_task_breadth_summary(
  task : ProviderTaskSpec,
  json : Json,
) -> String {
  provider_task_json_string_field(json, "summary").unwrap_or(
    provider_task_json_string_field(json, "message").unwrap_or(
      "Split provider task \{task.title} into narrower executable steps before running it.",
    ),
  )
}

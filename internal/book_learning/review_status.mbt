///|
/// The canonical status field owns admission. A legacy accepted flag is used
/// only when no status was declared; descriptive and nested fields are not
/// review decisions.
fn agent_memory_review_fields(fields : Map[String, Json]) -> String {
  match fields.get("status") {
    Some(String(value)) =>
      if value.trim().to_owned().to_lower() == "accepted" ||
        value.trim().to_owned().to_lower() == "promoted" {
        "accepted"
      } else {
        "candidate"
      }
    Some(_) => "candidate"
    None =>
      if fields.get("accepted") is Some(True) {
        "accepted"
      } else {
        "candidate"
      }
  }
}

///|
fn agent_memory_text_status_value(value : String) -> String {
  let value = value.trim().to_owned()
  match (try? @json.parse(value)) {
    Ok(String(text)) => text
    _ =>
      if value.length() >= 2 && value.has_prefix("'") && value.has_suffix("'") {
        value[1:value.length() - 1].to_owned()
      } else {
        value
      }
  }
}

///|
/// Legacy text records may declare a one-line status or an initial Markdown
/// metadata block. Never search the document body, code examples, or indented
/// descriptive values for acceptance markers.
fn agent_memory_text_review_status(content : String) -> String {
  let text = content.trim().to_owned()
  let lines = text.split("\n").to_array()
  if lines.length() == 1 {
    let line = lines[0].trim_end().to_owned()
    if line.has_prefix("status:") {
      return agent_memory_review_fields({
        "status": agent_memory_text_status_value(
          line["status:".length():].to_owned(),
        ).to_json(),
      })
    }
    return "candidate"
  }
  if lines[0].trim_end() != "---" {
    return "candidate"
  }
  let fields : Map[String, Json] = {}
  let mut closed = false
  for index in 1..<lines.length() {
    let line = lines[index].trim_end().to_owned()
    if line == "---" {
      closed = true
      break
    }
    if line.has_prefix("status:") {
      if fields.contains("status") {
        return "candidate"
      }
      fields["status"] = agent_memory_text_status_value(
        line["status:".length():].to_owned(),
      ).to_json()
    } else if line.has_prefix("accepted:") {
      if fields.contains("accepted") {
        return "candidate"
      }
      fields["accepted"] = (line["accepted:".length():].trim() == "true").to_json()
    }
  }
  if closed {
    agent_memory_review_fields(fields)
  } else {
    "candidate"
  }
}

///|
pub fn review_status(content : String) -> String {
  match (try? @json.parse(content)) {
    Ok(Object(fields)) => agent_memory_review_fields(fields)
    Ok(_) => "candidate"
    Err(_) => agent_memory_text_review_status(content)
  }
}

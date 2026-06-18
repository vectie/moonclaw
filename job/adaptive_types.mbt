///|
pub(all) struct AdaptiveSubstepPayload {
  title : String
  prompt : String
  kind : String?
} derive(FromJson, ToJson, Debug)

///|
pub(all) struct AdaptiveAnalysisEnvelope {
  verdict : String
  summary : String?
  missing_inputs : Array[String]?
  suggested_substeps : Array[AdaptiveSubstepPayload]?
  substeps : Array[AdaptiveSubstepPayload]?
} derive(FromJson, ToJson, Debug)

///|
fn adaptive_json_string_field(
  object : Map[String, Json],
  key : String,
) -> String? {
  match object.get(key) {
    Some(String(value)) if !value.trim().is_empty() =>
      Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn adaptive_json_string_array_field(
  object : Map[String, Json],
  key : String,
) -> Array[String]? {
  match object.get(key) {
    Some(Array(values)) => {
      let items : Array[String] = []
      for value in values {
        guard value is String(text) else { continue }
        let trimmed = text.trim().to_owned()
        if !trimmed.is_blank() {
          items.push(trimmed)
        }
      }
      if items.is_empty() {
        None
      } else {
        Some(items)
      }
    }
    _ => None
  }
}

///|
fn parse_adaptive_substep(value : Json) -> AdaptiveSubstepPayload? {
  guard value is Object(object) else { return None }
  let title = match adaptive_json_string_field(object, "title") {
    Some(title) => title
    None => return None
  }
  let prompt = match adaptive_json_string_field(object, "prompt") {
    Some(prompt) => prompt
    None => title
  }
  let kind = adaptive_json_string_field(object, "kind")
  Some(AdaptiveSubstepPayload::{ title, prompt, kind })
}

///|
fn adaptive_json_substeps_field(
  object : Map[String, Json],
  key : String,
) -> Array[AdaptiveSubstepPayload]? {
  match object.get(key) {
    Some(Array(values)) => {
      let items : Array[AdaptiveSubstepPayload] = []
      for value in values {
        match parse_adaptive_substep(value) {
          Some(item) => items.push(item)
          None => ()
        }
      }
      if items.is_empty() {
        None
      } else {
        Some(items)
      }
    }
    _ => None
  }
}

///|
fn parse_adaptive_analysis_envelope(
  content : String,
) -> AdaptiveAnalysisEnvelope? {
  let trimmed = content.trim().to_owned()
  if trimmed.is_blank() || !trimmed.has_prefix("{") {
    return None
  }
  let json = @json.parse(trimmed) catch { _ => return None }
  guard json is Object(object) else { return None }
  let verdict = match adaptive_json_string_field(object, "verdict") {
    Some(verdict) => verdict
    None => return None
  }
  Some(AdaptiveAnalysisEnvelope::{
    verdict,
    summary: adaptive_json_string_field(object, "summary"),
    missing_inputs: adaptive_json_string_array_field(object, "missing_inputs"),
    suggested_substeps: adaptive_json_substeps_field(
      object, "suggested_substeps",
    ),
    substeps: adaptive_json_substeps_field(object, "substeps"),
  })
}

///|
fn is_completed_keeper_plan_packet(content : String) -> Bool {
  let trimmed = content.trim().to_owned()
  if trimmed.is_blank() || !trimmed.has_prefix("{") {
    return false
  }
  let json = @json.parse(trimmed) catch { _ => return false }
  guard json is Object(object) else { return false }
  let packet_type = adaptive_json_string_field(object, "packet_type")
  let status = adaptive_json_string_field(object, "status")
  match (packet_type, status) {
    (Some("keeper.plan.packet.v1"), Some("ok")) => true
    _ => false
  }
}

///|
fn adaptive_substeps(
  envelope : AdaptiveAnalysisEnvelope,
) -> Array[AdaptiveSubstepPayload] {
  match envelope.suggested_substeps {
    Some(steps) if !steps.is_empty() => steps
    _ => envelope.substeps.unwrap_or([])
  }
}

///|
fn adaptive_missing_inputs_line(envelope : AdaptiveAnalysisEnvelope) -> String {
  match envelope.missing_inputs {
    Some(inputs) if !inputs.is_empty() => inputs.join("; ")
    _ => envelope.summary.unwrap_or("Analysis requires additional inputs.")
  }
}

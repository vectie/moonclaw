///|
pub fn extract_output_format_hint(request_text : String) -> String? {
  for line in request_text.split("\n") {
    let trimmed = line.trim().to_string()
    let lower = trimmed.to_lower()
    if lower.has_prefix("output format:") {
      let value = trimmed[14:].to_string().trim().to_string()
      if !value.is_blank() {
        return Some(value)
      }
    }
    if lower.has_prefix("format:") {
      let value = trimmed[7:].to_string().trim().to_string()
      if !value.is_blank() {
        return Some(value)
      }
    }
  }
  None
}

///|
fn merge_intake_metadata(base : Json, extra : Json) -> Json {
  let merged : Map[String, Json] = {}
  match base {
    Object(obj) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  match extra {
    Object(obj) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  Json::object(merged)
}

///|
pub fn job_intake_json(
  request_text : String,
  attachments : Array[E2EStarterAttachment],
  message_id? : String? = None,
  thread_id? : String? = None,
  content_type? : String? = None,
) -> Json {
  E2EJobIntake::new(
    request_text~,
    requested_output_format=extract_output_format_hint(request_text),
    starter_attachments=attachments,
    message_id~,
    thread_id~,
    content_type~,
  ).to_json()
}

///|
pub fn merge_job_intake_metadata(
  profile_metadata : Json,
  intake : Json?,
) -> Json {
  match intake {
    Some(intake) =>
      merge_intake_metadata(
        profile_metadata,
        Json::object({ "job_intake": intake }),
      )
    None => profile_metadata
  }
}

///|
pub fn proposal_initial_input(proposal : JobProposal) -> Json? {
  match proposal.profile_metadata {
    Object(obj) => obj.get("job_intake")
    _ => None
  }
}

///|
fn inline_output_format_suffix(text : String) -> String? {
  let lower = text.to_lower()
  let markers = [" output format:", " format:"]
  for marker in markers {
    match lower.find(marker) {
      Some(index) => {
        let value = text[index + marker.length():]
          .to_string()
          .trim()
          .to_string()
        if !value.is_blank() {
          return Some(value)
        }
      }
      None => ()
    }
  }
  None
}

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
  inline_output_format_suffix(request_text.trim().to_string())
}

///|
pub fn normalized_request_text(request_text : String) -> String {
  let lines : Array[String] = []
  for line in request_text.split("\n") {
    let trimmed = line.trim().to_string()
    let lower = trimmed.to_lower()
    if lower.has_prefix("output format:") || lower.has_prefix("format:") {
      continue
    }
    let without_suffix = match inline_output_format_suffix(trimmed) {
      Some(_) =>
        match lower.find(" output format:") {
          Some(index) => trimmed[:index].to_string().trim().to_string()
          None =>
            match lower.find(" format:") {
              Some(index) => trimmed[:index].to_string().trim().to_string()
              None => trimmed
            }
        }
      None => trimmed
    }
    if !without_suffix.is_blank() {
      lines.push(without_suffix)
    }
  }
  lines.join("\n").trim().to_string()
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
pub fn merge_initial_input_for_resume(
  base : Json?,
  resume_input : Json,
) -> Json {
  match (base, resume_input) {
    (Some(Object(base_obj)), Object(resume_obj)) => {
      let merged : Map[String, Json] = {}
      for key, value in base_obj {
        merged.set(key, value)
      }
      for key, value in resume_obj {
        merged.set(key, value)
      }
      Json::object(merged)
    }
    (Some(base), _) =>
      Json::object({
        "previous_initial_input": base,
        "resume_input": resume_input,
      })
    (None, _) => resume_input
  }
}

///|
pub fn job_intake_json(
  request_text : String,
  attachments : Array[E2EStarterAttachment],
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  message_id? : String? = None,
  thread_id? : String? = None,
  content_type? : String? = None,
) -> Json {
  let normalized = normalized_request_text(request_text)
  E2EJobIntake::new(
    request_text=normalized,
    requested_output_format=extract_output_format_hint(request_text),
    starter_attachments=attachments,
    channel_id~,
    account_id~,
    recipient~,
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

///|
pub fn mark_proposal_as_e2e(proposal : JobProposal) -> JobProposal {
  JobProposal::{
    ..proposal,
    profile_metadata: merge_intake_metadata(proposal.profile_metadata, {
      "proposal_mode": "e2e",
    }),
  }
}

///|
pub fn proposal_is_e2e(proposal : JobProposal) -> Bool {
  match proposal.profile_metadata {
    Object(obj) =>
      match obj.get("proposal_mode") {
        Some(String(mode)) => mode == "e2e"
        _ => false
      }
    _ => false
  }
}

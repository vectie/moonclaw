///|
pub struct ExternalProposalPacket {
  packet_id : String?
  title : String?
  summary : String?
  request_text : String
  profile : String
  output_contract : Json?
  context_pages : Array[String]
  skill_paths : Array[String]
  notes : Array[String]
  tags : Array[String]
  metadata : Json
} derive(ToJson, Show)

///|
pub struct ExternalProposalImportResult {
  proposal : JobProposal
  confirm_result : ConfirmProposalResult?
}

///|
fn external_packet_string_field(
  obj : Map[String, Json],
  key : String,
) -> String? {
  match obj.get(key) {
    Some(String(value)) => {
      let trimmed = value.trim().to_string()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    _ => None
  }
}

///|
fn external_packet_string_list(value : Json?) -> Array[String] {
  match value {
    Some(String(text)) => {
      let trimmed = text.trim().to_string()
      if trimmed.is_blank() {
        []
      } else {
        [trimmed]
      }
    }
    Some(Array(items)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          String(text) => {
            let trimmed = text.trim().to_string()
            if !trimmed.is_blank() {
              values.push(trimmed)
            }
          }
          _ => ()
        }
      }
      values
    }
    _ => []
  }
}

///|
fn external_packet_required_string_list(
  value : Json?,
  path : @json.JsonPath,
  field : String,
) -> Array[String] raise @json.JsonDecodeError {
  match value {
    Some(Array(items)) => {
      let values : Array[String] = []
      let mut index = 0
      for item in items {
        match item {
          String(text) => {
            let trimmed = text.trim().to_string()
            if trimmed.is_blank() {
              raise @json.JsonDecodeError(
                (
                  path.add_key(field).add_index(index),
                  "ExternalProposalPacket: \{field} entries must be non-blank strings",
                ),
              )
            }
            values.push(trimmed)
          }
          _ =>
            raise @json.JsonDecodeError(
              (
                path.add_key(field).add_index(index),
                "ExternalProposalPacket: \{field} must be an array of strings",
              ),
            )
        }
        index += 1
      }
      if values.is_empty() {
        raise @json.JsonDecodeError(
          (
            path.add_key(field),
            "ExternalProposalPacket: \{field} must not be empty",
          ),
        )
      }
      values
    }
    Some(_) =>
      raise @json.JsonDecodeError(
        (
          path.add_key(field),
          "ExternalProposalPacket: \{field} must be an array of strings",
        ),
      )
    None =>
      raise @json.JsonDecodeError(
        (path, "ExternalProposalPacket: missing \{field}"),
      )
  }
}

///|
fn external_packet_output_contract(
  value : Json?,
  path : @json.JsonPath,
) -> Json raise @json.JsonDecodeError {
  match value {
    Some(String(text)) => {
      let trimmed = text.trim().to_string()
      if trimmed.is_blank() {
        raise @json.JsonDecodeError(
          (
            path.add_key("output_contract"),
            "ExternalProposalPacket: output_contract must be non-blank",
          ),
        )
      }
      trimmed.to_json()
    }
    Some(Array(items)) => {
      if items.is_empty() {
        raise @json.JsonDecodeError(
          (
            path.add_key("output_contract"),
            "ExternalProposalPacket: output_contract array must not be empty",
          ),
        )
      }
      let values : Array[String] = []
      let mut index = 0
      for item in items {
        match item {
          String(text) => {
            let trimmed = text.trim().to_string()
            if trimmed.is_blank() {
              raise @json.JsonDecodeError(
                (
                  path.add_key("output_contract").add_index(index),
                  "ExternalProposalPacket: output_contract array entries must be non-blank strings",
                ),
              )
            }
            values.push(trimmed)
          }
          _ =>
            raise @json.JsonDecodeError(
              (
                path.add_key("output_contract").add_index(index),
                "ExternalProposalPacket: output_contract array entries must be strings",
              ),
            )
        }
        index += 1
      }
      values.to_json()
    }
    Some(Object(obj)) => {
      if obj.is_empty() {
        raise @json.JsonDecodeError(
          (
            path.add_key("output_contract"),
            "ExternalProposalPacket: output_contract object must not be empty",
          ),
        )
      }
      Json::object(obj)
    }
    Some(_) =>
      raise @json.JsonDecodeError(
        (
          path.add_key("output_contract"),
          "ExternalProposalPacket: output_contract must be string, array, or object",
        ),
      )
    None =>
      raise @json.JsonDecodeError(
        (path, "ExternalProposalPacket: missing output_contract"),
      )
  }
}

///|
fn external_packet_request_text(
  obj : Map[String, Json],
  title : String?,
  summary : String?,
) -> String? {
  for key in ["request_text", "request", "goal", "objective"] {
    match external_packet_string_field(obj, key) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  match (title, summary) {
    (Some(title), Some(summary)) if !summary.is_blank() =>
      Some("\{title}\n\n\{summary}")
    (Some(title), _) => Some(title)
    _ => None
  }
}

///|
pub impl @json.FromJson for ExternalProposalPacket with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ExternalProposalPacket raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "ExternalProposalPacket: expected object"),
    )
  }
  let packet_id = match external_packet_string_field(obj, "packet_id") {
    Some(value) => Some(value)
    None =>
      match external_packet_string_field(obj, "source_id") {
        Some(value) => Some(value)
        None => external_packet_string_field(obj, "id")
      }
  }
  let title = external_packet_string_field(obj, "title")
  let summary = match external_packet_string_field(obj, "summary") {
    Some(value) => Some(value)
    None => external_packet_string_field(obj, "overview")
  }
  let request_text = match external_packet_request_text(obj, title, summary) {
    Some(value) => value
    None =>
      raise @json.JsonDecodeError(
        (
          path, "ExternalProposalPacket: missing request_text/request/goal/objective/title",
        ),
      )
  }
  let profile = match external_packet_string_field(obj, "profile") {
    Some(value) => value
    None =>
      raise @json.JsonDecodeError(
        (path, "ExternalProposalPacket: missing profile"),
      )
  }
  let output_contract = Some(
    external_packet_output_contract(obj.get("output_contract"), path),
  )
  let context_pages = external_packet_required_string_list(
    obj.get("context_pages"),
    path,
    "context_pages",
  )
  let skill_paths = external_packet_required_string_list(
    obj.get("skill_paths"),
    path,
    "skill_paths",
  )
  let notes = external_packet_string_list(obj.get("notes"))
  let tags = external_packet_string_list(obj.get("tags"))
  let metadata = match obj.get("metadata") {
    Some(Object(fields)) => Json::object(fields)
    Some(_) =>
      raise @json.JsonDecodeError(
        (
          path.add_key("metadata"),
          "ExternalProposalPacket: metadata must be object",
        ),
      )
    None => {}
  }
  {
    packet_id,
    title,
    summary,
    request_text,
    profile,
    output_contract,
    context_pages,
    skill_paths,
    notes,
    tags,
    metadata,
  }
}

///|
pub fn parse_external_proposal_packet_text(
  text : String,
) -> Result[ExternalProposalPacket, String] {
  let json = @json.parse(text) catch {
    error =>
      return Err("Failed to parse external proposal packet JSON: \{error}")
  }
  parse_external_proposal_packet_json(json)
}

///|
pub fn parse_external_proposal_packet_json(
  json : Json,
) -> Result[ExternalProposalPacket, String] {
  Ok(
    @json.from_json(json) catch {
      error => return Err("Invalid external proposal packet: \{error}")
    },
  )
}

///|
fn external_packet_skill_name(path : String) -> String? {
  let trimmed = path.trim().to_string()
  if trimmed.is_blank() {
    return None
  }
  let segments = trimmed.split("/").to_array()
  if segments.is_empty() {
    return None
  }
  let last = segments[segments.length() - 1]
  let name = if last == "SKILL.md" && segments.length() >= 2 {
    segments[segments.length() - 2]
  } else if last.has_suffix(".md") && last.length() > 3 {
    last[:last.length() - 3].to_string()
  } else {
    last.to_string()
  }
  let normalized = name.trim().to_string()
  if normalized.is_blank() {
    None
  } else {
    Some(normalized)
  }
}

///|
fn external_packet_preferred_skills(
  packet : ExternalProposalPacket,
  existing? : Array[String] = [],
) -> Array[String] {
  let merged : Array[String] = []
  let seen : Map[String, Bool] = {}
  for skill in existing {
    let trimmed = skill.trim().to_string()
    if !trimmed.is_blank() && !seen.contains(trimmed) {
      seen.set(trimmed, true)
      merged.push(trimmed)
    }
  }
  for path in packet.skill_paths {
    match external_packet_skill_name(path) {
      Some(skill) if !seen.contains(skill) => {
        seen.set(skill, true)
        merged.push(skill)
      }
      _ => ()
    }
  }
  merged
}

///|
pub fn external_proposal_packet_summary(
  packet : ExternalProposalPacket,
) -> String {
  match packet.summary {
    Some(summary) => summary
    None =>
      [
        "Imported external proposal packet.", "This proposal uses the existing confirm and execution lifecycle.",
      ].join(" ")
  }
}

///|
fn external_packet_job_intake(
  packet : ExternalProposalPacket,
  source_path : String,
) -> Json {
  let intake : Map[String, Json] = {}
  intake.set("external_packet_source_path", source_path.to_json())
  intake.set("context_pages", packet.context_pages.to_json())
  intake.set("skill_paths", packet.skill_paths.to_json())
  intake.set("notes", packet.notes.to_json())
  match packet.output_contract {
    Some(output_contract) => {
      intake.set("output_contract", output_contract)
      match output_contract {
        String(text) => intake.set("requested_output_format", text.to_json())
        _ => ()
      }
    }
    None => ()
  }
  match packet.packet_id {
    Some(packet_id) => intake.set("external_packet_id", packet_id.to_json())
    None => ()
  }
  Json::object(intake)
}

///|
fn external_proposal_packet_metadata(
  packet : ExternalProposalPacket,
  source_path : String,
) -> Json {
  let packet_metadata : Map[String, Json] = {}
  packet_metadata.set(
    "schema",
    "moonclaw.external_proposal_packet.v1".to_json(),
  )
  packet_metadata.set("source_path", source_path.to_json())
  packet_metadata.set("profile", packet.profile.to_json())
  packet_metadata.set("context_pages", packet.context_pages.to_json())
  packet_metadata.set("skill_paths", packet.skill_paths.to_json())
  packet_metadata.set("notes", packet.notes.to_json())
  packet_metadata.set("tags", packet.tags.to_json())
  match packet.packet_id {
    Some(packet_id) => packet_metadata.set("packet_id", packet_id.to_json())
    None => ()
  }
  match packet.output_contract {
    Some(output_contract) =>
      packet_metadata.set("output_contract", output_contract)
    None => ()
  }
  if packet.metadata is Object(fields) {
    packet_metadata.set("metadata", Json::object(fields))
  }
  { "external_packet": Json::object(packet_metadata) }
}

///|
fn external_packet_step_metadata(
  step_metadata : Json,
  packet : ExternalProposalPacket,
  source_path : String,
) -> Json {
  let existing_skills = match step_metadata {
    { "preferred_skills": Array(items), .. } =>
      items.filter_map(fn(item) {
        match item {
          String(value) => {
            let trimmed = value.trim().to_string()
            if trimmed.is_blank() {
              None
            } else {
              Some(trimmed)
            }
          }
          _ => None
        }
      })
    _ => []
  }
  let extra : Map[String, Json] = {}
  extra.set("external_packet_source_path", source_path.to_json())
  extra.set("context_pages", packet.context_pages.to_json())
  extra.set("skill_paths", packet.skill_paths.to_json())
  extra.set("external_packet_notes", packet.notes.to_json())
  extra.set(
    "preferred_skills",
    external_packet_preferred_skills(packet, existing=existing_skills).to_json(),
  )
  match packet.output_contract {
    Some(output_contract) => {
      extra.set("external_output_contract", output_contract)
      match output_contract {
        String(text) => extra.set("output_contract", text.to_json())
        _ => ()
      }
    }
    None => ()
  }
  merge_json_metadata(step_metadata, Json::object(extra))
}

///|
fn proposal_with_external_packet(
  proposal_id : String,
  packet : ExternalProposalPacket,
  source_path : String,
  now_ms : Int,
) -> JobProposal {
  let draft = draft_job_proposal(proposal_id, packet.request_text, now_ms)
  let title = packet.title.unwrap_or(compact_title(packet.request_text))
  let tags = [..draft.tags, packet.profile, ..packet.tags]
  JobProposal::{
    ..draft,
    title,
    summary: external_proposal_packet_summary(packet),
    suggested_family: Some(packet.profile),
    profile_metadata: merge_job_intake_metadata(
      merge_json_metadata(
        draft.profile_metadata,
        external_proposal_packet_metadata(packet, source_path),
      ),
      Some(external_packet_job_intake(packet, source_path)),
    ),
    tags,
  }
}

///|
pub async fn GatewayJobApp::execute_definition(
  self : GatewayJobApp,
  job_id : String,
  initial_input? : Json? = None,
  child_executor? : ChildRunExecutor? = None,
  analysis_executor? : AnalysisExecutor? = None,
) -> Result[JobRun, String] {
  let run = match
    self
    .runtime()
    .trigger_definition(
      human_readable_run_id(self.now(), self.next_id()),
      job_id,
      TriggerSource::Manual,
      self.now(),
    ) {
    Ok(run) => run
    Err(error) => return Err(error)
  }
  execute_run_lifecycle(
    self.runtime(),
    run.id,
    fn() { self.now() },
    fn() {
      self.new_workflow_engine_with_executors(
        child_executor~,
        analysis_executor~,
      )
    },
    initial_input~,
  )
  Ok(self.runtime().store().get_run(run.id).unwrap_or(run))
}

///|
pub async fn GatewayJobApp::confirm_proposal_and_execute(
  self : GatewayJobApp,
  proposal : JobProposal,
  proposal_id : String,
  child_executor? : ChildRunExecutor? = None,
  analysis_executor? : AnalysisExecutor? = None,
) -> Result[ConfirmProposalResult, String] {
  self.confirm_proposal(proposal, proposal_id, async fn(job_id, initial_input) {
    self.execute_definition(
      job_id,
      initial_input~,
      child_executor~,
      analysis_executor~,
    )
  })
}

///|
pub async fn GatewayJobApp::import_external_proposal_packet(
  self : GatewayJobApp,
  packet : ExternalProposalPacket,
  source_path : String,
  confirm? : Bool = false,
  child_executor? : ChildRunExecutor? = None,
  analysis_executor? : AnalysisExecutor? = None,
) -> Result[ExternalProposalImportResult, String] {
  let profile = match load_job_profile(self.home, self.cwd, packet.profile) {
    Some(profile) => profile
    None =>
      return Err(
        "Unknown external proposal profile: \{packet.profile}. Configure it in moonclaw.jobs.json before import.",
      )
  }
  let proposal_id = human_readable_proposal_id(
    packet.request_text,
    self.now(),
    self.next_id(),
  )
  let imported = proposal_with_external_packet(
    proposal_id,
    packet,
    source_path,
    self.now(),
  )
  let profiled = apply_named_job_profile(
    imported,
    self.cwd,
    self.home,
    self.workspace_root(),
    Some(profile.family),
  )
  let profiled = JobProposal::{
    ..profiled,
    profile_metadata: match packet.output_contract {
      Some(String(contract)) =>
        merge_json_metadata(profiled.profile_metadata, {
          "output_contract": contract,
        })
      _ => profiled.profile_metadata
    },
    steps: profiled.steps.map(fn(step) {
      JobProposalStep::{
        ..step,
        metadata: external_packet_step_metadata(
          step.metadata,
          packet,
          source_path,
        ),
      }
    }),
  }
  self.runtime().store().save_job_proposal(profiled)
  if !confirm {
    return Ok(ExternalProposalImportResult::{
      proposal: profiled,
      confirm_result: None,
    })
  }
  let confirm_result = match
    self.confirm_proposal_and_execute(
      profiled,
      proposal_id,
      child_executor~,
      analysis_executor~,
    ) {
    Ok(result) => result
    Err(error) => return Err(error)
  }
  let saved = self
    .runtime()
    .store()
    .get_job_proposal(proposal_id)
    .unwrap_or(profiled)
  Ok(ExternalProposalImportResult::{
    proposal: saved,
    confirm_result: Some(confirm_result),
  })
}

///|
pub async fn GatewayJobApp::import_external_proposal_packet_file(
  self : GatewayJobApp,
  path : String,
  confirm? : Bool = false,
  child_executor? : ChildRunExecutor? = None,
  analysis_executor? : AnalysisExecutor? = None,
) -> Result[ExternalProposalImportResult, String] {
  let text = @fsx.read_file(path) catch {
    error =>
      return Err("Failed to read external proposal packet \{path}: \{error}")
  }
  let packet = match parse_external_proposal_packet_text(text) {
    Ok(packet) => packet
    Err(error) => return Err(error)
  }
  self.import_external_proposal_packet(
    packet,
    path,
    confirm~,
    child_executor~,
    analysis_executor~,
  )
}

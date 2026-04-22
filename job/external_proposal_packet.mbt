///|
pub struct ExternalProposalPacket {
  packet_id : String?
  title : String?
  summary : String?
  request_text : String
  profile : String
  output_contract : Json?
  source_path : String?
  source_page : String?
  context_pages : Array[String]
  related_pages : Array[String]
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
fn detached_run_input_dir(home : String) -> String {
  @pathx.join(@pathx.join(home, "jobs"), "detached-inputs")
}

///|
fn detached_run_input_path(home : String, run_id : String) -> String {
  @pathx.join(detached_run_input_dir(home), "\{run_id}.json")
}

///|
fn detached_run_args(
  run_id : String,
  home : String,
  cwd : String,
  initial_input_path? : String? = None,
) -> Array[String] {
  let args = ["proposal", "run", run_id, "--home", home, "--cwd", cwd]
  match initial_input_path {
    Some(path) => {
      args.push("--initial-input-file")
      args.push(path)
    }
    None => ()
  }
  args
}

///|
async fn default_detached_run_spawner(
  exec_path : String,
  args : Array[String],
) -> Unit {
  ignore(@process.spawn_orphan(exec_path, args))
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
  let source_path = external_packet_string_field(obj, "source_path")
  let source_page = external_packet_string_field(obj, "source_page")
  let context_pages = external_packet_required_string_list(
    obj.get("context_pages"),
    path,
    "context_pages",
  )
  let related_pages = external_packet_string_list(obj.get("related_pages"))
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
    source_path,
    source_page,
    context_pages,
    related_pages,
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
fn keeper_packet_workspace_root(packet_file_path : String) -> String? {
  let normalized = @pathx.normalize(packet_file_path)
  let marker = "/keeper/jobs/"
  match normalized.find(marker) {
    Some(index) if index > 0 => Some(normalized[:index].to_string())
    _ => None
  }
}

///|
fn source_path_workspace_root(source_path : String?) -> String? {
  match source_path {
    Some(source_path) if @pathx.is_absolute(source_path) => {
      let normalized = @pathx.normalize(source_path)
      let marker = "/raw/"
      match normalized.find(marker) {
        Some(index) if index > 0 => Some(normalized[:index].to_string())
        _ => None
      }
    }
    _ => None
  }
}

///|
fn external_packet_workspace_root(
  packet : ExternalProposalPacket,
  packet_file_path : String,
) -> String? {
  match keeper_packet_workspace_root(packet_file_path) {
    Some(root) => Some(root)
    None => source_path_workspace_root(packet.source_path)
  }
}

///|
fn resolve_packet_path(workspace_root : String?, path : String) -> String {
  if @pathx.is_absolute(path) {
    @pathx.normalize(path)
  } else {
    match workspace_root {
      Some(root) => @pathx.join(root, path)
      None => path
    }
  }
}

///|
fn resolve_packet_paths(
  workspace_root : String?,
  paths : Array[String],
) -> Array[String] {
  paths.map(fn(path) { resolve_packet_path(workspace_root, path) })
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
  packet_file_path : String,
) -> Json {
  let workspace_root = external_packet_workspace_root(packet, packet_file_path)
  let resolved_context_pages = resolve_packet_paths(
    workspace_root,
    packet.context_pages,
  )
  let resolved_skill_paths = resolve_packet_paths(
    workspace_root,
    packet.skill_paths,
  )
  let resolved_source_page = match packet.source_page {
    Some(source_page) => Some(resolve_packet_path(workspace_root, source_page))
    None => None
  }
  let resolved_related_pages = resolve_packet_paths(
    workspace_root,
    packet.related_pages,
  )
  let intake : Map[String, Json] = {}
  intake.set("external_packet_source_path", packet_file_path.to_json())
  intake.set("context_pages", resolved_context_pages.to_json())
  intake.set("skill_paths", resolved_skill_paths.to_json())
  intake.set("raw_context_pages", packet.context_pages.to_json())
  intake.set("raw_skill_paths", packet.skill_paths.to_json())
  intake.set("related_pages", resolved_related_pages.to_json())
  if workspace_root is Some(root) {
    intake.set("external_workspace_root", root.to_json())
  }
  match packet.source_path {
    Some(source_path) =>
      intake.set(
        "source_path",
        resolve_packet_path(workspace_root, source_path).to_json(),
      )
    None => ()
  }
  match resolved_source_page {
    Some(source_page) => intake.set("source_page", source_page.to_json())
    None => ()
  }
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
  packet_file_path : String,
) -> Json {
  let workspace_root = external_packet_workspace_root(packet, packet_file_path)
  let packet_metadata : Map[String, Json] = {}
  packet_metadata.set(
    "schema",
    "moonclaw.external_proposal_packet.v1".to_json(),
  )
  packet_metadata.set("source_path", packet_file_path.to_json())
  packet_metadata.set("profile", packet.profile.to_json())
  packet_metadata.set("context_pages", packet.context_pages.to_json())
  packet_metadata.set("skill_paths", packet.skill_paths.to_json())
  packet_metadata.set(
    "resolved_context_pages",
    resolve_packet_paths(workspace_root, packet.context_pages).to_json(),
  )
  packet_metadata.set(
    "resolved_skill_paths",
    resolve_packet_paths(workspace_root, packet.skill_paths).to_json(),
  )
  packet_metadata.set("related_pages", packet.related_pages.to_json())
  packet_metadata.set("notes", packet.notes.to_json())
  packet_metadata.set("tags", packet.tags.to_json())
  match workspace_root {
    Some(root) => packet_metadata.set("workspace_root", root.to_json())
    None => ()
  }
  match packet.source_path {
    Some(source_path) =>
      packet_metadata.set("packet_source_path", source_path.to_json())
    None => ()
  }
  match packet.source_page {
    Some(source_page) =>
      packet_metadata.set("source_page", source_page.to_json())
    None => ()
  }
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
fn external_packet_runtime_profile_metadata(
  packet : ExternalProposalPacket,
) -> Json {
  let promoted : Map[String, Json] = {}
  match packet.metadata {
    Object(fields) => {
      match fields.get("disable_waiting_for_input") {
        Some(value) => promoted.set("disable_waiting_for_input", value)
        None => ()
      }
      match fields.get("best_effort_on_missing_input") {
        Some(value) => promoted.set("best_effort_on_missing_input", value)
        None => ()
      }
      match fields.get("profile_metadata") {
        Some(Object(profile_metadata)) =>
          for key, value in profile_metadata {
            promoted.set(key, value)
          }
        _ => ()
      }
    }
    _ => ()
  }
  Json::object(promoted)
}

///|
fn external_packet_runtime_step_metadata(
  packet : ExternalProposalPacket,
) -> Json {
  let promoted : Map[String, Json] = {}
  match packet.metadata {
    Object(fields) =>
      match fields.get("step_metadata") {
        Some(Object(step_metadata)) =>
          for key, value in step_metadata {
            promoted.set(key, value)
          }
        _ => ()
      }
    _ => ()
  }
  Json::object(promoted)
}

///|
fn metadata_has_key(metadata : Json, key : String) -> Bool {
  match metadata {
    Object(fields) => fields.contains(key)
    _ => false
  }
}

///|
fn external_packet_text_mentions_web_tools(
  packet : ExternalProposalPacket,
) -> Bool {
  let mut combined = packet.request_text.to_lower()
  for path in packet.skill_paths {
    combined = combined + "\n" + path.to_lower()
  }
  for note in packet.notes {
    combined = combined + "\n" + note.to_lower()
  }
  match packet.output_contract {
    Some(contract) =>
      combined = combined + "\n" + contract.stringify().to_lower()
    None => ()
  }
  combined.contains("web_search") ||
  combined.contains("web-fetch") ||
  combined.contains("web_fetch") ||
  combined.contains("web-first")
}

///|
fn external_packet_step_metadata(
  step_metadata : Json,
  packet : ExternalProposalPacket,
  packet_file_path : String,
) -> Json {
  let workspace_root = external_packet_workspace_root(packet, packet_file_path)
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
  extra.set("external_packet_source_path", packet_file_path.to_json())
  extra.set(
    "context_pages",
    resolve_packet_paths(workspace_root, packet.context_pages).to_json(),
  )
  extra.set(
    "skill_paths",
    resolve_packet_paths(workspace_root, packet.skill_paths).to_json(),
  )
  extra.set("raw_context_pages", packet.context_pages.to_json())
  extra.set("raw_skill_paths", packet.skill_paths.to_json())
  extra.set(
    "related_pages",
    resolve_packet_paths(workspace_root, packet.related_pages).to_json(),
  )
  extra.set("external_packet_notes", packet.notes.to_json())
  match workspace_root {
    Some(root) => extra.set("external_workspace_root", root.to_json())
    None => ()
  }
  match packet.source_path {
    Some(source_path) =>
      extra.set(
        "source_path",
        resolve_packet_path(workspace_root, source_path).to_json(),
      )
    None => ()
  }
  match packet.source_page {
    Some(source_page) =>
      extra.set(
        "source_page",
        resolve_packet_path(workspace_root, source_page).to_json(),
      )
    None => ()
  }
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
  let runtime_step_metadata = external_packet_runtime_step_metadata(packet)
  if external_packet_text_mentions_web_tools(packet) {
    if !metadata_has_key(step_metadata, "enable_tools") &&
      !metadata_has_key(runtime_step_metadata, "enable_tools") {
      extra.set("enable_tools", true.to_json())
    }
    if !metadata_has_key(step_metadata, "web_search") &&
      !metadata_has_key(runtime_step_metadata, "web_search") {
      extra.set("web_search", true.to_json())
    }
    if !metadata_has_key(step_metadata, "tool_contract") &&
      !metadata_has_key(runtime_step_metadata, "tool_contract") {
      extra.set(
        "tool_contract",
        AnalysisToolContract::new(web_fetch=true, web_search=true).to_json(),
      )
    }
  }
  let merged = merge_json_metadata(step_metadata, runtime_step_metadata)
  merge_json_metadata(merged, Json::object(extra))
}

///|
fn proposal_with_external_packet(
  proposal_id : String,
  packet : ExternalProposalPacket,
  packet_file_path : String,
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
        merge_json_metadata(
          draft.profile_metadata,
          external_packet_runtime_profile_metadata(packet),
        ),
        external_proposal_packet_metadata(packet, packet_file_path),
      ),
      Some(external_packet_job_intake(packet, packet_file_path)),
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
      self.next_run_id(),
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
pub async fn GatewayJobApp::execute_existing_run(
  self : GatewayJobApp,
  run_id : String,
  initial_input? : Json? = None,
  child_executor? : ChildRunExecutor? = None,
  analysis_executor? : AnalysisExecutor? = None,
) -> Result[JobRun, String] {
  let existing = match self.runtime().store().get_run(run_id) {
    Some(run) => run
    None => return Err("Unknown job run: \{run_id}")
  }
  match self.ensure_existing_run_definition(existing) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  execute_run_lifecycle(
    self.runtime(),
    run_id,
    fn() { self.now() },
    fn() {
      self.new_workflow_engine_with_executors(
        child_executor~,
        analysis_executor~,
      )
    },
    initial_input~,
  )
  Ok(self.runtime().store().get_run(run_id).unwrap_or(existing))
}

///|
fn proposal_matches_run(proposal : JobProposal, run : JobRun) -> Bool {
  proposal.last_run_id == Some(run.id) || proposal.job_id == Some(run.job_id)
}

///|
pub async fn GatewayJobApp::ensure_existing_run_definition(
  self : GatewayJobApp,
  run : JobRun,
) -> Result[Unit, String] {
  let store = self.runtime().store()
  match store.get_definition(run.job_id) {
    Some(definition) =>
      match definition.workflow_id {
        Some(workflow_id) if store.get_workflow(workflow_id) is None => ()
        _ => return Ok(())
      }
    None => ()
  }
  let proposal = match
    store
    .list_job_proposals()
    .iter()
    .find_first(fn(proposal) { proposal_matches_run(proposal, run) }) {
    Some(proposal) => proposal
    None =>
      return Err(
        "Missing job definition: \{run.job_id}; no confirmed proposal found for run \{run.id}",
      )
  }
  match proposal.status {
    Confirmed => ()
    _ =>
      return Err(
        "Missing job definition: \{run.job_id}; proposal \{proposal.id} is not confirmed",
      )
  }
  let compilation = self.compile_proposal(proposal)
  if compilation.definition.id != run.job_id {
    return Err(
      "Missing job definition: \{run.job_id}; confirmed proposal \{proposal.id} recompiles to \{compilation.definition.id}",
    )
  }
  self.runtime().register_definition(compilation.definition)
  self.runtime().register_workflow(compilation.workflow)
  for binding in compilation.bindings {
    store.save_chat_binding(binding)
  }
  Ok(())
}

///|
pub async fn GatewayJobApp::launch_definition_detached(
  self : GatewayJobApp,
  job_id : String,
  initial_input? : Json? = None,
  spawn_runner? : async (String, Array[String]) -> Unit = default_detached_run_spawner,
) -> Result[JobRun, String] {
  let run = match
    self
    .runtime()
    .trigger_definition(
      self.next_run_id(),
      job_id,
      TriggerSource::Manual,
      self.now(),
    ) {
    Ok(run) => run
    Err(error) => return Err(error)
  }
  let initial_input_path = match initial_input {
    Some(input) => {
      let dir = detached_run_input_dir(self.home)
      @fsx.make_directory(dir, recursive=true, exists_ok=true) catch {
        error =>
          return Err(
            "Failed to create detached input directory \{dir}: \{error}",
          )
      }
      let path = detached_run_input_path(self.home, run.id)
      @fsx.write_to_file(path, input.stringify()) catch {
        error =>
          return Err(
            "Failed to persist detached initial input for run \{run.id}: \{error}",
          )
      }
      Some(path)
    }
    None => None
  }
  let exec_path = @os.executable() catch {
    error => return Err("Failed to resolve MoonClaw executable path: \{error}")
  }
  spawn_runner(
    exec_path,
    detached_run_args(run.id, self.home, self.cwd, initial_input_path~),
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
pub async fn GatewayJobApp::confirm_proposal_and_launch(
  self : GatewayJobApp,
  proposal : JobProposal,
  proposal_id : String,
  spawn_runner? : async (String, Array[String]) -> Unit = default_detached_run_spawner,
) -> Result[ConfirmProposalResult, String] {
  self.confirm_proposal(proposal, proposal_id, async fn(job_id, initial_input) {
    self.launch_definition_detached(job_id, initial_input~, spawn_runner~)
  })
}

///|
pub async fn GatewayJobApp::import_external_proposal_packet(
  self : GatewayJobApp,
  packet : ExternalProposalPacket,
  packet_file_path : String,
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
    packet_file_path,
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
          packet_file_path,
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

///|
fn infer_job_tags(request_text : String) -> Array[String] {
  let lower = request_text.to_lower()
  let tags = ["job"]
  if lower.contains("summarize") || lower.contains("summary") {
    tags.push("summary")
  }
  if lower.contains("monitor") ||
    lower.contains("track") ||
    lower.contains("watch") {
    tags.push("monitoring")
  }
  tags
}

///|
fn compact_title(text : String) -> String {
  let trimmed = text.trim().to_string()
  if trimmed.length() <= 72 {
    trimmed
  } else {
    "\{trimmed[:69].to_string()}..."
  }
}

///|
fn compact_preview(text : String, max_len : Int) -> String {
  let trimmed = text.trim().to_string()
  if trimmed.length() <= max_len {
    trimmed
  } else {
    "\{trimmed[:max_len - 3].to_string()}..."
  }
}

///|
fn generic_proposal_steps(request_text : String) -> Array[JobProposalStep] {
  [
    JobProposalStep::{
      id: "execute",
      title: "Execute requested work",
      kind: "job.analysis",
      metadata: {},
      child_profile: None,
      execution_mode: None,
      execution_target: None,
      include_parent_outputs: None,
      max_depth: None,
      prompt: [
        "Perform the requested job directly.",
        "Produce concrete results, not just advice.",
        "State any assumptions and remaining risks in the final output.",
        "Request: \{request_text}",
      ].join("\n\n"),
    },
  ]
}

///|
fn non_blank_string_or_none(value : Json?) -> String? {
  match value {
    Some(String(text)) => {
      let trimmed = text.trim().to_string()
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
fn non_blank_string_array_lines(value : Json?) -> String? {
  match value {
    Some(Array(items)) => {
      let lines : Array[String] = []
      for item in items {
        match item {
          String(text) => {
            let trimmed = text.trim().to_string()
            if !trimmed.is_blank() {
              lines.push(trimmed)
            }
          }
          _ => ()
        }
      }
      if lines.is_empty() {
        None
      } else {
        Some(lines.join("\n"))
      }
    }
    _ => None
  }
}

///|
fn proposal_requested_output_format(proposal : JobProposal) -> String? {
  match proposal_initial_input(proposal) {
    Some(Object(obj)) =>
      match obj.get("requested_output_format") {
        Some(String(value)) if !value.trim().to_string().is_blank() =>
          Some(value.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn proposal_starter_file_labels(proposal : JobProposal) -> Array[String] {
  match proposal_initial_input(proposal) {
    Some(Object(obj)) =>
      match obj.get("starter_attachments") {
        Some(Array(items)) => {
          let files : Array[String] = []
          for item in items {
            match item {
              Object(attachment) => {
                let label = match attachment.get("filename") {
                  Some(String(name)) if !name.trim().to_string().is_blank() =>
                    name.trim().to_string()
                  _ =>
                    match attachment.get("id") {
                      Some(String(id)) if !id.trim().to_string().is_blank() =>
                        id.trim().to_string()
                      _ => ""
                    }
                }
                if !label.is_blank() {
                  files.push(label)
                }
              }
              _ => ()
            }
          }
          files
        }
        _ => []
      }
    _ => []
  }
}

///|
struct ProposalPlanStepPayload {
  id : String?
  title : String
  prompt : String
  kind : String?
  metadata : Json?
  child_profile : String?
  execution_mode : String?
  execution_target : String?
  include_parent_outputs : Bool?
  max_depth : Int?
} derive(ToJson, Show)

///|
impl @json.FromJson for ProposalPlanStepPayload with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ProposalPlanStepPayload raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "ProposalPlanStepPayload: expected object"),
    )
  }
  let id : String? = match obj.get("id") {
    Some(String(id)) => Some(id)
    _ => None
  }
  let title : String = match obj.get("title") {
    Some(String(title)) => title
    _ =>
      match obj.get("step") {
        Some(String(step)) if !step.trim().to_string().is_blank() => step
        _ =>
          raise @json.JsonDecodeError(
            (path, "ProposalPlanStepPayload: missing 'title'/'step'"),
          )
      }
  }
  let prompt : String = match non_blank_string_or_none(obj.get("prompt")) {
    Some(prompt) => prompt
    None =>
      match non_blank_string_or_none(obj.get("details")) {
        Some(details) => details
        None =>
          match non_blank_string_array_lines(obj.get("details")) {
            Some(details) => details
            None =>
              match non_blank_string_or_none(obj.get("description")) {
                Some(description) => description
                None =>
                  match non_blank_string_or_none(obj.get("instruction")) {
                    Some(instruction) => instruction
                    None =>
                      match non_blank_string_or_none(obj.get("objective")) {
                        Some(objective) => objective
                        None =>
                          match non_blank_string_or_none(obj.get("step")) {
                            Some(step) => step
                            None =>
                              raise @json.JsonDecodeError(
                                (
                                  path, "ProposalPlanStepPayload: missing 'prompt'/'details'/'description'/'instruction'/'objective'/'step'",
                                ),
                              )
                          }
                      }
                  }
              }
          }
      }
  }
  let kind : String? = match obj.get("kind") {
    Some(String(kind)) => Some(kind)
    _ => None
  }
  let metadata : Json? = match obj.get("metadata") {
    Some(metadata) => Some(metadata)
    _ => None
  }
  let child_profile : String? = match obj.get("child_profile") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      Some(value.trim().to_string())
    _ => None
  }
  let execution_mode : String? = match obj.get("execution_mode") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      Some(value.trim().to_string())
    _ => None
  }
  let execution_target : String? = match obj.get("execution_target") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      Some(value.trim().to_string())
    _ => None
  }
  let include_parent_outputs : Bool? = match obj.get("include_parent_outputs") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
  let max_depth : Int? = match obj.get("max_depth") {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
  {
    id,
    title,
    prompt,
    kind,
    metadata,
    child_profile,
    execution_mode,
    execution_target,
    include_parent_outputs,
    max_depth,
  }
}

///|
struct ProposalPlanPayload {
  title : String?
  summary : String?
  tags : Array[String]?
  steps : Array[ProposalPlanStepPayload]?
} derive(ToJson, Show)

///|
impl @json.FromJson for ProposalPlanPayload with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ProposalPlanPayload raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "ProposalPlanPayload: expected object"))
  }
  let title : String? = match non_blank_string_or_none(obj.get("title")) {
    Some(title) => Some(title)
    None => non_blank_string_or_none(obj.get("job"))
  }
  let summary : String? = match obj.get("summary") {
    Some(String(summary)) if !summary.trim().to_string().is_blank() =>
      Some(summary)
    _ =>
      match obj.get("overview") {
        Some(String(overview)) if !overview.trim().to_string().is_blank() =>
          Some(overview)
        _ => None
      }
  }
  let tags : Array[String]? = match obj.get("tags") {
    Some(tags_json) => Some(@json.from_json(tags_json, path~))
    _ => None
  }
  let steps : Array[ProposalPlanStepPayload]? = match obj.get("steps") {
    Some(steps_json) => Some(@json.from_json(steps_json, path~))
    _ =>
      match obj.get("plan") {
        Some(plan_json) => Some(@json.from_json(plan_json, path~))
        _ =>
          match obj.get("draft_plan") {
            Some(plan_json) => Some(@json.from_json(plan_json, path~))
            _ => None
          }
      }
  }
  { title, summary, tags, steps }
}

///|
fn normalize_proposal_step_id(
  index : Int,
  step : ProposalPlanStepPayload,
) -> String {
  match step.id {
    Some(id) if !id.trim().to_string().is_blank() => id.trim().to_string()
    _ => "step_\{index + 1}"
  }
}

///|
fn merge_step_metadata(base : Json?, extras : Array[(String, Json?)]) -> Json {
  let merged : Map[String, Json] = {}
  match base {
    Some(Object(obj)) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  for extra in extras {
    match extra.1 {
      Some(value) => merged.set(extra.0, value)
      None => ()
    }
  }
  Json::object(merged)
}

///|
fn step_metadata_with_aliases(step : ProposalPlanStepPayload) -> Json {
  let object = match step.metadata {
    Some(Object(obj)) => Some(obj)
    _ => None
  }
  let field = fn(key : String) {
    match object {
      Some(obj) => obj.get(key)
      None => None
    }
  }
  merge_step_metadata(step.metadata, [
    ("preferred_skills", field("preferred_skills")),
    ("enable_tools", field("enable_tools")),
    ("web_search", field("web_search")),
    ("model", field("model")),
    ("system_prompt", field("system_prompt")),
  ])
}

///|
fn step_kind_or_default(step : ProposalPlanStepPayload) -> String {
  match step.kind {
    Some(kind) if !kind.trim().to_string().is_blank() => kind.trim().to_string()
    _ => "job.analysis"
  }
}

///|
fn normalized_plan_steps(
  payload : ProposalPlanPayload,
  fallback_request : String,
) -> Array[JobProposalStep] {
  let fallback = generic_proposal_steps(fallback_request)
  match payload.steps {
    Some(steps) if !steps.is_empty() => {
      let normalized = []
      let mut index = 0
      for step in steps {
        normalized.push(JobProposalStep::{
          id: normalize_proposal_step_id(index, step),
          title: step.title.trim().to_string(),
          prompt: step.prompt.trim().to_string(),
          kind: step_kind_or_default(step),
          metadata: step_metadata_with_aliases(step),
          child_profile: step.child_profile,
          execution_mode: step.execution_mode,
          execution_target: step.execution_target,
          include_parent_outputs: step.include_parent_outputs,
          max_depth: step.max_depth,
        })
        index += 1
      }
      normalized
    }
    _ => fallback
  }
}

///|
fn request_prefers_multi_step_plan(request_text : String) -> Bool {
  let lower = request_text.to_lower()
  lower.contains("calculate") ||
  lower.contains("calculation") ||
  lower.contains("estimation") ||
  lower.contains("estimate") ||
  lower.contains("analysis") ||
  lower.contains("financial") ||
  lower.contains("business") ||
  lower.contains("land acquisition") ||
  lower.contains("report") ||
  lower.contains("assessment")
}

///|
fn is_generic_single_execute_plan(payload : ProposalPlanPayload) -> Bool {
  match payload.steps {
    Some([step]) => {
      let title = step.title.trim().to_lower()
      let prompt = step.prompt.trim().to_lower()
      let id = step.id.map(fn(id) { id.trim().to_lower() }).unwrap_or("")
      (id == "execute" || id == "step_1") &&
      (
        title == "execute" ||
        title == "execute requested work" ||
        title == "do the work"
      ) &&
      (
        prompt.contains("execute") ||
        prompt.contains("perform the requested job")
      )
    }
    _ => false
  }
}

///|
fn is_under_decomposed_plan(
  payload : ProposalPlanPayload,
  request_text : String,
) -> Bool {
  let steps = normalized_plan_steps(payload, request_text)
  if !request_prefers_multi_step_plan(request_text) {
    return false
  }
  if steps.length() >= 2 {
    return false
  }
  if is_generic_single_execute_plan(payload) {
    return true
  }
  match steps {
    [step] => {
      let title = step.title.trim().to_lower()
      let prompt = step.prompt.trim().to_lower()
      title == "execute" ||
      title == "execute requested work" ||
      title == "analysis" ||
      title == "do the work" ||
      prompt.contains("perform the requested job directly") ||
      prompt.contains("execute requested work")
    }
    _ => true
  }
}

///|
fn planner_repair_prompt(
  request_text : String,
  prior_output : String,
) -> String {
  [
    "Your previous plan did not follow the required planning contract closely enough.",
    "The loaded `job-planning` skill is authoritative. Follow its exact JSON schema and forbidden-alias rules.",
    "Return JSON only.",
    "Use the exact top-level shape from the skill: `title`, `summary`, `tags`, `steps`.",
    "Do not use aliases such as `plan`, `draft_plan`, `job`, `request_text`, `overview`, `step`, `details`, or `objective`.",
    "Do not return a single generic execute step.",
    "Produce 4 to 8 concrete phases when the request is analytical, business, estimation, due-diligence, or report-oriented.",
    "For this request, return at least 5 steps unless the request is obviously trivial.",
    "Each step must have a concrete business or analytical deliverable, not filler.",
    "Request:\n\{request_text}",
    "Previous planner output:\n\{prior_output}",
  ].join("\n\n")
}

///|
fn proposal_with_planner_diagnostic(
  proposal : JobProposal,
  reason : String,
  preview? : String? = None,
) -> JobProposal {
  let diagnostic = match preview {
    Some(preview) if !preview.trim().to_string().is_blank() =>
      "Planner fallback used: \{reason}. Planner output preview: \{compact_preview(preview, 240)}"
    _ => "Planner fallback used: \{reason}."
  }
  JobProposal::{ ..proposal, summary: diagnostic }
}

///|
fn proposal_payload_to_proposal(
  proposal_id : String,
  request_text : String,
  payload : ProposalPlanPayload,
  now_ms : Int,
  channel_id : String?,
  account_id : String?,
  recipient : String?,
  thread_id : String?,
  existing? : JobProposal? = None,
) -> JobProposal {
  let fallback = match existing {
    Some(existing) => existing
    None =>
      draft_job_proposal(
        proposal_id,
        request_text,
        now_ms,
        channel_id~,
        account_id~,
        recipient~,
        thread_id~,
      )
  }
  let title = payload.title.map(compact_title).unwrap_or(fallback.title)
  let summary = payload.summary
    .map(fn(text) { text.trim().to_string() })
    .unwrap_or(fallback.summary)
  let steps = normalized_plan_steps(payload, request_text)
  let tags = payload.tags.unwrap_or(fallback.tags)
  JobProposal::{
    ..fallback,
    title,
    request_text,
    summary,
    revision_history: fallback.revision_history,
    status: Draft,
    steps,
    tags,
    updated_at: now_ms,
  }
}

///|
fn render_profile_step_template(
  template : String,
  proposal : JobProposal,
  family : String,
  workspace_root : String,
) -> String {
  let rendered = template.replace_all(
    old="${request}",
    new=proposal.request_text,
  )
  let rendered = rendered.replace_all(old="${proposal.id}", new=proposal.id)
  let rendered = rendered.replace_all(
    old="${proposal.title}",
    new=proposal.title,
  )
  let rendered = rendered.replace_all(
    old="${proposal.summary}",
    new=proposal.summary,
  )
  let rendered = rendered.replace_all(old="${family}", new=family)
  rendered.replace_all(old="${workspace}", new=workspace_root)
}

///|
async fn maybe_apply_job_profile(
  proposal : JobProposal,
  cwd : String,
  home : String,
  workspace_root : String,
) -> JobProposal {
  let family = suggest_job_profile_family(proposal.request_text, home, cwd)
  apply_named_job_profile(proposal, cwd, home, workspace_root, family)
}

///|
fn merge_json_metadata(base : Json, extra : Json) -> Json {
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
pub async fn apply_named_job_profile(
  proposal : JobProposal,
  cwd : String,
  home : String,
  workspace_root : String,
  family : String?,
) -> JobProposal {
  let profile = match family {
    Some(family) => load_job_profile(home, cwd, family)
    None => None
  }
  match profile {
    Some(profile) if !profile.steps.is_empty() => {
      let family = profile.family
      let steps = profile.steps.map(fn(step) {
        let prompt_source = if step.kind == "job.delegate" {
          step.request_template.unwrap_or(proposal.request_text)
        } else {
          step.prompt_template.unwrap_or(proposal.request_text)
        }
        JobProposalStep::{
          id: step.id,
          title: step.title,
          kind: step.kind,
          metadata: step.metadata.unwrap_or({}),
          child_profile: step.child_profile,
          execution_mode: step.execution_mode,
          execution_target: step.execution_target,
          include_parent_outputs: step.include_parent_outputs,
          max_depth: step.max_depth,
          prompt: render_profile_step_template(
            prompt_source, proposal, family, workspace_root,
          ),
        }
      })
      JobProposal::{
        ..proposal,
        suggested_family: Some(family),
        profile_id: Some(profile.id),
        profile_role: profile.role,
        profile_metadata: merge_json_metadata(
          proposal.profile_metadata,
          profile.metadata,
        ),
        steps,
        tags: [..proposal.tags, ..profile.tags],
      }
    }
    _ => proposal
  }
}

///|
fn planner_system_prompt(e2e_mode? : Bool = false) -> String {
  [
    "You design safe draft job plans for an automation system.",
    "Never execute the job.",
    "The loaded `job-planning` skill is the authoritative output contract.",
    "Follow that skill exactly.",
    "Return strict JSON only.",
    "Use the exact field names defined by the skill and do not invent aliases.",
    "Use kind `job.analysis` unless a better existing workflow step kind is clearly required.",
    "Write concrete, execution-oriented steps.",
    "Use the smallest sufficient number of steps, but do not collapse non-trivial work into one generic execute step.",
    "For non-trivial analytical, business, calculation, due-diligence, or report requests, produce 4 to 8 distinct phases.",
    ..if e2e_mode {
      e2e_planner_system_guidance()
    } else {
      []
    },
    "Step titles should be short and human-readable.",
    "Step prompts should tell the step exactly what to produce.",
  ].join("\n")
}

///|
fn planner_request_prompt(
  request_text : String,
  intake? : Json? = None,
  skills_prompt? : String = "",
  revision? : String? = None,
  existing? : JobProposal? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
  e2e_mode? : Bool = false,
) -> String {
  let parts = ["Create a draft plan for this requested job:", request_text]
  let parts = if e2e_mode {
    [..parts, ..e2e_planner_prompt_sections(intake)]
  } else {
    parts
  }
  let parts = match workspace {
    Some(workspace) if !workspace.trim().to_string().is_blank() =>
      [..parts, "Workspace root: \{workspace}"]
    _ => parts
  }
  let parts = match memory_context {
    Some(memory_context) if !memory_context.trim().to_string().is_blank() =>
      [..parts, memory_context]
    _ => parts
  }
  let parts = if skills_prompt.is_blank() {
    parts
  } else {
    [..parts, skills_prompt]
  }
  let parts = match existing {
    Some(existing) => {
      let rendered_steps = existing.steps
        .map(fn(step) { "- \{step.id}: \{step.title}" })
        .join("\n")
      let revision_notes = if existing.revision_history.is_empty() {
        ""
      } else {
        let items = existing.revision_history
          .map(fn(item) { "- \{item}" })
          .join("\n")
        "Previous revision guidance:\n\{items}"
      }
      [
        ..parts,
        "Existing proposal title: \{existing.title}",
        "Existing proposal summary: \{existing.summary}",
        "Existing proposal steps:\n\{rendered_steps}",
        revision_notes,
      ]
    }
    None => parts
  }
  let parts = match revision {
    Some(revision) if !revision.trim().to_string().is_blank() =>
      [..parts, "Revise the draft with this extra guidance:", revision]
    _ => parts
  }
  [
    ..parts, "Use the loaded `job-planning` skill as the authoritative contract.",
    "Return JSON only.", "Use the exact field names from the skill and do not invent aliases.",
    "If the request is non-trivial, decompose it into multiple meaningful steps instead of a single generic execution step.",
  ].join("\n\n")
}

///|
fn maybe_parse_payload(text : String) -> ProposalPlanPayload? {
  let trimmed = text.trim().to_string()
  if trimmed.is_blank() {
    return None
  }
  let first = match trimmed.find("{") {
    Some(index) => index
    None => return None
  }
  let mut end = trimmed.length()
  while end > first {
    let candidate = trimmed[first:end].to_string()
    if !candidate.has_suffix("}") {
      end = end - 1
      continue
    }
    let parsed_json = try? @json.parse(candidate)
    match parsed_json {
      Ok(json) => {
        let payload_result = try? @json.from_json(json)
        match payload_result {
          Ok(payload) => return Some(payload)
          Err(_) => ()
        }
      }
      Err(_) => ()
    }
    end = end - 1
  }
  None
}

///|
fn planner_preferred_skills() -> Array[String] {
  ["job-planning"]
}

///|
fn with_e2e_pipeline(proposal : JobProposal) -> JobProposal {
  proposal
  |> mark_proposal_as_e2e()
  |> with_e2e_preprocess_steps()
  |> with_e2e_postprocess_steps()
}

///|
async fn plan_job_proposal_with_mode(
  proposal_id : String,
  request_text : String,
  now_ms : Int,
  e2e_mode : Bool,
  executor? : AnalysisExecutor = default_analysis_executor(),
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
  cwd? : String = ".",
  home? : String? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
) -> JobProposal {
  let preferred_skills = planner_preferred_skills()
  let loaded_skills = loaded_skills_prompt(cwd, home, preferred_skills)
  let request = AnalysisRequest::{
    job_id: "proposal:\{proposal_id}",
    run_id: "proposal:\{proposal_id}",
    step_id: "planner",
    prompt: planner_request_prompt(
      request_text,
      intake~,
      skills_prompt=loaded_skills,
      workspace~,
      memory_context~,
      e2e_mode~,
    ),
    model_name: model.unwrap_or("default"),
    cwd,
    home,
    execution_mode: None,
    execution_target: None,
    system_prompt: planner_system_prompt(e2e_mode~),
    preferred_skills,
    enable_tools: false,
    web_search: false,
    tool_contract: AnalysisToolContract::new(
      shell=false,
      list_files=false,
      read_files=false,
      search_files=false,
      todo=false,
      file_write=false,
      web_search=false,
    ),
    execution_isolation: None,
    role_runtime_contract: None,
  }
  let fallback = draft_job_proposal(
    proposal_id,
    request_text,
    now_ms,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
  )
  let fallback = match intake {
    Some(intake) =>
      JobProposal::{
        ..fallback,
        profile_metadata: merge_job_intake_metadata(
          fallback.profile_metadata,
          Some(intake),
        ),
      }
    None => fallback
  }
  let fallback = maybe_apply_job_profile(
    fallback,
    cwd,
    home.unwrap_or(cwd),
    workspace.unwrap_or(cwd),
  )
  let execution = match (executor.run)(request) {
    Ok(execution) => execution
    Err(error) =>
      return proposal_with_planner_diagnostic(
        fallback,
        "analysis executor failed",
        preview=Some(error),
      )
  }
  match maybe_parse_payload(execution.content) {
    Some(payload) => {
      let initial_payload = payload
      let payload = if is_under_decomposed_plan(payload, request_text) {
        let repair_request = AnalysisRequest::{
          ..request,
          step_id: "planner.repair",
          prompt: planner_repair_prompt(request_text, execution.content),
        }
        match (executor.run)(repair_request) {
          Ok(repair_execution) =>
            maybe_parse_payload(repair_execution.content).unwrap_or(payload)
          Err(_) => payload
        }
      } else {
        payload
      }
      if is_under_decomposed_plan(payload, request_text) {
        let preview = if payload.steps is Some(_) {
          payload.to_json().stringify()
        } else {
          execution.content
        }
        return proposal_with_planner_diagnostic(
          fallback,
          if is_under_decomposed_plan(initial_payload, request_text) {
            "planner returned an under-decomposed plan even after repair"
          } else {
            "planner returned an under-decomposed plan"
          },
          preview=Some(preview),
        )
      }
      let proposal = proposal_payload_to_proposal(
        proposal_id, request_text, payload, now_ms, channel_id, account_id, recipient,
        thread_id,
      )
      let proposal = JobProposal::{
        ..proposal,
        profile_metadata: fallback.profile_metadata,
      }
      let proposal = maybe_apply_job_profile(
        proposal,
        cwd,
        home.unwrap_or(cwd),
        workspace.unwrap_or(cwd),
      )
      proposal
    }
    None =>
      proposal_with_planner_diagnostic(
        fallback,
        "model output was not valid proposal JSON",
        preview=Some(execution.content),
      )
  }
}

///|
pub struct JobPlanPreviewStep {
  id : String
  title : String
} derive(Show, ToJson, FromJson)

///|
pub struct JobPlanPreview {
  title : String
  request_text : String
  summary : String
  steps : Array[JobPlanPreviewStep]
  requested_output_format : String?
  starter_files : Array[String]
  source : String
} derive(Show, ToJson, FromJson)

///|
fn proposal_to_plan_preview(
  proposal : JobProposal,
  source : String,
) -> JobPlanPreview {
  JobPlanPreview::{
    title: proposal.title,
    request_text: proposal.request_text,
    summary: proposal.summary,
    steps: proposal.steps.map(fn(step) {
      JobPlanPreviewStep::{ id: step.id, title: step.title }
    }),
    requested_output_format: proposal_requested_output_format(proposal),
    starter_files: proposal_starter_file_labels(proposal),
    source,
  }
}

///|
pub fn plan_preview_from_proposal(
  proposal : JobProposal,
  source? : String = "plan_mode",
) -> JobPlanPreview {
  proposal_to_plan_preview(proposal, source)
}

///|
pub async fn plan_chat_mode(
  request_text : String,
  now_ms : Int,
  executor? : AnalysisExecutor = default_analysis_executor(),
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
  cwd? : String = ".",
  home? : String? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
) -> JobPlanPreview {
  let proposal = plan_job_proposal_with_mode(
    "plan-preview",
    request_text,
    now_ms,
    false,
    executor~,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
    cwd~,
    home~,
    workspace~,
    memory_context~,
  )
  proposal_to_plan_preview(proposal, "plan_mode")
}

///|
pub fn promote_plan_candidate(
  candidate : JobProposal,
  proposal_id : String,
  request_text : String,
  now_ms : Int,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
) -> JobProposal {
  JobProposal::{
    ..candidate,
    id: proposal_id,
    title: compact_title(request_text),
    request_text,
    status: Draft,
    channel_id,
    account_id,
    recipient,
    thread_id,
    presented_message_id: None,
    job_id: None,
    workflow_id: None,
    last_run_id: None,
    created_at: now_ms,
    updated_at: now_ms,
  }
}

///|
pub async fn plan_job_proposal(
  proposal_id : String,
  request_text : String,
  now_ms : Int,
  executor? : AnalysisExecutor = default_analysis_executor(),
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
  cwd? : String = ".",
  home? : String? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
) -> JobProposal {
  plan_job_proposal_with_mode(
    proposal_id,
    request_text,
    now_ms,
    false,
    executor~,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
    cwd~,
    home~,
    workspace~,
    memory_context~,
  )
}

///|
pub async fn plan_e2e_job_proposal(
  proposal_id : String,
  request_text : String,
  now_ms : Int,
  executor? : AnalysisExecutor = default_analysis_executor(),
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
  cwd? : String = ".",
  home? : String? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
) -> JobProposal {
  with_e2e_pipeline(
    plan_job_proposal_with_mode(
      proposal_id,
      request_text,
      now_ms,
      true,
      executor~,
      intake~,
      channel_id~,
      account_id~,
      recipient~,
      thread_id~,
      model~,
      cwd~,
      home~,
      workspace~,
      memory_context~,
    ),
  )
}

///|
pub async fn revise_job_proposal(
  proposal : JobProposal,
  revision : String,
  now_ms : Int,
  executor? : AnalysisExecutor = default_analysis_executor(),
  model? : String? = None,
  cwd? : String = ".",
  home? : String? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
) -> JobProposal {
  let preferred_skills = planner_preferred_skills()
  let loaded_skills = loaded_skills_prompt(cwd, home, preferred_skills)
  let request = AnalysisRequest::{
    job_id: "proposal:\{proposal.id}",
    run_id: "proposal:\{proposal.id}",
    step_id: "planner.revise",
    prompt: planner_request_prompt(
      proposal.request_text,
      intake=proposal_initial_input(proposal),
      skills_prompt=loaded_skills,
      revision=Some(revision),
      existing=Some(proposal),
      workspace~,
      memory_context~,
      e2e_mode=proposal_is_e2e(proposal),
    ),
    model_name: model.unwrap_or("default"),
    cwd,
    home,
    execution_mode: None,
    execution_target: None,
    system_prompt: planner_system_prompt(e2e_mode=proposal_is_e2e(proposal)),
    preferred_skills,
    enable_tools: false,
    web_search: false,
    tool_contract: AnalysisToolContract::new(
      shell=false,
      list_files=false,
      read_files=false,
      search_files=false,
      todo=false,
      file_write=false,
      web_search=false,
    ),
    execution_isolation: None,
    role_runtime_contract: None,
  }
  let execution = match (executor.run)(request) {
    Ok(execution) => execution
    Err(_) =>
      return JobProposal::{
        ..proposal,
        revision_history: [..proposal.revision_history, revision],
        updated_at: now_ms,
      }
  }
  match maybe_parse_payload(execution.content) {
    Some(payload) => {
      let revised = JobProposal::{
        ..proposal_payload_to_proposal(
          proposal.id,
          proposal.request_text,
          payload,
          now_ms,
          proposal.channel_id,
          proposal.account_id,
          proposal.recipient,
          proposal.thread_id,
          existing=Some(proposal),
        ),
        revision_history: [..proposal.revision_history, revision],
      }
      let revised = maybe_apply_job_profile(
        revised,
        cwd,
        home.unwrap_or(cwd),
        workspace.unwrap_or(cwd),
      )
      if proposal_is_e2e(proposal) {
        with_e2e_pipeline(revised)
      } else {
        revised
      }
    }
    None =>
      JobProposal::{
        ..proposal,
        revision_history: [..proposal.revision_history, revision],
        updated_at: now_ms,
      }
  }
}

///|
pub fn ensure_draft_proposal(
  proposal : JobProposal,
  proposal_ref : String,
) -> String? {
  guard proposal.status is Draft else {
    return Some(
      "Proposal \{proposal_ref} is already \{proposal.status.to_json().stringify()}",
    )
  }
  None
}

///|
pub async fn save_confirmed_job_proposal(
  store : SystemStore,
  proposal : JobProposal,
  compilation : ProposalCompilation,
  run_id : String,
  now_ms : Int,
) -> Unit {
  store.save_job_proposal(JobProposal::{
    ..proposal,
    suggested_family: Some(compilation.family),
    status: Confirmed,
    job_id: Some(compilation.definition.id),
    workflow_id: Some(compilation.workflow.id),
    last_run_id: Some(run_id),
    updated_at: now_ms,
  })
}

///|
pub async fn save_rejected_job_proposal(
  store : SystemStore,
  proposal : JobProposal,
  now_ms : Int,
) -> Unit {
  store.save_job_proposal(JobProposal::{
    ..proposal,
    status: Rejected,
    updated_at: now_ms,
  })
}

///|
pub fn draft_job_proposal(
  proposal_id : String,
  request_text : String,
  now_ms : Int,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
) -> JobProposal {
  let steps = generic_proposal_steps(request_text)
  let tags = infer_job_tags(request_text)
  JobProposal::{
    id: proposal_id,
    title: compact_title(request_text),
    request_text,
    summary: [
      "Draft job proposal generated from chat request.", "This proposal will not execute until explicitly confirmed.",
    ].join(" "),
    revision_history: [],
    suggested_family: Some("generic"),
    profile_id: None,
    profile_role: None,
    profile_metadata: {},
    status: Draft,
    steps,
    tags,
    channel_id,
    account_id,
    recipient,
    thread_id,
    presented_message_id: None,
    job_id: None,
    workflow_id: None,
    last_run_id: None,
    created_at: now_ms,
    updated_at: now_ms,
  }
}

///|
pub fn proposal_as_workflow(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root? : String = cwd,
) -> (JobDefinition, WorkflowDefinition) {
  let compilation = compile_job_proposal(
    proposal,
    now_ms,
    cwd,
    home,
    workspace_root~,
  )
  (compilation.definition, compilation.workflow)
}

///|
pub fn render_job_proposal_for_chat(proposal : JobProposal) -> String {
  let family = proposal.suggested_family.unwrap_or("")
  let lines = [
    "Job proposal `\{proposal.id}`",
    "",
    "Title: \{proposal.title}",
    "Status: \{proposal.status.to_json().stringify()}",
  ]
  if !family.is_blank() {
    lines.push("Family: \{family}")
  }
  match proposal_requested_output_format(proposal) {
    Some(format) => lines.push("Requested output: \{format}")
    None => ()
  }
  lines.push("")
  lines.push("Summary: \{proposal.summary}")
  let starter_files = proposal_starter_file_labels(proposal)
  let lines = if starter_files.is_empty() {
    lines
  } else {
    [
      ..lines,
      "",
      "Included starter files:",
      ..starter_files.map(fn(file) { "- \{file}" }),
    ]
  }
  let lines = [..lines, "", "Planned steps:"]
  let lines = proposal.steps.fold(init=lines, fn(lines, step) {
    [..lines, "\{step.id}. \{step.title}"]
  })
  [
    ..lines,
    "",
    "Confirm with `/confirm \{proposal.id}`",
    "Revise with `/revise \{proposal.id} <extra guidance>`",
    "Reject with `/reject \{proposal.id}`",
  ].join("\n")
}

///|
pub fn render_job_plan_preview_for_chat(preview : JobPlanPreview) -> String {
  let lines = ["Plan preview", "", "Title: \{preview.title}"]
  match preview.requested_output_format {
    Some(format) => lines.push("Requested output: \{format}")
    None => ()
  }
  let lines = [..lines, "", "Summary: \{preview.summary}"]
  let lines = if preview.starter_files.is_empty() {
    lines
  } else {
    [
      ..lines,
      "",
      "Included starter files:",
      ..preview.starter_files.map(fn(file) { "- \{file}" }),
    ]
  }
  let lines = [..lines, "", "Planned steps:"]
  let lines = preview.steps.fold(init=lines, fn(lines, step) {
    [..lines, "\{step.id}. \{step.title}"]
  })
  [
    ..lines,
    "",
    "This is an in-session plan preview. It is not saved and will not execute by itself.",
    "Reply in the same thread with plain text to refine this plan.",
    "Use `/preview` to inspect the current plan-mode state again without promoting it.",
    "Use `/promote` to turn this plan into a durable proposal.",
    "Use `/plan-job \{preview.request_text}` to create a separate durable proposal directly.",
    "Use `/e2e \{preview.request_text}` for preprocess + planned execution.",
  ].join("\n")
}

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
struct ProposalPlanStepPayload {
  id : String?
  title : String
  prompt : String
  kind : String?
} derive(FromJson, ToJson, Show)

///|
struct ProposalPlanPayload {
  title : String?
  summary : String?
  tags : Array[String]?
  steps : Array[ProposalPlanStepPayload]?
} derive(FromJson, ToJson, Show)

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
          metadata: {},
          child_profile: None,
          execution_mode: None,
          execution_target: None,
          include_parent_outputs: None,
          max_depth: None,
        })
        index += 1
      }
      normalized
    }
    _ => fallback
  }
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
        profile_metadata: profile.metadata,
        steps,
        tags: [..proposal.tags, ..profile.tags],
      }
    }
    _ => proposal
  }
}

///|
fn planner_system_prompt() -> String {
  [
    "You design safe draft job plans for an automation system.", "Never execute the job.",
    "Return strict JSON only.", "JSON shape:", "{\"title\": string, \"summary\": string, \"tags\": string[], \"steps\": [{\"id\": string, \"title\": string, \"prompt\": string, \"kind\": string}]}",
    "Use kind `job.analysis` unless a better existing workflow step kind is clearly required.",
    "Write concrete, execution-oriented steps.",
  ].join("\n")
}

///|
fn planner_request_prompt(
  request_text : String,
  revision? : String? = None,
  existing? : JobProposal? = None,
  workspace? : String? = None,
  memory_context? : String? = None,
) -> String {
  let parts = ["Create a draft plan for this requested job:", request_text]
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
  [..parts, "Return JSON only."].join("\n\n")
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
pub async fn plan_job_proposal(
  proposal_id : String,
  request_text : String,
  now_ms : Int,
  executor? : AnalysisExecutor = default_analysis_executor(),
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
  let request = AnalysisRequest::{
    job_id: "proposal:\{proposal_id}",
    run_id: "proposal:\{proposal_id}",
    step_id: "planner",
    prompt: planner_request_prompt(request_text, workspace~, memory_context~),
    model_name: model.unwrap_or("default"),
    cwd,
    home,
    execution_mode: None,
    execution_target: None,
    system_prompt: planner_system_prompt(),
    preferred_skills: [],
    enable_tools: false,
    web_search: false,
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
  let fallback = maybe_apply_job_profile(
    fallback,
    cwd,
    home.unwrap_or(cwd),
    workspace.unwrap_or(cwd),
  )
  let execution = match (executor.run)(request) {
    Ok(execution) => execution
    Err(_) => return fallback
  }
  match maybe_parse_payload(execution.content) {
    Some(payload) => {
      let proposal = proposal_payload_to_proposal(
        proposal_id, request_text, payload, now_ms, channel_id, account_id, recipient,
        thread_id,
      )
      maybe_apply_job_profile(
        proposal,
        cwd,
        home.unwrap_or(cwd),
        workspace.unwrap_or(cwd),
      )
    }
    None => fallback
  }
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
  let request = AnalysisRequest::{
    job_id: "proposal:\{proposal.id}",
    run_id: "proposal:\{proposal.id}",
    step_id: "planner.revise",
    prompt: planner_request_prompt(
      proposal.request_text,
      revision=Some(revision),
      existing=Some(proposal),
      workspace~,
      memory_context~,
    ),
    model_name: model.unwrap_or("default"),
    cwd,
    home,
    execution_mode: None,
    execution_target: None,
    system_prompt: planner_system_prompt(),
    preferred_skills: [],
    enable_tools: false,
    web_search: false,
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
      maybe_apply_job_profile(
        revised,
        cwd,
        home.unwrap_or(cwd),
        workspace.unwrap_or(cwd),
      )
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
  lines.push("")
  lines.push("Summary: \{proposal.summary}")
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

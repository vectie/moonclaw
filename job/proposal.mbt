///|
fn infer_job_tags(request_text : String) -> Array[String] {
  let lower = request_text.to_lower()
  let tags = ["job"]
  if lower.contains("research") ||
    lower.contains("paper") ||
    lower.contains("arxiv") {
    tags.push("research")
  }
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
      id: "requirements",
      title: "Clarify objective and success criteria",
      kind: "job.analysis",
      prompt: [
        "Take the following requested job and restate the real objective, constraints, assumptions, and success criteria.",
        "Identify any missing information but keep moving with explicit assumptions.",
        "Request: \{request_text}",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "plan",
      title: "Build execution plan",
      kind: "job.analysis",
      prompt: [
        "Build a concrete execution plan for the requested job.", "Break the work into sequential tasks with clear inputs, outputs, and validation points.",
        "Use the prior step output as context.",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "execute",
      title: "Execute main work",
      kind: "job.analysis",
      prompt: [
        "Perform the main requested work using the prior outputs as context.", "Be concrete and produce a useful working result, not just advice.",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "verify",
      title: "Verify and refine result",
      kind: "job.analysis",
      prompt: [
        "Review the result critically.", "Find gaps, risks, and quality problems, then refine the result.",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "deliver",
      title: "Prepare final delivery",
      kind: "job.analysis",
      prompt: [
        "Prepare a concise final delivery summary.", "Include what was done, what remains open, and what artifacts or outputs were produced.",
      ].join("\n\n"),
    },
  ]
}

///|
fn research_proposal_steps(request_text : String) -> Array[JobProposalStep] {
  [
    JobProposalStep::{
      id: "scope",
      title: "Define research scope",
      kind: "job.analysis",
      prompt: [
        "Determine the exact research topic, scope, timeframe, and what counts as relevant source material.",
        "Request: \{request_text}",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "collect",
      title: "Collect candidate sources",
      kind: "job.analysis",
      prompt: [
        "Plan how to collect the most relevant papers and sources.", "Identify search terms, source criteria, and expected artifact structure.",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "analyze",
      title: "Analyze sources",
      kind: "job.analysis",
      prompt: [
        "Analyze the collected material.", "Focus on novelty, methods, evidence quality, and practical relevance.",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "synthesize",
      title: "Synthesize findings",
      kind: "job.analysis",
      prompt: [
        "Synthesize the most important findings into structured conclusions and action items.",
      ].join("\n\n"),
    },
    JobProposalStep::{
      id: "deliver",
      title: "Prepare research brief",
      kind: "job.analysis",
      prompt: [
        "Prepare a final research brief with recommendations, unanswered questions, and next actions.",
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
  let fallback = if fallback_request.to_lower().contains("research") ||
    fallback_request.to_lower().contains("paper") ||
    fallback_request.to_lower().contains("arxiv") {
    research_proposal_steps(fallback_request)
  } else {
    generic_proposal_steps(fallback_request)
  }
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
  JobProposal::{
    ..fallback,
    title: payload.title.map(compact_title).unwrap_or(fallback.title),
    request_text,
    summary: payload.summary
    .map(fn(text) { text.trim().to_string() })
    .unwrap_or(fallback.summary),
    status: Draft,
    steps: normalized_plan_steps(payload, request_text),
    tags: payload.tags.unwrap_or(fallback.tags),
    updated_at: now_ms,
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
) -> String {
  let parts = ["Create a draft plan for this requested job:", request_text]
  let parts = match existing {
    Some(existing) => {
      let rendered_steps = existing.steps
        .map(fn(step) { "- \{step.id}: \{step.title}" })
        .join("\n")
      [
        ..parts,
        "Existing proposal title: \{existing.title}",
        "Existing proposal summary: \{existing.summary}",
        "Existing proposal steps:\n\{rendered_steps}",
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
) -> JobProposal {
  let request = AnalysisRequest::{
    job_id: "proposal:\{proposal_id}",
    run_id: "proposal:\{proposal_id}",
    step_id: "planner",
    prompt: planner_request_prompt(request_text),
    model_name: model.unwrap_or("default"),
    cwd,
    home,
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
  let execution = match (executor.run)(request) {
    Ok(execution) => execution
    Err(_) => return fallback
  }
  match maybe_parse_payload(execution.content) {
    Some(payload) =>
      proposal_payload_to_proposal(
        proposal_id, request_text, payload, now_ms, channel_id, account_id, recipient,
        thread_id,
      )
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
) -> JobProposal {
  let request = AnalysisRequest::{
    job_id: "proposal:\{proposal.id}",
    run_id: "proposal:\{proposal.id}",
    step_id: "planner.revise",
    prompt: planner_request_prompt(
      proposal.request_text,
      revision=Some(revision),
      existing=Some(proposal),
    ),
    model_name: model.unwrap_or("default"),
    cwd,
    home,
    system_prompt: planner_system_prompt(),
    preferred_skills: [],
    enable_tools: false,
    web_search: false,
  }
  let execution = match (executor.run)(request) {
    Ok(execution) => execution
    Err(_) => return JobProposal::{ ..proposal, updated_at: now_ms }
  }
  match maybe_parse_payload(execution.content) {
    Some(payload) =>
      proposal_payload_to_proposal(
        proposal.id,
        proposal.request_text,
        payload,
        now_ms,
        proposal.channel_id,
        proposal.account_id,
        proposal.recipient,
        proposal.thread_id,
        existing=Some(proposal),
      )
    None => JobProposal::{ ..proposal, updated_at: now_ms }
  }
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
  let lower = request_text.to_lower()
  let steps = if lower.contains("research") ||
    lower.contains("paper") ||
    lower.contains("arxiv") {
    research_proposal_steps(request_text)
  } else {
    generic_proposal_steps(request_text)
  }
  JobProposal::{
    id: proposal_id,
    title: compact_title(request_text),
    request_text,
    summary: [
      "Draft job proposal generated from chat request.", "This proposal will not execute until explicitly confirmed.",
    ].join(" "),
    status: Draft,
    steps,
    tags: infer_job_tags(request_text),
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
) -> (JobDefinition, WorkflowDefinition) {
  let job_id = "job.proposal.\{proposal.id}"
  let workflow_id = "workflow.proposal.\{proposal.id}"
  let steps = proposal.steps.map(fn(step) {
    WorkflowStepDefinition::{
      id: step.id,
      kind: step.kind,
      config: AnalysisStepConfig::new(
        prompt=step.prompt,
        cwd=Some(cwd),
        home=Some(home),
        preferred_skills=[],
        enable_tools=true,
        web_search=false,
        policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
        artifacts=AnalysisArtifactConfig::new(
          report_artifact_type="job.proposal.step.report",
          result_artifact_type="job.proposal.step.result",
          logical_key=Some("\{proposal.id}:\{step.id}"),
          scope=["jobs", "proposal:\{proposal.id}"],
          append_only=false,
        ),
        metadata={
          "proposal_id": proposal.id,
          "proposal_step_id": step.id,
          "proposal_step_title": step.title,
        },
      ).to_json(),
      retry_policy: None,
    }
  })
  let definition = JobDefinition::{
    id: job_id,
    kind: "job.proposal",
    enabled: true,
    config: {
      "proposal_id": proposal.id,
      "notify": {
        "channel": proposal.channel_id,
        "account_id": proposal.account_id,
        "to": proposal.recipient,
        "thread_id": proposal.thread_id,
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: None,
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: proposal.tags,
  }
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "job.proposal",
    steps,
    output_bindings: proposal.steps.map(fn(step) { step.id }),
  }
  (definition, workflow)
}

///|
pub fn render_job_proposal_for_chat(proposal : JobProposal) -> String {
  let lines = [
    "Job proposal `\{proposal.id}`",
    "",
    "Title: \{proposal.title}",
    "Status: \{proposal.status.to_json().stringify()}",
    "",
    "Summary: \{proposal.summary}",
    "",
    "Planned steps:",
  ]
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

///|
fn metadata_bool_or_false(metadata : Json, key : String) -> Bool {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
fn e2e_preprocessing_disabled(proposal : JobProposal) -> Bool {
  match proposal.profile_metadata {
    Object(obj) =>
      match obj.get("disable_preprocessing") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
fn has_context_preprocess_step(proposal : JobProposal) -> Bool {
  proposal.steps.any(fn(step) {
    step.id == "context_preprocess" ||
    metadata_bool_or_false(step.metadata, "preprocess_context")
  })
}

///|
fn requested_output_format_from_preprocess_intake(intake : Json?) -> String? {
  match intake {
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
fn preprocess_step_prompt(proposal : JobProposal) -> String {
  let requested_format = match
    requested_output_format_from_preprocess_intake(
      proposal_initial_input(proposal),
    ) {
    Some(value) => value
    None => "final deliverable"
  }
  [
    "Do a lightweight preprocessing pass before the main workflow starts.",
    "Use the starter attachments, local context, tools, and public web search to gather missing background facts relevant to the job.",
    "When using local file tools, search inside the active workspace first. At most, inspect the workspace parent directory when clearly necessary. Do not roam across unrelated directories.",
    "If the initial input includes `resume_content` or resume attachments, treat them as newly supplied user input that may resolve earlier missing-data gaps.",
    "Do not try to produce the final answer yet.",
    "Instead, produce a compact context pack for downstream steps.",
    "Include: core facts already known, missing facts you could discover, discovered public facts, working assumptions, source pointers, and recommended focus areas for later steps.",
    "Prefer grounded searching over guessing, but if some public data remains unavailable, make clearly labeled reasonable assumptions so later steps can continue.",
    "Do not request a child subplan from this preprocessing step.",
    "If preprocessing is still blocked on user-provided or external facts, return JSON only as {\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]} and make `missing_inputs` explicit and concrete.",
    "Requested final output format: \{requested_format}",
    "Original request: \{proposal.request_text}",
  ].join("\n\n")
}

///|
fn preprocess_step_system_prompt() -> String {
  [
    @prompt.prelude, "You are running a job-level preprocessing pass.", "This step runs once at the very beginning of the job to gather useful related context.",
    "Do not ask the user for more input in this step.", "Do not request a child subplan in this step.",
    "Search available workspace files, tools, and public sources as appropriate, then produce a compact context pack.",
    "If some facts are still unavailable, make clearly labeled reasonable assumptions so the main workflow can continue.",
    "Return normal prose or markdown only, not control JSON.",
  ].join("\n\n")
}

///|
fn preprocess_step_metadata() -> Json {
  {
    "preferred_skills": ["research", "context-gathering"],
    "enable_tools": true,
    "web_search": true,
    "system_prompt": preprocess_step_system_prompt(),
    "report_file_name": "preprocess_context.md",
    "result_file_name": "preprocess_context.json",
    "skip_primary_workspace_output": true,
    "disable_adaptive": true,
    "preprocess_context": true,
    "board_lane": "Preprocess",
    "board_order": 10,
  }
}

///|
fn context_preprocess_step(proposal : JobProposal) -> JobProposalStep {
  JobProposalStep::{
    id: "context_preprocess",
    title: "Gather context and public facts",
    prompt: preprocess_step_prompt(proposal),
    kind: "job.analysis",
    metadata: preprocess_step_metadata(),
    child_profile: None,
    execution_mode: None,
    execution_target: None,
    include_parent_outputs: None,
    max_depth: None,
  }
}

///|
pub fn with_e2e_preprocess_steps(proposal : JobProposal) -> JobProposal {
  if e2e_preprocessing_disabled(proposal) ||
    has_context_preprocess_step(proposal) {
    return proposal
  }
  if proposal.request_text.trim().to_string().is_blank() {
    return proposal
  }
  JobProposal::{
    ..proposal,
    steps: [context_preprocess_step(proposal), ..proposal.steps],
  }
}

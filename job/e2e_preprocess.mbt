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
    "Do not try to produce the final answer yet.",
    "Instead, produce a compact context pack for downstream steps.",
    "Include: core facts already known, missing facts you could discover, discovered public facts, working assumptions, source pointers, and recommended focus areas for later steps.",
    "Prefer grounded searching over guessing, but if some public data remains unavailable, make clearly labeled reasonable assumptions so later steps can continue.",
    "Requested final output format: \{requested_format}",
    "Original request: \{proposal.request_text}",
  ].join("\n\n")
}

///|
fn preprocess_step_metadata() -> Json {
  {
    "preferred_skills": ["research", "context-gathering"],
    "enable_tools": true,
    "web_search": true,
    "report_file_name": "preprocess_context.md",
    "result_file_name": "preprocess_context.json",
    "skip_primary_workspace_output": true,
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

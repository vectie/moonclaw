///|
fn requested_output_format_from_intake(intake : Json?) -> String? {
  match intake {
    Some(Object(obj)) =>
      match obj.get("requested_output_format") {
        Some(String(value)) if !value.trim().to_owned().is_blank() =>
          Some(value.trim().to_owned())
        _ => None
      }
    _ => None
  }
}

///|
fn requested_output_format_text(proposal : JobProposal) -> String {
  match requested_output_format_from_intake(proposal_initial_input(proposal)) {
    Some(text) => text
    None => ""
  }
}

///|
pub fn e2e_requests_presentation(proposal : JobProposal) -> Bool {
  let format = requested_output_format_text(proposal).to_lower()
  format.contains("presentation") ||
  format.contains("slide") ||
  format.contains("deck") ||
  format.contains("ppt")
}

///|
fn presentation_step_prompt(proposal : JobProposal) -> String {
  let requested_format = match
    requested_output_format_from_intake(proposal_initial_input(proposal)) {
    Some(format) => format
    None => "presentation deck"
  }
  [
    "Convert the completed job result into a structured presentation plan.",
    "Use the prior step outputs, especially the main report/result artifacts, as the source material.",
    "Return a presentation specification that describes what each page should look like, not just the text content.",
    "Target output format: \{requested_format}",
    presentation_deck_spec_schema_prompt(),
    "Each page must include concrete layout direction and visual intent that a downstream rendering vendor can implement.",
    "The render_handoff field should summarize what the downstream rendering vendor needs in order to produce the deck faithfully.",
    "Prefer executive, presentation-ready pages over long prose.",
    "Job title: \{proposal.title}",
    "Original request: \{proposal.request_text}",
  ].join("\n\n")
}

///|
fn presentation_step_metadata() -> Json {
  {
    "preferred_skills": ["presentation-planning"],
    "enable_tools": false,
    "web_search": false,
    "result_content_json_contract": presentation_contract_version(),
    "result_file_name": "presentation_plan.json",
    "report_file_name": "presentation_outline.md",
    "skip_primary_workspace_output": true,
    "postprocess_kind": "presentation",
    "postprocess_contract": presentation_contract_version(),
    "board_lane": "Presentation",
    "board_order": 900,
  }
}

///|
fn presentation_renderer_config(proposal : JobProposal) -> Json? {
  match proposal_initial_input(proposal) {
    Some(Object(obj)) =>
      match obj.get("presentation_renderer") {
        Some(Object(config)) => Some(Json::object(config))
        _ =>
          match proposal.profile_metadata {
            Object(metadata) =>
              match metadata.get("presentation_renderer") {
                Some(Object(config)) => Some(Json::object(config))
                _ => None
              }
            _ => None
          }
      }
    _ => None
  }
}

///|
fn presentation_renderer_execution_mode(proposal : JobProposal) -> String? {
  match presentation_renderer_config(proposal) {
    Some(config) => metadata_string(config, "execution_mode")
    None => None
  }
}

///|
fn presentation_renderer_execution_target(proposal : JobProposal) -> String? {
  match presentation_renderer_config(proposal) {
    Some(config) => metadata_string(config, "execution_target")
    None => None
  }
}

///|
fn presentation_renderer_theme(proposal : JobProposal) -> String? {
  match presentation_renderer_config(proposal) {
    Some(config) => metadata_string(config, "theme")
    None => None
  }
}

///|
fn presentation_renderer_metadata(proposal : JobProposal) -> Json {
  let metadata : Map[String, Json] = {
    "preferred_skills": Json::array([]),
    "enable_tools": false.to_json(),
    "web_search": false.to_json(),
    "postprocess_contract": presentation_contract_version(),
    "result_content_json_contract": presentation_render_contract_version().to_json(),
    "result_file_name": "presentation_render_result.json",
    "report_file_name": "presentation_render_report.md",
    "skip_primary_workspace_output": true.to_json(),
    "postprocess_kind": "presentation-render",
    "board_lane": "Presentation",
    "board_order": 910,
  }
  match presentation_renderer_config(proposal) {
    Some(config) => metadata.set("presentation_renderer", config)
    None => ()
  }
  match presentation_renderer_theme(proposal) {
    Some(theme) => metadata.set("presentation_theme", theme.to_json())
    None => ()
  }
  Json::object(metadata)
}

///|
fn presentation_render_step(proposal : JobProposal) -> JobProposalStep {
  JobProposalStep::{
    id: "presentation_render",
    title: "Render presentation package",
    prompt: [
      "Use the generated `presentation_plan.json` from the previous step and produce a renderer-ready presentation package.",
      "Treat the previous step's output as a `\{presentation_contract_version()}` deck specification.",
      "Preserve the page order, layout instructions, visual intent, and render handoff details from that plan.",
      "Prefer deterministic rendering or vendor handoff work over rewriting the deck content.",
      "If a renderer target is configured, execute against that target and return the produced artifact locations and render metadata.",
      "If no renderer is available, return a render request package that a vendor can consume directly.",
      presentation_render_package_schema_prompt(),
      "Requested output format: \{requested_output_format_text(proposal)}",
      "Job title: \{proposal.title}",
    ].join("\n\n"),
    kind: "job.analysis",
    metadata: presentation_renderer_metadata(proposal),
    child_profile: None,
    execution_mode: presentation_renderer_execution_mode(proposal),
    execution_target: presentation_renderer_execution_target(proposal),
    include_parent_outputs: None,
    max_depth: None,
  }
}

///|
fn presentation_postprocess_step(proposal : JobProposal) -> JobProposalStep {
  JobProposalStep::{
    id: "presentation_postprocess",
    title: "Generate presentation plan",
    prompt: presentation_step_prompt(proposal),
    kind: "job.analysis",
    metadata: presentation_step_metadata(),
    child_profile: None,
    execution_mode: None,
    execution_target: None,
    include_parent_outputs: None,
    max_depth: None,
  }
}

///|
pub fn with_e2e_postprocess_steps(proposal : JobProposal) -> JobProposal {
  if !e2e_requests_presentation(proposal) {
    return proposal
  }
  if proposal.steps.any(fn(step) {
      step.id == "presentation_postprocess" || step.id == "presentation_render"
    }) {
    return proposal
  }
  let steps = [..proposal.steps, presentation_postprocess_step(proposal)]
  let steps = match presentation_renderer_config(proposal) {
    Some(_) => [..steps, presentation_render_step(proposal)]
    None => steps
  }
  JobProposal::{ ..proposal, steps, }
}

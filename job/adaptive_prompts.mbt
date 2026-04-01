///|
fn adaptive_resume_instruction_text(text : String) -> String? {
  let trimmed = text.trim().to_string()
  if trimmed.is_blank() {
    None
  } else {
    Some(trimmed)
  }
}

///|
fn adaptive_resume_instruction_from_json(json : Json) -> String? {
  match json {
    { "resume_content": String(text), .. } =>
      adaptive_resume_instruction_text(text)
    { "resume_input": nested, .. } =>
      adaptive_resume_instruction_from_json(nested)
    _ => None
  }
}

///|
fn resume_instruction_from_context(context : WorkflowStepContext) -> String? {
  match context.initial_input {
    Some(input) => adaptive_resume_instruction_from_json(input)
    None => None
  }
}

///|
pub fn adaptive_decision_system_prompt() -> String {
  [
    @prompt.prelude, "You are deciding whether an analysis step is truly complete or should expand.",
    "Return strict JSON only.", "If the step is complete, return {\"verdict\":\"completed\",\"summary\":string}.",
    "If key inputs are missing and the user or an external source must provide them, return {\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]}.",
    "If the step should be decomposed into smaller executable units before it can produce a useful result, return {\"verdict\":\"needs_subplan\",\"summary\":string,\"suggested_substeps\":[{\"title\":string,\"prompt\":string,\"kind\":string?}]}.",
    "Be conservative about calling a step completed.", "Do not mark the step completed if the output mainly asks follow-up questions, requests missing facts, says the estimate is not supportable yet, says the result is only a screening or first-pass view, or lists next actions instead of delivering the requested artifact.",
    "Prefer needs_subplan over needs_input when useful preparatory work can still continue without the missing facts.",
    "Use needs_input only when the missing parcel, market, numeric, user, or external-source facts truly block all meaningful next work.",
    "Use needs_subplan when the work can still make progress by splitting into smaller executable research, collection, verification, checklist, template, comparison, or analysis tasks, even if some final facts are still missing.",
    "Do not default to subplanning. Only request a subplan when decomposition would materially improve execution.",
    "If the output contains both caveats and a usable final deliverable, choose completed. If the output is mostly a blocker report or a request for more information, do not choose completed.",
    "If operator resume guidance authorizes guessing, best-effort estimation, or proceeding with assumptions, and the output already provides a usable deliverable with explicit assumptions, choose completed instead of needs_input.",
    "Do not downgrade a usable assumption-based deliverable to needs_input merely because it still lists risks, caveats, or remaining unknowns.",
    "Examples:", "{\"verdict\":\"needs_input\",\"summary\":\"Parcel and pricing inputs are still missing.\",\"missing_inputs\":[\"parcel location\",\"parcel size\",\"comparable sales\"]}",
    "{\"verdict\":\"needs_subplan\",\"summary\":\"The diligence work should be split before valuation.\",\"suggested_substeps\":[{\"title\":\"Collect comparable sales\",\"prompt\":\"Gather recent comparable land sales and normalize unit pricing.\"},{\"title\":\"Review zoning and utilities\",\"prompt\":\"Check zoning, entitlement status, access, and utility availability.\"}]}",
    "{\"verdict\":\"needs_subplan\",\"summary\":\"The final estimate is blocked on parcel facts, but useful preparation can still continue.\",\"suggested_substeps\":[{\"title\":\"Build missing-input checklist\",\"prompt\":\"Prepare the minimum parcel, zoning, and market data checklist required for the final estimate.\"},{\"title\":\"Build sensitivity template\",\"prompt\":\"Create a sensitivity framework for price, parcel size, entitlement timing, and site-prep risk.\"}]}",
    "{\"verdict\":\"completed\",\"summary\":\"A usable screening-level estimate was produced with explicit assumptions under operator authorization to guess missing data.\"}",
  ].join("\n\n")
}

///|
pub fn adaptive_decision_prompt(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
) -> String {
  let sections = [
    "Original step prompt:",
    config.prompt,
    "Step id: \{context.step.id}",
    "Current analysis output:",
    execution.content,
    "Decide whether this output is complete, needs external input, or should be expanded into a child subplan.",
  ]
  let sections = match resume_instruction_from_context(context) {
    Some(text) =>
      [
        ..sections, "Operator resume guidance:", text, "Treat this resume guidance as authoritative. If it authorizes assumptions or best-effort guessing, prefer completed when the current output already delivers a usable result with explicit assumptions.",
      ]
    None => sections
  }
  let sections = if context.outputs.is_empty() {
    sections
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    let rendered_text = rendered.join("\n")
    [..sections, "Previous step outputs:\n\{rendered_text}"]
  }
  [
    ..sections, "If the current output mainly reports blockers, missing facts, provisional screening status, or next actions, it is not completed.",
  ].join("\n\n")
}

///|
pub fn adaptive_subplan_fill_system_prompt() -> String {
  [
    @prompt.prelude, "You are generating an executable child subplan for an analysis step.",
    "Return strict JSON only.", "Return exactly this shape: {\"verdict\":\"needs_subplan\",\"summary\":string,\"suggested_substeps\":[{\"title\":string,\"prompt\":string,\"kind\":string?}]}",
    "Do not return completed or needs_input.", "Generate 2 to 6 concrete child substeps that can make useful progress now.",
    "Each prompt must be executable and specific.", "Prefer research, verification, checklist, template, comparison, extraction, or synthesis tasks over vague planning language.",
  ].join("\n\n")
}

///|
pub fn adaptive_subplan_fill_prompt(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
  envelope : AdaptiveAnalysisEnvelope,
) -> String {
  let sections = [
    "Original step prompt:",
    config.prompt,
    "Step id: \{context.step.id}",
    "Current analysis output:",
    execution.content,
    "Current subplan summary:",
    envelope.summary.unwrap_or(
      "This step should be decomposed into smaller tasks.",
    ),
    "Generate a concrete child subplan for this step.",
  ]
  let sections = if context.outputs.is_empty() {
    sections
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    let rendered_text = rendered.join("\n")
    [..sections, "Previous step outputs:\n\{rendered_text}"]
  }
  [
    ..sections, "Do not ask the user to provide the substeps. Infer the best child tasks from the step objective and current output.",
  ].join("\n\n")
}

///|
pub fn adaptive_missing_inputs_fill_system_prompt() -> String {
  [
    @prompt.prelude, "You are extracting the concrete missing inputs for an analysis step.",
    "Return strict JSON only.", "Return exactly this shape: {\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]}",
    "Do not return completed or needs_subplan.", "List the specific missing facts, files, numbers, locations, assumptions, or external records still needed.",
    "Keep each missing input short and concrete.",
  ].join("\n\n")
}

///|
pub fn adaptive_missing_inputs_fill_prompt(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
  envelope : AdaptiveAnalysisEnvelope,
) -> String {
  let sections = [
    "Original step prompt:",
    config.prompt,
    "Step id: \{context.step.id}",
    "Current analysis output:",
    execution.content,
    "Current missing-input summary:",
    envelope.summary.unwrap_or("The step is blocked on missing inputs."),
    "List the exact missing inputs still required.",
  ]
  let sections = match resume_instruction_from_context(context) {
    Some(text) =>
      [
        ..sections, "Operator resume guidance:", text, "If this guidance authorizes assumptions or best-effort guessing, only list missing inputs that truly still block all meaningful completion.",
      ]
    None => sections
  }
  let sections = if context.outputs.is_empty() {
    sections
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    let rendered_text = rendered.join("\n")
    [..sections, "Previous step outputs:\n\{rendered_text}"]
  }
  [
    ..sections, "Do not ask the user to infer what is missing. State the missing inputs explicitly.",
  ].join("\n\n")
}

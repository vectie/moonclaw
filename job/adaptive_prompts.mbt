///|
fn adaptive_decision_system_prompt() -> String {
  [
    @prompt.prelude, "You are deciding whether an analysis step is complete, blocked on external input, or should expand.",
    "The loaded `analysis-adaptation` skill is authoritative for the decision procedure.",
    "Return strict JSON only.", "Allowed shapes:", "{\"verdict\":\"completed\",\"summary\":string}",
    "{\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]}",
    "{\"verdict\":\"needs_subplan\",\"summary\":string,\"suggested_substeps\":[{\"title\":string,\"prompt\":string,\"kind\":string?}]}",
  ].join("\n\n")
}

///|
fn adaptive_decision_prompt(
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
fn adaptive_subplan_fill_system_prompt() -> String {
  [
    @prompt.prelude, "You are generating an executable child subplan for an analysis step.",
    "The loaded `analysis-adaptation` skill is authoritative for subplan quality.",
    "Return strict JSON only.", "Return exactly this shape: {\"verdict\":\"needs_subplan\",\"summary\":string,\"suggested_substeps\":[{\"title\":string,\"prompt\":string,\"kind\":string?}]}",
    "Do not return completed or needs_input.",
  ].join("\n\n")
}

///|
fn adaptive_subplan_fill_prompt(
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
fn adaptive_missing_inputs_fill_system_prompt() -> String {
  [
    @prompt.prelude, "You are extracting the concrete missing inputs for an analysis step.",
    "The loaded `analysis-adaptation` skill is authoritative for missing-input quality.",
    "Return strict JSON only.", "Return exactly this shape: {\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]}",
    "Do not return completed or needs_subplan.",
  ].join("\n\n")
}

///|
fn adaptive_missing_inputs_fill_prompt(
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

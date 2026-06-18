///|
fn adaptive_resume_instruction_text(text : String) -> String? {
  let trimmed = text.trim().to_owned()
  if trimmed.is_blank() {
    None
  } else {
    Some(trimmed)
  }
}

///|
fn resume_instruction_from_serialized_json(text : String) -> String? {
  let marker = "\"resume_content\":\""
  match text.find(marker) {
    Some(start) => {
      let remainder = text[start + marker.length():].to_owned()
      match remainder.find("\"") {
        Some(end) =>
          adaptive_resume_instruction_text(remainder[:end].to_owned())
        None => None
      }
    }
    None => None
  }
}

///|
fn resume_instruction_from_json(input : Json) -> String? {
  match input {
    { "resume_content": String(text), .. } => {
      let trimmed = text.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    { "resume_input": nested, .. } => resume_instruction_from_json(nested)
    _ => resume_instruction_from_serialized_json(input.stringify())
  }
}

///|
fn resume_instruction_from_input(input : Json?) -> String? {
  match input {
    Some({ "resume_content": String(text), .. }) => {
      let trimmed = text.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    Some({ "resume_input": nested, .. }) => resume_instruction_from_json(nested)
    Some(json) => resume_instruction_from_json(json)
    None => None
  }
}

///|
fn resume_instruction_from_context(context : WorkflowStepContext) -> String? {
  match context.initial_input {
    Some(input) => resume_instruction_from_json(input)
    None => None
  }
}

///|
fn should_preserve_first_pass_on_empty_subplan(
  context : WorkflowStepContext,
  execution : AnalysisExecution,
) -> Bool {
  match
    (
      resume_instruction_from_input(context.initial_input),
      parse_adaptive_analysis_envelope(execution.content),
    ) {
    (Some(_), None) if !execution.content.trim().to_owned().is_blank() => true
    _ => false
  }
}

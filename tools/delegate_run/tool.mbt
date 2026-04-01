///|
pub struct DelegateRunResult {
  title : String
  request_text : String
  expected_output : String?
  child_profile : String?
  execution_mode : String?
  execution_target : String?
  include_parent_outputs : Bool
  max_depth : Int
  bounded : Bool
  step_kind : String
  step_config : Json
  summary : String
} derive(ToJson, FromJson, Show)

///|
pub fn new() -> @tool.Tool[DelegateRunResult] {
  @tool.new(
    name="delegate_run",
    description="Create a typed, bounded child-run request for delegated work. This does not execute the child run directly; it returns a normalized job.delegate request surface that can be persisted or passed to runtime delegation.",
    schema={
      "type": "object",
      "properties": {
        "title": { "type": "string" },
        "request_text": { "type": "string" },
        "expected_output": { "type": "string" },
        "child_profile": { "type": "string" },
        "execution_mode": { "type": "string" },
        "execution_target": { "type": "string" },
        "include_parent_outputs": { "type": "boolean" },
        "max_depth": { "type": "integer", "minimum": 1, "maximum": 4 },
      },
      "required": ["title", "request_text"],
    },
    fn(args) -> @tool.ToolResult[DelegateRunResult] noraise {
      guard args
        is { "title": String(title), "request_text": String(request_text), .. } else {
        return @tool.error(
          "Error: 'title' and 'request_text' parameters are required",
        )
      }
      let title = title.trim().to_string()
      let request_text = request_text.trim().to_string()
      guard !title.is_blank() else {
        return @tool.error("Error: 'title' must not be blank")
      }
      guard !request_text.is_blank() else {
        return @tool.error("Error: 'request_text' must not be blank")
      }
      let expected_output = match args {
        { "expected_output": String(value), .. } if !value
          .trim()
          .to_string()
          .is_blank() => Some(value.trim().to_string())
        _ => None
      }
      let child_profile = match args {
        { "child_profile": String(value), .. } if !value
          .trim()
          .to_string()
          .is_blank() => Some(value.trim().to_string())
        _ => None
      }
      let execution_mode = match args {
        { "execution_mode": String(value), .. } if !value
          .trim()
          .to_string()
          .is_blank() => Some(value.trim().to_string())
        _ => None
      }
      let execution_target = match args {
        { "execution_target": String(value), .. } if !value
          .trim()
          .to_string()
          .is_blank() => Some(value.trim().to_string())
        _ => None
      }
      let include_parent_outputs = match args {
        { "include_parent_outputs": False, .. } => false
        _ => true
      }
      let max_depth = match args {
        { "max_depth": Number(value, ..), .. } =>
          Int::min(4, Int::max(1, value.to_int()))
        _ => 2
      }
      let bounded = max_depth <= 4
      let step_config : Json = {
        "request_text": request_text,
        "child_profile": child_profile,
        "execution_mode": execution_mode,
        "execution_target": execution_target,
        "include_parent_outputs": include_parent_outputs,
        "max_depth": max_depth,
        "delegation_title": title,
        "expected_output": expected_output,
      }
      let summary = [
        "Delegation request prepared for `job.delegate`.",
        "Title: \{title}",
        "Max depth: \{max_depth}",
        if include_parent_outputs {
          "Parent outputs will be included."
        } else {
          "Parent outputs will not be included."
        },
      ].join(" ")
      @tool.ok(DelegateRunResult::{
        title,
        request_text,
        expected_output,
        child_profile,
        execution_mode,
        execution_target,
        include_parent_outputs,
        max_depth,
        bounded,
        step_kind: "job.delegate",
        step_config,
        summary,
      })
    },
  )
}

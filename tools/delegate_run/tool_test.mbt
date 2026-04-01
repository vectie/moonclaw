///|
async test "delegate_run returns bounded child-run config" {
  let tool = new()
  let result = tool.call({
    "title": "Review docs",
    "request_text": "Review the docs and propose edits.",
    "include_parent_outputs": true,
    "max_depth": 2,
  })
  guard result is Ok(output) else {
    fail("Expected Ok result but got: \{result}")
  }
  inspect(output.step_kind, content="job.delegate")
  inspect(output.max_depth.to_string(), content="2")
  inspect(
    output.step_config
    .stringify()
    .contains("\"request_text\":\"Review the docs and propose edits.\""),
    content="true",
  )
}

///|
async test "runtime_context returns the provided context" {
  let tool = new(
    RuntimeContextResult::new(
      cwd="/tmp/demo",
      home=Some("/tmp/home"),
      run_id=Some("run-1"),
      job_id=Some("job-1"),
      step_id=Some("step-1"),
      model_name=Some("codex/gpt-5.4"),
      execution_mode=Some("vendor.presentation"),
      execution_target=Some("slides-main"),
      workspace_dir=Some("/tmp/workspace"),
      execution_isolation=Some({ "mode": "git_worktree" }),
      enabled_tools=["runtime_context", "list_worktrees"],
    ),
  )
  let result = tool.call({})
  guard result is Ok(output) else {
    fail("Expected Ok result but got: \{result}")
  }
  inspect(output.run_id.unwrap_or(""), content="run-1")
  inspect(
    output.enabled_tools.join(","),
    content="runtime_context,list_worktrees",
  )
}

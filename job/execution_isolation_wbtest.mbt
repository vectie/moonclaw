///|
async test "required git worktree isolation fails closed outside a repository" {
  @fsx.with_temporary_directory("job-isolation-fail-closed-XXXXXX", dir => {
    let context = WorkflowStepContext::new(
      run={
        id: "run-isolation-fail-closed",
        job_id: "job-isolation-fail-closed",
        trigger: Manual,
        parent_run_id: None,
        parent_step_id: None,
        depth: 0,
        workspace_dir: Some(dir),
        status: Running,
        attempt: 1,
        retry_of: None,
        started_at: Some(1),
        finished_at: None,
        summary: None,
        error: None,
      },
      step={
        id: "step-isolation-fail-closed",
        kind: "job.analysis",
        config: {},
        retry_policy: None,
      },
    )
    let config = AnalysisStepConfig::new(
      prompt="Run in an isolated worktree.",
      cwd=Some(dir),
      metadata={
        "execution_isolation": {
          "mode": "git_worktree",
          "task_key": "required isolation",
        },
      },
    )
    try resolve_analysis_execution_isolation(context, config, dir) catch {
      error =>
        assert_true("\{error}".contains("required git worktree isolation"))
    } noraise {
      resolution =>
        fail(
          "required isolation unexpectedly used workspace: \{resolution.cwd}",
        )
    }
  })
}

///|
test "unknown execution isolation mode is rejected" {
  let context = WorkflowStepContext::new(
    run={
      id: "run-isolation-mode",
      job_id: "job-isolation-mode",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(1),
      finished_at: None,
      summary: None,
      error: None,
    },
    step={
      id: "step-isolation-mode",
      kind: "job.analysis",
      config: {},
      retry_policy: None,
    },
  )
  let config = AnalysisStepConfig::new(prompt="Run with invalid isolation.", metadata={
    "execution_isolation": { "mode": "best_effort" },
  })
  try analysis_execution_isolation_spec(context, config) catch {
    error =>
      assert_true(
        "\{error}".contains("unsupported execution isolation mode: best_effort"),
      )
  } noraise {
    _ => fail("unknown isolation mode must be rejected")
  }
}
